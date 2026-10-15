# Builds the installer wizard out\ii-windows-Setup-<version>.exe from a package folder (make-package.ps1).
#   make-setup.ps1 [-Package out\ii-windows-<version>]     default: the newest package folder
param([string]$Package = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found (winget install JRSoftware.InnoSetup)' }
if (-not $Package) {
    $Package = Get-ChildItem (Join-Path $root 'out') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'install.ps1') } | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
}
$Package = (Resolve-Path $Package).Path
if (-not (Test-Path (Join-Path $Package 'install.ps1'))) { throw "not a package folder: $Package" }
$version = (Get-Content (Join-Path $Package 'app\VERSION') | Select-Object -First 1).Trim()
Write-Output "package $Package ($version)"
& $iscc "/DSourceDir=$Package" "/DAppVersion=$version" "/DRepoRoot=$root" (Join-Path $PSScriptRoot 'setup.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
Get-ChildItem (Join-Path $root 'out') -Filter 'ii-windows-Setup-*.exe' | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { "{0}  {1:N1} MB" -f $_.FullName, ($_.Length / 1MB) }
