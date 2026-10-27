# ---------------------------------------------------------------------------------------------
# Helix data pack at runtime. The build step converts the Cowork-Lab data pack (zip of YAML and
# binary files) into one gzipped JSON bundle. It is either embedded in the script
# ($script:HelixPackEmbedded, base64) or downloaded from the DataPackUrl lab variable.
#
# Bundle shape: { manifest, company, people, mail, teams, calendar, files: {name: base64},
#                 photos: {key: base64} }
# ---------------------------------------------------------------------------------------------

function Expand-HelixBundle([byte[]]$Gzip) {
    $in = [IO.Compression.GZipStream]::new([IO.MemoryStream]::new($Gzip), [IO.Compression.CompressionMode]::Decompress)
    $r = [IO.StreamReader]::new($in, [Text.Encoding]::UTF8)
    $json = $r.ReadToEnd(); $r.Dispose()
    return ($json | ConvertFrom-Json -AsHashtable -Depth 50)
}

function Get-HelixPack {
    param([string]$Url)
    $bytes = $null
    if ($script:HelixPackEmbedded) {
        $bytes = [Convert]::FromBase64String($script:HelixPackEmbedded)
    }
    elseif ($Url -and $Url -notmatch '^@lab') {
        $tmp = [IO.Path]::GetTempFileName()
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
            $bytes = [IO.File]::ReadAllBytes($tmp)
        }
        finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
    else { throw 'No data pack: build with -EmbedDataPack or set the DataPackUrl lab variable.' }
    $pack = Expand-HelixBundle $bytes
    foreach ($k in 'manifest', 'company', 'people', 'mail', 'teams', 'calendar', 'files', 'photos') {
        if (-not $pack.ContainsKey($k)) { throw "Data pack is missing '$k'." }
    }
    return $pack
}

function Get-PackFile($Pack, [string]$Name) { return , [Convert]::FromBase64String($Pack.files[$Name]) }
function Get-PackPhoto($Pack, [string]$Key) {
    if (-not $Pack.photos.ContainsKey($Key)) { return $null }
    return , [Convert]::FromBase64String($Pack.photos[$Key])
}

function Get-PackPerson($Pack, [string]$Key) {
    foreach ($p in $Pack.people.internal) { if ($p.key -eq $Key) { return $p + @{ kind = 'internal' } } }
    foreach ($p in $Pack.people.external) { if ($p.key -eq $Key) { return $p + @{ kind = 'external' } } }
    throw "Unknown person key '$Key'."
}

function Get-PackDisplayName($Person) { return "$($Person.given) $($Person.surname)" }

function Get-PackFileLayout($Pack) {
    <# [(subfolder or $null, file name)] for the channel files folder. #>
    $channel = $Pack.teams.team.channels[0]
    $out = @()
    foreach ($folder in $channel.files_folder.Keys) {
        foreach ($n in $channel.files_folder[$folder]) {
            $out += , @($(if ($folder -eq 'shared') { $null } else { $folder }), $n)
        }
    }
    return $out
}
