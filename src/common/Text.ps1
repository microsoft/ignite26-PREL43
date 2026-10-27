# ---------------------------------------------------------------------------------------------
# Placeholder rendering for data pack text and Office files, and plain-text extraction from
# .docx/.xlsx/.pptx/.pdf for scoring. No external modules.
#
# Placeholders: {{learner}} {{learner_first}} {{learner_email}} {{date:D+2}} {{weekday:D+2}}
#               {{mention:learner}} (Teams @mention; plain name elsewhere)
# ---------------------------------------------------------------------------------------------

Add-Type -AssemblyName System.IO.Compression

function ConvertTo-HtmlText([string]$Text) {
    # html.escape(quote=False): only &, <, >
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Format-HelixText {
    <# Renders {{...}} placeholders. $Context: Timeline, Learner, LearnerFirst, LearnerEmail. #>
    param([string]$Text, $Context, [switch]$Escape)
    if ($null -eq $Text) { return '' }
    return [regex]::Replace($Text, '\{\{\s*([a-z_]+)(?::([^}]+))?\s*\}\}', {
            param($m)
            $name = $m.Groups[1].Value
            $arg = $m.Groups[2].Value.Trim()
            $v = switch ($name) {
                'learner' { $Context.Learner }
                'learner_first' { $Context.LearnerFirst }
                'learner_email' { $Context.LearnerEmail }
                'date' { Get-TimelineDateText $Context.Timeline $arg }
                'weekday' { Get-TimelineWeekday $Context.Timeline $arg }
                'mention' { $Context.Learner }
                default { throw "Unknown placeholder {{$name}}" }
            }
            if ($Escape) { ConvertTo-HtmlText $v } else { $v }
        })
}

function ConvertTo-ParagraphHtml([string]$Text) {
    <# Plain text with blank-line paragraphs -> simple HTML. #>
    $paras = @(($Text.Trim() -split "`n`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $out = foreach ($p in $paras) {
        '<p>' + ((($p -split "`n") | ForEach-Object { ConvertTo-HtmlText $_ }) -join '<br>') + '</p>'
    }
    return ($out -join "`n")
}

function Format-OfficeFile {
    <# Renders placeholders inside the XML parts of a .docx/.xlsx/.pptx; other files pass through. #>
    param([string]$Name, [byte[]]$Data, $Context)
    if ($Name -notmatch '\.(docx|xlsx|pptx)$') { return , $Data }
    $src = [IO.Compression.ZipArchive]::new([IO.MemoryStream]::new($Data), [IO.Compression.ZipArchiveMode]::Read)
    $buf = [IO.MemoryStream]::new()
    $dst = [IO.Compression.ZipArchive]::new($buf, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($entry in $src.Entries) {
        $ms = [IO.MemoryStream]::new()
        $s = $entry.Open(); $s.CopyTo($ms); $s.Dispose()
        $raw = $ms.ToArray()
        if ($entry.FullName.EndsWith('.xml')) {
            $txt = [Text.Encoding]::UTF8.GetString($raw)
            if ($txt.Contains('{{')) { $raw = [Text.Encoding]::UTF8.GetBytes((Format-HelixText -Text $txt -Context $Context -Escape)) }
        }
        $out = $dst.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
        $out.LastWriteTime = $entry.LastWriteTime
        $w = $out.Open(); $w.Write($raw, 0, $raw.Length); $w.Dispose()
    }
    $dst.Dispose(); $src.Dispose()
    return , $buf.ToArray()
}

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
