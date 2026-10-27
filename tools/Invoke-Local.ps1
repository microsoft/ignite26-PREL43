<#
.SYNOPSIS
  Runs a built Skillable script (skillable/...) on your machine against a test tenant, exactly as
  Skillable would: @lab tokens are replaced with the values you pass, and Set-LabVariable,
  Set-ActivityResult and Send-LabNotification print instead of talking to Skillable.

.DESCRIPTION
  Use it with the dev/test tenant and a test app registration that has the same Microsoft Graph
  application permissions as the Skillable cloud credential. Pass the secret through the
  SKILLABLE_TEST_CLIENT_SECRET environment variable rather than on the command line.

.EXAMPLE
  $env:SKILLABLE_TEST_CLIENT_SECRET = '<test app secret>'
  ./tools/Invoke-Local.ps1 -Script skillable/activities/M1/1-drafts-saved.ps1 -TenantId 9e9dab93-f5bd-40b1-bed8-59a535fe26c0 `
      -ClientId <test-app-id> -LearnerUpn user1@<tenant>.onmicrosoft.com -EventDate (Get-Date -Format yyyy-MM-dd) -EventTimeZone 'India Standard Time'

.EXAMPLE
  ./tools/Invoke-Local.ps1 -Script skillable/optional/TapIssue.ps1 ...
#>
param(
    [Parameter(Mandatory)][string]$Script,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ClientId,
    [string]$ClientSecret = $env:SKILLABLE_TEST_CLIENT_SECRET,
    [Parameter(Mandatory)][string]$LearnerUpn,
    [Parameter(Mandatory)][string]$EventDate,
    [Parameter(Mandatory)][string]$EventTimeZone,
    [string]$DataPackUrl = '',
    [string]$TenantName = '',     # value for @lab.CloudCredential(...).TenantName, e.g. contoso.onmicrosoft.com
    [hashtable]$LabVariables = @{},
    [string]$Inject,          # tests only: a file dot-sourced just before the script's Run section
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if (-not $ClientSecret) { throw 'Set $env:SKILLABLE_TEST_CLIENT_SECRET or pass -ClientSecret.' }

$text = Get-Content -Raw -Path $Script
# Run as the given learner, whatever the script's learner line says (e.g. AlexW@<lab tenant>).
$text = [regex]::Replace($text, "(?m)^\`$LearnerUpn(\s*)= '[^'\r\n]*'", { param($m) "`$LearnerUpn$($m.Groups[1].Value)= '$($LearnerUpn.Replace("'", "''"))'" })
$vars = @{ EventDate = $EventDate; EventTimeZone = $EventTimeZone; DataPackUrl = $DataPackUrl } + $LabVariables
$text = [regex]::Replace($text, '@lab\.CloudCredential\([^)]*\)\.TenantId', [regex]::Escape($TenantId).Replace('\', ''))
$text = [regex]::Replace($text, '@lab\.CloudCredential\([^)]*\)\.ClientId', $ClientId)
$text = [regex]::Replace($text, '@lab\.CloudCredential\([^)]*\)\.TenantName', $TenantName)
$text = [regex]::Replace($text, '@lab\.CloudCredential\([^)]*\)\.ClientSecret', { $ClientSecret.Replace("'", "''") })
$text = [regex]::Replace($text, '@lab\.CloudPortalCredential\([^)]*\)\.Username', $LearnerUpn)
$text = [regex]::Replace($text, '@lab\.Variable\(([^)]+)\)', { param($m) "$($vars[$m.Groups[1].Value])".Replace("'", "''") })
if ($Inject) { $text = $text.Replace('# ===== Run =====', ". '$((Resolve-Path $Inject).Path)'`n# ===== Run =====") }

$script:LocalLabVariables = @{}
function global:Set-LabVariable {
    param([string]$Name, $Value)
    $script:LocalLabVariables[$Name] = $Value
    $shown = if ($Name -match 'TAP|Secret|Password') { '********' } else { $Value }
    if (-not $Quiet) { Write-Host "[lab variable] $Name = $shown" -ForegroundColor Cyan }
}
function global:Set-ActivityResult {
    param([switch]$Correct, [switch]$Incorrect, [double]$Percentage = -1, [string]$Message)
    $global:LastActivityResult = @{ Correct = [bool]$Correct; Message = $Message }
    if (-not $Quiet) { Write-Host ("[activity] {0}{1}" -f $(if ($Correct) { 'CORRECT' } else { 'INCORRECT' }), $(if ($Message) { " - $Message" } else { '' })) -ForegroundColor $(if ($Correct) { 'Green' } else { 'Yellow' }) }
}
function global:Send-LabNotification { param([string]$Message) if (-not $Quiet) { Write-Host "[notification] $Message" -ForegroundColor Magenta } }

$sw = [Diagnostics.Stopwatch]::StartNew()
$VerbosePreference = if ($Quiet) { 'SilentlyContinue' } else { 'Continue' }
try { & ([scriptblock]::Create($text)) }
finally {
    $VerbosePreference = 'SilentlyContinue'
    if (-not $Quiet) { Write-Host ("[done] {0} in {1:mm\:ss}" -f (Split-Path $Script -Leaf), $sw.Elapsed) -ForegroundColor DarkGray }
}
