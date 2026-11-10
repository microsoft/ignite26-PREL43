# Check M2 / unconfirmed-marked (7 points) - Cowork Lab v1.0.6.
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