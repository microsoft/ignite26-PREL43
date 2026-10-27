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
