Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
$bar = (& C:\ii\tools\dev\zorder.ps1) -split "`n" | Where-Object { $_ -match 'quickshell.*1520x63' } | Select-Object -First 1
$hwnd = ($bar.Trim() -split '\s+')[1]
"bar line: $bar"
& C:\ii\tools\dev\capture-window.ps1 -Hwnd $hwnd -Out C:\xchg\outbox\bar-window.png
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\bar-screen.png -H 80 | Out-Null
$cfg = Get-Content "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -Raw | ConvertFrom-Json
'bar config: ' + ($cfg.bar | ConvertTo-Json -Depth 4 -Compress).Substring(0, 600)
Stop-Process -Id $p.Id -Force
