# ---------------------------------------------------------------------------------------------
# Life cycle action: Readiness check (Post-Build, blocking, after Hydrate).
#
# Confirms the six day-one items from readiness.json are in place, and that no scoring check
# already passes on the fresh workspace (so nobody can score without doing the work).
# Ends the lab (Error Action) if anything is wrong. Ported from glc_hydrate ops/check.py
# (day-one items and scoring integrity; fact anchors and search indexing are left to the proctor
# spot-check because indexing takes longer than a build).
# ---------------------------------------------------------------------------------------------

function ConvertTo-UtcDate([string]$Iso) {
    $iso = [regex]::Replace($Iso, '(\.\d{6})\d+', '$1')
    return [datetime]::Parse($iso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]'AdjustToUniversal,AssumeUniversal')
}

function Get-HelixChannel([string]$TeamName) {
    $name = ConvertTo-ODataLiteral $TeamName
    foreach ($g in @((Invoke-Graph -Path "/groups?`$filter=displayName eq '$name'&`$select=id").value)) {
        $ext = Invoke-Graph -Path "/groups/$($g.id)/extensions/com.vectorsense.helixHydration" -Ok404
        if ($ext -and $ext.postsComplete) { return @{ teamId = $g.id; channelId = $ext.channelId } }
    }
    return $null
}

function Test-DayOneItem($Item, $Ctx) {
    $p = $Item.params
    switch ($Item.type) {
        'seat_access' {
            $u = Invoke-Graph -Path "/users/$($Ctx.LearnerId)?`$select=assignedLicenses"
            if (@($u.assignedLicenses).Count -eq 0) { return @{ ok = $false; detail = 'learner has no licences' } }
            return @{ ok = $true; detail = 'licensed (sign-in issued by Skillable at assignment)' }
        }
        'mail_thread' {
            $want = $p.subject_contains.ToLowerInvariant()
            $thread = @($Ctx.Inbox | Where-Object { "$($_.subject)".ToLowerInvariant().Contains($want) })
            $convs = @($thread | ForEach-Object { $_.conversationId } | Sort-Object -Unique)
            $note = "$($thread.Count) messages" + $(if ($convs.Count -gt 1) { " across $($convs.Count) conversations" } else { '' })
            return @{ ok = ($thread.Count -eq [int]$p.count); detail = $note }
        }
        'channel_messages' {
            if (-not $Ctx.Channel) { return @{ ok = $false; detail = 'Helix team not found' } }
            $msgs = Get-GraphAll -Path "/teams/$($Ctx.Channel.teamId)/channels/$($Ctx.Channel.channelId)/messages?`$expand=replies&`$top=50"
            $n = ($msgs | ForEach-Object { 1 + @($_.replies).Count } | Measure-Object -Sum).Sum
            return @{ ok = ($n -eq [int]$p.count); detail = "$n messages" }
        }
        'channel_files' {
            if (-not $Ctx.Channel) { return @{ ok = $false; detail = 'Helix team not found' } }
            $root = Invoke-Graph -Path "/teams/$($Ctx.Channel.teamId)/channels/$($Ctx.Channel.channelId)/filesFolder"
            $drive = $root.parentReference.driveId
            $parent = $root.id
            if ($p.folder) {
                $sub = Get-GraphAll -Path "/drives/$drive/items/$parent/children?`$select=id,name" | Where-Object { $_.name -eq $p.folder } | Select-Object -First 1
                if (-not $sub) { return @{ ok = $false; detail = "folder $($p.folder) missing" } }
                $parent = $sub.id
            }
            $names = @(Get-GraphAll -Path "/drives/$drive/items/$parent/children?`$select=id,name" | ForEach-Object { $_.name })
            $missing = @($p.names | Where-Object { $names -notcontains $_ })
            return @{ ok = ($missing.Count -eq 0); detail = $(if ($missing) { 'missing: ' + ($missing -join ', ') } else { "$(@($p.names).Count) files" }) }
        }
        'calendar_window' {
            $from = Get-TimelineUtcIso $Ctx.Timeline $p.from; $to = Get-TimelineUtcIso $Ctx.Timeline $p.to
            $evs = @(Get-GraphAll -Headers @{ Prefer = 'outlook.timezone="UTC"' } -Path "/users/$($Ctx.LearnerId)/calendarView?startDateTime=$from&endDateTime=$to&`$top=200&`$select=subject,start,end,isCancelled" |
                Where-Object { -not $_.isCancelled })
            $spans = @($evs | ForEach-Object { , @((ConvertTo-UtcDate $_.start.dateTime), (ConvertTo-UtcDate $_.end.dateTime)) } | Sort-Object { $_[0] })
            $overlaps = 0
            for ($i = 0; $i -lt $spans.Count - 1; $i++) { if ($spans[$i][1] -gt $spans[$i + 1][0]) { $overlaps++ } }
            $busy = @()
            $minutes = if ($p.slot_minutes) { [int]$p.slot_minutes } else { 30 }
            foreach ($slot in @($p.free_slots)) {
                $a = Get-TimelineUtc $Ctx.Timeline $slot; $b = $a.AddMinutes($minutes)
                if ($spans | Where-Object { $_[0] -lt $b -and $a -lt $_[1] }) { $busy += $slot }
            }
            $ok = ($evs.Count -eq [int]$p.count) -and ($overlaps -ge [int]$p.min_overlaps) -and -not $busy
            return @{ ok = $ok; detail = "$($evs.Count) meetings, $overlaps overlap(s)" + $(if ($busy) { ", busy: $($busy -join ', ')" } else { '' }) }
        }
        default { throw "Unknown day-one type '$($Item.type)'." }
    }
}

function Invoke-Readiness {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$LearnerUpn,
        [Parameter(Mandatory)][string]$EventDate,
        [Parameter(Mandatory)][string]$EventTimeZone,
        [Parameter(Mandatory)][string]$TeamName
    )
    Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $tl = New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone
    $score = New-ScoreContext -LearnerUpn $LearnerUpn -Timeline $tl -Scorecard $script:Scorecard
    $ctx = [pscustomobject]@{
        LearnerId = $score.UserId; Timeline = $tl; Channel = (Get-HelixChannel $TeamName)
        Inbox = @(Get-GraphAll -Limit 200 -Path "/users/$($score.UserId)/mailFolders/inbox/messages?`$select=id,subject,conversationId&`$top=100")
    }
    $failures = @()
    $report = [ordered]@{}
    foreach ($item in $script:Readiness.day_one) {
        try { $r = Test-DayOneItem $item $ctx } catch { $r = @{ ok = $false; detail = "error: $($_.Exception.Message)" } }
        $report[$item.id] = $r
        if (-not $r.ok) { $failures += "$($item.id): $($r.detail)" }
    }
    # Scoring integrity: nothing seeded may already satisfy a check (absence checks pass by design).
    foreach ($c in $script:Scorecard.checks) {
        if ($c.type -eq 'event_absent') { continue }
        try { $r = Test-ScoreCheck $score $c } catch { $r = @{ passed = $false } }
        if ($r.passed) { $failures += "integrity: check $($c.id) already passes ($($r.detail))" }
    }
    if ($failures) { throw ("Readiness check failed:`n- " + ($failures -join "`n- ")) }
    return $report
}
