# INSIDE the sandbox: is Explorer's taskbar visible after an Explorer restart, with and without ii's tray?
param([switch]$WithShell)
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Add-Type -Namespace TD -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);'
function State() {
    $h = [IntPtr]::Zero; $list = @()
    while (($h = [TD.W]::FindWindowEx([IntPtr]::Zero, $h, 'Shell_TrayWnd', [NullString]::Value)) -ne [IntPtr]::Zero) {
        $procId = 0; [void][TD.W]::GetWindowThreadProcessId($h, [ref]$procId)
        $r = New-Object TD.W+RECT; [void][TD.W]::GetWindowRect($h, [ref]$r)
        $list += "$((Get-Process -Id $procId).ProcessName) vis=$([TD.W]::IsWindowVisible($h)) $($r.L),$($r.T)-$($r.R),$($r.B)"
    }
    $list -join ' | '
}
if ($WithShell) {
    $dist = "$env:USERPROFILE\ii-dist"
    robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    $local = "$env:USERPROFILE\qs-config"
    robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $local + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
    $p = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep 14
}
"before: $(State)"
Get-Process explorer | Stop-Process -Force
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
for ($i = 1; $i -le 6; $i++) { Start-Sleep 4; "t+$(4 * $i)s: $(State)" }
& "$dev\screenshot.ps1" -Out "$out\diag-explorer.png" -H 823 | Out-Null
if ($WithShell) {
    Stop-Process -Id $p.Id -Force
    Start-Sleep 3
    "after shell exit: $(State)"
    & "$dev\screenshot.ps1" -Out "$out\diag-explorer-exit.png" | Out-Null
}
