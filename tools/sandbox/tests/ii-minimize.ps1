# INSIDE the sandbox: with ii-host, minimizing the only app window must leave the bar and the
# dock on screen (reported on the real PC: both vanished until another app opened).
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
public static class Z {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool r);
    public struct RECT { public int L, T, R, B; }
    public static string Dump() {
        var sb = new StringBuilder(); int i = 0;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            string name; try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { name = "?"; }
            RECT r; GetWindowRect(h, out r);
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            bool top = (GetWindowLong(h, -20) & 8) != 0;
            sb.AppendLine(string.Format("{0,2} {1,-12} {2,-28} {3} {4},{5} {6}x{7}{8}", i++, name, c, top ? "TOP" : "   ", r.L, r.T, r.R - r.L, r.B - r.T, h == GetForegroundWindow() ? "  <- foreground" : ""));
            return i < 25;
        }, IntPtr.Zero);
        return sb.ToString();
    }
}
'@
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Start-Process explorer.exe -ArgumentList "/n,$env:WINDIR"
Start-Sleep 4
$app = @((New-Object -ComObject Shell.Application).Windows()) | Select-Object -First 1
& "$dev\screenshot.ps1" -Out "$out\min-0-app.png" | Out-Null
[void][Z]::MoveWindow([IntPtr]$app.HWND, 200, 150, 900, 500, $true)
Start-Sleep 1
# Click its title bar: the app must be in front, as when the user presses its minimize button.
& "$dev\click.ps1" -X 600 -Y 165 -Button Left
Start-Sleep 1
"--- before"; [Z]::Dump()
# WM_SYSCOMMAND SC_MINIMIZE: what the title bar's minimize button sends.
[void][Z]::PostMessage([IntPtr]$app.HWND, 0x112, [IntPtr]0xF020, [IntPtr]::Zero)
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\min-1-minimized.png" | Out-Null
"--- after minimize"; [Z]::Dump()
$app.Quit()
Get-Process quickshell -ErrorAction SilentlyContinue | ForEach-Object { "quickshell $($_.Id)" }
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'ullscreen|Ignoring|lock|Lock' | Select-Object -Last 10
& C:\ii\host\build\ii-host.exe --rescue | Out-Null
