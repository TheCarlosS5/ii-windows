# INSIDE the sandbox: Explorer restarts while ii's tray runs. The shell must take the tray back
# and both ii and Explorer must still show the app's icon.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Add-Type -Namespace TT -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'
function Trays() {
    $h = [IntPtr]::Zero; $list = @()
    while (($h = [TT.W]::FindWindowEx([IntPtr]::Zero, $h, 'Shell_TrayWnd', [NullString]::Value)) -ne [IntPtr]::Zero) {
        $procId = 0; [void][TT.W]::GetWindowThreadProcessId($h, [ref]$procId); $list += (Get-Process -Id $procId).ProcessName
    }
    $list -join ', '
}

$app = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '90', '-Name', 'superviviente' -PassThru -WindowStyle Hidden
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 14
"trays before restart: $(Trays)"

Get-Process explorer | Stop-Process -Force
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
Start-Sleep 10
"trays after restart:  $(Trays)"
& "$dev\screenshot.ps1" -Out "$out\tray-explorer-ii.png" -H 60 | Out-Null

Stop-Process -Id $p.Id -Force
Start-Sleep 2
& "$dev\click.ps1" -X 1322 -Y 798 -Button Left
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\tray-explorer-win.png" | Out-Null
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'tray|Tray' } | Select-Object -Last 10
$app | Stop-Process -Force -ErrorAction SilentlyContinue
