# Check M2 / risk-register-columns (10 points) - Cowork Lab v1.0.6.
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
ZuO65h9hfjYZiP8FE/znifFOAAA=
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