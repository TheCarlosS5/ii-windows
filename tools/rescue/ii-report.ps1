# ii-windows: "Report a problem". Writes a diagnostics file to the Desktop (no user name, no
# settings contents) and opens the GitHub bug form with the version and Windows build filled in.
# Nothing is sent anywhere by this script: the user attaches the file to the form if they want.
param([switch]$NoBrowser)
$ErrorActionPreference = 'Continue'
$installDir = Split-Path $PSScriptRoot
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$repo = 'https://github.com/TheCarlosS5/ii-windows'

# Anything that could identify the person: user name, profile path, computer name.
$secrets = @($env:USERPROFILE, $env:USERNAME, $env:COMPUTERNAME) | Where-Object { $_ -and $_.Length -ge 2 } | Sort-Object Length -Descending
function Scrub([string]$text) {
    foreach ($s in $secrets) { $text = $text -ireplace [regex]::Escape($s), $(if ($s -eq $env:USERPROFILE) { '<home>' } elseif ($s -eq $env:COMPUTERNAME) { '<pc>' } else { '<user>' }) }
    $text
}
function Tail($path, $lines) {
    if (Test-Path $path) { (Get-Content $path -Tail $lines -ErrorAction SilentlyContinue) -join "`n" } else { "(no existe)" }
}

$version = (Get-Content (Join-Path $installDir 'VERSION') -ErrorAction SilentlyContinue) -join ' / '
if (-not $version) { $version = 'desconocida' }
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$windows = "$($os.Caption) $($cv.DisplayVersion) (build $($cv.CurrentBuild).$($cv.UBR))"
Add-Type -AssemblyName System.Windows.Forms
$screens = ([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) { ' (principal)' })" }) -join ', '
$dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
$gpus = (Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) (driver $($_.DriverVersion))" }) -join '; '
$running = (Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | ForEach-Object { "$($_.ProcessName) $($_.Id)" }) -join ', '
$qsLog = Get-ChildItem (Join-Path $env:TEMP 'quickshell\by-id') -Filter log.log -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$report = @"
ii-windows - reporte de diagnostico ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))
Adjunta este archivo al reporte en $repo/issues (revisalo antes: es texto normal).

Version:        $version
Windows:        $windows
Pantallas:      $screens  (DPI $dpi)
GPU:            $gpus
Procesos de ii: $(if ($running) { $running } else { 'ninguno (ii no esta corriendo)' })
Idioma:         $((Get-Culture).Name)

===== ii-host (ultimas 150 lineas) =====
$(Tail (Join-Path $dataDir 'host.log') 150)

===== quickshell (ultimas 200 lineas) =====
$(if ($qsLog) { Tail $qsLog.FullName 200 } else { '(sin log)' })
"@

$desktop = [Environment]::GetFolderPath('Desktop')
$file = Join-Path $desktop "ii-windows-reporte-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
Scrub $report | Set-Content $file -Encoding UTF8
Write-Host "Diagnostico guardado en: $file"

if (-not $NoBrowser) {
    $q = 'template=bug_report.yml&version=' + [uri]::EscapeDataString($version.Split(' ')[0]) + '&windows=' + [uri]::EscapeDataString($windows)
    Start-Process "$repo/issues/new?$q"
    Start-Process explorer.exe "/select,`"$file`""
}
