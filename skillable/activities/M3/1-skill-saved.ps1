# Check M3 / skill-saved (12 points) - Cowork Lab v1.0.6.
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