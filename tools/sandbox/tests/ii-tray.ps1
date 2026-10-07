# INSIDE the sandbox: ii's tray shows apps' notification icons, and Explorer keeps them too.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$out\tray-clicks.txt" -ErrorAction SilentlyContinue
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
# One icon before the shell starts (needs the re-announce), one after.
$before = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '70', '-Name', 'antes' -PassThru -WindowStyle Hidden
Start-Sleep 4
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
$after = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '50', '-Name', 'despues' -PassThru -WindowStyle Hidden
Start-Sleep 5
& "$dev\screenshot.ps1" -Out "$out\tray-bar.png" | Out-Null
# Bar tray, right to left: [network] [despues] [volume] [antes] [eject] (1520 px wide sandbox)
& "$dev\click.ps1" -X 1350 -Y 19 -Button Left
Start-Sleep 1
& "$dev\click.ps1" -X 1420 -Y 19 -Button Right
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\tray-menu.png" -H 250 | Out-Null
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
"--- clicks the apps received"
Get-Content "$out\tray-clicks.txt" -ErrorAction SilentlyContinue
"--- Shell_TrayWnd windows (first = what apps find)"
Add-Type -Namespace TT -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'
$h = [IntPtr]::Zero
while (($h = [TT.W]::FindWindowEx([IntPtr]::Zero, $h, 'Shell_TrayWnd', [NullString]::Value)) -ne [IntPtr]::Zero) {
    $procId = 0; [void][TT.W]::GetWindowThreadProcessId($h, [ref]$procId)
    "  $h $((Get-Process -Id $procId).ProcessName)"
}
Stop-Process -Id $p.Id -Force
Start-Sleep 2
"--- after the shell exits, a new icon still reaches Explorer"
& "$dev\click.ps1" -X 1322 -Y 798 -Button Left   # Explorer's "show hidden icons" chevron
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\tray-after-exit.png" | Out-Null
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'tray|Tray' } | Select-Object -Last 10
$before, $after | Stop-Process -Force -ErrorAction SilentlyContinue
