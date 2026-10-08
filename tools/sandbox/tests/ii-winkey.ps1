# INSIDE the sandbox, with ii-host: the Windows key (and Win+Tab) open ii's overview above a
# maximized app that has the focus, and Start stays closed. Also after minimizing that app.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class K {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, ref int v, int s);
    public static void Keys(params int[] seq) {
        foreach (var k in seq) {
            var a = new IN[1]; var vk = (ushort)Math.Abs(k);
            a[0].type = 1; a[0].ki.vk = vk; a[0].ki.scan = (ushort)MapVirtualKey(vk, 0);
            a[0].ki.flags = (k < 0 ? 2u : 0u) | (vk == 0x5B ? 1u : 0u);
            SendInput(1, a, Marshal.SizeOf(typeof(IN)));
            System.Threading.Thread.Sleep(40);
        }
    }
    public static uint FgPid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
}
'@
# Start's window always exists; Windows hides it by cloaking it (DWMWA_CLOAKED).
function StartMenuOpen {
    $s = [K]::FindWindow('Windows.UI.Core.CoreWindow', 'Inicio')
    if ($s -eq [IntPtr]::Zero) { $s = [K]::FindWindow('Windows.UI.Core.CoreWindow', 'Start') }
    if ($s -eq [IntPtr]::Zero) { return $false }
    $cloaked = 0; [void][K]::DwmGetWindowAttribute($s, 14, [ref]$cloaked, 4)
    return [K]::IsWindowVisible($s) -and $cloaked -eq 0
}

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
$qs = (Get-Process quickshell | Select-Object -First 1).Id
# Like on the real PC: another app's invisible, click-through overlay covering the screen.
$overlay = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\fake-overlay.ps1' -PassThru -WindowStyle Hidden
Start-Sleep 3
Start-Process explorer.exe -ArgumentList "/n,$env:WINDIR"
Start-Sleep 4
$app = @((New-Object -ComObject Shell.Application).Windows()) | Select-Object -First 1
[void][K]::PostMessage([IntPtr]$app.HWND, 0x112, [IntPtr]0xF030, [IntPtr]::Zero)   # maximize
Start-Sleep 1
& "$dev\click.ps1" -X 700 -Y 400 -Button Left    # focus the app (its content)
Start-Sleep 1
Check 'app in front' ([K]::FgPid() -ne $qs)

for ($round = 1; $round -le 3; $round++) {
    [K]::Keys(0x5B, -0x5B)
    Start-Sleep 1
    & "$dev\screenshot.ps1" -Out "$out\winkey-$round.png" | Out-Null
    Check "Win opens ii's search above the app ($round)" ([K]::FgPid() -eq $qs)
    Check "Start stays closed ($round)" (-not (StartMenuOpen))
    [K]::Keys(0x1B, -0x1B)   # Esc closes it
    Start-Sleep 1
}
[K]::Keys(0x5B, 0x09, -0x09, -0x5B)
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\winkey-tab.png" | Out-Null
Check 'Win+Tab opens the overview above the app' ([K]::FgPid() -eq $qs)
[K]::Keys(0x1B, -0x1B)
Start-Sleep 1

# Minimize the app in front: the bar and dock must stay, and Win still opens ii.
& "$dev\click.ps1" -X 700 -Y 400 -Button Left
Start-Sleep 1
[void][K]::PostMessage([IntPtr]$app.HWND, 0x112, [IntPtr]0xF020, [IntPtr]::Zero)
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\winkey-minimized.png" | Out-Null
[K]::Keys(0x5B, -0x5B)
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\winkey-after-min.png" | Out-Null
Check 'Win opens ii after minimizing' ([K]::FgPid() -eq $qs)
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
$entered = @(Get-Content $log.FullName | Select-String 'Fullscreen app entered').Count
Check 'no fullscreen app detected (bar and dock stay)' ($entered -eq 0) "($entered)"
$overlay | Stop-Process -Force -ErrorAction SilentlyContinue
[K]::Keys(0x1B, -0x1B)
$app.Quit()
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'Fullscreen|fullscreen' | Select-Object -Last 8
& C:\ii\host\build\ii-host.exe --rescue | Out-Null
"fails: $script:fails"
