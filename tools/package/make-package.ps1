# Builds the ii-windows package: out\ii-windows-<version>\ (install.cmd + app\) and its .zip.
# Run after building (quickshell, host), tools\dev\deploy.ps1 and tools\dev\stage-ii.ps1.
# app\ is one complete version: it carries payload.manifest (sha256 of every file) and build-info.json
# (what it was built from), and the installer refuses it if any file differs from the manifest.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ii-runtime.ps1')
$root = Split-Path (Split-Path $PSScriptRoot)
$commit = (git -C $root rev-parse --short HEAD).Trim()
$qsCommit = (git -C (Join-Path $root 'quickshell') rev-parse --short HEAD).Trim()
$baseVersion = '0.6.0'
$version = "$baseVersion-$(Get-Date -Format yyyyMMdd)-$commit"
$name = "ii-windows-$version"
$outRoot = Join-Path $root 'out'
$pkg = Join-Path $outRoot $name
$app = Join-Path $pkg 'app'
# The newest host build: host\build-clang (clang-cl, what is built today) or host\build (an older cl.exe tree). A package
# must never carry a stale ii-host.exe from a tree nobody builds any more.
$hostBuild = @('host\build-clang', 'host\build') | Where-Object { Test-Path (Join-Path $root "$_\ii-host.exe") } |
    Sort-Object { (Get-Item (Join-Path $root "$_\ii-host.exe")).LastWriteTime } | Select-Object -Last 1
if (-not $hostBuild) { $hostBuild = 'host\build-clang' }

foreach ($required in 'dist\quickshell\quickshell.exe', 'dist\quickshell\bin\ii-shim.exe', "$hostBuild\ii-host.exe", "$hostBuild\ii-launcher.exe",
                       'build\ii\shell.qml', 'third_party\cursors\Bibata-Modern-Classic\Pointer.cur',
                       'third_party\fastfetch\fastfetch.exe') {
    if (-not (Test-Path (Join-Path $root $required))) { throw "missing $required (build, deploy, stage, fetch first)" }
}

Remove-Item $pkg -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $app | Out-Null
function Mirror($from, $to) {
    & robocopy (Join-Path $root $from) (Join-Path $app $to) /MIR /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copy $from failed" }
}
Mirror 'dist\quickshell' 'quickshell'
Mirror 'build\ii' 'ii'
Mirror 'third_party\cursors\Bibata-Modern-Classic' 'cursors\Bibata-Modern-Classic'
New-Item -ItemType Directory -Force (Join-Path $app 'rescue') | Out-Null
Copy-Item (Join-Path $root 'tools\rescue\ii-rescue.ps1'), (Join-Path $root 'tools\rescue\ii-rescue.cmd'),
          (Join-Path $root 'tools\rescue\ii-report.ps1'), (Join-Path $root 'tools\rescue\ii-report.cmd') (Join-Path $app 'rescue')
# fastfetch with ii's config, as the `fastfetch` command (app\bin goes on the user's PATH if they agree)
Mirror 'third_party\fastfetch' 'fastfetch'
Copy-Item (Join-Path $root 'extras\fastfetch\ii.jsonc'), (Join-Path $root 'extras\fastfetch\ii-logo.txt'), (Join-Path $root 'extras\fastfetch\ii-logo-ascii.txt') (Join-Path $app 'fastfetch')
New-Item -ItemType Directory -Force (Join-Path $app 'bin') | Out-Null
Copy-Item (Join-Path $root 'extras\fastfetch\fastfetch.cmd') (Join-Path $app 'bin')
Copy-Item (Join-Path $root "$hostBuild\ii-host.exe") $app
"$version`nii-windows $commit, quickshell $qsCommit" | Set-Content (Join-Path $app 'VERSION') -Encoding ASCII

# Licenses: every component that ships, with its own text.
$lic = Join-Path $app 'licenses'
New-Item -ItemType Directory -Force $lic | Out-Null
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $lic 'ii-windows-GPL-3.0.txt')
Copy-Item (Join-Path $root 'upstream\LICENSE') (Join-Path $lic 'illogical-impulse-GPL-3.0.txt')
Copy-Item (Join-Path $root 'quickshell\LICENSE') (Join-Path $lic 'quickshell-and-Qt-LGPL-3.0.txt')
Copy-Item (Join-Path $root 'quickshell\LICENSE-GPL') (Join-Path $lic 'GPL-3.0.txt')
Copy-Item (Join-Path $root 'third_party\material-color-utilities\LICENSE') (Join-Path $lic 'material-color-utilities-Apache-2.0.txt')
Copy-Item (Join-Path $root 'third_party\fastfetch\LICENSE') (Join-Path $lic 'fastfetch-MIT.txt')
Get-ChildItem (Join-Path $root 'third_party\fonts') -Filter 'LICENSE-*' | Copy-Item -Destination $lic
Get-ChildItem (Join-Path $root 'third_party\icons\LICENSES') | Copy-Item -Destination $lic
@"
ii-windows $version - componentes de terceros

illogical-impulse (end-4/dots-hyprland) ......... GPL-3.0   https://github.com/end-4/dots-hyprland
Quickshell (fork con backend Windows) ........... LGPL-3.0  https://git.outfoxxed.me/quickshell/quickshell
  fuente del fork: carpeta quickshell/ del proyecto ii-windows (commit $qsCommit)
Qt 6.12 (DLL en app\quickshell, reemplazables) .. LGPL-3.0  https://download.qt.io/  (fuente: qt-everywhere-src-6.12.0)
material-color-utilities (en ii-shim.exe) ....... Apache-2.0 https://github.com/material-foundation/material-color-utilities
Bibata Modern Classic (cursores) ................ GPL-3.0   https://github.com/ful1e5/Bibata_Cursor (v2.0.7)
fastfetch 2.69.0 (app\fastfetch) ................ MIT       https://github.com/fastfetch-cli/fastfetch
Google Sans Flex, Readex Pro, Space Grotesk, Rubik, JetBrains Mono Nerd Font ... SIL OFL 1.1
Material Symbols ................................ Apache-2.0
  Modificadas: en Google Sans Flex y Material Symbols Rounded se quitaron instancias con nombre (pesos que ii
  no usa; todos los ejes variables siguen); de JetBrains Mono Nerd Font van solo Regular, Medium y Bold.
  Ver tools/dev/trim_fonts.py en el codigo de ii-windows.
Breeze / Breeze Plus (iconos) ................... LGPL-3.0 / LGPL-2.1

Los textos de cada licencia estan en esta carpeta.
"@ | Set-Content (Join-Path $lic 'THIRD-PARTY.txt') -Encoding UTF8

# What this version was built from, inside the payload (so it is covered by the manifest).
function GitState([string]$dir) {
    if (-not (Test-Path (Join-Path $dir '.git'))) { return $null }
    [ordered]@{ head = ((git -C $dir rev-parse HEAD) | Select-Object -First 1).Trim(); dirty = [bool](git -C $dir status --porcelain) }
}
$qsCache = Join-Path $root 'quickshell\build\CMakeCache.txt'
if (-not (Test-Path $qsCache)) { $qsCache = Join-Path $root 'quickshell\build-r\CMakeCache.txt' }
$buildType = $null
if (Test-Path $qsCache) { $buildType = (Select-String -Path $qsCache -Pattern '^CMAKE_BUILD_TYPE:STRING=(.*)$' | Select-Object -First 1).Matches.Groups[1].Value }
$qtCore = Get-Item (Join-Path $root 'dist\quickshell\Qt6Core.dll') -ErrorAction SilentlyContinue
[ordered]@{
    version   = $version
    built     = (Get-Date).ToString('s')
    commits   = [ordered]@{ ii = GitState $root; quickshellWindows = GitState (Join-Path $root 'quickshell'); upstream = GitState (Join-Path $root 'upstream') }
    quickshell = [ordered]@{ cmakeBuildType = $buildType; qtCore = if ($qtCore) { $qtCore.VersionInfo.ProductVersion } else { $null } }
    note      = 'dirty = the working tree had uncommitted changes when this was built; a release must be false.'
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $app 'build-info.json') -Encoding UTF8

# ii-windows' own programs signed (plan 1.4; says NOT SIGNED without a certificate), before the manifest: a signature
# changes the file.
& (Join-Path $PSScriptRoot 'sign.ps1') -Path $app

# The manifest is the last thing written into app\: every file above is covered by it.
$files = New-IiPayloadManifest $app
"payload manifest: $files files"

# Installer scripts: UTF-8 with BOM, so Windows PowerShell 5.1 reads them correctly.
$utf8Bom = New-Object System.Text.UTF8Encoding $true
foreach ($script in 'install.ps1', 'uninstall.ps1', 'uninstall-gui.ps1', 'autostart-task.ps1', 'ii-ownership.ps1', 'ii-autostart.ps1', 'ii-changes.ps1', 'ii-runtime.ps1') {
    $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $script))
    [IO.File]::WriteAllText((Join-Path $pkg $script), $text, $utf8Bom)
}
Copy-Item (Join-Path $PSScriptRoot 'install.cmd'), (Join-Path $PSScriptRoot 'uninstall.cmd') $pkg
# The one stable entry point: next to the installer, not inside the versioned payload.
Copy-Item (Join-Path $root "$hostBuild\ii-launcher.exe") $pkg
& (Join-Path $PSScriptRoot 'sign.ps1') -Path (Join-Path $pkg 'ii-launcher.exe')
@"
ii-windows $version

Instalar: doble clic en install.cmd (solo para tu usuario; pregunta antes de cada paso).
Desinstalar: menu Inicio > ii-windows > Desinstalar, o Configuracion > Aplicaciones.
Si algo sale mal mientras ii corre: Ctrl+Alt+Shift+R, o menu Inicio > ii-windows > Rescate de ii.
"@ | Set-Content (Join-Path $pkg 'LEEME.txt') -Encoding UTF8

$zip = Join-Path $outRoot "$name.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $pkg -DestinationPath $zip -CompressionLevel Optimal
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
"package: $zip ($size MB)"
# Version information, packers, signatures and hashes of every program (plan 1.4): <package>\release-check.md.
& (Join-Path $PSScriptRoot 'release-check.ps1') -Package $pkg
