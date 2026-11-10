# Check M5 / skill-inventory (5 points) - Cowork Lab v1.0.6.
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