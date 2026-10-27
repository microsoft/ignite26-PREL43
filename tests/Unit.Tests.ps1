BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src'
    . (Join-Path $src 'common/Graph.ps1')
    . (Join-Path $src 'common/Timeline.ps1')
    . (Join-Path $src 'common/Text.ps1')
    . (Join-Path $src 'common/DataPack.ps1')
    . (Join-Path $src 'lifecycle/Hydrate.ps1')
    $packPath = Join-Path $PSScriptRoot '..' 'datapack' 'helix-datapack-1.0.0.json.gz'
    $script:HelixPackEmbedded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($packPath))
    $script:Pack = Get-HelixPack
    $script:Tl = New-Timeline -EventDate '2026-11-18' -TimeZoneName 'India Standard Time'
    $script:Ctx = [pscustomobject]@{ Timeline = $script:Tl; Learner = 'Asha Kumar'; LearnerFirst = 'Asha'; LearnerEmail = 'asha@lab.test' }
}

Describe 'Timeline' {
    It 'parses offsets' {
        (ConvertFrom-Offset 'D-9 09:12').Days | Should -Be -9
        (ConvertFrom-Offset 'D-9 09:12').Time | Should -Be ([timespan]'09:12:00')
        (ConvertFrom-Offset 'D+10').Days | Should -Be 10
        (ConvertFrom-Offset 'D').Days | Should -Be 0
        { ConvertFrom-Offset 'tomorrow' } | Should -Throw
    }
    It 'converts event-local times to UTC (IST is UTC+5:30)' {
        Get-TimelineUtcIso $Tl 'D-1 09:00' | Should -Be '2026-11-17T03:30:00.000Z'
        Get-TimelineLocalIso $Tl 'D+1 11:00' | Should -Be '2026-11-19T11:00:00'
    }
    It 'renders date and weekday text like the Python engine' {
        Get-TimelineDateText $Tl 'D+10' | Should -Be 'Saturday 28 November 2026'
        Get-TimelineWeekday $Tl 'D+2' | Should -Be 'Friday'
    }
    It 'resolves Windows time zone names' {
        (Get-EventTimeZone 'Pacific Standard Time').BaseUtcOffset.TotalHours | Should -Be -8
        { Get-EventTimeZone 'Mars Standard Time' } | Should -Throw
    }
}

Describe 'Text rendering' {
    It 'renders placeholders' {
        Format-HelixText -Text 'Hi {{learner_first}}, ship date {{date:D+10}} ({{weekday:D+10}}). {{learner}} <{{learner_email}}>' -Context $Ctx |
            Should -Be 'Hi Asha, ship date Saturday 28 November 2026 (Saturday). Asha Kumar <asha@lab.test>'
    }
    It 'escapes for XML when asked' {
        $c = [pscustomobject]@{ Timeline = $Tl; Learner = 'A & B <C>'; LearnerFirst = 'A'; LearnerEmail = 'x' }
        Format-HelixText -Text '{{learner}}' -Context $c -Escape | Should -Be 'A &amp; B &lt;C&gt;'
    }
    It 'builds paragraph HTML' {
        ConvertTo-ParagraphHtml "Hi Nadia,`n`nLine one`nLine <two>" | Should -Be "<p>Hi Nadia,</p>`n<p>Line one<br>Line &lt;two&gt;</p>"
    }
}

Describe 'Office files from the data pack' {
    It 'extracts text from the real Helix spec (.docx) and pricing (.xlsx)' {
        (Get-FileText -Name 'Helix-Product-Spec.docx' -Data (Get-PackFile $Pack 'Helix-Product-Spec.docx')) | Should -Match 'FCC and CE certification'
        (Get-FileText -Name 'Helix-Pricing.xlsx' -Data (Get-PackFile $Pack 'Helix-Pricing.xlsx')) | Should -Match '279'
    }
    It 'extracts text from the competitor PDF (readiness anchor F5 expects 0.2)' {
        (Get-FileText -Name 'Competitor-1-SensorCloud.pdf' -Data (Get-PackFile $Pack 'Competitor-1-SensorCloud.pdf')) | Should -Match '0\.2'
    }
    It 'renders placeholders inside Office XML and leaves a valid file' {
        $out = Format-OfficeFile -Name 'Helix-Launch-Plan.docx' -Data (Get-PackFile $Pack 'Helix-Launch-Plan.docx') -Context $Ctx
        $text = Get-FileText -Name 'x.docx' -Data $out
        $text | Should -Not -Match '\{\{'
        $text | Should -Match 'Helix'
    }
    It 'passes non-Office files through unchanged' {
        $pdf = Get-PackFile $Pack 'Competitor-2-EdgeSense.pdf'
        (Format-OfficeFile -Name 'a.pdf' -Data $pdf -Context $Ctx).Length | Should -Be $pdf.Length
    }
}

Describe 'Data pack bundle' {
    It 'has the counts in its manifest' {
        $Pack.mail.messages.Count | Should -Be $Pack.manifest.counts.messages
        $Pack.teams.posts.Count | Should -Be $Pack.manifest.counts.channel_posts
        $Pack.calendar.events.Count | Should -Be $Pack.manifest.counts.events
        $Pack.people.internal.Count | Should -Be $Pack.manifest.counts.personas
    }
    It 'needs exactly six meeting organisers' {
        (Get-OrganiserKeys $Pack) -join ',' | Should -Be 'chloe,elena,ethan,grace,nadia,tomas'
    }
    It 'lays out channel files with a Recordings subfolder' {
        $layout = Get-PackFileLayout $Pack
        @($layout | Where-Object { $_[0] -eq 'Recordings' }).Count | Should -Be 2
        @($layout | Where-Object { -not $_[0] }).Count | Should -Be 6
    }
}

Describe 'Mail threading (PidTagConversationIndex)' {
    It 'matches the Python engine byte for byte' {
        $seed = 'labuser@ignite.test/supplier'
        $f = [datetime]::new(2026, 11, 9, 3, 42, 0, [DateTimeKind]::Utc)
        $a = Get-ConversationIndex -Parent $null -First $f -Current $f -Seed $seed -Seq 0
        $b = Get-ConversationIndex -Parent $a -First $f -Current ([datetime]::new(2026, 11, 9, 8, 15, 0, [DateTimeKind]::Utc)) -Seed $seed -Seq 1
        $c = Get-ConversationIndex -Parent $b -First $f -Current ([datetime]::new(2026, 11, 12, 11, 5, 0, [DateTimeKind]::Utc)) -Seed $seed -Seq 2
        $d = Get-ConversationIndex -Parent $c -First $f -Current ([datetime]::new(2027, 6, 1, 0, 0, 0, [DateTimeKind]::Utc)) -Seed $seed -Seq 3
        [Convert]::ToBase64String($a) | Should -Be 'AQHdb/xG+qN8jqrdV2GP5M7JaDOqPA=='
        [Convert]::ToBase64String($b) | Should -Be 'AQHdb/xG+qN8jqrdV2GP5M7JaDOqPAAJiP1x'
        [Convert]::ToBase64String($c) | Should -Be 'AQHdb/xG+qN8jqrdV2GP5M7JaDOqPAAJiP1xAKZYuOI='
        [Convert]::ToBase64String($d) | Should -Be 'AQHdb/xG+qN8jqrdV2GP5M7JaDOqPAAJiP1xAKZYuOIoC7JqUw=='
    }
}

Describe 'Hydration window' {
    It 'refuses to run before D-1 09:30 in the event time zone' {
        $future = New-Timeline -EventDate ((Get-Date).AddDays(5).ToString('yyyy-MM-dd')) -TimeZoneName 'UTC'
        { Assert-HydrationWindow $future $Pack } | Should -Throw '*Outside the hydration window*'
    }
    It 'refuses to run after the event day' {
        $past = New-Timeline -EventDate ((Get-Date).AddDays(-3).ToString('yyyy-MM-dd')) -TimeZoneName 'UTC'
        { Assert-HydrationWindow $past $Pack } | Should -Throw '*has passed*'
    }
    It 'runs on the event day' {
        $today = New-Timeline -EventDate ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')) -TimeZoneName 'UTC'
        { Assert-HydrationWindow $today $Pack } | Should -Not -Throw
    }
}

# The fake tenant replaces Invoke-Graph, so these run the real one. Pester mocks keep the real
# Invoke-WebRequest parameters, so a parameter the cmdlet doesn't have fails here too.
Describe 'Graph client against Invoke-WebRequest' {
    BeforeAll {
        function New-Resp([int]$Status, [string]$Content, [hashtable]$Headers = @{}) {
            $h = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new()
            foreach ($k in $Headers.Keys) { $h[$k] = [string[]]@($Headers[$k]) }
            if ($Content) { $h['Content-Type'] = [string[]]@('application/json; charset=utf-8') }
            return [pscustomobject]@{ StatusCode = $Status; Headers = $h; Content = $Content }
        }
    }
    BeforeEach { Mock Get-GraphToken { 'token' }; Mock Start-Sleep { } }
    It 'returns parsed JSON' {
        Mock Invoke-WebRequest { New-Resp 200 '{"id":"u1","value":[1,2]}' }
        (Invoke-Graph -Path '/users/x').id | Should -Be 'u1'
    }
    It 'retries 429 using Retry-After, then succeeds' {
        $script:calls = 0
        Mock Invoke-WebRequest { $script:calls++; if ($script:calls -eq 1) { New-Resp 429 '{"error":{"code":"TooMany"}}' @{ 'Retry-After' = '3' } } else { New-Resp 200 '{"ok":true}' } }
        (Invoke-Graph -Path '/x').ok | Should -BeTrue
        Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -ge 3 }
    }
    It 'returns $null for 404 with -Ok404, and throws GraphError with status otherwise' {
        Mock Invoke-WebRequest { New-Resp 404 '{"error":{"code":"Request_ResourceNotFound","message":"nope"}}' }
        Invoke-Graph -Path '/x' -Ok404 | Should -BeNullOrEmpty
        $err = $null
        try { Invoke-Graph -Path '/x' } catch { $err = $_.Exception }
        $err.Status | Should -Be 404
        $err.Code | Should -Be 'Request_ResourceNotFound'
    }
    It 'exposes headers on -Raw (Teams creation reads Location)' {
        Mock Invoke-WebRequest { New-Resp 202 '' @{ Location = "/teams('t1')/operations('o1')" } }
        $r = Invoke-Graph -Method POST -Path '/teams' -Body @{ a = 1 } -Raw
        $r.Status | Should -Be 202
        "$($r.Headers['Location'])" | Should -Be "/teams('t1')/operations('o1')"
    }
}
