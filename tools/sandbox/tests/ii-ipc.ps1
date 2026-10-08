# INSIDE the sandbox: `qs ... ipc call` reaches the running shell; full screenshot to clipboard.
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
& "$dist\bin\ii-shim.exe" screenshot --copy
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img) { "PASS full screenshot: $($img.Width)x$($img.Height)" } else { "FAIL full screenshot" }
"--- ipc show"
& "$dist\bin\qs.exe" -p $local ipc show 2>&1 | Select-Object -First 8
"--- ipc call region screenshot (exit code follows)"
& "$dist\bin\qs.exe" -p $local ipc call region screenshot 2>&1 | Select-Object -First 5
"exit=$LASTEXITCODE"
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\ipc-region.png" -H 120 | Out-Null
Stop-Process -Id $p.Id -Force
