# Check M4 / briefing-email-received (15 points) - Cowork Lab v1.0.6.
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
7h/hPzat8P8Drb9FLstAAAA=
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