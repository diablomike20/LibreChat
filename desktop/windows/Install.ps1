#Requires -Version 5.1
<#
LibreChat Desktop Windows first-run installer (proof of concept).
Starts no Docker service, writes only to the current user's LocalAppData.
Expected location: <LibreChatRepo>\desktop\windows\Install.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step([string]$msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function New-Secret([int]$length = 32) {
  $bytes = New-Object byte[] $length
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}
function Save-Utf8NoBom([string]$path, [string]$value) {
  [IO.File]::WriteAllText($path, $value, (New-Object Text.UTF8Encoding($false)))
}
function Set-DotEnv([string]$name, [string]$value) {
  $body = [IO.File]::ReadAllText($script:envFile)
  $pattern = '(?m)^' + [regex]::Escape($name) + '=.*$'
  if ([regex]::IsMatch($body, $pattern)) {
    $body = [regex]::Replace($body, $pattern, ($name + '=' + $value))
  } else {
    $body += "`n$name=$value`n"
  }
  Save-Utf8NoBom $script:envFile $body
}
function RunChecked([string]$exe, [string[]]$arguments, [string]$working) {
  Push-Location $working
  try {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed (code $LASTEXITCODE)." }
  } finally { Pop-Location }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows 10/11 rendszer szukseges.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Ez a telepito csak 64 bites Windowson mukodik.' }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path (Join-Path $repo 'api\server\index.js'))) { throw 'A LibreChat teljes forraskodja hianyzik.' }
$localRoot = Join-Path $env:LOCALAPPDATA 'LibreChatDesktop'
$nodeDir = Join-Path $localRoot 'runtime\node'
$nodeExe = Join-Path $nodeDir 'node.exe'
$npmCmd = Join-Path $nodeDir 'npm.cmd'
New-Item -ItemType Directory -Force -Path $localRoot | Out-Null

Step '1/5: Hordozhato Node.js 24.16.0 ellenorzese'
if (-not (Test-Path $nodeExe)) {
  $zipPath = Join-Path $env:TEMP 'librechat-node-v24.16.0.zip'
  $nodeUrl = 'https://nodejs.org/dist/v24.16.0/node-v24.16.0-win-x64.zip'
  $expectedSHA256 = 'edaca9bd58ec8e92037dac4e877d52f6b8f430b81c18b57e264b4e2fb111cd56'
  Invoke-WebRequest -Uri $nodeUrl -OutFile $zipPath -UseBasicParsing
  if ((Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSHA256) {
    Remove-Item -Force $zipPath
    throw 'Node.js ZIP ellenorzesi osszeg elter. A telepites leallt.'
  }
  $extract = Join-Path $env:TEMP 'librechat-node-portable-unzip'
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive -Path $zipPath -DestinationPath $extract
  New-Item -ItemType Directory -Force -Path (Split-Path $nodeDir -Parent) | Out-Null
  Move-Item -Path (Join-Path $extract 'node-v24.16.0-win-x64') -Destination $nodeDir
  Remove-Item -Recurse -Force $extract
  Remove-Item -Force $zipPath
}
if (-not (Test-Path $npmCmd)) { throw 'A Node.js telepites hianyos (npm.cmd nem talalhato).' }
$env:PATH = $nodeDir + ';' + $env:PATH
RunChecked -exe $nodeExe -arguments @('--version') -working $repo

Step '2/5: Helyi konfiguracio (egyedi titkos kulcsok, csak localhost)'
$script:envFile = Join-Path $repo '.env'
if (-not (Test-Path $script:envFile)) {
  Copy-Item (Join-Path $repo '.env.example') $script:envFile
  Set-DotEnv 'JWT_SECRET' (New-Secret 48)
  Set-DotEnv 'JWT_REFRESH_SECRET' (New-Secret 48)
  # CREDS_KEY / CREDS_IV persist in LocalAppData via LIBRECHAT_TEMP_CREDENTIALS_PATH.
}
Set-DotEnv 'HOST' '127.0.0.1'
Set-DotEnv 'DOMAIN_CLIENT' 'http://127.0.0.1:3080'
Set-DotEnv 'DOMAIN_SERVER' 'http://127.0.0.1:3080'
Set-DotEnv 'SEARCH' 'false'
Set-DotEnv 'ALLOW_REGISTRATION' 'true'
Set-DotEnv 'ALLOW_EMAIL_LOGIN' 'true'
Set-DotEnv 'SESSION_COOKIE_SECURE' 'false'
# MONGO_URI and PORT are assigned dynamically by Electron on each launch.

Step '3/5: LibreChat fuggosegek telepitese'
RunChecked -exe $npmCmd -arguments @('ci', '--no-audit', '--no-fund') -working $repo
Step '4/5: LibreChat frontend es kozos csomagok forditasa'
$env:NODE_OPTIONS = '--max-old-space-size=8192'
RunChecked -exe $npmCmd -arguments @('run', 'frontend') -working $repo
if (-not (Test-Path (Join-Path $repo 'client\dist\index.html'))) { throw 'A LibreChat frontend build nem jott letre.' }

Step '5/5: Electron + helyi MongoDB motor telepitese'
$desktopDir = Join-Path $repo 'desktop'
RunChecked -exe $npmCmd -arguments @('install', '--no-audit', '--no-fund', '--prefix', $desktopDir) -working $repo
$electronExe = Join-Path $desktopDir 'node_modules\electron\dist\electron.exe'
if (-not (Test-Path $electronExe)) { throw 'Az Electron binaris hianyzik a telepites utan.' }

Step 'Windows Start menu es asztali parancsikon'
$wsh = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$targets = @((Join-Path $startMenu 'LibreChat Desktop.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'LibreChat Desktop.lnk'))
foreach ($target in $targets) {
  $shortcut = $wsh.CreateShortcut($target)
  $shortcut.TargetPath = $electronExe
  $shortcut.Arguments = ('"' + $desktopDir + '"')
  $shortcut.WorkingDirectory = $desktopDir
  $shortcut.Description = 'LibreChat Desktop – helyi Windows alkalmazas Docker nelkul'
  $shortcut.IconLocation = "$electronExe,0"
  $shortcut.Save()
}
Write-Host "`nKESZ. LibreChat Desktop az asztalon es a Start menuben." -ForegroundColor Green
Write-Host 'Elso inditaskor a MongoDB binaris automatikusan letoltodik. Ez internetet igenyel.'
Write-Host 'A MongoDB adatok es a naplok a LocalAppData\LibreChatDesktop\data mappaban maradnak.'
Write-Host 'Az AI szolgaltatokhoz szukseges kulcsokat kulon kell megadni a LibreChat beallitasainal.'
Step 'Alkalmazas inditasa'
Start-Process -FilePath $electronExe -ArgumentList ('"' + $desktopDir + '"') -WorkingDirectory $desktopDir
