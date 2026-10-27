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
