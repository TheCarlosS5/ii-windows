# INSIDE the sandbox: an app window + overview -> live previews.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Start-Process explorer.exe -ArgumentList 'C:\Windows'
Start-Process explorer.exe -ArgumentList 'C:\Users'
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
& "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\overview-previews.png" | Out-Null
Stop-Process -Id $p.Id -Force
