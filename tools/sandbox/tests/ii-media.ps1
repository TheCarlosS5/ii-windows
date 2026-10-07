# INSIDE the sandbox: a silent media session (media-source.ps1), then ii's bar and media controls.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$src = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\media-source.ps1' -PassThru -WindowStyle Hidden
Start-Sleep 8
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$psi.Environment['QT_LOGGING_RULES'] = 'quickshell.win32.mpris.debug=true'
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
& "$dev\screenshot.ps1" -Out "$out\media-bar.png" -H 60 | Out-Null
& "$dev\send-shortcut.ps1" -Name mediaControlsToggle | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\media-controls.png" | Out-Null
Stop-Process -Id $p.Id -Force
Stop-Process -Id $src.Id -Force -ErrorAction SilentlyContinue
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match "mpris" } | Select-Object -Last 12
Get-Content "$out\media-source.txt" -ErrorAction SilentlyContinue
