# Check M1 / drafts-saved (8 points) - Cowork Lab v1.0.6.
# Scored Activity script: Execute in Virtual Machine (Win11-Pro-Base), PowerShell. No cloud subscription needed.
# Runs the check in the PowerShell 7 that the "Prepare Helix workspace" action installed (works in Windows
# PowerShell 5.1), then reports Correct or Incorrect to Skillable.
$ErrorActionPreference = 'Stop'
$TenantId     = '@lab.CloudCredential(WWLM365E7).TenantId'
$ClientId     = '@lab.CloudCredential(WWLM365E7).ClientId'
$ClientSecret = '@lab.CloudCredential(WWLM365E7).ClientSecret'
$LearnerUpn   = '@lab.Variable(LearnerUpn)'
# The check itself (PowerShell 7, gzip + base64).
$Check = @'
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
'@

function Set-CheckResult([bool]$Correct, [string]$Message) {
    if (-not (Get-Command Set-ActivityResult -ErrorAction SilentlyContinue)) {
        # Skillable's fallback: the last value in the output decides.
        Write-Output $Message
        Write-Output $Correct
        return
    }
    try {
        if ($Correct) { Set-ActivityResult -Correct -Message $Message } else { Set-ActivityResult -Incorrect -Message $Message }
    }
    catch [System.Management.Automation.ParameterBindingException] {
        if ($Correct) { Set-ActivityResult -Correct } else { Set-ActivityResult -Incorrect }
        Write-Output $Message
    }
}

$pwsh = @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramData\HelixKit\pwsh\pwsh.exe", $env:HELIXKIT_PWSH) |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $pwsh) {
    Set-CheckResult $false "Your lab isn't ready yet. Tell your proctor."
    Write-Output 'Details: PowerShell 7 was not found in the VM. The "Prepare Helix workspace" action installs it.'
    return
}

$gz = New-Object IO.Compression.GZipStream((New-Object IO.MemoryStream(, [Convert]::FromBase64String(($Check -replace '\s', '')))), [IO.Compression.CompressionMode]::Decompress)
$reader = New-Object IO.StreamReader($gz)
$body = $reader.ReadToEnd()
$reader.Dispose()
# In PowerShell 7 the result comes back as one "##RESULT" line.
$shim = @'
function Set-ActivityResult { param([switch]$Correct, [switch]$Incorrect, [string]$Message)
    Write-Output ('##RESULT ' + $(if ($Correct) { 'Correct' } else { 'Incorrect' }) + ' ' + ($Message -replace '\r?\n', ' ')) }
'@
$file = Join-Path ([IO.Path]::GetTempPath()) ('HelixCheck-' + [guid]::NewGuid().ToString('N') + '.ps1')
[IO.File]::WriteAllText($file, $shim + "`n" + $body)

# Secrets go through the environment, not the command line.
$env:HELIXKIT_TENANT_ID = $TenantId
$env:HELIXKIT_CLIENT_ID = $ClientId
$env:HELIXKIT_CLIENT_SECRET = $ClientSecret
$env:HELIXKIT_LEARNER_UPN = $LearnerUpn
$env:NO_COLOR = '1'
try {
    # Windows PowerShell 5.1 turns redirected stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $lines = @(& $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file 2>&1 |
        ForEach-Object { "$_" -replace "$([char]27)\[[0-9;]*m", '' })
    $ErrorActionPreference = 'Stop'
}
finally {
    Remove-Item $file -ErrorAction SilentlyContinue
    Remove-Item Env:\HELIXKIT_TENANT_ID, Env:\HELIXKIT_CLIENT_ID, Env:\HELIXKIT_CLIENT_SECRET, Env:\HELIXKIT_LEARNER_UPN, Env:\NO_COLOR -ErrorAction SilentlyContinue
}

$result = $lines | Where-Object { $_ -match '^##RESULT (Correct|Incorrect)' } | Select-Object -Last 1
$lines | Where-Object { $_ -notmatch '^##RESULT ' -and $_.Trim() } | ForEach-Object { Write-Output $_ }
if ($result -match '^##RESULT (Correct|Incorrect) ?(.*)$') { Set-CheckResult ($Matches[1] -eq 'Correct') $Matches[2] }
else {
    # PowerShell 7 failed before the check could report: let the learner simply check again.
    Set-CheckResult $false "We couldn't check this right now. Wait 1 minute, then select Check my work again."
}