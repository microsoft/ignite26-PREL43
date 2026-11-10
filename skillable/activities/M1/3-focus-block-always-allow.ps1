# Check M1 / focus-block-always-allow (7 points) - Cowork Lab v1.0.6.
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
bY4fqEAAAA==
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