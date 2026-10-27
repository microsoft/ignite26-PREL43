# Choosing the learner in a freshly provisioned tenant (no user name assumed).
BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src'
    foreach ($f in 'common/Graph.ps1', 'common/Timeline.ps1', 'common/Text.ps1', 'common/DataPack.ps1', 'lifecycle/Hydrate.ps1', 'lifecycle/Learner.ps1') { . (Join-Path $src $f) }
    . (Join-Path $PSScriptRoot 'FakeGraph.ps1')
    $script:Cred = @{ TenantId = 't'; ClientId = 'c'; ClientSecret = 's' }
    function Set-LabVariable { param($Name, $Value) $script:LabVars[$Name] = $Value }
    function Get-Marked { @($script:FakeTenant.Users.Values | Where-Object { $_.employeeId -eq 'helix:learner' }) }
}

Describe 'Learner selection' {
    BeforeEach { [void](New-FakeTenant); $script:LabVars = @{} }

    It 'picks the first licensed, non-admin user by UPN when set to auto, and marks it' {
        $out = Resolve-Learner @Cred -Preferred 'auto'
        $LabVars.LearnerUpn | Should -Be 'AlexW@lab.test'
        "$out" | Should -Match 'chosen automatically'
        (Get-Marked).userPrincipalName | Should -Be 'AlexW@lab.test'
    }
    It 'treats an unfilled Skillable token as auto' {
        Resolve-Learner @Cred -Preferred '@lab.Variable(Learner)' | Out-Null
        $LabVars.LearnerUpn | Should -Be 'AlexW@lab.test'
    }
    It 'never picks the admin or a disabled or unlicensed account' {
        foreach ($u in $script:FakeTenant.Users.Values) {
            if ($u.userPrincipalName -ne 'admin@lab.test' -and $u.userPrincipalName -ne 'labuser@lab.test') { $u.accountEnabled = $false }
        }
        $lab = $script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'labuser@lab.test'
        Resolve-Learner @Cred -Preferred 'auto' | Out-Null
        $LabVars.LearnerUpn | Should -Be 'labuser@lab.test'
        $lab.assignedLicenses = @()
        $lab.employeeId = $null
        { Resolve-Learner @Cred -Preferred 'auto' } | Should -Throw '*No licensed*'
    }
    It 'uses the configured learner when it exists and is licensed' {
        Resolve-Learner @Cred -Preferred 'labuser@lab.test' | Out-Null
        $LabVars.LearnerUpn | Should -Be 'labuser@lab.test'
    }
    It 'uses the tenant admin when configured, even though auto never picks admins' {
        $out = Resolve-Learner @Cred -Preferred 'admin@lab.test'
        $LabVars.LearnerUpn | Should -Be 'admin@lab.test'
        "$out" | Should -Match 'already has Copilot'
    }
    It 'gives an unlicensed admin a free Copilot seat, with a usage location' {
        [void](New-FakeTenant -AdminUnlicensed -FreeSeats 1)
        $out = Resolve-Learner @Cred -Preferred 'admin@lab.test'
        "$out" | Should -Match 'from a free seat'
        $admin = $script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'admin@lab.test'
        $admin.assignedLicenses.skuId | Should -Be 'e7-sku'
        $admin.usageLocation | Should -Be 'IN'
        $admin.mailbox | Should -BeTrue
    }
    It 'moves a seat from the last spare user when none is free, keeping 6 organiser hosts' {
        [void](New-FakeTenant -AdminUnlicensed)
        $out = Resolve-Learner @Cred -Preferred 'admin@lab.test'
        "$out" | Should -Match 'from the seat of PattiF@lab.test'
        ($script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'PattiF@lab.test').assignedLicenses | Should -BeNullOrEmpty
        ($script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'admin@lab.test').assignedLicenses.skuId | Should -Be 'e7-sku'
    }
    It 'stops clearly when no seat can be spared' {
        [void](New-FakeTenant -AdminUnlicensed -LicensedUsers 5)
        { Resolve-Learner @Cred -Preferred 'admin@lab.test' } | Should -Throw '*No free Microsoft_365_E7 seat*need 6*'
    }
    It 'stops clearly when the tenant has no Copilot licence at all' {
        [void](New-FakeTenant -AdminUnlicensed -FreeSeats 1)
        $script:FakeTenant.Skus[0].servicePlans = @(@{ servicePlanName = 'EXCHANGE_S_ENTERPRISE' })
        { Resolve-Learner @Cred -Preferred 'admin@lab.test' } | Should -Throw '*includes Microsoft 365 Copilot*'
    }
    It 'falls back to automatic when the configured learner does not exist' {
        $out = Resolve-Learner @Cred -Preferred 'nobody@lab.test'
        "$out" | Should -Match 'not found'
        $LabVars.LearnerUpn | Should -Be 'AlexW@lab.test'
    }
    It 'keeps the same learner on a re-run, and moves the mark when the configured learner changes' {
        Resolve-Learner @Cred -Preferred 'auto' | Out-Null
        Resolve-Learner @Cred -Preferred 'auto' | Out-Null
        $LabVars.LearnerUpn | Should -Be 'AlexW@lab.test'
        Resolve-Learner @Cred -Preferred 'admin@lab.test' | Out-Null
        $LabVars.LearnerUpn | Should -Be 'admin@lab.test'
        (Get-Marked).userPrincipalName | Should -Be 'admin@lab.test'
    }
    It 'leaves the learner out of the organiser hosts during hydration' {
        Resolve-Learner @Cred -Preferred 'auto' | Out-Null
        $script:HelixPackEmbedded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..' 'datapack' 'helix-datapack-1.0.0.json.gz')))
        $learner = $script:FakeTenant.Users.Values | Where-Object userPrincipalName -eq 'AlexW@lab.test'
        $map = Sync-Personas -Pack (Get-HelixPack) -Learner $learner -Domain 'lab.test'
        $map.Values.upn | Should -Not -Contain 'AlexW@lab.test'
        $learner.employeeId | Should -Be 'helix:learner'
    }
}
