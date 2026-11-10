# =============================================================================================
# Enable TAP + issue the admin's TAP  (Cowork Lab COWORK-T1, kit v1.0.6)
# Skillable life cycle action: Execute Script in Cloud Platform, PowerShell, Post-Build,
# Blocking: Yes, Error Action: End Lab.
#
# Skillable's "Enable TAP Prereqs + Generate TAP" script for the tenant admin, unchanged except:
# the pass lasts 48 hours (2880 minutes) instead of 8, so a lab pre-built on D-1 still has a valid
# TAP on D. Enables the tenant TAP policy, grants this app's service principal Privileged
# Authentication Administrator (needed for a TAP on an admin), then issues a Temporary Access Pass
# for the admin and publishes it to the lab variable TAP2, which the lab guide shows.
#
# Graph APPLICATION permissions on the cloud credential, admin-consented:
#   RoleManagement.ReadWrite.Directory, Policy.ReadWrite.AuthenticationMethod,
#   UserAuthenticationMethod.ReadWrite.All
# =============================================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TenantId     = '@lab.CloudCredential(WWLM365E7).TenantId'
$ClientId     = '@lab.CloudCredential(WWLM365E7).ClientId'
$ClientSecret = '@lab.CloudCredential(WWLM365E7).ClientSecret'
$TapUserUpn   = '@lab.CloudCredential(WWLM365E7).AdministrativeUsername'

$Graph     = 'https://graph.microsoft.com/v1.0'
$PaaRoleId = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'   # Privileged Authentication Administrator (same in every tenant)
$PolicyUri = "$Graph/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass"

$Policy = @{
    '@odata.type'            = '#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration'
    state                    = 'enabled'
    isUsableOnce             = $false
    defaultLength            = 8
    defaultLifetimeInMinutes = 2880
    minimumLifetimeInMinutes = 60
    maximumLifetimeInMinutes = 2880
    includeTargets           = @(@{ targetType = 'group'; id = 'all_users'; isRegistrationRequired = $false })
}

# The issued TAP must agree with the policy above, so take both values from it.
$Lifetime = $Policy.defaultLifetimeInMinutes
$OneTime  = $Policy.isUsableOnce

function Get-Token {
    (Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://graph.microsoft.com/.default'
        }).access_token
}

# Fresh token per attempt: new-tenant grants take time to propagate and are baked into the token.
function Invoke-WithRetry {
    param([scriptblock]$Action)
    for ($i = 1; $i -le 5; $i++) {
        try   { return & $Action @{ Authorization = "Bearer $(Get-Token)" } }
        catch { if ($i -eq 5) { throw }; Start-Sleep -Seconds 15 }
    }
}

# 1. Self-assign Privileged Authentication Administrator (idempotent).
$RoleCreated = Invoke-WithRetry {
    param($h)
    $spId = (Invoke-RestMethod -Headers $h -Uri "$Graph/servicePrincipals(appId='$ClientId')").id
    $has  = (Invoke-RestMethod -Headers $h -Uri "$Graph/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spId' and roleDefinitionId eq '$PaaRoleId'").value
    if ($has) { return $false }
    Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/json' `
        -Uri "$Graph/roleManagement/directory/roleAssignments" `
        -Body (@{ principalId = $spId; roleDefinitionId = $PaaRoleId; directoryScopeId = '/' } | ConvertTo-Json) | Out-Null
    return $true
}

# 2. Enable the tenant TAP policy.
Invoke-WithRetry {
    param($h)
    Invoke-RestMethod -Method Patch -Headers $h -Uri $PolicyUri -ContentType 'application/json' `
        -Body ($Policy | ConvertTo-Json -Depth 5) | Out-Null
}

# A brand-new role assignment needs a moment before the TAP call will honour it.
if ($RoleCreated) { Start-Sleep -Seconds 30 }

# 3. Delete any existing TAP first (a user may hold only one), then issue a fresh one.
$MethodsUri = "$Graph/users/$([uri]::EscapeDataString($TapUserUpn))/authentication/temporaryAccessPassMethods"
$tap = Invoke-WithRetry {
    param($h)
    foreach ($m in (Invoke-RestMethod -Headers $h -Uri $MethodsUri).value) {
        Invoke-RestMethod -Method Delete -Headers $h -Uri "$MethodsUri/$($m.id)" | Out-Null
    }
    Invoke-RestMethod -Method Post -Headers $h -Uri $MethodsUri -ContentType 'application/json' `
        -Body (@{ lifetimeInMinutes = $Lifetime; isUsableOnce = $OneTime } | ConvertTo-Json)
}

Set-LabVariable -Name TAP2 -Value $tap.temporaryAccessPass