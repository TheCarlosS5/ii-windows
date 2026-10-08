# INSIDE the sandbox: ii's region screenshot (copy) and region OCR, end to end.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Clipboard]::Clear()

# 1. Copy a 400x300 region.
& "$dev\send-shortcut.ps1" -Name regionScreenshot | Out-Null
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\snip-selector.png" | Out-Null
& "$dev\drag.ps1" -X1 300 -Y1 200 -X2 700 -Y2 500
Start-Sleep 3
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img) { "PASS copy: clipboard image $($img.Width)x$($img.Height)"; $img.Save("$out\snip-clipboard.png") } else { "FAIL copy: no image on the clipboard" }
"formats: $([System.Windows.Forms.Clipboard]::GetDataObject().GetFormats() -join ', ')"

# 2. OCR over the bar (clock and date text).
& "$dev\send-shortcut.ps1" -Name regionOcr | Out-Null
Start-Sleep 3
& "$dev\drag.ps1" -X1 900 -Y1 2 -X2 1150 -Y2 38
Start-Sleep 5
$text = [System.Windows.Forms.Clipboard]::GetText()
"ocr text: [$text]"
"temp left: $((Get-ChildItem "$env:TEMP\quickshell\media\screenshot" -ErrorAction SilentlyContinue).Count) file(s)"
"C:\tmp exists: $(Test-Path C:\tmp)"
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'egion|creenshot|Snip|notif' } | Select-Object -Last 10
