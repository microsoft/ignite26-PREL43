<#
.SYNOPSIS
  Builds everything the team pastes into Skillable, into skillable/.

.DESCRIPTION
  skillable/lifecycle/Prepare-Helix-Workspace.ps1
      The one life cycle action (Execute Script in Virtual Machine). Small launcher, Windows PowerShell
      5.1 compatible. Finds the HelixKit media in the VM and runs Pre-flight, Hydrate and Readiness.
  skillable/media/HelixKit/   (and HelixKit-<version>.iso when -Iso is used)
      Contents of the removable media: the full Pre-flight, Hydrate (with the Helix data pack inside),
      Readiness and Score-all scripts for PowerShell 7, plus a portable PowerShell 7.
  skillable/activities/M1..M5/
      The 12 "Check my work" scripts (Execute in Cloud Platform). Kept small: Skillable passes a
      script to pwsh as one command-line argument, and large scripts fail ("argument list too long").
  skillable/optional/
      Cloud-platform TAP scripts, if the lab's own TAP action is ever replaced.

  Scripts pasted into Skillable are pure ASCII (its editor corrupts curly quotes), compressed and
  contain only the functions they call.

.EXAMPLE
  ./build/Build.ps1 -CloudCredential WWLM365E7 -Iso
#>
param(
    [Parameter(Mandatory)][string]$CloudCredential,
    # Microsoft 365 learner account. 'admin': each launch's Office 365 admin (learners sign in with the
    # Administrative Username/Password). 'auto': a licensed non-admin user. Either way the life cycle
    # action publishes it as lab variable LearnerUpn, which the checks use. Or a fixed UPN.
    [string]$LearnerUpn = 'admin',
    [string]$EventDate = 'YYYY-MM-DD',
    [string]$EventTimeZone = 'India Standard Time',
    [string]$DataPack = (Join-Path $PSScriptRoot '..' 'datapack' 'helix-datapack-1.0.0.json.gz'),
    [string]$PwshZip = (Join-Path $PSScriptRoot '..' 'vendor' 'PowerShell-7.4.6-win-x64.zip'),
    [switch]$Iso,
    [string]$OutDir = (Join-Path $PSScriptRoot '..' 'skillable')
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src = Join-Path $root 'src'
Add-Type -AssemblyName System.IO.Compression
# Scripts that run after the life cycle action read the learner it chose from the lab variable.
$checkLearner = if ($LearnerUpn -in 'auto', 'admin') { '@lab.Variable(LearnerUpn)' } else { $LearnerUpn }
$version = (Get-Content -Raw (Join-Path $root 'VERSION')).Trim()

function Read-Source([string]$Rel) { return (Get-Content -Raw -Path (Join-Path $src $Rel)).TrimEnd() }

function ConvertTo-AsciiJson([string]$Json) {
    return [regex]::Replace($Json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}

function Compress-ScriptText([string]$Text) {
    <# Drops comment lines and blocks, blank lines and indentation; here-strings stay untouched. #>
    $out = [System.Collections.Generic.List[string]]::new()
    $inHere = $false; $inBlock = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if ($inHere) { $out.Add($line); if ($line -match "^'@") { $inHere = $false }; continue }
        $t = $line.Trim()
        if ($inBlock) { if ($t -match '#>\s*$') { $inBlock = $false }; continue }
        if ($t -match '^<#') { if ($t -notmatch '#>\s*$') { $inBlock = $true }; continue }
        if ($t -eq '' -or ($t -match '^#' -and $t -notmatch '^# =====')) { continue }
        $out.Add($t)
        if ($t -match "@'$") { $inHere = $true }
    }
    return ($out -join "`n")
}

function Remove-UnusedFunctions([string]$Library, [string]$Entry) {
    <# Keeps only the library functions reachable from the entry code (calls found via the PowerShell AST). #>
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Library, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "Library does not parse: $($errors[0].Message)" }
    $funcs = @{}
    foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Parent.Parent -eq $ast }, $false)) { $funcs[$f.Name] = $f }
    function Get-Calls($node) { $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } }
    $entryAst = [System.Management.Automation.Language.Parser]::ParseInput($Entry, [ref]$tokens, [ref]$errors)
    $keep = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($c in (Get-Calls $entryAst)) { $queue.Enqueue($c) }
    foreach ($st in $ast.EndBlock.Statements) { if ($st -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { foreach ($c in (Get-Calls $st)) { $queue.Enqueue($c) } } }
    while ($queue.Count) {
        $n = $queue.Dequeue()
        if ($funcs.ContainsKey($n) -and $keep.Add($n)) { foreach ($c in (Get-Calls $funcs[$n].Body)) { $queue.Enqueue($c) } }
    }
    $text = $Library
    foreach ($f in @($funcs.Values | Where-Object { -not $keep.Contains($_.Name) } | Sort-Object { $_.Extent.StartOffset } -Descending)) {
        $text = $text.Remove($f.Extent.StartOffset, $f.Extent.EndOffset - $f.Extent.StartOffset)
    }
    return $text
}

function Save-Text([string]$Path, [string]$Text, [switch]$Ascii) {
    if ($Ascii) {
        $bad = [regex]::Matches($Text, '[^\x00-\x7F]') | Select-Object -First 3
        if ($bad) { throw "$Path contains non-ASCII characters ($(($bad | ForEach-Object { 'U+{0:X4}' -f [int][char]$_.Value }) -join ', ')); Skillable's editor would corrupt them." }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $crlf = ($Text -replace "`r?`n", "`r`n")   # the team edits these on Windows
    [IO.File]::WriteAllText($Path, $crlf, [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ Path = $Path; KB = [math]::Round((Get-Item $Path).Length / 1KB, 1) }
}

function Get-Rel([string]$Path) { return $Path.Substring($OutDir.Length).TrimStart('/', '\').Replace('\', '/') }

# ------------------------------------------------------------------------------------------- inputs
$scorecard = Get-Content -Raw (Join-Path $root 'config' 'scorecard.json') | ConvertFrom-Json -AsHashtable
$readiness = Get-Content -Raw (Join-Path $root 'config' 'readiness.json') | ConvertFrom-Json -AsHashtable
$packBytes = [IO.File]::ReadAllBytes((Resolve-Path $DataPack))
$gz = [IO.Compression.GZipStream]::new([IO.MemoryStream]::new($packBytes), [IO.Compression.CompressionMode]::Decompress)
$pack = ([IO.StreamReader]::new($gz)).ReadToEnd() | ConvertFrom-Json -AsHashtable -Depth 50
$teamName = $pack.teams.team.display_name

$scorecardSlim = ConvertTo-AsciiJson ((@{ max = $scorecard.max; pass_mark = $scorecard.pass_mark; window = $scorecard.window
            checks = @($scorecard.checks | ForEach-Object { @{ id = $_.id; type = $_.type; params = $_.params; points = $_.points } }) }) | ConvertTo-Json -Depth 10 -Compress)
$readinessSlim = ConvertTo-AsciiJson ((@{ day_one = $readiness.day_one }) | ConvertTo-Json -Depth 10 -Compress)
function Get-JsonEmbed([string]$Var, [string]$Json) { return "`$script:$Var = @'`n$Json`n'@ | ConvertFrom-Json -AsHashtable -Depth 50" }

if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$built = @()

# ------------------------------------------------------------------------------------------- media kit (PowerShell 7, runs in the VM)
$kitDir = Join-Path $OutDir 'media' 'HelixKit'
$kitHeader = @"
# HelixKit v$version - runs in PowerShell 7 inside the lab VM, started by Prepare-Helix-Workspace.ps1.
param([string]`$TenantId, [string]`$ClientId, [string]`$ClientSecret = `$env:HELIXKIT_CLIENT_SECRET,
      [string]`$LearnerUpn, [string]`$EventDate, [string]`$EventTimeZone)
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$VerbosePreference = 'Continue'
if (`$PSStyle) { `$PSStyle.OutputRendering = 'PlainText' }
`$DataPackUrl = ''
# Lab variables are reported to the launcher, which sets them in Skillable.
function Set-LabVariable { param([string]`$Name, `$Value) Write-Output "##LABVAR `$Name=`$Value" }
"@
function New-KitScript([string]$Name, [string[]]$Library, [string[]]$Embeds, [string]$Run) {
    $lib = Remove-UnusedFunctions -Library (($Library | ForEach-Object { Read-Source $_ }) -join "`n") -Entry $Run
    $text = @($kitHeader, '# ===== Library =====', $lib) + ($Embeds | Where-Object { $_ }) + @('# ===== Run =====', $Run.Trim()) -join "`n"
    return Save-Text -Path (Join-Path $kitDir $Name) -Text $text
}
$cred = '-TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret'
$common = @('common/Graph.ps1', 'common/Timeline.ps1')

$built += New-KitScript 'Grant.ps1' ($common + @('lifecycle/Preflight.ps1', 'lifecycle/Grant.ps1')) @() @"
Invoke-PermissionGrant $cred -AdminUser `$env:HELIXKIT_ADMIN_USER -AdminPassword `$env:HELIXKIT_ADMIN_PASSWORD
Set-LabVariable -Name PermissionStatus -Value 'ok'
"@
$built += New-KitScript 'Learner.ps1' ($common + @('lifecycle/Hydrate.ps1', 'lifecycle/Learner.ps1')) @() @"
Resolve-Learner $cred -Preferred `$LearnerUpn
"@
$built += New-KitScript 'Preflight.ps1' ($common + 'lifecycle/Preflight.ps1') @() @"
`$r = Invoke-Preflight $cred -LearnerUpn `$LearnerUpn -EventDate `$EventDate -EventTimeZone `$EventTimeZone
Set-LabVariable -Name PreflightStatus -Value 'ok'
"@
$built += New-KitScript 'Hydrate.ps1' ($common + @('common/Text.ps1', 'common/DataPack.ps1', 'lifecycle/Hydrate.ps1')) @("`$script:HelixPackEmbedded = '$([Convert]::ToBase64String($packBytes))'") @"
try { `$r = Invoke-Hydration $cred -LearnerUpn `$LearnerUpn -EventDate `$EventDate -EventTimeZone `$EventTimeZone -DataPackUrl `$DataPackUrl }
catch { throw "Hydration failed during '`$script:Phase': `$(`$_.Exception.Message)" }
Set-LabVariable -Name HydrationStatus -Value 'ok'
Set-LabVariable -Name HydratedAt -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
"@
$built += New-KitScript 'Readiness.ps1' ($common + @('common/Text.ps1', 'scoring/Checks.ps1', 'lifecycle/Readiness.ps1')) @((Get-JsonEmbed 'Scorecard' $scorecardSlim), (Get-JsonEmbed 'Readiness' $readinessSlim)) @"
`$r = Invoke-Readiness $cred -LearnerUpn `$LearnerUpn -EventDate `$EventDate -EventTimeZone `$EventTimeZone -TeamName '$($teamName.Replace("'", "''"))'
Set-LabVariable -Name ReadinessStatus -Value 'ok'
"@
$built += New-KitScript 'Score-All.ps1' ($common + @('common/Text.ps1', 'scoring/Checks.ps1')) @(Get-JsonEmbed 'Scorecard' $scorecardSlim) @"
Connect-Graph $cred
`$ctx = New-ScoreContext -LearnerUpn `$LearnerUpn -Timeline (New-Timeline -EventDate `$EventDate -TimeZoneName `$EventTimeZone) -Scorecard `$script:Scorecard
Invoke-Scorecard `$ctx | ConvertTo-Json -Depth 5
"@
Set-Content -Path (Join-Path $kitDir 'kit.json') -Value (@{ name = 'HelixKit'; version = $version; datapack = $pack.manifest.version } | ConvertTo-Json) -Encoding utf8NoBOM
Save-Text -Path (Join-Path $kitDir 'README.txt') -Text @"
HelixKit v$version

Removable media for the Copilot Cowork lab (COWORK-T1). Attached to the lab VM; the life cycle action
"Prepare Helix workspace" (Prepare-Helix-Workspace.ps1) finds this folder and runs, in PowerShell 7:

  Grant.ps1       grants the cloud credential's app any missing Graph permissions (as tenant admin)
  Learner.ps1     sets the learner (the tenant admin) and gives it a Copilot licence (lab variable LearnerUpn)
  Preflight.ps1   checks Microsoft Graph permissions, learner and licences (writes nothing)
  Hydrate.ps1     writes the Helix launch story into the learner's Microsoft 365 (data pack inside)
  Readiness.ps1   confirms the day-one items and that no scoring check already passes
  Score-All.ps1   prints the whole scorecard as JSON (for testing)

pwsh\ holds a portable PowerShell 7, used when PowerShell 7 is not installed on the VM.
"@ | Out-Null
if (Test-Path $PwshZip) {
    New-Item -ItemType Directory -Force -Path (Join-Path $kitDir 'pwsh') | Out-Null
    Copy-Item $PwshZip (Join-Path $kitDir 'pwsh')
}
else { Write-Warning "Portable PowerShell zip not found at $PwshZip; the VM must have PowerShell 7 installed. Run ./tools/Get-PortablePwsh.ps1 first." }

# ------------------------------------------------------------------------------------------- launcher (pasted into Skillable)
$launcher = (Read-Source 'lifecycle/Launcher.ps1').Replace('__VERSION__', $version).Replace('__CRED__', $CloudCredential).
    Replace('__LEARNER__', $LearnerUpn).Replace('__EVENTDATE__', $EventDate).Replace('__TZ__', $EventTimeZone)
$built += Save-Text -Path (Join-Path $OutDir 'lifecycle' 'Prepare-Helix-Workspace.ps1') -Text $launcher -Ascii

# ------------------------------------------------------------------------------------------- activities (pasted into Skillable)
$settings = @"
`$TenantId     = '@lab.CloudCredential($CloudCredential).TenantId'
`$ClientId     = '@lab.CloudCredential($CloudCredential).ClientId'
`$ClientSecret = '@lab.CloudCredential($CloudCredential).ClientSecret'
`$LearnerUpn   = '$checkLearner'
"@
$i = @{}
foreach ($c in $scorecard.checks) {
    $i[$c.milestone] = 1 + [int]$i[$c.milestone]
    $one = ConvertTo-AsciiJson ((@{ max = $scorecard.max; pass_mark = $scorecard.pass_mark; window = $scorecard.window
                checks = @(@{ id = $c.id; type = $c.type; params = $c.params; points = $c.points; hint = $c.hint; passes_when = $c.passes_when }) }) | ConvertTo-Json -Depth 10 -Compress)
    $lib = $common + $(if ($c.type -eq 'drive_file_contains') { @('common/Text.ps1') } else { @() }) + @('scoring/Checks.ps1', 'scoring/Activity.ps1')
    $run = "Invoke-ActivityCheck -CheckId '$($c.id)' $cred -LearnerUpn `$LearnerUpn"
    $body = Remove-UnusedFunctions -Library (($lib | ForEach-Object { Read-Source $_ }) -join "`n") -Entry $run
    $text = @("# Check $($c.milestone) / $($c.id) ($($c.points) points) - Cowork Lab v$version. Execute in Cloud Platform, PowerShell 7.",
        "`$ErrorActionPreference = 'Stop'", "`$ProgressPreference = 'SilentlyContinue'", $settings, (Compress-ScriptText $body),
        (Get-JsonEmbed 'Scorecard' $one), '# ===== Run =====', $run) -join "`n"
    $built += Save-Text -Path (Join-Path $OutDir 'activities' $c.milestone "$($i[$c.milestone])-$($c.id).ps1") -Text $text -Ascii
}

# ------------------------------------------------------------------------------------------- lab instructions
$built += Save-Text -Path (Join-Path $OutDir 'Lab-Instructions.md') -Text ((Get-Content -Raw (Join-Path $root 'content' 'Lab-Instructions.md')).Replace('__CRED__', $CloudCredential))

# ------------------------------------------------------------------------------------------- optional cloud TAP scripts
foreach ($pair in @(@('TapPolicy', "Invoke-TapPolicy $cred"), @('TapIssue', "`$tap = Invoke-TapIssue $cred -LearnerUpn `$LearnerUpn"))) {
    $body = Remove-UnusedFunctions -Library ((@('common/Graph.ps1', 'lifecycle/Tap.ps1') | ForEach-Object { Read-Source $_ }) -join "`n") -Entry $pair[1]
    $text = @("# Optional: $($pair[0]) - only if the lab's own TAP action is replaced. Execute in Cloud Platform, PowerShell 7.",
        "`$ErrorActionPreference = 'Stop'", $settings, (Compress-ScriptText $body), '# ===== Run =====', $pair[1]) -join "`n"
    $built += Save-Text -Path (Join-Path $OutDir 'optional' "$($pair[0]).ps1") -Text $text -Ascii
}

# ------------------------------------------------------------------------------------------- ISO
if ($Iso) {
    # The ISO root holds the HelixKit folder, so the VM sees <drive>:\HelixKit\kit.json.
    $isoPath = Join-Path $OutDir "HelixKit-$version.iso"
    if ($IsMacOS) { & hdiutil makehybrid -quiet -iso -joliet -default-volume-name HELIXKIT -o $isoPath (Join-Path $OutDir 'media') }
    elseif (Get-Command oscdimg -ErrorAction SilentlyContinue) { & oscdimg -n -m -lHELIXKIT (Join-Path $OutDir 'media') $isoPath }
    else { Write-Warning 'No ISO tool found (hdiutil on macOS, oscdimg on Windows). Upload the media\HelixKit folder contents instead.' }
    if (Test-Path $isoPath) { $built += [pscustomobject]@{ Path = $isoPath; KB = [math]::Round((Get-Item $isoPath).Length / 1KB, 0) } }
}

Write-Host "Built Cowork Lab Skillable package v$version into $OutDir (credential $CloudCredential, learner $LearnerUpn)."
$built | ForEach-Object { '{0,10} KB  {1}' -f $_.KB, (Get-Rel $_.Path) }
