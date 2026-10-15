# Starts the shell (no host) on the staged QML and lists the moment each of its windows first appears.
param([int]$Seconds = 10, [string]$Runtime = "$env:USERPROFILE\dev\ii-dev-runtime")
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class WinList {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  public static IntPtr First(uint pid) { IntPtr found = IntPtr.Zero; EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { found = h; return false; } return true; }, IntPtr.Zero); return found; }
  public static bool Responds(IntPtr h, uint ms) { IntPtr r; return SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 3, ms, out r) != IntPtr.Zero; }
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  public static List<string> ForPid(uint pid) {
    var list = new List<string>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { RECT r; GetWindowRect(h, out r); list.Add(h.ToInt64().ToString("x") + " " + (r.R - r.L) + "x" + (r.B - r.T) + "@" + r.L + "," + r.T); } return true; }, IntPtr.Zero);
    return list;
  }
}
'@
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Runtime\quickshell\quickshell.exe"
$psi.Arguments = "-p `"$root\build\ii`""
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$psi.EnvironmentVariables['PATH'] = "$Runtime\quickshell\bin;" + $psi.EnvironmentVariables['PATH']
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = [System.Diagnostics.Process]::Start($psi)
$seen = @{}
$target = [IntPtr]::Zero
$blockedSince = -1
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    foreach ($w in [WinList]::ForPid([uint32]$p.Id)) { if (-not $seen[$w]) { $seen[$w] = $true; "{0,6:N0} ms  {1}" -f $sw.Elapsed.TotalMilliseconds, $w } }
    if ($target -eq [IntPtr]::Zero) { $target = [WinList]::First([uint32]$p.Id) }
    if ($target -ne [IntPtr]::Zero) {
        $ok = [WinList]::Responds($target, 120)
        $t = $sw.Elapsed.TotalMilliseconds
        if (-not $ok -and $blockedSince -lt 0) { $blockedSince = $t }
        if ($ok -and $blockedSince -ge 0) { '{0,6:N0} ms  main thread blocked for {1:N0} ms (since {2:N0})' -f $t, ($t - $blockedSince), $blockedSince; $blockedSince = -1 }
    }
    Start-Sleep -Milliseconds 30
}
try { $p.Kill() } catch {}
