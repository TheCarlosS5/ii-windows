# INSIDE the sandbox: open the overview, type into its search (with and without clicking first).
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  public static void Vk(string text) {
    foreach (var ch in text.ToUpper()) {
      var a = new IN[2]; a[0].type = 1; a[0].ki.vk = ch; a[0].ki.scan = (ushort)MapVirtualKey(ch, 0); a[1] = a[0]; a[1].ki.flags = 2;
      SendInput(2, a, Marshal.SizeOf(typeof(IN))); System.Threading.Thread.Sleep(40);
    }
  }
  public static void Key(ushort vk) { var a = new IN[2]; a[0].type = 1; a[0].ki.vk = vk; a[1] = a[0]; a[1].ki.flags = 2; SendInput(2, a, Marshal.SizeOf(typeof(IN))); }
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(200);
    mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(300);
  }
}
'@
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
# run from the sandbox's own disk: the mapped folder is far slower than a real install
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.EnvironmentVariables['QT_LOGGING_RULES'] = 'qt.qpa.events=true';
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16

& "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null
Start-Sleep 1.5
$fg = [K]::GetForegroundWindow(); $fpid = 0; [K]::GetWindowThreadProcessId($fg, [ref]$fpid) | Out-Null
"foreground after open: 0x{0:X} ({1})" -f $fg.ToInt64(), (Get-Process -Id $fpid).ProcessName
& "$dev\zorder.ps1" | Select-Object -First 8
[K]::Vk('calc')
Start-Sleep 1.5
& "$dev\screenshot.ps1" -Out "$out\launcher-calc.png" | Out-Null

# same again, but click into the field first like a user would
[K]::Click(730, 78)
[K]::Vk('term')
Start-Sleep 1.5
& "$dev\screenshot.ps1" -Out "$out\launcher-term.png" | Out-Null

Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'DBGSEARCH' } | Select-Object -Last 40
