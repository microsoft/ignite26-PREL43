<#
.SYNOPSIS
  Downloads the portable PowerShell 7 (Windows x64 zip) from Microsoft's GitHub releases into vendor/,
  so the build can put it on the HelixKit media for VMs without PowerShell 7 installed.
#>
param([string]$Version = '7.4.6')
$ErrorActionPreference = 'Stop'
$dest = Join-Path $PSScriptRoot '..' 'vendor'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$file = Join-Path $dest "PowerShell-$Version-win-x64.zip"
if (Test-Path $file) { "Already present: $file"; return }
Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip" -OutFile $file -UseBasicParsing
"Downloaded $file ({0:N0} MB)" -f ((Get-Item $file).Length / 1MB)
