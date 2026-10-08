# INSIDE the sandbox: how long does ii's UI thread stall when the overview opens with several
# windows? Pings quickshell's windows (WM_NULL) every 15 ms while the overview opens and reports
# the longest gap; screenshots the overview.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host, notepad -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Diagnostics; using System.Collections.Generic;
public static class OP {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeoutW(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  public static IntPtr AnyWindow(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  // Longest time the GUI thread took to answer, sampling for `ms`.
  public static string Probe(int pid, int ms) {
    var h = AnyWindow(pid); var total = Stopwatch.StartNew(); long worst = 0; int n = 0; IntPtr r;
    while (total.ElapsedMilliseconds < ms) {
      var sw = Stopwatch.StartNew();
      SendMessageTimeoutW(h, 0, IntPtr.Zero, IntPtr.Zero, 0, 10000, out r);
      worst = Math.Max(worst, sw.ElapsedMilliseconds); n++;
      System.Threading.Thread.Sleep(15);
    }
    return "worst " + worst + " ms over " + n + " pings";
  }
}
'@

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
foreach ($i in 1..3) { Start-Process notepad; Start-Sleep 1 }
Start-Process explorer.exe $env:USERPROFILE
Start-Process cmd.exe
Start-Sleep 6
$qs = Get-Process quickshell | Select-Object -First 1
"idle: $([OP]::Probe($qs.Id, 1000))"

foreach ($round in 1..3) {
    & "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null
    "open $round : $([OP]::Probe($qs.Id, 2500))"
    if ($round -eq 1) { & "$dev\screenshot.ps1" -Out "$out\overview-open.png" | Out-Null }
    & "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null
    "close ${round}: $([OP]::Probe($qs.Id, 1500))"
}
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'overview|Overview|winapps|icon' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 12
& "$hostDir\ii-host.exe" --rescue
Get-Process notepad, cmd -ErrorAction SilentlyContinue | Stop-Process -Force
"done"
