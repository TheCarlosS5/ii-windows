# Plan 2026-10-31, F1/E10: Quickshell.Windows PrivacyMonitor lists the apps using the microphone, camera and location
# (Windows' own taskbar shows that; ii hides it). Runs the real quickshell.exe on a tiny config against a throwaway key
# (II_PRIVACY_TEST_STORE, only honoured with II_DATA_DIR) shaped like Windows' consent store, and changes it: a desktop
# app starts and stops using the microphone, a packaged app uses the camera. Windows' own store is never touched.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$exe = @("$repo\quickshell\build\quickshell.exe", "$repo\quickshell\build-r\quickshell.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { Skip-Test 'quickshell.exe not built' }
$qtBin = @("$env:QTDIR\bin", "$env:USERPROFILE\dev\Qt\6.12.0-msvc2022_64\bin") | Where-Object { $_ -and (Test-Path "$_\Qt6Core.dll") } | Select-Object -First 1

$base = Join-Path $env:TEMP ('ii-privacy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force "$base\cfg", "$base\data" | Out-Null
$keyPath = 'Software\ii-windows-test\privacy-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$reg = "HKCU:\$keyPath"
New-Item -Path "$reg\microphone\NonPackaged" -Force | Out-Null
New-Item -Path "$reg\webcam" -Force | Out-Null
New-Item -Path "$reg\location" -Force | Out-Null
function Set-Use([string]$Path, [long]$Start, [long]$Stop) {
    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name LastUsedTimeStart -PropertyType QWord -Value $Start -Force | Out-Null
    New-ItemProperty -Path $Path -Name LastUsedTimeStop -PropertyType QWord -Value $Stop -Force | Out-Null
}
# Already there before the shell starts: a desktop app that used the microphone earlier (stopped) - not in use.
Set-Use "$reg\microphone\NonPackaged\C:#Program Files#Old#Old.exe" 100 200

Set-Content "$base\cfg\shell.qml" @'
import QtQuick
import Quickshell
import Quickshell.Windows
ShellRoot {
    Connections {
        target: PrivacyMonitor
        function onChanged() { console.info("PRIV mic=[" + PrivacyMonitor.microphone.join(",") + "] cam=[" + PrivacyMonitor.camera.join(",") + "] loc=[" + PrivacyMonitor.location.join(",") + "]") }
    }
    Timer { interval: 9000; running: true; onTriggered: Qt.quit() }
}
'@
$p = $null
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe, "-p `"$base\cfg`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['II_DATA_DIR'] = "$base\data"
    $psi.Environment['II_PRIVACY_TEST_STORE'] = $keyPath
    if ($qtBin) { $psi.Environment['PATH'] = "$qtBin;" + $psi.Environment['PATH'] }
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 2
    Set-Use "$reg\microphone\NonPackaged\C:#Program Files#Discord#Discord.exe" 1000 0          # Discord starts using the mic
    Start-Sleep -Seconds 1
    Set-Use "$reg\webcam\Microsoft.WindowsCamera_8wekyb3d8bbwe" 2000 0                        # the Camera app opens
    Start-Sleep -Seconds 1
    Set-ItemProperty -Path "$reg\microphone\NonPackaged\C:#Program Files#Discord#Discord.exe" -Name LastUsedTimeStop -Value 3000 # Discord stops
    $p.WaitForExit(20000) | Out-Null
    $lines = @((($out.Result + $err.Result) -split "`r?`n") | Where-Object { $_ -match 'PRIV ' } | ForEach-Object { $_ -replace '^.*PRIV ', '' })
    $lines | ForEach-Object { "  $_" }
    Assert-True ($lines.Count -ge 3) 'the monitor reported the first state and each change'
    Assert-Equal $lines[0] 'mic=[] cam=[] loc=[]' 'at start nothing is in use (an app that stopped earlier does not count)'
    Assert-True ($lines -contains 'mic=[Discord] cam=[] loc=[]') 'a desktop app using the microphone is named after its exe'
    Assert-True ($lines -contains 'mic=[Discord] cam=[WindowsCamera] loc=[]') 'a packaged app using the camera is named after its package'
    Assert-Equal $lines[-1] 'mic=[] cam=[WindowsCamera] loc=[]' 'when the app stops, it goes from the list'
} finally {
    if ($p -and -not $p.HasExited) { $p.Kill() }
    Remove-Item -Path "HKCU:\Software\ii-windows-test" -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
