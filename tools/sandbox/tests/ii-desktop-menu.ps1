# INSIDE the sandbox: right click on the desktop opens ii's desktop menu; turning the photo widget
# on from it places it under the pointer; the music widget shows a silent media session.
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
function Widgets() { (Get-Content $configPath -Raw | ConvertFrom-Json).background.widgets }

$src = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\media-source.ps1' -PassThru -WindowStyle Hidden
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 32
& "$dev\screenshot.ps1" -Out "$out\menu-0-desktop.png" | Out-Null

& "$dev\click.ps1" -X 700 -Y 300 -Button Right
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\menu-1-open.png" | Out-Null

# Entries are 36 px tall from y+6 (menu opens at the pointer): Photo is the 8th row after a
# separator and a header (3 rows, 9 px, 28 px, then clock, music, photo).
$photoY = 300 + 6 + 3 * 38 + 11 + 30 + 2 * 38 + 18
& "$dev\click.ps1" -X 760 -Y $photoY -Button Left
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\menu-2-photo-on.png" | Out-Null
$w = Widgets
Check 'photo turned on from the menu' ($w.photo.enable -eq $true)
Check 'photo placed under the pointer' ([math]::Abs($w.photo.x - 700) -le 2 -and [math]::Abs($w.photo.y - 300) -le 2) "($($w.photo.x),$($w.photo.y))"

& "$dev\click.ps1" -X 300 -Y 600 -Button Left
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\menu-3-closed.png" | Out-Null

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'DesktopMenu|MediaWidget|PhotoWidget|background/' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -First 15
& "$hostDir\ii-host.exe" --rescue
Stop-Process -Id $src.Id -Force -ErrorAction SilentlyContinue
"fails: $script:fails"
