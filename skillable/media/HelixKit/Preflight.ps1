# HelixKit v1.0.4 - runs in PowerShell 7 inside the lab VM, started by Prepare-Helix-Workspace.ps1.
param([string]$TenantId, [string]$ClientId, [string]$ClientSecret = $env:HELIXKIT_CLIENT_SECRET,
      [string]$LearnerUpn, [string]$EventDate, [string]$EventTimeZone)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'Continue'
if ($PSStyle) { $PSStyle.OutputRendering = 'PlainText' }
$DataPackUrl = ''
# Lab variables are reported to the launcher, which sets them in Skillable.
function Set-LabVariable { param([string]$Name, $Value) Write-Output "##LABVAR $Name=$Value" }
# ===== Library =====
# ---------------------------------------------------------------------------------------------
# Microsoft Graph client: app-only token from the Skillable cloud credential, retries on
# throttling (429) and transient errors (5xx) honouring Retry-After, paging, token roles.
# Targets PowerShell 7.1+ (Skillable "Execute Script in Cloud Platform").
# ---------------------------------------------------------------------------------------------

$script:GraphRoot = 'https://graph.microsoft.com/v1.0'
$script:GraphAuth = $null
$script:GraphRetryBudgetSeconds = 600   # Check my work scripts lower this so learners never wait long

class GraphError : System.Exception {
    [int]$Status
    [string]$Code
    GraphError([string]$message, [int]$status, [string]$code) : base($message) {
        $this.Status = $status
        $this.Code = $code
    }
}

function Connect-Graph {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret
    )
    $script:GraphAuth = @{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret; Token = $null; Expires = [datetime]::MinValue }
    [void](Get-GraphToken -Force)
}

function Get-GraphToken {
    param([switch]$Force)
    $a = $script:GraphAuth
    if (-not $a) { throw 'Connect-Graph has not been called.' }
    if (-not $Force -and $a.Token -and (Get-Date).ToUniversalTime() -lt $a.Expires.AddMinutes(-5)) { return $a.Token }
    $body = @{
        client_id     = $a.ClientId
        client_secret = $a.ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }
    $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($a.TenantId)/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
    $a.Token = $r.access_token
    $a.Expires = (Get-Date).ToUniversalTime().AddSeconds([int]$r.expires_in)
    return $a.Token
}

function Get-GraphRoles {
    <# Application permissions present in the current token (the "roles" claim). #>
    $payload = (Get-GraphToken).Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    return @($claims.roles)
}

function Invoke-Graph {
    <#
      Calls Microsoft Graph. Returns the parsed JSON as hashtables, $null for 404 when -Ok404,
      or the raw response object when -Raw (status, headers, content).
    #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [byte[]]$Bytes,
        [string]$ContentType,
        [hashtable]$Headers,
        [switch]$Ok404,
        [switch]$Raw,
        [int]$MaxRetries = 8
    )
    $uri = if ($Path -match '^https?://') { $Path } else { "$script:GraphRoot$Path" }
    $refreshed = $false
    $started = Get-Date
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        $h = @{ Authorization = "Bearer $(Get-GraphToken)" }
        if ($Headers) { foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] } }
        # -SkipHttpErrorCheck (PowerShell 7.0+) returns 4xx/5xx responses instead of throwing.
        $p = @{ Method = $Method; Uri = $uri; Headers = $h; SkipHttpErrorCheck = $true }
        if ($null -ne $Bytes) {
            $p.Body = $Bytes
            $p.ContentType = if ($ContentType) { $ContentType } else { 'application/octet-stream' }
        }
        elseif ($null -ne $Body) {
            $p.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 -Compress }
            $p.ContentType = if ($ContentType) { $ContentType } else { 'application/json; charset=utf-8' }
        }
        try {
            $resp = Invoke-WebRequest @p -UseBasicParsing
        }
        catch {
            $netError = $_.Exception -is [System.Net.Http.HttpRequestException] -or $_.Exception -is [System.Threading.Tasks.TaskCanceledException] -or $_.Exception -is [System.IO.IOException] -or $_.Exception -is [System.Net.WebException]
            if (-not $netError -or $attempt -eq $MaxRetries -or ((Get-Date) - $started).TotalSeconds -gt $script:GraphRetryBudgetSeconds) {
                throw [GraphError]::new("$Method $Path : $($_.Exception.GetType().Name): $($_.Exception.Message)", 0, 'network')
            }
            Start-Sleep -Seconds ([math]::Min(60, [math]::Pow(2, $attempt)))
            continue
        }
        $status = [int]$resp.StatusCode
        $rh = $resp.Headers
        if ($status -eq 401 -and -not $refreshed) { [void](Get-GraphToken -Force); $refreshed = $true; $attempt--; continue }
        if ($status -in 429, 500, 502, 503, 504 -and $attempt -lt $MaxRetries -and ((Get-Date) - $started).TotalSeconds -lt $script:GraphRetryBudgetSeconds) {
            $wait = 0
            if ($rh -and $rh['Retry-After']) { [void][int]::TryParse("$($rh['Retry-After'] | Select-Object -First 1)", [ref]$wait) }
            if ($wait -le 0) { $wait = [math]::Min(60, [math]::Pow(2, $attempt)) }
            Start-Sleep -Seconds ($wait + (Get-Random -Minimum 0 -Maximum 2))
            continue
        }
        if ($status -eq 404 -and $Ok404) { return $null }
        if ($status -ge 400) {
            $code = ''; $msg = "$($resp.Content)"
            try { $e = ($resp.Content | ConvertFrom-Json).error; $code = $e.code; $msg = "$($e.code): $($e.message)" } catch { }
            throw [GraphError]::new("$Method $Path -> $status $msg", $status, $code)
        }
        if ($Raw) { return [pscustomobject]@{ Status = $status; Headers = $rh; Content = $resp.Content } }
        if ($status -eq 204 -or -not $resp.Content) { return @{} }
        $ctype = "$($rh['Content-Type'] | Select-Object -First 1)"
        if ($ctype -match 'json') {
            $text = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { $resp.Content }
            return ($text | ConvertFrom-Json -AsHashtable -Depth 50)
        }
        return $resp.Content
    }
    throw [GraphError]::new("$Method $Path : retries exhausted", 0, 'retries')
}

function Get-GraphAll {
    <# GET with paging (@odata.nextLink). #>
    param([Parameter(Mandatory)][string]$Path, [hashtable]$Headers, [int]$Limit = 0)
    $out = [System.Collections.Generic.List[object]]::new()
    $page = Invoke-Graph -Path $Path -Headers $Headers
    while ($true) {
        foreach ($v in @($page.value)) { if ($null -ne $v) { $out.Add($v) } }
        $next = $page.'@odata.nextLink'
        if (-not $next -or ($Limit -gt 0 -and $out.Count -ge $Limit)) { break }
        $page = Invoke-Graph -Path $next -Headers $Headers
    }
    if ($Limit -gt 0 -and $out.Count -gt $Limit) { return $out.GetRange(0, $Limit).ToArray() }
    return $out.ToArray()
}





function Test-GraphRoles {
    <#
      Each requirement is an array of acceptable roles (any one satisfies it).
      Returns the requirements that are not met, as readable strings.
    #>
    param([Parameter(Mandatory)][object[]]$Required)
    $have = Get-GraphRoles
    $missing = @()
    foreach ($req in $Required) {
        $any = @($req)
        if (-not ($any | Where-Object { $have -contains $_ })) { $missing += ($any -join ' or ') }
    }
    return $missing
}
# ---------------------------------------------------------------------------------------------
# Relative dates. Every time in the data pack is an offset from the event day (D0) in the event
# time zone, for example "D-9 09:12" or "D+10". The event day comes from the lab profile
# variable EventDate, so the Helix launch is always ten days out on the day of the event.
# ---------------------------------------------------------------------------------------------

# Windows time zone names (used by Exchange and the lab profile) to IANA names (used on Linux hosts).
$script:WindowsToIana = @{
    'UTC'                           = 'UTC'
    'GMT Standard Time'             = 'Europe/London'
    'W. Europe Standard Time'       = 'Europe/Berlin'
    'Romance Standard Time'         = 'Europe/Paris'
    'Central Europe Standard Time'  = 'Europe/Budapest'
    'India Standard Time'           = 'Asia/Kolkata'
    'Singapore Standard Time'       = 'Asia/Singapore'
    'Tokyo Standard Time'           = 'Asia/Tokyo'
    'China Standard Time'           = 'Asia/Shanghai'
    'AUS Eastern Standard Time'     = 'Australia/Sydney'
    'Arabian Standard Time'         = 'Asia/Dubai'
    'Eastern Standard Time'         = 'America/New_York'
    'Central Standard Time'         = 'America/Chicago'
    'Mountain Standard Time'        = 'America/Denver'
    'Pacific Standard Time'         = 'America/Los_Angeles'
    'E. South America Standard Time' = 'America/Sao_Paulo'
}

function Get-EventTimeZone {
    <# Resolves a Windows time zone name on Windows or Linux hosts. #>
    param([Parameter(Mandatory)][string]$Name)
    foreach ($id in @($Name, $script:WindowsToIana[$Name])) {
        if (-not $id) { continue }
        try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
    }
    throw "Unknown time zone '$Name'. Use a Windows time zone name such as 'India Standard Time'."
}

function New-Timeline {
    param(
        [Parameter(Mandatory)][string]$EventDate,      # yyyy-MM-dd
        [Parameter(Mandatory)][string]$TimeZoneName     # Windows name, e.g. 'India Standard Time'
    )
    $day = [datetime]::ParseExact($EventDate.Trim(), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    return [pscustomobject]@{ Day = $day.Date; Tz = (Get-EventTimeZone $TimeZoneName); TzName = $TimeZoneName }
}
















# ---------------------------------------------------------------------------------------------
# Life cycle action: Pre-flight check (Post-Build, blocking, first action).
#
# Runs before anything is written to the tenant. Confirms that the Skillable cloud credential has
# every Microsoft Graph application permission the lab's scripts need (hydration, readiness,
# TAP and scoring), that the learner account exists and is licensed, and that the tenant has
# enough licensed users with mailboxes for the Helix meeting organisers.
# Ends the lab (Error Action) with one readable list of everything that is missing.
# ---------------------------------------------------------------------------------------------

$script:PermissionGroups = [ordered]@{
    'Hydration: users and personas'   = @(, @('User.ReadWrite.All', 'Directory.ReadWrite.All'))
    'Hydration: mail'                 = @(, @('Mail.ReadWrite'))
    'Hydration: calendar'             = @(, @('Calendars.ReadWrite'))
    'Hydration: mailbox settings'     = @(, @('MailboxSettings.ReadWrite'))
    'Hydration: channel files'        = @(, @('Files.ReadWrite.All', 'Sites.ReadWrite.All'))
    'Hydration: Teams import'         = @(, @('Teamwork.Migrate.All'))
    'Hydration: team (group)'         = @(, @('Group.ReadWrite.All', 'Directory.ReadWrite.All'))
    'Hydration: team members'         = @(, @('TeamMember.ReadWrite.All'))
    'Readiness: channel messages'     = @(, @('ChannelMessage.Read.All'))
    'Learner: Copilot licence'        = @(, @('Organization.Read.All', 'Directory.Read.All', 'Organization.ReadWrite.All', 'Directory.ReadWrite.All'))
    'Scoring: mail, calendar, files'  = @(@('Mail.Read', 'Mail.ReadWrite'), @('Calendars.Read', 'Calendars.ReadWrite'), @('Files.Read.All', 'Files.ReadWrite.All', 'Sites.Read.All', 'Sites.ReadWrite.All'))
    'TAP: authentication methods'     = @(, @('UserAuthenticationMethod.ReadWrite.All'))
    'TAP: tenant policy'              = @(, @('Policy.ReadWrite.AuthenticationMethod'))
}

function Invoke-Preflight {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$LearnerUpn,
        [string]$EventDate,
        [string]$EventTimeZone,
        [int]$OrganisersNeeded = 6,
        # The lab's own TAP action issues the pass; check TAP permissions only when our TAP scripts are used.
        [switch]$IncludeTap
    )
    $problems = [System.Collections.Generic.List[string]]::new()

    # Lab profile variables.
    foreach ($pair in @(@('EventDate', $EventDate), @('EventTimeZone', $EventTimeZone))) {
        if (-not $pair[1] -or $pair[1] -match '^@lab') { $problems.Add("Lab profile variable $($pair[0]) is not set.") }
    }
    if ($EventDate -and $EventDate -notmatch '^@lab') {
        try { $tl = New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone } catch { $problems.Add($_.Exception.Message) }
    }

    # Sign-in.
    try { Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret }
    catch { throw "Pre-flight: cannot sign in with the cloud credential (tenant $TenantId): $($_.Exception.Message)" }

    # Permissions, grouped by what needs them.
    foreach ($group in $script:PermissionGroups.Keys) {
        if (-not $IncludeTap -and $group -like 'TAP:*') { continue }
        $missing = Test-GraphRoles -Required $script:PermissionGroups[$group]
        foreach ($m in $missing) { $problems.Add("Missing permission for ${group}: $m") }
    }

    # Learner and organisers (only if user reads are possible).
    $canRead = -not (Test-GraphRoles -Required @(, @('User.Read.All', 'User.ReadWrite.All', 'Directory.Read.All', 'Directory.ReadWrite.All')))
    if ($canRead) {
        $learner = Invoke-Graph -Path "/users/$([uri]::EscapeDataString($LearnerUpn))?`$select=id,assignedLicenses" -Ok404
        if (-not $learner) { $problems.Add("Learner account $LearnerUpn not found.") }
        elseif (@($learner.assignedLicenses).Count -eq 0) { $problems.Add("Learner account $LearnerUpn has no licences.") }
        $users = Get-GraphAll -Path '/users?$top=999&$select=id,userPrincipalName,displayName,userType,accountEnabled,assignedLicenses,employeeId'
        $hosts = @($users | Where-Object {
                $_.userType -eq 'Member' -and $_.accountEnabled -and @($_.assignedLicenses).Count -gt 0 -and
                (-not $learner -or $_.id -ne $learner.id) -and $_.userPrincipalName -notmatch '#EXT#' -and
                $_.userPrincipalName -notmatch '^(admin|administrator)@' -and "$($_.displayName)" -notmatch 'admin'
            })
        if ($hosts.Count -lt $OrganisersNeeded) {
            $problems.Add("Needs $OrganisersNeeded licensed users (besides the learner) to host the Helix meeting organisers; found $($hosts.Count).")
        }
    }

    if ($problems.Count) {
        throw ("Pre-flight failed; nothing was written to the tenant.`n- " + ($problems -join "`n- "))
    }
    return @{ ok = $true; roles = (Get-GraphRoles).Count }
}
# ===== Run =====
$r = Invoke-Preflight -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -LearnerUpn $LearnerUpn -EventDate $EventDate -EventTimeZone $EventTimeZone
Set-LabVariable -Name PreflightStatus -Value 'ok'