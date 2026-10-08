# INSIDE the sandbox: the desktop photo widget. Turn it on from the desktop menu, give it an
# image, resize it with the wheel, open its own menu, and open/cancel the file picker.
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
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
$configPath = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
function Config() { Get-Content $configPath -Raw | ConvertFrom-Json }
Add-Type -Namespace PW -Name M -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int data, System.UIntPtr extra);
'@
function Wheel($x, $y, $clicks) { [void][PW.M]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 200; for ($i = 0; $i -lt [math]::Abs($clicks); $i++) { [PW.M]::mouse_event(0x0800, 0, 0, 120 * [math]::Sign($clicks), [UIntPtr]::Zero); Start-Sleep -Milliseconds 150 } }

# Start from ii's defaults (earlier runs move widgets around and leave the photo configured).
Remove-Item $configPath -ErrorAction SilentlyContinue
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 32

# Menu: right click at (600,150), high enough that the menu isn't moved up to clear the dock;
# then its "Photo" row (see ii-desktop-menu.ps1 for the arithmetic).
& "$dev\click.ps1" -X 600 -Y 150 -Button Right
Start-Sleep 1
& "$dev\click.ps1" -X 660 -Y (150 + 6 + 4 * 38 + 11 + 3 * 38 + 11 + 30 + 36 + 17) -Button Left
Start-Sleep 1
& "$dev\click.ps1" -X 200 -Y 700 -Button Left
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\photo-1-empty.png" | Out-Null
Check 'photo on, at the pointer' ((Config).background.widgets.photo.enable -eq $true -and (Config).background.widgets.photo.x -eq 600)

# Choose… (the empty card's button, card at 600,150) opens Windows' file dialog; Escape cancels.
& "$dev\click.ps1" -X 740 -Y 268 -Button Left
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\photo-2-dialog.png" | Out-Null
$dialog = Get-Process | Where-Object { $_.MainWindowTitle -match 'Abrir|Open|Choose|Elegir|photo|foto' } | Select-Object -First 1
"dialog window: $($dialog.ProcessName) '$($dialog.MainWindowTitle)'"
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep 1

# Give it an image as the dialog would (config write; ii reloads it).
$img = "$local\assets\images\default_wallpaper.png"
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json
$cfg.background.widgets.photo.source = $img
$cfg | ConvertTo-Json -Depth 20 -Compress | Set-Content $configPath -Encoding UTF8
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\photo-3-image.png" | Out-Null

Wheel 700 230 3
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\photo-4-bigger.png" | Out-Null
$scale = (Config).background.widgets.photo.scale
Check 'wheel makes it bigger and saves the scale' ($scale -gt 1.05) "(scale=$scale)"

& "$dev\click.ps1" -X 700 -Y 230 -Button Right
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\photo-5-menu.png" | Out-Null
& "$dev\click.ps1" -X 100 -Y 700 -Button Left
Start-Sleep 1

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'PhotoWidget|photo/' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -First 15
& "$hostDir\ii-host.exe" --rescue
"fails: $script:fails"
