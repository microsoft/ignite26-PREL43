# ---------------------------------------------------------------------------------------------
# Scored Activity script: one scorecard check. The build generates one copy per check with
# $CheckId set, and each script's score value in Skillable is that check's points.
#
# The learner clicks "Check my work"; this script reads their Microsoft 365 data and reports
# Correct (with what was found) or Incorrect (with the check's hint).
# ---------------------------------------------------------------------------------------------

function Set-CheckResult([bool]$Correct, [string]$Message) {
    # Set-ActivityResult -Message is not documented everywhere; fall back to plain output.
    try {
        if ($Correct) { Set-ActivityResult -Correct -Message $Message } else { Set-ActivityResult -Incorrect -Message $Message }
    }
    catch [System.Management.Automation.ParameterBindingException] {
        if ($Correct) { Set-ActivityResult -Correct } else { Set-ActivityResult -Incorrect }
        Write-Output $Message
    }
}

function Invoke-ActivityCheck {
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$LearnerUpn,
        [string]$EventDate,
        [string]$EventTimeZone
    )
    $script:GraphRetryBudgetSeconds = 40
    # Checks only use the event day for the calendar window (D-1 .. D+14). Without one, today is used,
    # so the 12 check scripts never need editing between events.
    if (-not $EventTimeZone -or $EventTimeZone -match '^@lab') { $EventTimeZone = 'UTC' }
    if (-not $EventDate -or $EventDate -notmatch '^\d{4}-\d{2}-\d{2}$') { $EventDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
    $check = $script:Scorecard.checks | Where-Object { $_.id -eq $CheckId }
    if (-not $check) { throw "Check '$CheckId' is not in the embedded scorecard." }
    if ($LearnerUpn -notmatch '^[^@\s]+@[^@\s]+$') {
        # The lab variable LearnerUpn is set by the "Prepare Helix workspace" life cycle action.
        Set-CheckResult $false "Your lab isn't ready yet. Tell your proctor."
        Write-Output "Details: LearnerUpn is '$LearnerUpn'."
        return
    }
    try {
        Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $tl = New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone
        $ctx = New-ScoreContext -LearnerUpn $LearnerUpn -Timeline $tl -Scorecard $script:Scorecard
        $r = Test-ScoreCheck $ctx $check
    }
    catch {
        # A Graph outage must not cost the learner points permanently: they can simply check again.
        Set-CheckResult $false "We couldn't check this right now. Wait 1 minute, then select Check my work again."
        Write-Output "Details: $($_.Exception.Message)"
        return
    }
    if ($r.passed) { Set-CheckResult $true "Done. $($check.passes_when)" }
    else { Set-CheckResult $false "Not yet. $($check.hint)" }
}
