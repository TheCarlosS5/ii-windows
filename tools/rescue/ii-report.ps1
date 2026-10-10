# ii-windows: "Report a problem". Writes a diagnostics file to the Desktop (no user name, no
# settings contents) and opens the GitHub bug form with the version and Windows build filled in.
# Nothing is sent anywhere by this script: the user attaches the file to the form if they want.
#   -DataDir / -QsLogDir / -OutFile  where to read ii's logs and where to write (tests; the defaults are the real ones)
#   -IncludePrivate  keep notification and chat text, tokens and keys in the report. Off by default: a
#                    report is meant to be attached to a public issue.
param([switch]$NoBrowser, [string]$DataDir = '', [string]$QsLogDir = '', [string]$OutFile = '', [switch]$IncludePrivate)
$ErrorActionPreference = 'Continue'
$installDir = Split-Path $PSScriptRoot
$dataDir = if ($DataDir) { $DataDir } elseif ($env:II_DATA_DIR) { $env:II_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'ii-windows' }
$repo = 'https://github.com/TheCarlosS5/ii-windows'

# Anything that could identify the person: user name, profile path, computer name.
$secrets = @($env:USERPROFILE, $env:USERNAME, $env:COMPUTERNAME) | Where-Object { $_ -and $_.Length -ge 2 } | Sort-Object Length -Descending
function Scrub([string]$text) {
    foreach ($s in $secrets) { $text = $text -ireplace [regex]::Escape($s), $(if ($s -eq $env:USERPROFILE) { '<home>' } elseif ($s -eq $env:COMPUTERNAME) { '<pc>' } else { '<user>' }) }
    if ($IncludePrivate) { return $text }
    # Private by default (R11): credentials of any shape, and what people wrote to each other.
    $text = $text -replace '(?im)(authorization|proxy-authorization|x-api-key|api[-_ ]?key|apikey|access[-_ ]?token|refresh[-_ ]?token|id[-_ ]?token|bearer|secret|password|passwd|client[-_ ]?secret)(["'']?\s*[:=]\s*["'']?)(?:bearer\s+)?[^\s"'',;&}]+', '$1$2<redacted>'
    $text = $text -replace '(?i)\b(api_key|user_id|key|token|access_token)=[^&\s"'']+', '$1=<redacted>'
    $text = $text -replace '\b(sk|pk|rk|ghp|gho|github_pat|xox[abps]|AIza|ya29)[-_A-Za-z0-9.]{12,}', '<redacted-key>'
    $text = $text -replace '(?m)(Notification \d+ from [^\r\n:]*?) : .*$', '$1 : <text omitted>'
    $text = $text -replace '(?im)^(.*(?:message|prompt|content|summary|body)\s*[:=]\s*).+$', '$1<text omitted>'
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
$qsLogRoot = if ($QsLogDir) { $QsLogDir } else { Join-Path $env:TEMP 'quickshell\by-id' }
$qsLog = Get-ChildItem $qsLogRoot -Filter log.log -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

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
$file = if ($OutFile) { $OutFile } else { Join-Path $desktop "ii-windows-reporte-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt" }
Scrub $report | Set-Content $file -Encoding UTF8
Write-Host "Diagnostico guardado en: $file"

if (-not $NoBrowser) {
    $q = 'template=bug_report.yml&version=' + [uri]::EscapeDataString($version.Split(' ')[0]) + '&windows=' + [uri]::EscapeDataString($windows)
    Start-Process "$repo/issues/new?$q"
    Start-Process explorer.exe "/select,`"$file`""
}
