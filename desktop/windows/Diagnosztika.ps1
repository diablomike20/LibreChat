#Requires -Version 5.1
# LibreChat Desktop hibaellenorzes: nem olvas .env/API-kulcsokat, nem torol adatokat.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'LibreChatDesktop'
$repo = Join-Path $root 'LibreChat'
$logs = Join-Path $root 'data\logs'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$report = Join-Path $root 'LIBRECHAT_HIBAJELENTES.txt'
$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('LibreChat Desktop - helyi hibajelentes')
$lines.Add(('Idopont: ' + (Get-Date).ToString('s')))
$lines.Add('Figyelem: megosztas elott nezd at, tartalmazhat helyi eleresi utakat.')
$lines.Add('')
$lines.Add(('Windows verzio: ' + [Environment]::OSVersion.VersionString))
$lines.Add(('64 bites OS: ' + [Environment]::Is64BitOperatingSystem))
$lines.Add(('Desktop forras letezik: ' + (Test-Path (Join-Path $repo 'desktop\main.cjs'))))
$lines.Add(('LibreChat backend forras letezik: ' + (Test-Path (Join-Path $repo 'api\server\index.js'))))
$lines.Add(('Frontend build letezik: ' + (Test-Path (Join-Path $repo 'client\dist\index.html'))))
$lines.Add(('Hordozo Node letezik: ' + (Test-Path (Join-Path $root 'runtime\node\node.exe'))))
$lines.Add(('Electron letezik: ' + (Test-Path (Join-Path $repo 'desktop\node_modules\electron\dist\electron.exe'))))
$lines.Add(('MongoDB adattar letezik: ' + (Test-Path (Join-Path $root 'data\mongodb'))))
$lines.Add('')
foreach ($file in @('bootstrap-last-error.txt','install-last-error.txt')) {
  $f = Join-Path $logs $file
  $lines.Add(('[ ' + $file + ' ]'))
  if (Test-Path $f) {
    foreach ($l in (Get-Content -LiteralPath $f -ErrorAction Stop)) {
      if ($l -match '^(Idopont|Lepes|Hiba|Telepitesi naplo|Reszletes naplo|Forrasmappa):') {
        $lines.Add($l)
      }
    }
  } else {
    $lines.Add('Nincs mentett hibajelentes (regi telepito vagy korai hiba).')
  }
  $lines.Add('')
}
$lines.Add('=== Telepitesi naplok (csak a fajlnevek, nem tartalom) ===')
if (Test-Path $logs) {
  Get-ChildItem -LiteralPath $logs -File | Sort-Object LastWriteTime -Descending |
    Select-Object -First 12 | ForEach-Object { $lines.Add(($_.Name + ' | ' + $_.Length + ' byte')) }
} else {
  $lines.Add('Nem jott letre naplo.')
}
$lines.Add('')
$lines.Add('Ne kuldd el az .env fajlt vagy API-kulcsaidat.')
[IO.File]::WriteAllLines($report, $lines.ToArray(), ([System.Text.UTF8Encoding]::new($false)))
Write-Host ('A hibajelentes elkeszult: ' + $report) -ForegroundColor Green
Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $report + '"')
