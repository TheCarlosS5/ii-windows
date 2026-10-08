# INSIDE the sandbox: the overview as a grid of all windows (click focuses), the dock's window
# previews on hover and its right-click menu. Also measures UI stalls while the overview opens.
param([int]$DockX = 672)
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
# A private staging (stage-ii.ps1 -Dest build\ii-claude) wins over build\ii when present.
$cfgSrc = if (Test-Path C:\ii\build\ii-claude) { 'C:\ii\build\ii-claude' } else { 'C:\ii\build\ii' }
robocopy $cfgSrc $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Diagnostics; using System.Text;
public static class OD {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeoutW(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  public static string ForegroundClass() { var s = new StringBuilder(200); GetClassNameW(GetForegroundWindow(), s, 200); return s.ToString(); }
  public static string Probe(int pid, int ms) {
    IntPtr h = IntPtr.Zero;
    EnumWindows((w, l) => { uint p; GetWindowThreadProcessId(w, out p); if (p == pid) { h = w; return false; } return true; }, IntPtr.Zero);
    var total = Stopwatch.StartNew(); long worst = 0; IntPtr r;
    while (total.ElapsedMilliseconds < ms) { var sw = Stopwatch.StartNew(); SendMessageTimeoutW(h, 0, IntPtr.Zero, IntPtr.Zero, 0, 10000, out r); worst = Math.Max(worst, sw.ElapsedMilliseconds); System.Threading.Thread.Sleep(15); }
    return worst + " ms";
  }
}
'@

$env:QT_LOGGING_RULES = 'quickshell.win32.compat.debug=true'
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Start-Process explorer.exe $env:USERPROFILE; Start-Sleep 2
Start-Process explorer.exe C:\; Start-Sleep 2
Start-Process cmd.exe; Start-Sleep 1
Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', '$host.UI.RawUI.WindowTitle = \"ii test\"'
Start-Sleep 5
$qs = Get-Process quickshell | Select-Object -First 1
# One minimized window: the overview shows it as a card with its icon.
Add-Type -Namespace MW -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
$cmdWindow = (Get-Process cmd | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
if ($cmdWindow) { [void][MW.W]::ShowWindow($cmdWindow, 6) }
Start-Sleep 1

& "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null
"overview open, worst UI stall: $([OD]::Probe($qs.Id, 1500))"
& "$dev\screenshot.ps1" -Out "$out\od-1-overview.png" | Out-Null
# Click the first preview (top-left cell): it should come to the front.
$before = [OD]::ForegroundClass()
& "$dev\click.ps1" -X 470 -Y 280 -Button Left
Start-Sleep 2
$after = [OD]::ForegroundClass()
Check 'clicking a preview focuses its window' ($after -ne '' -and $after -notmatch 'Qt') "(before=$before after=$after)"
& "$dev\screenshot.ps1" -Out "$out\od-2-focused.png" | Out-Null

# Dock: reveal, hover the Explorer icon (two windows), then right click it.
[void][OD]::SetCursorPos($DockX, 822); Start-Sleep 1
[void][OD]::SetCursorPos($DockX, 790); Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\od-3-dock-hover.png" | Out-Null
& "$dev\click.ps1" -X $DockX -Y 790 -Button Right
Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\od-4-dock-menu.png" | Out-Null
& "$dev\click.ps1" -X 300 -Y 300 -Button Left
Start-Sleep 1

$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'thumbnail|Overview|Dock|dock' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 30
& "$hostDir\ii-host.exe" --rescue
Get-Process cmd, powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.MainWindowTitle } | Stop-Process -Force -ErrorAction SilentlyContinue
"fails: $script:fails"
