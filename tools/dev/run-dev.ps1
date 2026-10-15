# Runs the staged QML (build\ii) on the real desktop with the installed ii-host/quickshell,
# replacing the ii that is running (rescue first: the taskbar/icons come back, then ii-host hides
# them again). The shell is started through explorer (a temporary shortcut) so it survives the
# end of this script.
#   run-dev.ps1 [-Config <dir>] [-Stop] [-WaitSec 25] [-Shot <png>]
#   -Stop     only stop ii (rescue) and exit; start the installed one again with "Iniciar ii".
param([string]$Config = '', [switch]$Stop, [int]$WaitSec = 25, [string]$Shot = '', [string]$ShellExe = '', [double]$Scale = 0)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Config) { $Config = "$root\build\ii" }
$inst = "$env:LOCALAPPDATA\Programs\ii-windows"
$cur = (Get-Content "$inst\current.txt" | Where-Object { $_ -like 'active=*' }) -replace 'active=', ''
$hostExe = if ($cur -and (Test-Path "$inst\versions\$cur\ii-host.exe")) { "$inst\versions\$cur\ii-host.exe" } else { "$inst\bin\ii-host.exe" }
$shell = Join-Path (Split-Path $hostExe) 'quickshell\quickshell.exe'
# -Shell <exe> to try a fresh build (dist\quickshell may be older than the installed one).
if ($ShellExe) { $shell = $ShellExe }

# Stop whatever runs now.
Start-Process $hostExe -ArgumentList '--rescue' -Wait -WindowStyle Hidden
Start-Sleep 2
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ($Stop) { 'stopped'; exit 0 }

$lnk = Join-Path $env:TEMP 'ii-dev.lnk'
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
if ($Scale -gt 0) {
    # Emulate a laptop display scale (QT_SCALE_FACTOR): 1.25 = 1920x1080 @125%, 1.5 = 1280x720 logical.
    $sc.TargetPath = "$env:SystemRoot\System32\conhost.exe"
    $sc.Arguments = "--headless cmd /c set QT_SCALE_FACTOR=$Scale&& `"$hostExe`" --shell `"$shell`" --config `"$Config`""
} else {
    $sc.TargetPath = $hostExe
    $sc.Arguments = "--shell `"$shell`" --config `"$Config`""
}
$sc.WorkingDirectory = Split-Path $hostExe
$sc.Save()
Start-Process explorer.exe $lnk
Start-Sleep $WaitSec
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Select-Object Name, Id | Format-Table -AutoSize | Out-String | Write-Output
if ($Shot) { & "$PSScriptRoot\screenshot.ps1" -Out $Shot }
