# ---------------------------------------------------------------------------------------------
# Life cycle actions for sign-in with a Temporary Access Pass (TAP).
#
#   Invoke-TapPolicy (Post-Build): optionally self-assigns Privileged Authentication Administrator
#     to the credential's service principal (needed only when the learner holds an admin role),
#     then enables the tenant TAP policy. Idempotent.
#   Invoke-TapIssue (Running Preinstance Assigned To User): replaces any existing TAP on the
#     learner and stores the new one in the lab variable TAP, so the lab guide can show it.
# Split from the existing Skillable "Enable TAP Prereqs + Generate TAP" action, so the pass is
# issued when the participant is assigned the lab rather than at pre-build.
# ---------------------------------------------------------------------------------------------

$script:PrivilegedAuthAdminRoleId = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'   # constant in every tenant

function Invoke-TapPolicy {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [int]$LifetimeMinutes = 480,
        [switch]$AssignPrivilegedAuthAdmin
    )
    Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $roleCreated = $false
    if ($AssignPrivilegedAuthAdmin) {
        $spId = (Invoke-Graph -Path "/servicePrincipals(appId='$ClientId')?`$select=id").id
        $has = @((Invoke-Graph -Path "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spId' and roleDefinitionId eq '$script:PrivilegedAuthAdminRoleId'").value)
        if (-not $has) {
            Invoke-Graph -Method POST -Path '/roleManagement/directory/roleAssignments' -Body @{
                principalId = $spId; roleDefinitionId = $script:PrivilegedAuthAdminRoleId; directoryScopeId = '/'
            } | Out-Null
            $roleCreated = $true
        }
    }
    Invoke-Graph -Method PATCH -Path '/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass' -Body @{
        '@odata.type'            = '#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration'
        state                    = 'enabled'
        isUsableOnce             = $false
        defaultLength            = 8
        defaultLifetimeInMinutes = $LifetimeMinutes
        minimumLifetimeInMinutes = 60
        maximumLifetimeInMinutes = $LifetimeMinutes
        includeTargets           = @(@{ targetType = 'group'; id = 'all_users'; isRegistrationRequired = $false })
    } | Out-Null
    if ($roleCreated) { Start-Sleep -Seconds 30 }   # a new role assignment takes a moment to apply
}

function Invoke-TapIssue {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$LearnerUpn,
        [int]$LifetimeMinutes = 480
    )
    Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $methods = "/users/$([uri]::EscapeDataString($LearnerUpn))/authentication/temporaryAccessPassMethods"
    # A user can hold only one TAP: remove any earlier one, then issue a fresh pass.
    foreach ($m in @((Invoke-Graph -Path $methods).value)) {
        Invoke-Graph -Method DELETE -Path "$methods/$($m.id)" -Ok404 | Out-Null
    }
    $tap = $null
    for ($i = 1; $i -le 4 -and -not $tap; $i++) {
        try { $tap = (Invoke-Graph -Method POST -Path $methods -Body @{ lifetimeInMinutes = $LifetimeMinutes; isUsableOnce = $false }).temporaryAccessPass }
        catch { if ($i -eq 4) { throw } Start-Sleep -Seconds 15 }   # a just-enabled policy can take a few seconds
    }
    Set-LabVariable -Name TAP -Value $tap
    return $tap
}
