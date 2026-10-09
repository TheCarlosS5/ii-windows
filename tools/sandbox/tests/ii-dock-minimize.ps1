# INSIDE the sandbox: clicking the dock icon of the app in front minimizes it (as the Windows
# taskbar does); clicking again brings it back.
param([int]$DockX = 725, [int]$DockY = 787)
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -Namespace DM -Name W -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
'@
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 28
# Earlier tests may leave Explorer windows: with several, a click cycles them instead.
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
Start-Sleep 1
Start-Process explorer.exe C:\
$win = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $win -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $win = [DM.W]::FindWindow('CabinetWClass', [NullString]::Value) }
Start-Sleep 2
# Reveal the dock, then click its Explorer icon: the window comes to the front.
[void][DM.W]::SetCursorPos($DockX, 822); Start-Sleep 1
[void][DM.W]::SetCursorPos($DockX, $DockY); Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\dm-1-dock.png" -Y 700 -H 123 | Out-Null
& "$dev\click.ps1" -X $DockX -Y $DockY -Button Left
Start-Sleep 1
Check 'click brings the window to the front' ([DM.W]::GetForegroundWindow() -eq $win) "(win=$win fg=$([DM.W]::GetForegroundWindow()))"
& "$dev\click.ps1" -X $DockX -Y $DockY -Button Left
Start-Sleep 1
Check 'click on the app in front minimizes it' ([DM.W]::IsIconic($win))
& "$dev\click.ps1" -X $DockX -Y $DockY -Button Left
Start-Sleep 1
Check 'click again restores it' (-not [DM.W]::IsIconic($win) -and [DM.W]::GetForegroundWindow() -eq $win)
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
& "$hostDir\ii-host.exe" --rescue
"fails: $script:fails"
