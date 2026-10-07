# Run the dev build of quickshell on a config for a few seconds and report its windows.
# usage: qsrun.ps1 -Config <dir or shell.qml> [-Wait 3] [-Shot screen.png] [-WinShot window.png] [-Verbose2] [-Keep]
param(
    [Parameter(Mandatory)][string]$Config,
    [double]$Wait = 3,
    [string]$Shot = '',
    [string]$WinShot = '',
    [switch]$Verbose2,
    [switch]$Keep,
    [string[]]$Extra = @()
)
$root = 'C:\Users\Calos\Desktop\ii-windows'
$dev = Join-Path $root 'tools\dev'
$env:Path = "C:\Users\Calos\dev\Qt\6.12.0-msvc2022_64\bin;$env:Path"
$env:QML_IMPORT_PATH = Join-Path $root 'quickshell\build\qml_modules'
$qsArgs = @('-p', $Config) + $Extra
if ($Verbose2) { $qsArgs += '-vv' }
$out = Join-Path $env:TEMP 'qsrun-out.txt'
$err = Join-Path $env:TEMP 'qsrun-err.txt'
# NOTE: never -WindowStyle Hidden: Windows applies SW_HIDE to the first ShowWindow of the process.
# CreateNoWindow gives the console app no console at all (and no STARTF_USESHOWWINDOW), and
# unlike -NoNewWindow the process survives this script exiting.
$psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $root 'quickshell\build\quickshell.exe')
foreach ($a in $qsArgs) { [void]$psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
$psi.EnvironmentVariables['QS_LOG_FILE_HINT'] = '1'
$p = [System.Diagnostics.Process]::Start($psi)
# logs: quickshell writes its own log files; copy the newest one at the end instead of stdout.
Start-Sleep -Milliseconds ([int]($Wait * 1000))
& (Join-Path $dev 'windows.ps1') -Process quickshell | Select-String -Pattern 'Qt6\d+QWindow'
if ($WinShot) { & (Join-Path $dev 'capture-window.ps1') -Process quickshell -Class Qt6120QWindowIcon -Out $WinShot }
if ($Shot) { & (Join-Path $dev 'screenshot.ps1') -Out $Shot | Out-Null }
if ($Keep) { "left running: pid $($p.Id)"; return }
if (-not $p.WaitForExit(30000)) { Stop-Process $p -Force; 'killed after timeout' }
$log = Get-ChildItem (Join-Path $env:TEMP 'quickshell\by-id\*\log.log') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if ($log) { Get-Content $log.FullName | Where-Object { $_ -notmatch 'DEBUG quickshell\.(qmlscanner|interceptor|paths)' } | Select-Object -Last 25 }
