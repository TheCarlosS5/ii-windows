# INSIDE the sandbox: case B (no config folders) with FileView logging, to see where startup stops.
$dir = "$env:LOCALAPPDATA\Programs\ii-windows"
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$env:LOCALAPPDATA\quickshell" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\quickshell\State\user" | Out-Null
Set-Content "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" 'x'
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dir\quickshell\quickshell.exe"
$psi.Arguments = '-p "' + "$dir\ii" + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$psi.EnvironmentVariables['QT_LOGGING_RULES'] = 'quickshell.io.fileview=true'
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 20
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-Object -Last 30
"cpu seconds: $((Get-Process -Id $p.Id).TotalProcessorTime.TotalSeconds)"
"threads: $((Get-Process -Id $p.Id).Threads.Count)"
Stop-Process -Id $p.Id -Force
