# Check M1 / third-block-cancelled (10 points) - Cowork Lab v1.0.6.
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