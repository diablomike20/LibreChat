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

function Step([string]$msg) { $script:InstallStage = $msg; Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function New-Secret([int]$length = 32) {
  $bytes = New-Object byte[] $length
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}
function Save-Utf8NoBom([string]$path, [string]$value) {
  [IO.File]::WriteAllText($path, $value, ([System.Text.UTF8Encoding]::new($false)))
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

$script:InstallStage = 'Telepites elokeszitese'
$script:InstallLogs = Join-Path $env:LOCALAPPDATA 'LibreChatDesktop\data\logs'
New-Item -ItemType Directory -Force -Path $script:InstallLogs | Out-Null
$script:InstallLog = Join-Path $script:InstallLogs ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$script:InstallError = Join-Path $script:InstallLogs 'install-last-error.txt'
Start-Transcript -Path $script:InstallLog -Append | Out-Null
try {
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

# The official LibreChat npm install guide pins npm 11.13.0.
# Node 24.16.0 ships npm 11.13.0: using the bundled one is a version mismatch.
$npmPrefix = Join-Path $localRoot 'runtime\npm-11.13'
$npmCli = Join-Path $npmPrefix 'node_modules\npm\bin\npm-cli.js'
if (-not (Test-Path $npmCli)) {
  Step '1b/5: LibreChat-hez elvart npm 11.13.0 telepitese'
  RunChecked -exe $npmCmd -arguments @('install', '--prefix', $npmPrefix, '--no-audit', '--no-fund', '--no-save', 'npm@11.13.0') -working $repo
}
if (-not (Test-Path $npmCli)) { throw 'A rögzített npm 11.13.0 telepitese sikertelen.' }
RunChecked -exe $nodeExe -arguments @($npmCli, '--version') -working $repo

Step '2/5: Helyi konfiguracio (egyedi titkos kulcsok, csak localhost)'
$script:envFile = Join-Path $repo '.env'
if (-not (Test-Path $script:envFile)) {
  Copy-Item (Join-Path $repo '.env.example') $script:envFile
}
# A failed first install can leave an existing .env with empty secrets.
# Fill only missing/blank values; never rotate valid secrets on repair.
$envBody = [IO.File]::ReadAllText($script:envFile)
foreach ($secret in @(
  @{ Name = 'JWT_SECRET'; Value = (New-Secret 48) },
  @{ Name = 'JWT_REFRESH_SECRET'; Value = (New-Secret 48) },
  @{ Name = 'CREDS_KEY'; Value = (New-Secret 16) },
  @{ Name = 'CREDS_IV'; Value = (New-Secret 8) }
)) {
  $pattern = '(?m)^' + [regex]::Escape($secret.Name) + '=(.*)$'
  $match = [regex]::Match($envBody, $pattern)
  if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) {
    Set-DotEnv $secret.Name $secret.Value
    $envBody = [IO.File]::ReadAllText($script:envFile)
  }
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
RunChecked -exe $nodeExe -arguments @($npmCli, 'ci', '--no-audit', '--no-fund') -working $repo
Step '4/5: LibreChat frontend es kozos csomagok forditasa'
$env:NODE_OPTIONS = '--max-old-space-size=8192'
RunChecked -exe $nodeExe -arguments @($npmCli, 'run', 'frontend') -working $repo
if (-not (Test-Path (Join-Path $repo 'client\dist\index.html'))) { throw 'A LibreChat frontend build nem jott letre.' }

Step '5/5: Electron + helyi MongoDB motor telepitese'
$desktopDir = Join-Path $repo 'desktop'
# Require devDependencies, lifecycle scripts and package-local installation.
# The first Windows CI reached this point and failed because the exe was not
# found at the hardcoded path despite npm reporting successful installation.
RunChecked -exe $nodeExe -arguments @($npmCli, 'install', '--no-audit', '--no-fund', '--include=dev', '--ignore-scripts=false', '--workspaces=false', '--prefix', $desktopDir) -working $repo
$electronPackages = @(
  (Join-Path $desktopDir 'node_modules\electron'),
  (Join-Path $repo 'node_modules\electron')
)
$electronExe = $null
foreach ($electronPackage in $electronPackages) {
  $candidate = Join-Path $electronPackage 'dist\electron.exe'
  if (Test-Path $candidate) { $electronExe = $candidate; break }
}
if (-not $electronExe) {
  $electronPackage = $electronPackages | Where-Object { Test-Path (Join-Path $_ 'install.js') } | Select-Object -First 1
  if (-not $electronPackage) { throw 'Az Electron npm csomag sem talalhato a telepites utan.' }
  # A binary download may have been skipped by the host environment.
  # Explicitly invoke Electron's official install script rather than
  # silently creating a shortcut to a missing executable.
  if (Test-Path Env:ELECTRON_SKIP_BINARY_DOWNLOAD) { Remove-Item Env:ELECTRON_SKIP_BINARY_DOWNLOAD }
  Step '5b/5: Az Electron Windows futtathato fajljanak beszerzese'
  RunChecked -exe $nodeExe -arguments @((Join-Path $electronPackage 'install.js')) -working $electronPackage
  $candidate = Join-Path $electronPackage 'dist\electron.exe'
  if (Test-Path $candidate) { $electronExe = $candidate }
}
if (-not $electronExe) {
  throw 'Az Electron telepult npm csomagkent, de a Windows electron.exe nem erheto el. A telepites itt leall.'
}
Write-Host ('Ellenorzott Electron: ' + $electronExe) -ForegroundColor Green

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

  if (Test-Path $script:InstallError) { Remove-Item -Force $script:InstallError }
} catch {
  $message = $_.Exception.Message
  $errorText = @(
    ('Idopont: ' + (Get-Date).ToString('s'))
    ('Lepes: ' + $script:InstallStage)
    ('Hiba: ' + $message)
    ('Telepitesi naplo: ' + $script:InstallLog)
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($script:InstallError, $errorText, ([System.Text.UTF8Encoding]::new($false)))
  Write-Host ''
  Write-Host 'A telepites HIBAVAL leallt.' -ForegroundColor Red
  Write-Host ('Lepes: ' + $script:InstallStage) -ForegroundColor Yellow
  Write-Host ('Hiba: ' + $message) -ForegroundColor Yellow
  Write-Host ('Naplo: ' + $script:InstallLog) -ForegroundColor Cyan
  Write-Host ('Rovid hibajelentes: ' + $script:InstallError) -ForegroundColor Cyan
  throw
} finally {
  Stop-Transcript | Out-Null
}
