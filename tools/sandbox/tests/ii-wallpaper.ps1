# INSIDE the sandbox: the wallpaper selector, and applying a wallpaper recolors the shell.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

# Pictures\Wallpapers with the test wallpaper and a bright orange one.
$walls = "$env:USERPROFILE\Pictures\Wallpapers"
New-Item -ItemType Directory -Force $walls | Out-Null
Copy-Item "$env:USERPROFILE\Pictures\ii-wallpaper.jpg" "$walls\lake.jpg" -Force
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 1600, 900
$g = [System.Drawing.Graphics]::FromImage($bmp)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 1600, 900), [System.Drawing.Color]::FromArgb(255, 120, 20), [System.Drawing.Color]::FromArgb(200, 40, 90))
$g.FillRectangle($brush, 0, 0, 1600, 900); $g.Dispose()
$bmp.Save("$walls\sunset.png", [System.Drawing.Imaging.ImageFormat]::Png)

$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
& "$dev\send-shortcut.ps1" -Name wallpaperSelectorToggle | Out-Null
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\wall-selector.png" | Out-Null
& "$dev\send-shortcut.ps1" -Name wallpaperSelectorToggle | Out-Null
Start-Sleep 1
$before = (Get-Content "$env:LOCALAPPDATA\quickshell\State\user\generated\colors.json" -Raw | ConvertFrom-Json).primary
& "$dist\bin\qs.exe" -p $local ipc call wallpapers apply "$($walls.Replace('\', '/'))/sunset.png"
Start-Sleep 5
$after = (Get-Content "$env:LOCALAPPDATA\quickshell\State\user\generated\colors.json" -Raw | ConvertFrom-Json).primary
"primary before $before after $after"
& "$dev\send-shortcut.ps1" -Name sidebarRightToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\wall-applied.png" | Out-Null
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'allpaper|switchwall|MaterialTheme' } | Select-Object -Last 8
