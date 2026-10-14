# One-command install of the latest Cardboard Espionage Action release on Windows.
#
#   irm https://raw.githubusercontent.com/ahab94/cardboard-espionage-action/main/install.ps1 | iex
#
# Installs into %LOCALAPPDATA%\CardboardEspionageAction (no admin rights needed),
# adds a Start menu shortcut, and starts the game.
# Uninstall: delete that folder and the "Cardboard Espionage Action" Start menu shortcut.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$repo = 'ahab94/cardboard-espionage-action'
$name = 'Cardboard Espionage Action'
$dest = Join-Path $env:LOCALAPPDATA 'CardboardEspionageAction'

Write-Host 'Finding the latest release...'
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$asset = $release.assets | Where-Object { $_.name -like '*-windows.zip' } | Select-Object -First 1
if (-not $asset) { throw "No Windows build in the latest release. See https://github.com/$repo/releases" }

$zip = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive $zip -DestinationPath $dest -Force
Remove-Item $zip

$exe = Join-Path $dest 'CardboardEspionageAction.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$name.lnk"
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $dest
$link.Save()

Write-Host "Installed to $dest"
Write-Host "Find '$name' in the Start menu. If SmartScreen warns, choose More info > Run anyway (the game isn't code-signed)."
Start-Process $exe
