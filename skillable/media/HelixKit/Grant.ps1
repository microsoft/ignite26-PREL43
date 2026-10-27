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


# ---------------------------------------------------------------------------------------------
# Life cycle step before Pre-flight: make sure the cloud credential's app has the Microsoft Graph
# application permissions the lab needs, in this launch's fresh tenant.
#
# Signs in with the cloud credential first. If every permission is already there (the Skillable
# credential template has them), it does nothing. Otherwise it signs in as the tenant's admin
# (username and password of this launch, from Skillable tokens), grants only the missing
# permissions to the app, and waits until new app tokens carry them.
#
# The admin sign-in is non-interactive (resource owner password flow, Azure CLI public client),
# so it fails if the admin account must use MFA; the error says so.
# ---------------------------------------------------------------------------------------------

$script:AzureCliClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
$script:GraphAppId = '00000003-0000-0000-c000-000000000000'

function Get-AdminGraphToken([string]$TenantId, [string]$Username, [string]$Password) {
    $body = @{ grant_type = 'password'; client_id = $script:AzureCliClientId; resource = 'https://graph.microsoft.com'
        username = $Username; password = $Password }
    try {
        return (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
    }
    catch {
        $detail = "$($_.ErrorDetails.Message) $($_.Exception.Message)"
        $reason = switch -Regex ($detail) {
            'AADSTS50076|AADSTS50079|AADSTS50158' { 'the admin account requires MFA, so it cannot sign in from a script'; break }
            'AADSTS50126' { 'wrong admin username or password'; break }
            'AADSTS50034' { 'the admin user does not exist in this tenant'; break }
            'AADSTS50055' { 'the admin password has expired'; break }
            'AADSTS53003' { 'blocked by Conditional Access'; break }
            default { $detail.Trim() }
        }
        throw "Cannot sign in as tenant admin $Username`: $reason"
    }
}

function Invoke-AdminGraph([string]$Token, [string]$Method = 'GET', [string]$Path, $Body) {
    $p = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0$Path"; Headers = @{ Authorization = "Bearer $Token" } }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Compress); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p
}

function Get-MissingPermissions([switch]$IncludeTap) {
    <#
      For each requirement the app's token does not satisfy, the permission to grant: its first option,
      unless another option is already being granted (Mail.ReadWrite for hydration also covers Mail.Read).
    #>
    $grant = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $script:PermissionGroups.Keys) {
        if (-not $IncludeTap -and $group -like 'TAP:*') { continue }
        foreach ($req in $script:PermissionGroups[$group]) {
            $any = @($req)
            if (-not (Test-GraphRoles -Required @(, $any)) -or ($any | Where-Object { $grant.Contains($_) })) { continue }
            $grant.Add($any[0])
        }
    }
    return $grant.ToArray()
}

function Invoke-PermissionGrant {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [string]$AdminUser,
        [string]$AdminPassword,
        [switch]$IncludeTap,
        [int]$WaitSeconds = 600
    )
    try { Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret }
    catch { throw "Cannot sign in with the cloud credential (tenant $TenantId): $($_.Exception.Message)" }
    $missing = @(Get-MissingPermissions -IncludeTap:$IncludeTap)
    if (-not $missing.Count) { Write-Output 'All Microsoft Graph permissions already granted.'; return }
    Write-Output "Missing Microsoft Graph permissions: $($missing -join ', ')"
    # An unfilled Skillable token stays as text, e.g. @lab.CloudCredential(X).AdministrativePassword.
    if (-not $AdminUser -or -not $AdminPassword -or $AdminUser -match '@lab\.\w+\(' -or $AdminPassword -match '^@lab\.\w+\(') {
        throw "The cloud credential lacks $($missing -join ', ') and no tenant admin sign-in is configured to grant them. Ask Skillable to add them to the credential, or check the admin username/password tokens in the life cycle script."
    }

    $admin = Get-AdminGraphToken -TenantId $TenantId -Username $AdminUser -Password $AdminPassword
    $graph = @((Invoke-AdminGraph $admin GET "/servicePrincipals?`$filter=appId eq '$script:GraphAppId'&`$select=id,appRoles").value)[0]
    $sp = @((Invoke-AdminGraph $admin GET "/servicePrincipals?`$filter=appId eq '$ClientId'&`$select=id,displayName").value)[0]
    if (-not $sp) { throw "The cloud credential's app ($ClientId) has no service principal in tenant $TenantId." }
    $have = @(@((Invoke-AdminGraph $admin GET "/servicePrincipals/$($sp.id)/appRoleAssignments").value) | Where-Object { $_.resourceId -eq $graph.id } | ForEach-Object { $_.appRoleId })
    foreach ($perm in $missing) {
        $role = @($graph.appRoles | Where-Object { $_.value -eq $perm -and $_.allowedMemberTypes -contains 'Application' })[0]
        if (-not $role) { throw "$perm is not a Microsoft Graph application permission." }
        if ($have -contains $role.id) { continue }
        [void](Invoke-AdminGraph $admin POST "/servicePrincipals/$($sp.id)/appRoleAssignments" @{ principalId = $sp.id; resourceId = $graph.id; appRoleId = $role.id })
        Write-Output "Granted $perm to $($sp.displayName)"
    }

    # New permissions reach the app's tokens after replication (usually 1-5 minutes).
    $started = Get-Date
    while ($true) {
        Start-Sleep -Seconds 30
        [void](Get-GraphToken -Force)
        $still = @(Get-MissingPermissions -IncludeTap:$IncludeTap)
        if (-not $still.Count) { break }
        if (((Get-Date) - $started).TotalSeconds -gt $WaitSeconds) {
            throw "Permissions were granted but the app's token still lacks $($still -join ', ') after $([int]($WaitSeconds / 60)) minutes."
        }
    }
    Write-Output "Permissions active after $([int]((Get-Date) - $started).TotalSeconds) s."
}
# ===== Run =====
Invoke-PermissionGrant -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -AdminUser $env:HELIXKIT_ADMIN_USER -AdminPassword $env:HELIXKIT_ADMIN_PASSWORD
Set-LabVariable -Name PermissionStatus -Value 'ok'