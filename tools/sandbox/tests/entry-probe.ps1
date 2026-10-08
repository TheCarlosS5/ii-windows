# INSIDE the sandbox: how app ids resolve in the app index.
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$probe = "$env:USERPROFILE\entry-probe"
robocopy C:\ii\prototypes\entry-probe $probe /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $probe + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
$p.WaitForExit(40000) | Out-Null
if (-not $p.HasExited) { $p.Kill() }
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'probe' }
