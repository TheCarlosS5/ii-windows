# INSIDE the sandbox: ii-host --boot (as the logon task starts it): ii's wallpaper covers the
# screen at once, an app opened meanwhile shows above it, the cover goes when the shell's own
# wallpaper is up, priorities go high then back to normal. Also the resize corner in edit mode.
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

# An orange wallpaper for ii (easy to tell from Windows' blue one).
Add-Type -AssemblyName System.Drawing
$wall = "$env:USERPROFILE\Pictures\ii-wall.png"
$bmp = New-Object System.Drawing.Bitmap 1600, 900
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(255, 230, 120, 30)); $g.Dispose()
$bmp.Save($wall); $bmp.Dispose()
$cfgDir = "$env:LOCALAPPDATA\quickshell\illogical-impulse"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$wallJson = $wall.Replace('\', '/')
@"
{"background":{"wallpaperPath":"$wallJson","widgets":{"calendar":{"enable":true,"x":400,"y":100}}},"sounds":{"ui":true,"uiVolume":0.6}}
"@ | Set-Content "$cfgDir\config.json" -Encoding UTF8

function CenterColor {
    Add-Type -AssemblyName System.Windows.Forms
    $b = New-Object System.Drawing.Bitmap 1, 1
    $gg = [System.Drawing.Graphics]::FromImage($b); $gg.CopyFromScreen(200, 600, 0, 0, (New-Object System.Drawing.Size 1, 1)); $gg.Dispose()
    $c = $b.GetPixel(0, 0); $b.Dispose(); return $c
}

$hostLog = "$env:LOCALAPPDATA\ii-windows\host.log"
$logStart = if (Test-Path $hostLog) { (Get-Content $hostLog).Count } else { 0 }
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--boot', '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep -Milliseconds 700
$c = CenterColor
& "$dev\screenshot.ps1" -Out "$out\boot-1-splash.png" | Out-Null
Check 'splash shows ii''s wallpaper at once' ($c.R -gt 200 -and $c.G -gt 90 -and $c.G -lt 150 -and $c.B -lt 60) "(pixel $($c.R),$($c.G),$($c.B))"
$hostProc = Get-Process ii-host | Sort-Object StartTime | Select-Object -First 1
Check 'host at high priority while booting' ($hostProc.PriorityClass -eq 'High') "($($hostProc.PriorityClass))"
Start-Sleep 2
$qs = Get-Process quickshell -ErrorAction SilentlyContinue | Select-Object -First 1
Check 'shell at high priority while booting' ($qs.PriorityClass -eq 'High') "($($qs.PriorityClass))"
Start-Process notepad.exe -ErrorAction SilentlyContinue
Start-Process explorer.exe C:\
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\boot-2-app-over-splash.png" | Out-Null
Start-Sleep 25
& "$dev\screenshot.ps1" -Out "$out\boot-3-ready.png" | Out-Null
Get-Content $hostLog | Select-Object -Skip $logStart | Select-String 'splash|boot' | ForEach-Object { $_.Line }
Check 'splash gone' (-not (Get-Process ii-host | ForEach-Object { $_.MainWindowTitle } | Where-Object { $_ -eq 'ii-windows' })) ''
Start-Sleep 35
$hostProc.Refresh(); $qs.Refresh()
Check 'host back to normal priority after boot' ($hostProc.PriorityClass -eq 'Normal') "($($hostProc.PriorityClass))"
Check 'shell back to normal priority after boot' ($qs.PriorityClass -eq 'Normal') "($($qs.PriorityClass))"

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'uisound|UiSound|UiSounds|WidgetEditFrame|ERROR' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 10
& "$hostDir\ii-host.exe" --rescue
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
"fails: $script:fails"
