# INSIDE the sandbox: dock hover previews and right click on a running app, then the right
# sidebar. Screenshots only (inventory of what works).
param([int]$IconX = 831)
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
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
Add-Type -Namespace DS -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Start-Process explorer.exe $env:USERPROFILE
Start-Sleep 2
Start-Process explorer.exe C:\
Start-Process cmd.exe
Start-Sleep 5
& "$dev\screenshot.ps1" -Out "$out\ds-0.png" | Out-Null

# Reveal the dock from the bottom edge, then hover the icon.
[void][DS.M]::SetCursorPos($IconX, 822); Start-Sleep 1
[void][DS.M]::SetCursorPos($IconX, 790); Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\ds-1-hover.png" | Out-Null
& "$dev\click.ps1" -X $IconX -Y 790 -Button Right
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\ds-2-rclick.png" | Out-Null

[void][DS.M]::SetCursorPos(700, 400)
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\ds-3-sidebar.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'WARN scene|ERROR' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Where-Object { $_ -notmatch 'btoa' } | Select-Object -Last 25
& "$hostDir\ii-host.exe" --rescue
Get-Process cmd -ErrorAction SilentlyContinue | Stop-Process -Force
"done"
