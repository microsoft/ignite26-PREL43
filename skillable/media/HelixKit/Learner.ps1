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




















# ---------------------------------------------------------------------------------------------
# Life cycle action: Hydrate Helix workspace (Post-Build, blocking).
#
# Builds the Zava Helix launch story in this lab's tenant for the learner account:
#   personas -> learner profile -> Teams (migration import) -> channel files -> mail -> calendar
#
# Every phase checks the tenant before writing, so a re-run (Skillable retries uncaught errors)
# finishes the job without duplicates. Nothing is written outside the hydration window
# (D-1 09:30 .. end of D in the event time zone), because Teams import refuses future posts.
# Ported from the Cowork-Lab glc_hydrate engine (ops/tenant.py, ops/seats.py).
# ---------------------------------------------------------------------------------------------

$script:HydrateRoles = @(
    @('User.ReadWrite.All', 'Directory.ReadWrite.All'),
    @('Mail.ReadWrite'),
    @('Calendars.ReadWrite'),
    @('MailboxSettings.ReadWrite'),
    @('Files.ReadWrite.All', 'Sites.ReadWrite.All'),
    @('Teamwork.Migrate.All'),
    @('Group.ReadWrite.All', 'Directory.ReadWrite.All'),
    @('TeamMember.ReadWrite.All')
)
$script:Company = 'Zava Corporation'
$script:TeamExtension = 'com.vectorsense.helixHydration'
$script:Phase = 'start'
$script:Deadline = $null









# ------------------------------------------------------------------------------- pre-flight





function Get-TenantUsers {
    return Get-GraphAll -Path ('/users?$top=999&$select=id,userPrincipalName,displayName,givenName,surname,userType,accountEnabled,assignedLicenses,employeeId,companyName,usageLocation')
}

function Test-MailboxReady([string]$UserId) {
    try { return $null -ne (Invoke-Graph -Path "/users/$UserId/mailboxSettings" -Ok404) }
    catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if ($_.Exception.Status -in 400, 403) { return $false } throw }
}



# ------------------------------------------------------------------------------- personas





# ------------------------------------------------------------------------------- learner



# ------------------------------------------------------------------------------- people helpers







# ------------------------------------------------------------------------------- Teams











# ------------------------------------------------------------------------------- mail











# ------------------------------------------------------------------------------- calendar



# ------------------------------------------------------------------------------- entry point


# ---------------------------------------------------------------------------------------------
# Life cycle step before Pre-flight: choose the learner account in this launch's tenant and make
# sure it can use Copilot (Cowork).
#
# Every launch gets a freshly provisioned tenant, so no user name is assumed. In order:
#   1. the learner configured in the life cycle script (normally this launch's Office 365 admin,
#      from the AdministrativeUsername token), if that user exists;
#   2. a user marked as the learner by an earlier run (employeeId helix:learner);
#   3. otherwise the first licensed, enabled member account by UPN that is not an admin or a
#      Helix persona, preferring one whose mailbox is ready.
# The learner then gets a licence that includes Copilot if it has none: a free seat if there is
# one, otherwise a seat moved from a spare user, keeping enough licensed users for the Helix
# meeting organisers. The learner is marked and published as lab variable LearnerUpn.
#
# Copilot Cowork itself (enabled for the tenant, Copilot credits) is tenant set-up that has no
# Graph API; it must come with the tenant.
# ---------------------------------------------------------------------------------------------

$script:LearnerMarker = 'helix:learner'

function Test-LearnerCandidate($User) {
    return @($User.assignedLicenses).Count -gt 0 -and $User.accountEnabled -and $User.userType -ne 'Guest' -and
        $User.userPrincipalName -notmatch '#EXT#' -and $User.userPrincipalName -notmatch '^(admin|administrator)@' -and
        "$($User.displayName)" -notmatch 'admin' -and -not ("$($User.employeeId)" -like 'helix:*')
}

function Get-CopilotSkus {
    <# Subscribed licences whose service plans include Copilot. #>
    return @(@((Invoke-Graph -Path '/subscribedSkus').value) | Where-Object {
            @($_.servicePlans | Where-Object { $_.servicePlanName -match 'COPILOT' }).Count -gt 0 })
}

function Grant-CopilotLicence {
    <#
      Gives the learner a licence that includes Copilot if it has none. Uses a free seat when there is
      one; otherwise moves a seat from the last spare licensed user by UPN (organiser hosts are taken
      from the first), keeping at least $KeepHosts licensed users for the meeting organisers.
    #>
    param([Parameter(Mandatory)]$Learner, [Parameter(Mandatory)][object[]]$Users, [int]$KeepHosts = 6)
    $skus = @(Get-CopilotSkus)   # @(): a tenant with one licence type still gives a list
    if (-not $skus) { throw 'No licence in this tenant includes Microsoft 365 Copilot, so the learner cannot use Cowork. The tenant needs Copilot licences.' }
    $held = @($Learner.assignedLicenses | ForEach-Object { $_.skuId })
    $has = @($skus | Where-Object { $held -contains $_.skuId })[0]
    if ($has) { Write-Output "Learner already has Copilot ($($has.skuPartNumber))."; return }

    # A licence needs a usage location.
    $me = Invoke-Graph -Path "/users/$($Learner.id)?`$select=id,usageLocation"
    if (-not $me.usageLocation) {
        $loc = @($Users | Where-Object { $_.usageLocation } | ForEach-Object { $_.usageLocation })[0]
        if (-not $loc) { $loc = 'US' }
        Invoke-Graph -Method PATCH -Path "/users/$($Learner.id)" -Body @{ usageLocation = $loc } | Out-Null
    }

    $free = @($skus | Where-Object { [int]$_.prepaidUnits.enabled - [int]$_.consumedUnits -gt 0 })[0]
    if ($free) { $sku = $free; $from = 'a free seat' }
    else {
        $sku = $skus[0]
        $spare = @($Users | Where-Object { $_.id -ne $Learner.id -and (Test-LearnerCandidate $_) -and @($_.assignedLicenses | Where-Object { $_.skuId -eq $sku.skuId }).Count } |
                Sort-Object userPrincipalName)
        if ($spare.Count -le $KeepHosts) {
            throw "No free $($sku.skuPartNumber) seat for the learner, and only $($spare.Count) licensed users (the Helix meeting organisers need $KeepHosts)."
        }
        $donor = $spare[-1]
        Invoke-Graph -Method POST -Path "/users/$($donor.id)/assignLicense" -Body @{ addLicenses = @(); removeLicenses = @($sku.skuId) } | Out-Null
        $from = "the seat of $($donor.userPrincipalName)"
    }
    Invoke-Graph -Method POST -Path "/users/$($Learner.id)/assignLicense" -Body @{ addLicenses = @(@{ skuId = $sku.skuId; disabledPlans = @() }); removeLicenses = @() } | Out-Null
    Write-Output "Assigned $($sku.skuPartNumber) (includes Copilot) to the learner from $from. Mailbox and Copilot can take a few minutes to appear."
}

function Resolve-Learner {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        # Configured learner (normally the tenant admin), or empty / 'auto' / an unfilled Skillable token to choose automatically.
        [string]$Preferred
    )
    Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $users = @(Get-TenantUsers)

    $chosen = $null
    if ($Preferred -and $Preferred -ne 'auto' -and $Preferred -notmatch '@lab\.\w+\(') {
        $chosen = @($users | Where-Object { $_.userPrincipalName -eq $Preferred })[0]
        $how = 'configured'
        if (-not $chosen) { Write-Output "Configured learner $Preferred not found; choosing automatically." }
    }
    if (-not $chosen) {
        $chosen = @($users | Where-Object { $_.employeeId -eq $script:LearnerMarker })[0]
        $how = 'chosen on an earlier run'
    }
    if (-not $chosen) {
        $candidates = @($users | Where-Object { Test-LearnerCandidate $_ } | Sort-Object userPrincipalName)
        if (-not $candidates) { throw 'No licensed, enabled, non-admin user in this tenant to use as the learner.' }
        $chosen = @($candidates | Where-Object { Test-MailboxReady $_.id })[0]
        if (-not $chosen) { $chosen = $candidates[0] }
        $how = "chosen automatically from $($candidates.Count) licensed users"
    }
    Write-Output "Learner: $($chosen.userPrincipalName) ($how)"

    # Only one learner marker: clear it from anyone else (a re-run with a different configuration).
    foreach ($old in @($users | Where-Object { $_.employeeId -eq $script:LearnerMarker -and $_.id -ne $chosen.id })) {
        Invoke-Graph -Method PATCH -Path "/users/$($old.id)" -Body @{ employeeId = $null } | Out-Null
    }
    if ($chosen.employeeId -ne $script:LearnerMarker) {
        Invoke-Graph -Method PATCH -Path "/users/$($chosen.id)" -Body @{ employeeId = $script:LearnerMarker } | Out-Null
    }
    Grant-CopilotLicence -Learner $chosen -Users $users
    Set-LabVariable -Name LearnerUpn -Value $chosen.userPrincipalName
}
# ===== Run =====
Resolve-Learner -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Preferred $LearnerUpn