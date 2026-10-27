BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src'
    foreach ($f in 'common/Graph.ps1', 'common/Timeline.ps1', 'common/Text.ps1', 'common/DataPack.ps1', 'lifecycle/Preflight.ps1',
        'lifecycle/Hydrate.ps1', 'lifecycle/Readiness.ps1', 'lifecycle/Tap.ps1', 'scoring/Checks.ps1', 'scoring/Activity.ps1') { . (Join-Path $src $f) }
    . (Join-Path $PSScriptRoot 'FakeGraph.ps1')
    $root = Join-Path $PSScriptRoot '..'
    $script:HelixPackEmbedded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'datapack' 'helix-datapack-1.0.0.json.gz')))
    $script:Scorecard = Get-Content -Raw (Join-Path $root 'config' 'scorecard.json') | ConvertFrom-Json -AsHashtable -Depth 50
    $script:Readiness = Get-Content -Raw (Join-Path $root 'config' 'readiness.json') | ConvertFrom-Json -AsHashtable -Depth 50
    $script:TeamName = 'Zava Product Launches'

    # Event day = today in UTC, so the run is inside the hydration window.
    $script:EventDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $script:RunArgs = @{ TenantId = 't'; ClientId = 'c'; ClientSecret = 's'; LearnerUpn = 'labuser@lab.test'; EventDate = $EventDate; EventTimeZone = 'UTC' }

    function Get-Score { Invoke-Scorecard (New-ScoreContext -LearnerUpn 'labuser@lab.test' -Timeline (New-Timeline $EventDate 'UTC') -Scorecard $script:Scorecard) }
    function Get-Inbox($u) { @($script:FakeTenant.Mail[$u.id].inbox) }
    function Get-HelixGroup { @($script:FakeTenant.Groups.Values | Where-Object { $_.displayName -eq $script:TeamName }) }

    $script:Activity = [System.Collections.Generic.List[object]]::new()
    function Set-ActivityResult { param([switch]$Correct, [switch]$Incorrect, [string]$Message) $script:Activity.Add(@{ correct = [bool]$Correct; message = $Message }) }
    function Set-LabVariable { param($Name, $Value) $script:LabVars[$Name] = $Value }
    $script:LabVars = @{}
}

Describe 'Pre-flight' {
    It 'passes when the credential has every permission' {
        [void](New-FakeTenant)
        (Invoke-Preflight @RunArgs).ok | Should -BeTrue
    }
    It 'lists every missing permission and writes nothing' {
        [void](New-FakeTenant -Roles @('User.ReadWrite.All', 'Mail.ReadWrite'))
        $before = $script:FakeTenant.Users.Count
        { Invoke-Preflight @RunArgs } | Should -Throw '*Teamwork.Migrate.All*'
        try { Invoke-Preflight @RunArgs } catch { $msg = $_.Exception.Message }
        $msg | Should -Match 'nothing was written'
        $msg | Should -Match 'Calendars.ReadWrite'
        $msg | Should -Not -Match 'UserAuthenticationMethod' -Because 'the lab''s own TAP action issues the pass'
        { Invoke-Preflight @RunArgs -IncludeTap } | Should -Throw '*UserAuthenticationMethod.ReadWrite.All*'
        $script:FakeTenant.Users.Count | Should -Be $before
    }
    It 'fails when there are too few licensed users to host the organisers' {
        [void](New-FakeTenant -LicensedUsers 4)
        { Invoke-Preflight @RunArgs } | Should -Throw '*Needs 6 licensed users*found 4*'
    }
    It 'fails clearly when lab variables are not set' {
        [void](New-FakeTenant)
        $a = $RunArgs.Clone(); $a.EventDate = '@lab.Variable(EventDate)'
        { Invoke-Preflight @a } | Should -Throw '*EventDate is not set*'
    }
}

Describe 'Hydration, readiness and scoring on a fresh tenant' {
    BeforeAll {
        $script:Learner = New-FakeTenant
        $script:Result = Invoke-Hydration @RunArgs
    }

    It 'maps the six organisers onto licensed users and creates the rest of the cast' {
        $helix = @($script:FakeTenant.Users.Values | Where-Object { "$($_.employeeId)" -like 'helix:*' })
        $helix.Count | Should -Be 33            # 32 personas + reviewer
        $hosts = @($helix | Where-Object { @($_.assignedLicenses).Count -gt 0 })
        $hosts.Count | Should -Be 6
        ($hosts | ForEach-Object { $_.employeeId } | Sort-Object) -join ',' | Should -Be 'helix:chloe,helix:elena,helix:ethan,helix:grace,helix:nadia,helix:tomas'
        ($hosts | Where-Object employeeId -eq 'helix:grace').displayName | Should -Be 'Grace Liu'
        @($helix | Where-Object { $_.accountEnabled -and @($_.assignedLicenses).Count -eq 0 }).Count | Should -Be 0
        ($script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'admin@lab.test').employeeId | Should -BeNullOrEmpty
    }
    It 'sets the learner profile, time zone and manager' {
        $script:Learner.timeZone | Should -Be 'UTC'
        $script:Learner.jobTitle | Should -Be 'Helix Launch Lead'
        ($script:FakeTenant.Users[$script:Learner.manager]).employeeId | Should -Be 'helix:grace'
    }
    It 'writes 35 messages, threaded, with meeting requests removed' {
        $inbox = Get-Inbox $script:Learner
        $inbox.Count | Should -Be 35
        @($inbox | Where-Object { $_.'@odata.type' -match 'eventMessage' }).Count | Should -Be 0
        $supplier = @($inbox | Where-Object { $_.subject -match 'Helix sensor modules: capacity risk' })
        $supplier.Count | Should -Be 6
        @($supplier | ForEach-Object conversationId | Sort-Object -Unique).Count | Should -Be 1
        @($inbox | Where-Object { -not $_.isRead }).Count | Should -BeGreaterThan 0
    }
    It 'imports the private team with 20 channel messages and the learner as owner' {
        $g = @(Get-HelixGroup)
        $g.Count | Should -Be 1
        $g[0].visibility | Should -Be 'private'
        $g[0].migrated | Should -BeTrue
        $ch = $g[0].channels | Where-Object displayName -eq 'Launch - Helix'
        ($ch.messages | ForEach-Object { 1 + $_.replies.Count } | Measure-Object -Sum).Sum | Should -Be 20
        ($g[0].members | Where-Object id -eq $script:Learner.id).roles | Should -Contain 'owner'
    }
    It 'uploads the 8 channel files with a Recordings subfolder' {
        $d = $script:FakeTenant.Drives[@(Get-HelixGroup)[0].drive]
        @($d.items | Where-Object { $_.file }).Count | Should -Be 8
        @($d.items | Where-Object { $_.name -eq 'Recordings' }).Count | Should -Be 1
    }
    It 'places 8 meetings in the learner calendar, all accepted' {
        $evs = @($script:FakeTenant.Events[$script:Learner.id])
        $evs.Count | Should -Be 8
        @($evs | Where-Object { $_.responseStatus.response -ne 'accepted' }).Count | Should -Be 0
    }
    It 'passes the readiness check' {
        { Invoke-Readiness @RunArgs -TeamName $TeamName } | Should -Not -Throw
    }
    It 'scores 10 before the learner does anything (only "third block cancelled" passes)' {
        $s = Get-Score
        $s.score | Should -Be 10
        $s.checks['third-block-cancelled'] | Should -Be 10
    }
    It 'is safe to run again: nothing is duplicated' {
        $users = $script:FakeTenant.Users.Count
        [void](Invoke-Hydration @RunArgs)
        $script:FakeTenant.Users.Count | Should -Be $users
        (Get-Inbox $script:Learner).Count | Should -Be 35
        @($script:FakeTenant.Events[$script:Learner.id]).Count | Should -Be 8
        @(Get-HelixGroup).Count | Should -Be 1
    }
    It 'scores 100 after the learner completes M1-M5' {
        Add-FakeLearnerWork -Learner $script:Learner -EventDayUtc ([datetime]::SpecifyKind([datetime]$EventDate, 'Utc'))
        $s = Get-Score
        $s.score | Should -Be 100
        $s.passed | Should -BeTrue
    }
    It 'loses the 10 points when the third focus block is not cancelled' {
        $start = ([datetime]::SpecifyKind([datetime]$EventDate, 'Utc')).AddDays(1).AddHours(16)
        $script:FakeTenant.Events[$script:Learner.id].Add(@{ id = 'x'; iCalUId = 'x'; subject = 'Helix status review'; startUtc = $start; endUtc = $start.AddMinutes(30); isCancelled = $false; responseStatus = @{} })
        (Get-Score).checks['third-block-cancelled'] | Should -Be 0
    }
}

Describe 'Recovery from an interrupted run' {
    It 'rebuilds a team that was left half-imported' {
        $learner = New-FakeTenant
        $script:FakeTenant.FailNext = 'completeMigration'      # interrupt the team phase once
        { Invoke-Hydration @RunArgs } | Should -Throw
        @(Get-HelixGroup).Count | Should -Be 1
        [void](Invoke-Hydration @RunArgs)                           # Skillable's retry
        $g = @(Get-HelixGroup)
        $g.Count | Should -Be 1
        $g[0].migrated | Should -BeTrue
        ($g[0].channels | Where-Object displayName -eq 'Launch - Helix').messages.Count | Should -Be 13
        (Get-Inbox $learner).Count | Should -Be 35
    }
    It 'stops before writing anything outside the hydration window' {
        [void](New-FakeTenant)
        $a = $RunArgs.Clone(); $a.EventDate = (Get-Date).AddDays(4).ToString('yyyy-MM-dd')
        $before = $script:FakeTenant.Calls
        { Invoke-Hydration @a } | Should -Throw '*Outside the hydration window*'
        $script:FakeTenant.Calls | Should -Be $before
    }
    It 'fails the readiness check on a tenant that was never hydrated' {
        [void](New-FakeTenant)
        { Invoke-Readiness @RunArgs -TeamName $TeamName } | Should -Throw '*Readiness check failed*supplier-thread*'
    }
}

Describe 'Scored Activities' {
    BeforeAll {
        $script:Learner = New-FakeTenant
        [void](Invoke-Hydration @RunArgs)
    }
    It 'marks an unfinished check Incorrect with its hint' {
        $script:Activity.Clear()
        Invoke-ActivityCheck -CheckId 'risk-register-columns' @RunArgs
        $script:Activity[0].correct | Should -BeFalse
        $script:Activity[0].message | Should -Match '^Not yet\. Go to step 2\.1\..*"Source evidence" column'
    }
    It 'marks a finished check Correct' {
        Add-FakeLearnerWork -Learner $script:Learner -EventDayUtc ([datetime]::SpecifyKind([datetime]$EventDate, 'Utc'))
        $script:Activity.Clear()
        Invoke-ActivityCheck -CheckId 'risk-register-columns' @RunArgs
        $script:Activity[0].correct | Should -BeTrue
    }
    It 'asks the learner to retry when Graph is unavailable' {
        $script:Activity.Clear()
        $script:FakeTenant.FailNext = '/users/'
        Invoke-ActivityCheck -CheckId 'drafts-saved' @RunArgs
        $script:Activity[0].correct | Should -BeFalse
        $script:Activity[0].message | Should -Match 'Check my work again'
    }
}

Describe 'Temporary Access Pass' {
    It 'enables the policy, then issues one pass and stores it in a lab variable' {
        [void](New-FakeTenant)
        Invoke-TapPolicy -TenantId t -ClientId c -ClientSecret s
        $script:FakeTenant.TapPolicy.state | Should -Be 'enabled'
        $tap1 = Invoke-TapIssue -TenantId t -ClientId c -ClientSecret s -LearnerUpn 'labuser@lab.test'
        $tap2 = Invoke-TapIssue -TenantId t -ClientId c -ClientSecret s -LearnerUpn 'labuser@lab.test'   # re-run replaces it
        $tap2 | Should -Not -BeNullOrEmpty
        $script:LabVars['TAP'] | Should -Be $tap2
    }
}
