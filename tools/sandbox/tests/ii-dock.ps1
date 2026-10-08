# INSIDE the sandbox: ii's dock (enabled by default on Windows) with pinned and open apps.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
# Defaults come from Config.qml: drop a config left by earlier tests so the dock defaults apply.
$cfg = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
if (Test-Path $cfg) {
    $json = Get-Content $cfg -Raw | ConvertFrom-Json
    if ($json.dock) { $json.PSObject.Properties.Remove('dock') }
    $json | ConvertTo-Json -Depth 32 | Set-Content $cfg -Encoding UTF8
}
Start-Process notepad
Start-Sleep 2
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
# The dock reveals on hover at the bottom edge.
Add-Type -Namespace DK -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'
[DK.M]::SetCursorPos(760, 822) | Out-Null
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\dock.png" | Out-Null
Stop-Process -Id $p.Id -Force
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'ock' } | Select-Object -Last 12
