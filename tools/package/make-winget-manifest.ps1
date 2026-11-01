# Plan 2026-10-31, G6: the winget manifest of a version (TheCarlosS5.ii-windows), from its Setup.
#   make-winget-manifest.ps1 -Setup out\ii-windows-Setup-<id>.exe -Version 0.8.0 [-ReleaseDate 2026-11-02] [-Out out\winget]
# Writes out\winget\<version>\ (version, installer and es-MX / en-US locale manifests, schema 1.6.0) with the Setup's
# SHA256 and its URL in the GitHub release v<version> (publish-release.ps1 uploads it there), then runs
# `winget validate`. It publishes nothing: sending it to microsoft/winget-pkgs is a pull request the author makes by hand
# (docs/PUBLICAR.md), after the release exists and its Setup can be downloaded.
param(
    [Parameter(Mandatory)][string]$Setup,
    [Parameter(Mandatory)][string]$Version,
    [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd'),
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Out) { $Out = "$root\out\winget" }
if (-not (Test-Path $Setup)) { throw "no Setup at $Setup" }
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$') { throw "not a version: $Version" }
$id = 'TheCarlosS5.ii-windows'
$manifest = '1.6.0'
$sha = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToUpper()
$setupName = Split-Path $Setup -Leaf
$url = "https://github.com/TheCarlosS5/ii-windows/releases/download/v$Version/$setupName"
$dir = Join-Path $Out $Version
New-Item -ItemType Directory -Force $dir | Out-Null
$schema = "# yaml-language-server: `$schema=https://aka.ms/winget-manifest"

function Write-Manifest([string]$Name, [string]$Kind, [string]$Body) {
    $text = "$schema.$Kind.$manifest.schema.json`n`n$Body`nManifestType: $Kind`nManifestVersion: $manifest`n"
    [IO.File]::WriteAllText((Join-Path $dir $Name), $text, (New-Object Text.UTF8Encoding $false))
}

Write-Manifest "$id.yaml" 'version' @"
PackageIdentifier: $id
PackageVersion: $Version
DefaultLocale: es-MX
"@

# Inno Setup, per user (PrivilegesRequired=lowest in setup.iss): winget passes Inno's own silent switches.
Write-Manifest "$id.installer.yaml" 'installer' @"
PackageIdentifier: $id
PackageVersion: $Version
InstallerType: inno
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
ReleaseDate: $ReleaseDate
Installers:
- Architecture: x64
  InstallerUrl: $url
  InstallerSha256: $sha
"@

Write-Manifest "$id.locale.es-MX.yaml" 'defaultLocale' @"
PackageIdentifier: $id
PackageVersion: $Version
PackageLocale: es-MX
Publisher: Carlos (TheCarlosS5)
PublisherUrl: https://github.com/TheCarlosS5
PublisherSupportUrl: https://github.com/TheCarlosS5/ii-windows/issues
PackageName: ii-windows
PackageUrl: https://github.com/TheCarlosS5/ii-windows
License: GPL-3.0
LicenseUrl: https://github.com/TheCarlosS5/ii-windows/blob/main/LICENSE
ShortDescription: El escritorio illogical-impulse (Quickshell) en Windows 11
Description: |-
  ii-windows lleva el escritorio illogical-impulse de Linux a Windows 11: barra, dock, escritorio con widgets, barras
  laterales, búsqueda y notificaciones con Material You. Funciona por usuario, sin permisos de administrador, y se
  quita entero desde Configuración de Windows > Aplicaciones.
Tags:
- desktop
- shell
- quickshell
- material-you
- dock
- taskbar
ReleaseNotesUrl: https://github.com/TheCarlosS5/ii-windows/releases/tag/v$Version
"@

Write-Manifest "$id.locale.en-US.yaml" 'locale' @"
PackageIdentifier: $id
PackageVersion: $Version
PackageLocale: en-US
Publisher: Carlos (TheCarlosS5)
PackageName: ii-windows
License: GPL-3.0
ShortDescription: The illogical-impulse desktop (Quickshell) on Windows 11
Description: |-
  ii-windows brings the illogical-impulse Linux desktop to Windows 11: bar, dock, desktop widgets, sidebars, search and
  notifications with Material You. Per user, no administrator rights, removed whole from Windows Settings > Apps.
"@

"winget manifest: $dir"
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    & winget validate --manifest $dir 2>&1 | ForEach-Object { "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "winget validate failed ($LASTEXITCODE)" }
} else {
    'winget not found: not validated'
}
