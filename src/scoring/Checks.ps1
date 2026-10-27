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
