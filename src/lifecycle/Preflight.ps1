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
