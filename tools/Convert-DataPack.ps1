<#
.SYNOPSIS
  Converts a Cowork-Lab data pack (helix-datapack-<version>.zip) into the gzipped JSON bundle
  the Skillable scripts load (datapack/helix-datapack-<version>.json.gz).

.DESCRIPTION
  Verifies the manifest checksums, parses source/*.yaml, and stores files and photos as base64.
  Dev-time only: needs the powershell-yaml module (Install-Module powershell-yaml -Scope CurrentUser).

.EXAMPLE
  ./tools/Convert-DataPack.ps1 -Zip ../Cowork-Lab/data/release/helix-datapack-1.0.0.zip
#>
param(
    [Parameter(Mandatory)][string]$Zip,
    [string]$OutDir = (Join-Path $PSScriptRoot '..' 'datapack')
)
$ErrorActionPreference = 'Stop'
Import-Module powershell-yaml
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$raw = @{}
$z = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Zip))
foreach ($e in $z.Entries) {
    if ($e.FullName.EndsWith('/')) { continue }
    $ms = [IO.MemoryStream]::new(); $s = $e.Open(); $s.CopyTo($ms); $s.Dispose()
    $raw[$e.FullName] = $ms.ToArray()
}
$z.Dispose()

if (-not $raw.ContainsKey('manifest.json')) { throw 'manifest.json missing' }
$manifest = [Text.Encoding]::UTF8.GetString($raw['manifest.json']) | ConvertFrom-Json -AsHashtable

# Checksums, exactly as the Python engine verifies them.
$sha = [Security.Cryptography.SHA256]::Create()
$problems = @()
foreach ($name in $manifest.sha256.Keys) {
    if (-not $raw.ContainsKey($name)) { $problems += "missing $name"; continue }
    $hex = -join ($sha.ComputeHash($raw[$name]) | ForEach-Object { $_.ToString('x2') })
    if ($hex -ne $manifest.sha256[$name]) { $problems += "checksum mismatch $name" }
}
if ($problems) { throw "Data pack failed verification: $($problems -join '; ')" }

$bundle = [ordered]@{ manifest = $manifest }
foreach ($src in 'company', 'people', 'mail', 'teams', 'calendar', 'documents') {
    $key = "source/$src.yaml"
    if (-not $raw.ContainsKey($key)) { throw "$key missing" }
    $bundle[$src] = ConvertFrom-Yaml ([Text.Encoding]::UTF8.GetString($raw[$key])) -Ordered
}
$bundle.files = [ordered]@{}
$bundle.photos = [ordered]@{}
foreach ($k in ($raw.Keys | Sort-Object)) {
    if ($k.StartsWith('files/')) { $bundle.files[$k.Substring(6)] = [Convert]::ToBase64String($raw[$k]) }
    elseif ($k.StartsWith('photos/')) { $bundle.photos[[IO.Path]::GetFileNameWithoutExtension($k)] = [Convert]::ToBase64String($raw[$k]) }
}

$json = $bundle | ConvertTo-Json -Depth 50 -Compress
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir "helix-datapack-$($manifest.version).json.gz"
$fs = [IO.File]::Create($out)
$gz = [IO.Compression.GZipStream]::new($fs, [IO.Compression.CompressionLevel]::Optimal)
$bytes = [Text.Encoding]::UTF8.GetBytes($json)
$gz.Write($bytes, 0, $bytes.Length); $gz.Dispose(); $fs.Dispose()
"{0}  ({1:N0} KB, {2} messages, {3} posts, {4} events, {5} files, {6} photos)" -f $out, ((Get-Item $out).Length / 1KB),
    $bundle.mail.messages.Count, $bundle.teams.posts.Count, $bundle.calendar.events.Count, $bundle.files.Count, $bundle.photos.Count
