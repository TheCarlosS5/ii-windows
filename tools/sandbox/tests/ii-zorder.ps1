Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
& C:\ii\tools\dev\zorder.ps1
Stop-Process -Id $p.Id -Force
