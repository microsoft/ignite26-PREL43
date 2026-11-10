# Check M5 / companion-template (4 points) - Cowork Lab v1.0.6.
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
AA==
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