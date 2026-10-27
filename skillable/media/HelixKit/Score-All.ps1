# HelixKit v1.0.4 - runs in PowerShell 7 inside the lab VM, started by Prepare-Helix-Workspace.ps1.
param([string]$TenantId, [string]$ClientId, [string]$ClientSecret = $env:HELIXKIT_CLIENT_SECRET,
      [string]$LearnerUpn, [string]$EventDate, [string]$EventTimeZone)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'Continue'
if ($PSStyle) { $PSStyle.OutputRendering = 'PlainText' }
$DataPackUrl = ''
# Lab variables are reported to the launcher, which sets them in Skillable.
function Set-LabVariable { param([string]$Name, $Value) Write-Output "##LABVAR $Name=$Value" }
# ===== Library =====
# ---------------------------------------------------------------------------------------------
# Microsoft Graph client: app-only token from the Skillable cloud credential, retries on
# throttling (429) and transient errors (5xx) honouring Retry-After, paging, token roles.
# Targets PowerShell 7.1+ (Skillable "Execute Script in Cloud Platform").
# ---------------------------------------------------------------------------------------------

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
    <#
      Calls Microsoft Graph. Returns the parsed JSON as hashtables, $null for 404 when -Ok404,
      or the raw response object when -Raw (status, headers, content).
    #>
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
        # -SkipHttpErrorCheck (PowerShell 7.0+) returns 4xx/5xx responses instead of throwing.
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
    <# GET with paging (@odata.nextLink). #>
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
    <# Downloads a binary resource (file content) as a byte array. #>
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




# ---------------------------------------------------------------------------------------------
# Relative dates. Every time in the data pack is an offset from the event day (D0) in the event
# time zone, for example "D-9 09:12" or "D+10". The event day comes from the lab profile
# variable EventDate, so the Helix launch is always ten days out on the day of the event.
# ---------------------------------------------------------------------------------------------

# Windows time zone names (used by Exchange and the lab profile) to IANA names (used on Linux hosts).
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
    <# Resolves a Windows time zone name on Windows or Linux hosts. #>
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
    <# 'D-9 09:12' -> @{Days=-9; Time=09:12}; 'D+10' -> @{Days=10; Time=$null}. #>
    param([Parameter(Mandatory)][string]$Offset)
    if ($Offset -notmatch '^\s*D\s*([+-]\s*\d+)?\s*(?:(\d{1,2}):(\d{2}))?\s*$') { throw "Not a lab-day offset: '$Offset'" }
    $days = if ($Matches[1]) { [int]($Matches[1] -replace '\s', '') } else { 0 }
    $time = if ($Matches[2]) { [timespan]::new([int]$Matches[2], [int]$Matches[3], 0) } else { $null }
    return @{ Days = $days; Time = $time }
}

function Get-TimelineLocal {
    <# Wall-clock time in the event time zone (Kind = Unspecified). #>
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








# ---------------------------------------------------------------------------------------------
# Placeholder rendering for data pack text and Office files, and plain-text extraction from
# .docx/.xlsx/.pptx/.pdf for scoring. No external modules.
#
# Placeholders: {{learner}} {{learner_first}} {{learner_email}} {{date:D+2}} {{weekday:D+2}}
#               {{mention:learner}} (Teams @mention; plain name elsewhere)
# ---------------------------------------------------------------------------------------------

Add-Type -AssemblyName System.IO.Compression









function ConvertFrom-OfficeXml([string]$Xml) {
    $Xml = [regex]::Replace($Xml, '</(w:p|a:p|row|si)>', "`n")
    $Xml = [regex]::Replace($Xml, '<(w:tab|w:br)\s*/>', ' ')
    $t = [regex]::Replace($Xml, '<[^>]+>', '')
    return $t.Replace('&amp;', '&').Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"').Replace('&apos;', "'")
}

function ConvertFrom-Ascii85([string]$Text) {
    $out = [IO.MemoryStream]::new()
    $group = [System.Collections.Generic.List[int]]::new()
    $end = $Text.IndexOf('~>'); if ($end -ge 0) { $Text = $Text.Substring(0, $end) }
    if ($Text.StartsWith('<~')) { $Text = $Text.Substring(2) }
    foreach ($ch in $Text.ToCharArray()) {
        if ([char]::IsWhiteSpace($ch)) { continue }
        if ($ch -eq 'z' -and $group.Count -eq 0) { $out.Write([byte[]](0, 0, 0, 0), 0, 4); continue }
        $group.Add([int]$ch - 33)
        if ($group.Count -eq 5) {
            [uint32]$v = 0; foreach ($d in $group) { $v = [uint32]($v * 85 + $d) }
            $b = [BitConverter]::GetBytes($v); [array]::Reverse($b); $out.Write($b, 0, 4); $group.Clear()
        }
    }
    if ($group.Count -gt 0) {
        $n = $group.Count
        while ($group.Count -lt 5) { $group.Add(84) }
        [uint32]$v = 0; foreach ($d in $group) { $v = [uint32]($v * 85 + $d) }
        $b = [BitConverter]::GetBytes($v); [array]::Reverse($b); $out.Write($b, 0, $n - 1)
    }
    return , $out.ToArray()
}

function Expand-Zlib([byte[]]$Data) {
    $ms = [IO.MemoryStream]::new($Data, 2, $Data.Length - 2)   # skip the 2-byte zlib header
    $ds = [IO.Compression.DeflateStream]::new($ms, [IO.Compression.CompressionMode]::Decompress)
    $out = [IO.MemoryStream]::new()
    try { $ds.CopyTo($out) } catch { }   # a truncated adler32 trailer is fine
    $ds.Dispose()
    return , $out.ToArray()
}

function Get-PdfText([byte[]]$Data) {
    <#
      Best-effort PDF text without a library: decodes each content stream (ASCII85Decode and
      FlateDecode filters) and collects the strings drawn with Tj/TJ. Enough to find marker
      words such as UNCONFIRMED or a figure like 0.2.
    #>
    $latin = [Text.Encoding]::GetEncoding('ISO-8859-1')
    $raw = $latin.GetString($Data)
    $chunks = [System.Collections.Generic.List[string]]::new()
    $chunks.Add($raw)
    foreach ($m in [regex]::Matches($raw, 'stream\r?\n')) {
        $start = $m.Index + $m.Length
        $end = $raw.IndexOf('endstream', $start)
        if ($end -lt 0) { continue }
        $dictStart = $raw.LastIndexOf('<<', $m.Index)
        $dict = if ($dictStart -ge 0) { $raw.Substring($dictStart, $m.Index - $dictStart) } else { '' }
        try {
            $bytes = [byte[]]$Data[$start..($end - 1)]
            if ($dict -match 'ASCII85Decode') { $bytes = ConvertFrom-Ascii85 ($latin.GetString($bytes)) }
            if ($dict -match 'FlateDecode') { $bytes = Expand-Zlib $bytes }
            $chunks.Add($latin.GetString($bytes))
        }
        catch { }
    }
    $text = [Text.StringBuilder]::new()
    foreach ($c in $chunks) {
        foreach ($s in [regex]::Matches($c, '\(((?:\\.|[^\\)])*)\)')) { [void]$text.Append($s.Groups[1].Value).Append(' ') }
    }
    return $text.ToString()
}

function Get-FileText {
    <# Plain text of a file for scoring (.docx .xlsx .pptx .pdf and text formats). #>
    param([string]$Name, [byte[]]$Data)
    $low = $Name.ToLowerInvariant()
    try {
        if ($low -match '\.(docx|xlsx|pptx)$') {
            $z = [IO.Compression.ZipArchive]::new([IO.MemoryStream]::new($Data), [IO.Compression.ZipArchiveMode]::Read)
            $parts = $z.Entries | Where-Object { $_.FullName.EndsWith('.xml') -and $_.FullName -match '^(word/|xl/|ppt/slides/|ppt/notesSlides/)' } | Sort-Object FullName
            $texts = foreach ($p in $parts) {
                $r = [IO.StreamReader]::new($p.Open(), [Text.Encoding]::UTF8)
                ConvertFrom-OfficeXml $r.ReadToEnd()
                $r.Dispose()
            }
            $z.Dispose()
            return ($texts -join "`n")
        }
        if ($low.EndsWith('.pdf')) { return Get-PdfText $Data }
        if ($low -match '\.(md|txt|csv|json|yaml|yml|html|htm)$' -or $low -notmatch '\.[^/]+$') {
            $txt = [Text.Encoding]::UTF8.GetString($Data)
            if ($low -match '\.html?$') { $txt = [regex]::Replace($txt, '<[^>]+>', ' ') }
            return $txt
        }
    }
    catch { return '' }
    return ''
}
# ---------------------------------------------------------------------------------------------
# Scorecard checks against the learner's own mailbox, calendar and OneDrive, read directly through
# Microsoft Graph (not search), so results don't wait for indexing.
# Ported from the Cowork-Lab glc_hydrate engine (scoring.py). Check definitions come from
# scorecard.json, embedded by the build as $script:Scorecard.
# ---------------------------------------------------------------------------------------------

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
    <# Runs one scorecard check. Returns @{ passed = bool; detail = string }. #>
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
            $pat = $p.pattern.ToLowerInvariant()
            foreach ($i in (Get-ScoreItems $Ctx)) {
                if ($i.name.ToLowerInvariant().Contains($pat) -and (-not $p.files_only -or $i.ContainsKey('file'))) { return @{ passed = $true; detail = $i.name } }
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

function Invoke-Scorecard {
    <# All checks with guards; the same result shape as glc-hydrate score --json. #>
    param($Ctx)
    $sc = $Ctx.Scorecard
    $points = [ordered]@{}; $details = [ordered]@{}; $passed = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($c in $sc.checks) {
        try { $r = Test-ScoreCheck $Ctx $c } catch { $r = @{ passed = $false; detail = "error: $($_.Exception.Message)" } }
        $points[$c.id] = if ($r.passed) { [int]$c.points } else { 0 }
        $details[$c.id] = $r.detail
        if ($r.passed) { [void]$passed.Add($c.id) }
    }
    if ($sc.guards) {
        foreach ($cid in $sc.guards.Keys) {
            $g = $sc.guards[$cid]
            if ($g.enabled -and $passed.Contains($cid) -and -not ($g.requires_any | Where-Object { $passed.Contains($_) })) {
                $points[$cid] = 0; [void]$passed.Remove($cid); $details[$cid] += '; guard: no focus block was created'
            }
        }
    }
    $total = ($points.Values | Measure-Object -Sum).Sum
    return [ordered]@{
        learner = $Ctx.Upn; score = [int]$total; max = $sc.max; pass_mark = $sc.pass_mark; passed = ($total -ge $sc.pass_mark)
        checks = $points; details = $details
    }
}
$script:Scorecard = @'
{"checks":[{"type":"mail_contains","id":"drafts-saved","params":{"phrase":"Sent by Copilot Cowork","folders":["drafts","sentitems","inbox"]},"points":8},{"type":"event_exists","id":"focus-block-approved","params":{"subject":"Helix messaging review"},"points":7},{"type":"event_exists","id":"focus-block-always-allow","params":{"subject":"Helix launch checklist"},"points":7},{"type":"event_absent","id":"third-block-cancelled","params":{"subject":"Helix status review"},"points":10},{"type":"drive_file_contains","id":"risk-register-columns","params":{"phrase":"Source evidence","case_sensitive":false,"extensions":[".xlsx",".csv",".docx",".md"]},"points":10},{"type":"drive_file_contains","id":"unconfirmed-marked","params":{"phrase":"UNCONFIRMED","case_sensitive":true,"extensions":[".xlsx",".csv",".docx",".pptx",".pdf"],"exclude_name_patterns":["SKILL.md","skill-quality-report"]},"points":7},{"type":"drive_item_name","id":"skill-saved","params":{"pattern":"launch-status-report"},"points":12},{"type":"drive_item_name","id":"status-report-produced","params":{"pattern":"Helix-Status","files_only":true},"points":10},{"type":"mail_subject","id":"briefing-email-received","params":{"subject_prefix":"Helix launch briefing","folders":["inbox"]},"points":15},{"type":"drive_item_name","id":"meeting-prep-skill","params":{"pattern":"helix-meeting-prep"},"points":5},{"type":"drive_item_name","id":"companion-template","params":{"pattern":"brief-template","files_only":true},"points":4},{"type":"drive_item_name","id":"skill-inventory","params":{"pattern":"Skill-Inventory","files_only":true},"points":5}],"pass_mark":70,"window":{"start":"D-1","end":"D+14"},"max":100}
'@ | ConvertFrom-Json -AsHashtable -Depth 50
# ===== Run =====
Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$ctx = New-ScoreContext -LearnerUpn $LearnerUpn -Timeline (New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone) -Scorecard $script:Scorecard
Invoke-Scorecard $ctx | ConvertTo-Json -Depth 5