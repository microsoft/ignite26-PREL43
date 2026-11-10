# Check M5 / meeting-prep-skill (5 points) - Cowork Lab v1.0.6.
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