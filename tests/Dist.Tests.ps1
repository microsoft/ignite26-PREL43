# Runs the built package in skillable/ (the exact files that go into Skillable and onto the HelixKit
# media) with the fake tenant injected in place of Microsoft Graph.
BeforeAll {
    $root = Join-Path $PSScriptRoot '..'
    $script:Pkg = (Resolve-Path (Join-Path $root 'skillable')).Path
    $script:Kit = Join-Path $Pkg 'media' 'HelixKit'
    $script:Runner = Join-Path $root 'tools' 'Invoke-Local.ps1'
    $script:Inject = Join-Path ([IO.Path]::GetTempPath()) "fake-inject-$PID.ps1"
    if (-not (Test-Path (Join-Path $Kit 'Hydrate.ps1'))) { throw 'Run ./build/Build.ps1 -CloudCredential X first.' }
    # Shared fake tenant across script runs: the injected file reuses the tenant in $global:FakeState.
    Set-Content -Path $Inject -Value @"
. '$(Join-Path $PSScriptRoot 'FakeGraph.ps1')'
if (-not `$global:FakeState) { [void](New-FakeTenant); `$global:FakeState = `$script:FakeTenant } else { `$script:FakeTenant = `$global:FakeState }
"@
    $script:Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $script:Common = @{ TenantId = 't'; ClientId = 'c'; ClientSecret = 's'; LearnerUpn = 'labuser@lab.test'
        EventDate = $Today; EventTimeZone = 'UTC'; Inject = $Inject; Quiet = $true }
    function Invoke-Pkg([string]$Rel) { & $script:Runner -Script (Join-Path $script:Pkg $Rel) @script:Common }
    # A kit script as the launcher runs it: parameters in, "##LABVAR name=value" lines out.
    function Invoke-Kit([string]$Name) {
        $text = (Get-Content -Raw (Join-Path $script:Kit $Name)).Replace('# ===== Run =====', ". '$script:Inject'`n# ===== Run =====")
        $env:HELIXKIT_CLIENT_SECRET = 's'
        try { return @(& ([scriptblock]::Create($text)) -TenantId t -ClientId c -LearnerUpn labuser@lab.test -EventDate $script:Today -EventTimeZone UTC 4>$null 6>$null) }
        finally { Remove-Item Env:\HELIXKIT_CLIENT_SECRET }
    }
    $global:FakeState = $null
}
AfterAll { Remove-Item $script:Inject -ErrorAction SilentlyContinue; $global:FakeState = $null }

Describe 'Scripts pasted into Skillable' {
    It 'use Skillable tokens for secrets, never literal values' {
        foreach ($f in Get-ChildItem $Pkg -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notlike "$Kit*" }) {
            (Get-Content -Raw $f.FullName) | Should -Match "\`$ClientSecret\s+= '@lab\.CloudCredential\([^)]+\)\.ClientSecret'" -Because $f.Name
        }
    }
    It 'are pure ASCII (Skillable''s editor corrupts curly quotes and other non-ASCII characters)' {
        foreach ($f in Get-ChildItem $Pkg -Recurse -Filter *.ps1) {
            [IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1 | Should -BeNullOrEmpty -Because $f.Name
        }
    }
    It 'are small enough to pass to pwsh as one argument (under 32 KB)' {
        foreach ($f in Get-ChildItem (Join-Path $Pkg 'activities'), (Join-Path $Pkg 'lifecycle'), (Join-Path $Pkg 'optional') -Recurse -Filter *.ps1) {
            $f.Length | Should -BeLessThan 32KB -Because $f.Name
        }
    }
    It 'still parse their embedded JSON after a paste that straightens quotes' {
        $t = Get-Content -Raw (Join-Path $Pkg 'activities/M1/1-drafts-saved.ps1')
        $json = [regex]::Match($t, "(?s)\`$script:Scorecard = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
        $expected = (Get-Content -Raw (Join-Path $PSScriptRoot '..' 'config' 'scorecard.json') | ConvertFrom-Json -AsHashtable).checks[0]
        $embedded = ($json | ConvertFrom-Json -AsHashtable).checks[0]
        $embedded.passes_when | Should -Be $expected.passes_when
        $embedded.hint | Should -Be $expected.hint
    }
}

Describe 'Life cycle launcher (Prepare-Helix-Workspace.ps1)' {
    BeforeAll { $script:L = Get-Content -Raw (Join-Path $Pkg 'lifecycle/Prepare-Helix-Workspace.ps1') }
    It 'parses, has every placeholder filled, and uses no PowerShell 7-only syntax (it runs in Windows PowerShell 5.1)' {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($L, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $L | Should -Not -Match '__[A-Z]+__'
        $L | Should -Match ([regex]::Escape("-ne '$((Get-Content -Raw (Join-Path $PSScriptRoot '..' 'VERSION')).Trim())'")) -Because 'it refuses an ISO of another version'
        $ops = $tokens | Where-Object { $_.Kind -in 'QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr' }
        $ops | Should -BeNullOrEmpty
        $tokens | Where-Object { $_.Kind -eq 'QuestionMark' } | Should -BeNullOrEmpty -Because 'ternary operator is PowerShell 7 only'
    }
    It 'passes secrets through the environment, not the command line, and runs Grant first' {
        $L | Should -Match 'HELIXKIT_CLIENT_SECRET'
        $L | Should -Match 'HELIXKIT_ADMIN_PASSWORD'
        $L | Should -Not -Match '-ClientSecret \$ClientSecret'
        $L | Should -Not -Match '-AdminPassword'
        $L | Should -Match "@\('Grant', 'Learner', 'Preflight', 'Hydrate', 'Readiness'\)"
        $L | Should -Match "LearnerUpn\s+= 'admin'"
        $L | Should -Match "if \(\`$LearnerUpn -eq 'admin'\) \{ \`$LearnerUpn = \`$AdminUser \}"
        $L | Should -Match "TAP\|Password\|Secret.*\*\*\*\*" -Because 'secrets are masked in the log'
    }
}

Describe 'HelixKit media' {
    It 'has the kit marker the launcher looks for' {
        (Get-Content -Raw (Join-Path $Kit 'kit.json') | ConvertFrom-Json).name | Should -Be 'HelixKit'
    }
    It 'runs pre-flight, hydrate and readiness in order and reports the lab variables' {
        $out = @(Invoke-Kit 'Grant.ps1') + @(Invoke-Kit 'Learner.ps1') + @(Invoke-Kit 'Preflight.ps1') + @(Invoke-Kit 'Hydrate.ps1') + @(Invoke-Kit 'Readiness.ps1')
        $vars = @($out | ForEach-Object { "$_" } | Where-Object { $_ -match '^##LABVAR ' })
        $vars | Should -Contain '##LABVAR PermissionStatus=ok'
        $vars | Should -Contain '##LABVAR LearnerUpn=labuser@lab.test'
        $vars | Should -Contain '##LABVAR PreflightStatus=ok'
        $vars | Should -Contain '##LABVAR HydrationStatus=ok'
        $vars | Should -Contain '##LABVAR ReadinessStatus=ok'
        $global:FakeState.Mail[($global:FakeState.Users.Values | Where-Object userPrincipalName -eq 'labuser@lab.test').id].inbox.Count | Should -Be 35
    }
    It 'is safe to run again (pre-built instance re-run)' {
        { Invoke-Kit 'Hydrate.ps1' } | Should -Not -Throw
        $global:FakeState.Mail[($global:FakeState.Users.Values | Where-Object userPrincipalName -eq 'labuser@lab.test').id].inbox.Count | Should -Be 35
    }
    It 'Score-All prints the scorecard with the baseline score' {
        $json = (Invoke-Kit 'Score-All.ps1' | ForEach-Object { "$_" }) -join "`n" | ConvertFrom-Json
        $json.score | Should -Be 10
    }
}

Describe 'Check my work activities' {
    It 'score every check Incorrect except "third block cancelled" before any work' {
        foreach ($f in Get-ChildItem (Join-Path $Pkg 'activities') -Recurse -Filter *.ps1) {
            Invoke-Pkg ($f.FullName.Substring($Pkg.Length + 1))
            $expected = $f.Name -match 'third-block-cancelled'
            $global:LastActivityResult.Correct | Should -Be $expected -Because $f.Name
            $global:LastActivityResult.Message | Should -Not -Match "couldn't check" -Because $f.Name
        }
    }
    It 'read the learner from the lab variable the life cycle action sets' {
        (Get-Content -Raw (Join-Path $Pkg 'activities/M1/1-drafts-saved.ps1')) | Should -Match "LearnerUpn\s+= '@lab\.Variable\(LearnerUpn\)'"
        $guide = Get-Content -Raw (Join-Path $Pkg 'Lab-Instructions.md')
        $guide | Should -Match '@lab\.CloudCredential\(WWLM365E7\)\.AdministrativeUsername' -Because 'learners sign in as the Office 365 admin'
        $guide | Should -Match '@lab\.CloudCredential\(WWLM365E7\)\.AdministrativePassword'
        $guide | Should -Not -Match 'AlexW|@lab\.Variable\(TAP\)'
    }
    It 'work without an event date (they never need editing between events)' {
        (Get-Content -Raw (Join-Path $Pkg 'activities/M1/1-drafts-saved.ps1')) | Should -Not -Match '(?m)^\$EventDate\s*='
    }
    It 'run the optional TAP scripts' {
        { Invoke-Pkg 'optional/TapPolicy.ps1' } | Should -Not -Throw
        { Invoke-Pkg 'optional/TapIssue.ps1' } | Should -Not -Throw
    }
}
