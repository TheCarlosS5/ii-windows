# INSIDE the sandbox: the desktop widgets (new ones on, a big photo), the right-click menu, edit
# mode (grid, frames, − / +), the right sidebar header, ii's settings page for widgets.
#   -Clicks "x,y[,Button];drag,x1,y1,x2,y2;..."  clicks/drags after the first captures, each followed by a capture
param([string]$Clicks = '')
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

# A 3000x2000 photo: it must come up card-sized, not screen-sized.
Add-Type -AssemblyName System.Drawing
$photo = "$env:USERPROFILE\Pictures\big-photo.png"
$bmp = New-Object System.Drawing.Bitmap 3000, 2000
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 40, 120, 200))
$g.FillEllipse([System.Drawing.Brushes]::Orange, 600, 300, 1800, 1400)
$g.Dispose(); $bmp.Save($photo); $bmp.Dispose()

$cfgDir = "$env:LOCALAPPDATA\quickshell\illogical-impulse"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$photoJson = $photo.Replace('\', '\\')
@"
{"background":{"widgets":{
 "clock":{"enable":true,"x":-48,"y":72},
 "media":{"enable":true},
 "photo":{"enable":true,"source":"$photoJson","x":40,"y":420},
 "folder":{"enable":false},
 "calendar":{"enable":true,"x":420,"y":64},
 "todo":{"enable":true,"x":760,"y":64},
 "resources":{"enable":true,"x":420,"y":440},
 "notes":{"enable":true,"text":"Hola desde la nota","x":760,"y":470},
 "japaneseClock":{"enable":true,"x":1120,"y":420},
 "timer":{"enable":false}
}}}
"@ | Set-Content "$cfgDir\config.json" -Encoding UTF8

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 32
& "$dev\screenshot.ps1" -Out "$out\w-1-desktop.png" | Out-Null
& "$dev\click.ps1" -X 300 -Y 300 -Button Right
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\w-2-menu.png" | Out-Null
& "$dev\click.ps1" -X 5 -Y 600 -Button Left   # close the menu
Start-Sleep 1
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\w-3-sidebar.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 1

$n = 4
foreach ($c in ($Clicks.Split(';') | Where-Object { $_ })) {
    $xy = $c.Split(',')
    if ($xy[0] -eq 'drag') { & "$dev\drag.ps1" -X1 ([int]$xy[1]) -Y1 ([int]$xy[2]) -X2 ([int]$xy[3]) -Y2 ([int]$xy[4]) -Steps 25 }
    else { & "$dev\click.ps1" -X ([int]$xy[0]) -Y ([int]$xy[1]) -Button ($(if ($xy.Count -gt 2) { $xy[2] } else { 'Left' })) }
    Start-Sleep 2
    & "$dev\screenshot.ps1" -Out "$out\w-$n-click.png" | Out-Null
    $n++
}

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'TypeError|ReferenceError|is not a type|not installed|Cannot assign|Unable to assign|binding loop|qml:|Widget|Card|Edit|uisound|UiSound' |
    Where-Object { $_.Line -notmatch 'cliphist|checkupdates|hyprctl|"ls"' } |
    ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 30
Get-Content "$cfgDir\config.json" -Raw | Select-String -Pattern '"widgetScale":\s*[0-9.]+|"scale":\s*[0-9.]+' -AllMatches | ForEach-Object { $_.Matches.Value }
& "$hostDir\ii-host.exe" --rescue
'done'
