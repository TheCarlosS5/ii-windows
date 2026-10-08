# INSIDE the sandbox: moving the pointer quickly across the dock's open apps. The window
# previews are DWM thumbnails drawn over the shell: they must stay inside the preview card
# while it animates (reported on the real PC: a long streak to the right of the card).
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Add-Type -Namespace Hover -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'
$env:QT_LOGGING_RULES = 'quickshell.win32.compat.debug=true'
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
# Three Explorer windows (one dock icon) and a console (another icon).
foreach ($d in "$env:WINDIR", "$env:WINDIR\System32", "$env:USERPROFILE") { Start-Process explorer.exe -ArgumentList "/n,$d"; Start-Sleep 2 }
Start-Process cmd.exe -ArgumentList '/k', 'title Consola de prueba'
Start-Sleep 4
& "$dev\screenshot.ps1" -Out "$out\hover-0.png" | Out-Null
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
Add-Type -AssemblyName System.Windows.Forms
$h = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$y = $h - 37
# The dock hides while windows are open: touch the bottom edge to reveal it first.
[void][Hover.M]::SetCursorPos(760, $h - 1); Start-Sleep -Milliseconds 800
& "$dev\screenshot.ps1" -Out "$out\hover-revealed.png" -Y ($h - 420) -H 420 | Out-Null
# Sweep the dock back and forth, then capture mid-animation after landing on each icon.
for ($round = 0; $round -lt 2; $round++) {
    for ($x = 680; $x -le 820; $x += 9) { [void][Hover.M]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 25 }
    for ($x = 820; $x -ge 680; $x -= 9) { [void][Hover.M]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 25 }
}
$i = 0
foreach ($x in 698, 806, 698, 806) {
    [void][Hover.M]::SetCursorPos($x, $y)
    foreach ($delay in 60, 120, 400) {
        Start-Sleep -Milliseconds $delay
        & "$dev\screenshot.ps1" -Out ("$out\hover-{0}-{1}.png" -f $i, $delay) -Y ($h - 420) -H 420 | Out-Null
    }
    $i++
}
Get-Process explorer | Where-Object MainWindowTitle | ForEach-Object { }
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
Get-Process cmd -ErrorAction SilentlyContinue | Stop-Process -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'thumbnail' | Select-Object -Last 25
& C:\ii\host\build\ii-host.exe --rescue | Out-Null
'done'
