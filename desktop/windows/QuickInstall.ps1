#Requires -Version 5.1
<#
LibreChat Desktop - ujraprobalhato bootstrap, Docker es Git nelkul.
Minden inditasnal frissiti a desktop modul forrasat a sajat GitHub-forkbol,
de NEM torli az adatbazist, a felhasznaloi .env-et vagy a node_modules-t.
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
$logDir = Join-Path $root 'data\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$bootstrapError = Join-Path $logDir 'bootstrap-last-error.txt'
$step = 'Forras letoltese'
try {
  Write-Host 'LibreChat Desktop forras frissitese a sajat GitHub-forkbol...' -ForegroundColor Cyan
  $temp = Join-Path $env:TEMP 'librechat-desktop-bootstrap'
  $archive = Join-Path $env:TEMP 'librechat-desktop-source.zip'
  if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
  if (Test-Path $archive) { Remove-Item -Force $archive }

  try {
    Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing -OutFile $archive
    $step = 'Forras ZIP kibontasa'
    Expand-Archive -Path $archive -DestinationPath $temp -Force
    $source = Get-ChildItem -Path $temp -Directory | Where-Object {
      Test-Path (Join-Path $_.FullName 'desktop\windows\Install.ps1')
    } | Select-Object -First 1
    if (-not $source) { throw 'A letoltott ZIP nem tartalmazza a Desktop modult.' }

    $step = 'Forraskod telepitese/frissitese'
    if (-not (Test-Path $repo)) {
      Move-Item -Path $source.FullName -Destination $repo
    } else {
      if (-not (Test-Path (Join-Path $repo 'api\server\index.js'))) {
        throw ('A korabbi forras hianyos: ' + $repo + '. Az adatokat ne torold; a mappat kulon mentsd.')
      }
      # Csak a Desktop modul ismert forrasfajljait frissitjuk, a nagy
      # LibreChat forrast/konfiguraciot/adatbazist megorizzuk.
      $desktopFiles = @(
        'main.cjs', 'backend-control.cjs', 'runtime.cjs', 'runtime.test.cjs', 'status.html',
        'package.json', 'README.hu.md', 'windows\Diagnosztika.ps1', 'windows\Diagnosztika.cmd', 'windows\Install.ps1',
        'windows\QuickInstall.ps1', 'windows\Telepites.cmd'
      )
      foreach ($rel in $desktopFiles) {
        $from = Join-Path (Join-Path $source.FullName 'desktop') $rel
        $to = Join-Path (Join-Path $repo 'desktop') $rel
        if (-not (Test-Path $from)) { throw ('Frissito fajl hianyzik: ' + $rel) }
        New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
      }
      Write-Host 'Korabbi telepitesi adatok es beallitasok megtartva.' -ForegroundColor Green
    }
  } finally {
    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    if (Test-Path $archive) { Remove-Item -Force $archive }
  }

  $step = 'LibreChat Desktop telepites'
  Write-Host 'LibreChat Desktop telepito inditasa...' -ForegroundColor Cyan
  & (Join-Path $repo 'desktop\windows\Install.ps1')
  if (-not $?) { throw 'A LibreChat Desktop telepites sikertelen.' }
  if (Test-Path $bootstrapError) { Remove-Item -Force $bootstrapError }
} catch {
  $message = $_.Exception.Message
  $errorText = @(
    ('Idopont: ' + (Get-Date).ToString('s')),
    ('Lepes: ' + $step),
    ('Hiba: ' + $message),
    ('Forrasmappa: ' + $repo),
    ('Reszletes naplo: ' + $logDir)
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($bootstrapError, $errorText, ([System.Text.UTF8Encoding]::new($false)))
  Write-Host ''
  Write-Host ('HIBA a ' + $step + ' lepesnel: ' + $message) -ForegroundColor Red
  Write-Host ('Hibajelentes: ' + $bootstrapError) -ForegroundColor Yellow
  throw
}
