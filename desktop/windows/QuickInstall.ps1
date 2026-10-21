#Requires -Version 5.1
<#
One-entry Windows bootstrap for this branch. Downloads your own fork source ZIP
and starts the repo's desktop/windows/Install.ps1. No Docker/Git prerequisite.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$branch = 'feature/windows-desktop-dockerless-poc'
$sourceUrl = 'https://github.com/diablomike20/LibreChat/archive/refs/heads/feature/windows-desktop-dockerless-poc.zip'
$root = Join-Path $env:LOCALAPPDATA 'LibreChatDesktop'
$repo = Join-Path $root 'LibreChat'
New-Item -ItemType Directory -Force -Path $root | Out-Null

if (-not (Test-Path (Join-Path $repo 'desktop\windows\Install.ps1'))) {
  Write-Host "A sajat LibreChat fork ($branch) letoltese..." -ForegroundColor Cyan
  $temp = Join-Path $env:TEMP 'librechat-desktop-bootstrap'
  $archive = Join-Path $env:TEMP 'librechat-desktop-source.zip'
  if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
  if (Test-Path $archive) { Remove-Item -Force $archive }
  try {
    Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing -OutFile $archive
    Expand-Archive -Path $archive -DestinationPath $temp
    $source = Get-ChildItem -Path $temp -Directory | Where-Object {
      Test-Path (Join-Path $_.FullName 'desktop\windows\Install.ps1')
    } | Select-Object -First 1
    if (-not $source) { throw 'A forras ZIP nem tartalmazza a Desktop modult.' }
    if (Test-Path $repo) {
      throw "A celmappa mar letezik, de hianyos: $repo. Vizsgald meg, mielott barmit felulirnal."
    }
    Move-Item -Path $source.FullName -Destination $repo
  } finally {
    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    if (Test-Path $archive) { Remove-Item -Force $archive }
  }
}
Write-Host 'LibreChat Desktop Windows telepito inditasa...' -ForegroundColor Cyan
& (Join-Path $repo 'desktop\windows\Install.ps1')
if (-not $?) { throw 'A LibreChat Desktop telepites sikertelen.' }
