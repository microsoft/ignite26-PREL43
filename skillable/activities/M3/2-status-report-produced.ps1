# Check M3 / status-report-produced (10 points) - Cowork Lab v1.0.6.
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
/8yFskAAAA==
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