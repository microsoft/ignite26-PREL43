# =============================================================================================
# Prepare Helix workspace  (Cowork Lab COWORK-T1, kit v__VERSION__)
# Skillable life cycle action: Execute Script in Virtual Machine, language PowerShell.
# Runs inside the lab VM. Needs the HelixKit-__VERSION__.iso removable media attached to the VM.
# Steps: Grant (missing Graph permissions only) -> Learner (the admin, with a Copilot licence) ->
# Pre-flight -> Hydrate -> Readiness.
# Sets lab variables PermissionStatus, LearnerUpn, PreflightStatus, HydrationStatus,
# HydratedAt, ReadinessStatus. Works in Windows PowerShell 5.1; the kit itself runs in PowerShell 7
# (installed, or the portable copy on the media).
# =============================================================================================
$ErrorActionPreference = 'Stop'

# ----- EDIT BEFORE EACH EVENT -----
$EventDate     = '__EVENTDATE__'   # event day, yyyy-MM-dd (hydration runs from D-1 09:30 to the end of D)
$EventTimeZone = '__TZ__'   # Windows time zone name
# ----- Filled by Skillable at run time -----
$TenantId      = '@lab.CloudCredential(__CRED__).TenantId'
$ClientId      = '@lab.CloudCredential(__CRED__).ClientId'
$ClientSecret  = '@lab.CloudCredential(__CRED__).ClientSecret'
$LearnerUpn    = '__LEARNER__'   # 'admin': this launch's Office 365 admin; 'auto': a licensed user; or a UPN
# Tenant admin of this launch: only used to grant the credential's app any missing Graph permissions.
$TenantName    = '@lab.CloudCredential(__CRED__).TenantName'
# Credential fields "Administrative Username" / "Administrative Password" in Lab Access (token = name without spaces).
$AdminUser     = '@lab.CloudCredential(__CRED__).AdministrativeUsername'
$AdminPassword = '@lab.CloudCredential(__CRED__).AdministrativePassword'

# A token Skillable did not fill stays as text: fall back to admin@<this launch's tenant>.
Write-Output ("Tokens filled: TenantName={0}, AdministrativeUsername={1}, AdministrativePassword={2}" -f
    ($TenantName -notmatch '@lab\.\w+\('), ($AdminUser -notmatch '@lab\.\w+\('), ($AdminPassword -notmatch '^@lab\.\w+\('))
if ($AdminUser -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $AdminUser = "admin@$TenantName" }
if ($LearnerUpn -eq 'admin') { $LearnerUpn = $AdminUser }   # learners sign in with the Office 365 admin account

# Test launches: with no event date set, today is the event day.
if ($EventDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
    $EventDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $EventTimeZone).ToString('yyyy-MM-dd')
    Write-Output "EventDate is not set; using today ($EventDate). Set it before pre-building for an event."
}

function Set-Status([string]$Name, [string]$Value) {
    if (Get-Command Set-LabVariable -ErrorAction SilentlyContinue) { Set-LabVariable -Name $Name -Value $Value }
    $shown = if ($Name -match 'TAP|Password|Secret') { '********' } else { $Value }   # never put a pass in the log
    Write-Output "[lab variable] $Name = $shown"
}

# 1. Find the HelixKit media (any drive with \HelixKit\kit.json). Optical media can take a moment to mount.
$kit = $null
for ($i = 0; $i -lt 12 -and -not $kit; $i++) {
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $candidate = Join-Path $d.RootDirectory.FullName 'HelixKit'
        if (Test-Path (Join-Path $candidate 'kit.json')) { $kit = $candidate; break }
    }
    if (-not $kit) { Start-Sleep -Seconds 10 }
}
if (-not $kit) {
    $seen = ([IO.DriveInfo]::GetDrives() | ForEach-Object { '{0} {1}{2}' -f $_.Name, $_.DriveType, $(if ($_.IsReady) { " '" + $_.VolumeLabel + "'" } else { ' (empty)' }) }) -join '; '
    throw "HelixKit media not found after 2 minutes. Drives in the VM: $seen. A CDRom drive marked (empty) means the ISO is attached to the lab profile but not inserted in the VM: set HelixKit Media as the VM's default/startup media. No CDRom drive means the VM has no optical drive."
}
$kitVersion = (Get-Content -Raw (Join-Path $kit 'kit.json') | ConvertFrom-Json).version
Write-Output "HelixKit $kitVersion found at $kit"
if ($kitVersion -ne '__VERSION__') {
    throw "The VM has HelixKit $kitVersion but this script needs __VERSION__. Upload HelixKit-__VERSION__.iso and set it as the Removable Media image path (and DVD Drive), then launch a new lab."
}

# 2. PowerShell 7: installed, already extracted, or extracted now from the media.
$pwsh = @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramData\HelixKit\pwsh\pwsh.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $pwsh) {
    $zip = Get-ChildItem -Path (Join-Path $kit 'pwsh') -Filter '*.zip' | Select-Object -First 1
    if (-not $zip) { throw 'PowerShell 7 is not installed and the media has no portable copy (HelixKit\pwsh\*.zip).' }
    $dest = "$env:ProgramData\HelixKit\pwsh"
    Expand-Archive -Path $zip.FullName -DestinationPath $dest -Force
    $pwsh = Join-Path $dest 'pwsh.exe'
}
Write-Output "PowerShell 7: $pwsh"

# 3. Wait for the network: at First Displayable the VM can be up before DNS and internet are.
$hosts = @('login.microsoftonline.com', 'graph.microsoft.com')
$netOk = $false
for ($i = 0; $i -lt 30 -and -not $netOk; $i++) {
    try { foreach ($h in $hosts) { [void][Net.Dns]::GetHostAddresses($h) }; $netOk = $true }
    catch { Start-Sleep -Seconds 10 }
}
if (-not $netOk) {
    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | ForEach-Object { "$($_.InterfaceAlias)=$($_.ServerAddresses -join ',')" }) -join '; '
    throw "No internet from the VM after 5 minutes: cannot resolve $($hosts -join ' / '). DNS servers: $dns. Check the lab profile network (Internet access) for this VM."
}
Write-Output "Network ready (waited about $($i * 10 - 10) s)."

# 4. Run the kit steps. Secrets go through the environment, not the command line.
$env:HELIXKIT_CLIENT_SECRET = $ClientSecret
$env:HELIXKIT_ADMIN_USER = $AdminUser
$env:HELIXKIT_ADMIN_PASSWORD = $AdminPassword
$env:NO_COLOR = '1'   # plain text output from PowerShell 7 (no colour codes in Skillable's log)
try {
    foreach ($step in @('Grant', 'Learner', 'Preflight', 'Hydrate', 'Readiness')) {
        Write-Output "----- $step -----"
        # Windows PowerShell 5.1 turns redirected stderr into terminating errors under 'Stop'.
        $ErrorActionPreference = 'Continue'
        $lines = & $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $kit "$step.ps1") `
            -TenantId $TenantId -ClientId $ClientId -LearnerUpn $LearnerUpn -EventDate $EventDate -EventTimeZone $EventTimeZone 2>&1 |
            ForEach-Object { "$_" -replace "$([char]27)\[[0-9;]*m", '' }
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        foreach ($l in $lines) {
            if ($l -match '^##LABVAR (\w+)=(.*)$') {
                Set-Status $Matches[1] $Matches[2]
                if ($Matches[1] -eq 'LearnerUpn') { $LearnerUpn = $Matches[2] }   # later steps use the chosen learner
            }
            else { Write-Output $l }
        }
        if ($code -ne 0) {
            $tail = $lines | Where-Object { $_ -notmatch '^(VERBOSE:|##LABVAR )' -and $_.Trim() -notmatch '^[\|~ ]*$' } | Select-Object -Last 8
            throw "$step failed: " + ($tail -join "`n")
        }
        if ($step -eq 'Grant') { Remove-Item Env:\HELIXKIT_ADMIN_USER, Env:\HELIXKIT_ADMIN_PASSWORD -ErrorAction SilentlyContinue }
    }
}
finally { Remove-Item Env:\HELIXKIT_CLIENT_SECRET, Env:\HELIXKIT_ADMIN_USER, Env:\HELIXKIT_ADMIN_PASSWORD, Env:\NO_COLOR -ErrorAction SilentlyContinue }
Write-Output 'Helix workspace ready.'
