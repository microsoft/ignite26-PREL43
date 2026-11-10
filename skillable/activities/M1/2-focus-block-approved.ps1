# Check M1 / focus-block-approved (7 points) - Cowork Lab v1.0.6.
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