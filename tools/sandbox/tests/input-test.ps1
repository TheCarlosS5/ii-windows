Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  public static void Vk(string text) { foreach (var ch in text.ToUpper()) { var a = new IN[2]; a[0].type = 1; a[0].ki.vk = ch; a[0].ki.scan = (ushort)MapVirtualKey(ch, 0); a[1] = a[0]; a[1].ki.flags = 2; SendInput(2, a, Marshal.SizeOf(typeof(IN))); System.Threading.Thread.Sleep(40); } }
  public static void Click(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(200); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(300); }
}
'@
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p C:\ii\prototypes\qs-input\shell.qml'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 5
& C:\ii\tools\dev\windows.ps1 -Process quickshell | Select-String 'QWindowIcon' | ForEach-Object { $_.Line.Trim() }
[K]::Vk('panel')
Start-Sleep 1
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\input-1.png | Out-Null
# click the floating window's field and type
$fw = (& C:\ii\tools\dev\windows.ps1 -Process quickshell | Select-String 'QWindowIcon' | Select-Object -First 1)
[K]::Click(760, 470)
[K]::Vk('click')
Start-Sleep 1
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\input-2.png | Out-Null
Stop-Process -Id $p.Id -Force
