# Check M5 / skill-inventory (5 points) - Cowork Lab v1.0.6. Execute in Cloud Platform, PowerShell 7.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$TenantId     = '@lab.CloudCredential(WWLM365E7).TenantId'
$ClientId     = '@lab.CloudCredential(WWLM365E7).ClientId'
$ClientSecret = '@lab.CloudCredential(WWLM365E7).ClientSecret'
$LearnerUpn   = '@lab.Variable(LearnerUpn)'
$script:GraphRoot = 'https://graph.microsoft.com/v1.0'
$script:GraphAuth = $null
$script:GraphRetryBudgetSeconds = 600   # Check my work scripts lower this so learners never wait long
class GraphError : System.Exception {
[int]$Status
[string]$Code
GraphError([string]$message, [int]$status, [string]$code) : base($message) {
$this.Status = $status
$this.Code = $code
}
}
function Connect-Graph {
param(
[Parameter(Mandatory)][string]$TenantId,
[Parameter(Mandatory)][string]$ClientId,
[Parameter(Mandatory)][string]$ClientSecret
)
$script:GraphAuth = @{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret; Token = $null; Expires = [datetime]::MinValue }
[void](Get-GraphToken -Force)
}
function Get-GraphToken {
param([switch]$Force)
$a = $script:GraphAuth
if (-not $a) { throw 'Connect-Graph has not been called.' }
if (-not $Force -and $a.Token -and (Get-Date).ToUniversalTime() -lt $a.Expires.AddMinutes(-5)) { return $a.Token }
$body = @{
client_id     = $a.ClientId
client_secret = $a.ClientSecret
scope         = 'https://graph.microsoft.com/.default'
grant_type    = 'client_credentials'
}
$r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($a.TenantId)/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
$a.Token = $r.access_token
$a.Expires = (Get-Date).ToUniversalTime().AddSeconds([int]$r.expires_in)
return $a.Token
}
function Invoke-Graph {
param(
[string]$Method = 'GET',
[Parameter(Mandatory)][string]$Path,
$Body,
[byte[]]$Bytes,
[string]$ContentType,
[hashtable]$Headers,
[switch]$Ok404,
[switch]$Raw,
[int]$MaxRetries = 8
)
$uri = if ($Path -match '^https?://') { $Path } else { "$script:GraphRoot$Path" }
$refreshed = $false
$started = Get-Date
for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
$h = @{ Authorization = "Bearer $(Get-GraphToken)" }
if ($Headers) { foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] } }
$p = @{ Method = $Method; Uri = $uri; Headers = $h; SkipHttpErrorCheck = $true }
if ($null -ne $Bytes) {
$p.Body = $Bytes
$p.ContentType = if ($ContentType) { $ContentType } else { 'application/octet-stream' }
}
elseif ($null -ne $Body) {
$p.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 -Compress }
$p.ContentType = if ($ContentType) { $ContentType } else { 'application/json; charset=utf-8' }
}
try {
$resp = Invoke-WebRequest @p -UseBasicParsing
}
catch {
$netError = $_.Exception -is [System.Net.Http.HttpRequestException] -or $_.Exception -is [System.Threading.Tasks.TaskCanceledException] -or $_.Exception -is [System.IO.IOException] -or $_.Exception -is [System.Net.WebException]
if (-not $netError -or $attempt -eq $MaxRetries -or ((Get-Date) - $started).TotalSeconds -gt $script:GraphRetryBudgetSeconds) {
throw [GraphError]::new("$Method $Path : $($_.Exception.GetType().Name): $($_.Exception.Message)", 0, 'network')
}
Start-Sleep -Seconds ([math]::Min(60, [math]::Pow(2, $attempt)))
continue
}
$status = [int]$resp.StatusCode
$rh = $resp.Headers
if ($status -eq 401 -and -not $refreshed) { [void](Get-GraphToken -Force); $refreshed = $true; $attempt--; continue }
if ($status -in 429, 500, 502, 503, 504 -and $attempt -lt $MaxRetries -and ((Get-Date) - $started).TotalSeconds -lt $script:GraphRetryBudgetSeconds) {
$wait = 0
if ($rh -and $rh['Retry-After']) { [void][int]::TryParse("$($rh['Retry-After'] | Select-Object -First 1)", [ref]$wait) }
if ($wait -le 0) { $wait = [math]::Min(60, [math]::Pow(2, $attempt)) }
Start-Sleep -Seconds ($wait + (Get-Random -Minimum 0 -Maximum 2))
continue
}
if ($status -eq 404 -and $Ok404) { return $null }
if ($status -ge 400) {
$code = ''; $msg = "$($resp.Content)"
try { $e = ($resp.Content | ConvertFrom-Json).error; $code = $e.code; $msg = "$($e.code): $($e.message)" } catch { }
throw [GraphError]::new("$Method $Path -> $status $msg", $status, $code)
}
if ($Raw) { return [pscustomobject]@{ Status = $status; Headers = $rh; Content = $resp.Content } }
if ($status -eq 204 -or -not $resp.Content) { return @{} }
$ctype = "$($rh['Content-Type'] | Select-Object -First 1)"
if ($ctype -match 'json') {
$text = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { $resp.Content }
return ($text | ConvertFrom-Json -AsHashtable -Depth 50)
}
return $resp.Content
}
throw [GraphError]::new("$Method $Path : retries exhausted", 0, 'retries')
}
function Get-GraphAll {
param([Parameter(Mandatory)][string]$Path, [hashtable]$Headers, [int]$Limit = 0)
$out = [System.Collections.Generic.List[object]]::new()
$page = Invoke-Graph -Path $Path -Headers $Headers
while ($true) {
foreach ($v in @($page.value)) { if ($null -ne $v) { $out.Add($v) } }
$next = $page.'@odata.nextLink'
if (-not $next -or ($Limit -gt 0 -and $out.Count -ge $Limit)) { break }
$page = Invoke-Graph -Path $next -Headers $Headers
}
if ($Limit -gt 0 -and $out.Count -gt $Limit) { return $out.GetRange(0, $Limit).ToArray() }
return $out.ToArray()
}
function Get-GraphBytes {
param([Parameter(Mandatory)][string]$Path)
$tmp = [IO.Path]::GetTempFileName()
try {
for ($attempt = 0; $attempt -le 5; $attempt++) {
try {
Invoke-WebRequest -Uri "$script:GraphRoot$Path" -Headers @{ Authorization = "Bearer $(Get-GraphToken)" } -OutFile $tmp -UseBasicParsing
return [IO.File]::ReadAllBytes($tmp)
}
catch {
if ($attempt -eq 5) { throw }
Start-Sleep -Seconds ([math]::Pow(2, $attempt))
}
}
}
finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}
$script:WindowsToIana = @{
'UTC'                           = 'UTC'
'GMT Standard Time'             = 'Europe/London'
'W. Europe Standard Time'       = 'Europe/Berlin'
'Romance Standard Time'         = 'Europe/Paris'
'Central Europe Standard Time'  = 'Europe/Budapest'
'India Standard Time'           = 'Asia/Kolkata'
'Singapore Standard Time'       = 'Asia/Singapore'
'Tokyo Standard Time'           = 'Asia/Tokyo'
'China Standard Time'           = 'Asia/Shanghai'
'AUS Eastern Standard Time'     = 'Australia/Sydney'
'Arabian Standard Time'         = 'Asia/Dubai'
'Eastern Standard Time'         = 'America/New_York'
'Central Standard Time'         = 'America/Chicago'
'Mountain Standard Time'        = 'America/Denver'
'Pacific Standard Time'         = 'America/Los_Angeles'
'E. South America Standard Time' = 'America/Sao_Paulo'
}
function Get-EventTimeZone {
param([Parameter(Mandatory)][string]$Name)
foreach ($id in @($Name, $script:WindowsToIana[$Name])) {
if (-not $id) { continue }
try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
}
throw "Unknown time zone '$Name'. Use a Windows time zone name such as 'India Standard Time'."
}
function New-Timeline {
param(
[Parameter(Mandatory)][string]$EventDate,      # yyyy-MM-dd
[Parameter(Mandatory)][string]$TimeZoneName     # Windows name, e.g. 'India Standard Time'
)
$day = [datetime]::ParseExact($EventDate.Trim(), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
return [pscustomobject]@{ Day = $day.Date; Tz = (Get-EventTimeZone $TimeZoneName); TzName = $TimeZoneName }
}
function ConvertFrom-Offset {
param([Parameter(Mandatory)][string]$Offset)
if ($Offset -notmatch '^\s*D\s*([+-]\s*\d+)?\s*(?:(\d{1,2}):(\d{2}))?\s*$') { throw "Not a lab-day offset: '$Offset'" }
$days = if ($Matches[1]) { [int]($Matches[1] -replace '\s', '') } else { 0 }
$time = if ($Matches[2]) { [timespan]::new([int]$Matches[2], [int]$Matches[3], 0) } else { $null }
return @{ Days = $days; Time = $time }
}
function Get-TimelineLocal {
param($Timeline, [string]$Offset)
$o = ConvertFrom-Offset $Offset
$t = if ($o.Time) { $o.Time } else { [timespan]::Zero }
return [datetime]::SpecifyKind($Timeline.Day.AddDays($o.Days).Add($t), [DateTimeKind]::Unspecified)
}
function Get-TimelineUtc {
param($Timeline, [string]$Offset)
return [TimeZoneInfo]::ConvertTimeToUtc((Get-TimelineLocal $Timeline $Offset), $Timeline.Tz)
}
function Get-TimelineUtcIso {
param($Timeline, [string]$Offset)
return (Get-TimelineUtc $Timeline $Offset).ToString("yyyy-MM-dd'T'HH:mm:ss'.000Z'", [Globalization.CultureInfo]::InvariantCulture)
}
$script:MaxDownload = 15MB
$script:MaxFiles = 60
function New-ScoreContext {
param([Parameter(Mandatory)][string]$LearnerUpn, [Parameter(Mandatory)]$Timeline, [Parameter(Mandatory)]$Scorecard)
$u = Invoke-Graph -Path "/users/$([uri]::EscapeDataString($LearnerUpn))?`$select=id,userPrincipalName" -Ok404
if (-not $u) { throw "Learner account $LearnerUpn not found." }
return [pscustomobject]@{
UserId = $u.id; Upn = $u.userPrincipalName; Timeline = $Timeline; Scorecard = $Scorecard
MailCache = @{}; EventsCache = $null; DriveLoaded = $false; Drive = $null; ItemsCache = $null; TextCache = @{}
}
}
function Get-ScoreMail($Ctx, [string]$Folder) {
if (-not $Ctx.MailCache.ContainsKey($Folder)) {
try {
$Ctx.MailCache[$Folder] = @(Get-GraphAll -Limit 200 -Headers @{ Prefer = 'outlook.body-content-type="text"' } `
-Path "/users/$($Ctx.UserId)/mailFolders/$Folder/messages?`$select=id,subject,body,bodyPreview,receivedDateTime&`$top=100&`$orderby=receivedDateTime desc")
}
catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  $Ctx.MailCache[$Folder] = @() }
}
return $Ctx.MailCache[$Folder]
}
function Get-ScoreEvents($Ctx) {
if ($null -eq $Ctx.EventsCache) {
$w = $Ctx.Scorecard.window; if (-not $w) { $w = @{ start = 'D-1'; end = 'D+14' } }
$s = Get-TimelineUtcIso $Ctx.Timeline $w.start
$e = Get-TimelineUtcIso $Ctx.Timeline $w.end
$Ctx.EventsCache = @(Get-GraphAll -Headers @{ Prefer = 'outlook.timezone="UTC"' } `
-Path "/users/$($Ctx.UserId)/calendarView?startDateTime=$s&endDateTime=$e&`$top=200&`$select=id,subject,start,end,isCancelled")
}
return $Ctx.EventsCache
}
function Get-ScoreDrive($Ctx) {
if (-not $Ctx.DriveLoaded) {
try { $Ctx.Drive = Invoke-Graph -Path "/users/$($Ctx.UserId)/drive" -Ok404 }
catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if ($_.Exception.Status -in 400, 403) { $Ctx.Drive = $null } else { throw } }
$Ctx.DriveLoaded = $true
}
return $Ctx.Drive
}
function Get-ScoreItems($Ctx) {
if ($null -eq $Ctx.ItemsCache) {
$d = Get-ScoreDrive $Ctx
$Ctx.ItemsCache = @()   # assigned directly: an empty array from an if-expression would become $null
if ($d) {
$Ctx.ItemsCache = @(Get-GraphAll -Path "/drives/$($d.id)/root/delta?`$select=id,name,file,folder,size,lastModifiedDateTime,parentReference,deleted,root" |
Where-Object { $_ -and $_.name -and -not $_.ContainsKey('deleted') -and -not $_.ContainsKey('root') })
}
}
return $Ctx.ItemsCache
}
function Get-ScoreText($Ctx, $Item) {
if (-not $Ctx.TextCache.ContainsKey($Item.id)) {
$Ctx.TextCache[$Item.id] = if ([long]$Item.size -gt $script:MaxDownload) { '' } else {
Get-FileText -Name $Item.name -Data (Get-GraphBytes -Path "/drives/$($Ctx.Drive.id)/items/$($Item.id)/content")
}
}
return $Ctx.TextCache[$Item.id]
}
function Get-MailText($m) { return "$($m.body.content)`n$($m.bodyPreview)" }
function Test-ScoreCheck {
param($Ctx, $Check)
$p = $Check.params
switch ($Check.type) {
'mail_contains' {
$phrase = $p.phrase.ToLowerInvariant()
$folders = if ($p.folders) { $p.folders } else { @('drafts', 'sentitems', 'inbox') }
foreach ($f in $folders) {
foreach ($m in (Get-ScoreMail $Ctx $f)) {
if ((Get-MailText $m).ToLowerInvariant().Contains($phrase)) { return @{ passed = $true; detail = "found in ${f}: $("$($m.subject)".Substring(0, [math]::Min(60, "$($m.subject)".Length)))" } }
}
}
return @{ passed = $false; detail = 'no message contains the phrase' }
}
'mail_subject' {
$pre = $p.subject_prefix.ToLowerInvariant()
$folders = if ($p.folders) { $p.folders } else { @('inbox') }
foreach ($f in $folders) {
foreach ($m in (Get-ScoreMail $Ctx $f)) {
if ("$($m.subject)".Trim().ToLowerInvariant().StartsWith($pre)) { return @{ passed = $true; detail = "${f}: $($m.subject)" } }
}
}
return @{ passed = $false; detail = 'no message with that subject' }
}
{ $_ -in 'event_exists', 'event_absent' } {
$want = $p.subject.Trim().ToLowerInvariant()
$hits = @(Get-ScoreEvents $Ctx | Where-Object { "$($_.subject)".Trim().ToLowerInvariant() -eq $want -and -not $_.isCancelled })
if ($Check.type -eq 'event_exists') {
return @{ passed = ($hits.Count -gt 0); detail = $(if ($hits.Count) { "$($hits.Count) event(s)" } else { 'no such event' }) }
}
return @{ passed = ($hits.Count -eq 0); detail = $(if ($hits.Count) { "$($hits.Count) event(s) present" } else { 'no such event' }) }
}
'drive_item_name' {
if (-not (Get-ScoreDrive $Ctx)) { return @{ passed = $false; detail = 'OneDrive not provisioned' } }
$norm = { param([string]$s) $t = $s.ToLowerInvariant(); if ($p.loose) { $t = ($t -replace '[^a-z0-9]', '') -replace 'skills', 'skill' }; $t }
$pat = & $norm $p.pattern
foreach ($i in (Get-ScoreItems $Ctx)) {
if ((& $norm $i.name).Contains($pat) -and (-not $p.files_only -or $i.ContainsKey('file'))) { return @{ passed = $true; detail = $i.name } }
}
return @{ passed = $false; detail = 'no matching OneDrive item' }
}
'drive_file_contains' {
if (-not (Get-ScoreDrive $Ctx)) { return @{ passed = $false; detail = 'OneDrive not provisioned' } }
$exts = @($p.extensions | ForEach-Object { $_.ToLowerInvariant() })
$excl = @($p.exclude_name_patterns | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
$cands = @(Get-ScoreItems $Ctx | Where-Object {
$n = $_.name.ToLowerInvariant()
$_.ContainsKey('file') -and (-not $exts -or ($exts | Where-Object { $n.EndsWith($_) })) -and -not ($excl | Where-Object { $n.Contains($_) })
} | Sort-Object { "$($_.lastModifiedDateTime)" } -Descending | Select-Object -First $script:MaxFiles)
foreach ($i in $cands) {
$txt = Get-ScoreText $Ctx $i
$hit = if ($p.case_sensitive) { $txt.Contains($p.phrase) } else { $txt.ToLowerInvariant().Contains($p.phrase.ToLowerInvariant()) }
if ($hit) { return @{ passed = $true; detail = $i.name } }
}
return @{ passed = $false; detail = "no file contains '$($p.phrase)' ($($cands.Count) checked)" }
}
default { throw "Unknown check type '$($Check.type)'." }
}
}
function Set-CheckResult([bool]$Correct, [string]$Message) {
try {
if ($Correct) { Set-ActivityResult -Correct -Message $Message } else { Set-ActivityResult -Incorrect -Message $Message }
}
catch [System.Management.Automation.ParameterBindingException] {
if ($Correct) { Set-ActivityResult -Correct } else { Set-ActivityResult -Incorrect }
Write-Output $Message
}
}
function Invoke-ActivityCheck {
param(
[Parameter(Mandatory)][string]$CheckId,
[Parameter(Mandatory)][string]$TenantId,
[Parameter(Mandatory)][string]$ClientId,
[Parameter(Mandatory)][string]$ClientSecret,
[Parameter(Mandatory)][string]$LearnerUpn,
[string]$EventDate,
[string]$EventTimeZone
)
$script:GraphRetryBudgetSeconds = 40
if (-not $EventTimeZone -or $EventTimeZone -match '^@lab') { $EventTimeZone = 'UTC' }
if (-not $EventDate -or $EventDate -notmatch '^\d{4}-\d{2}-\d{2}$') { $EventDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
$check = $script:Scorecard.checks | Where-Object { $_.id -eq $CheckId }
if (-not $check) { throw "Check '$CheckId' is not in the embedded scorecard." }
if ($LearnerUpn -notmatch '^[^@\s]+@[^@\s]+$') {
Set-CheckResult $false "Your lab isn't ready yet. Tell your proctor."
Write-Output "Details: LearnerUpn is '$LearnerUpn'."
return
}
try {
Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$tl = New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone
$ctx = New-ScoreContext -LearnerUpn $LearnerUpn -Timeline $tl -Scorecard $script:Scorecard
$r = Test-ScoreCheck $ctx $check
}
catch {
Set-CheckResult $false "We couldn't check this right now. Wait 1 minute, then select Check my work again."
Write-Output "Details: $($_.Exception.Message)"
return
}
if ($r.passed) { Set-CheckResult $true "Done. $($check.passes_when)" }
else { Set-CheckResult $false "Not yet. $($check.hint)" }
}
$script:Scorecard = @'
{"pass_mark":70,"max":100,"window":{"start":"D-1","end":"D+14"},"checks":[{"hint":"Go to step 5.9. Create a Word file named Skill-Inventory.docx anywhere in your OneDrive.","type":"drive_item_name","points":5,"passes_when":"Found Skill-Inventory in your OneDrive.","params":{"pattern":"Skill-Inventory","files_only":true,"loose":true},"id":"skill-inventory"}]}
'@ | ConvertFrom-Json -AsHashtable -Depth 50
# ===== Run =====
Invoke-ActivityCheck -CheckId 'skill-inventory' -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -LearnerUpn $LearnerUpn