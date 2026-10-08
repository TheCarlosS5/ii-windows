# INSIDE the sandbox: SHAppBarMessage's wire format when the taskbar window lives in ANOTHER
# process (the normal case, and what ii's tray sees from apps). A child PowerShell hosts a fake
# Shell_TrayWnd and dumps what it receives; this process sends QUERYPOS/SETPOS.
param([switch]$Tray, [string]$Log = "$env:TEMP\appbar-capture2.txt")
$code = @'
using System; using System.Runtime.InteropServices; using System.Text; using System.IO;
public static class CAP2 {
  delegate IntPtr WndProc(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WNDCLASS { public uint style; public WndProc proc; public int cls; public int wnd; public IntPtr inst; public IntPtr icon; public IntPtr cursor; public IntPtr bg; public string menu; public string name; }
  [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr h; public uint m; public IntPtr w; public IntPtr l; public uint t; public int x, y; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern ushort RegisterClassW(ref WNDCLASS c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
  [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern int GetMessageW(out MSG m, IntPtr h, uint a, uint b);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref MSG m);
  [DllImport("user32.dll")] static extern bool ChangeWindowMessageFilterEx(IntPtr h, uint m, uint a, IntPtr p);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandleW(IntPtr n);
  [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
  [DllImport("shlwapi.dll")] static extern IntPtr SHLockShared(IntPtr h, uint pid);
  [DllImport("shlwapi.dll")] static extern bool SHUnlockShared(IntPtr p);
  static WndProc keep = Proc;
  public static string LogPath;
  static void W(string s) { File.AppendAllText(LogPath, s + "\n"); }
  static void Dump(string label, IntPtr p, int n) { var b = new byte[n]; Marshal.Copy(p, b, 0, n); var sb = new StringBuilder(label); for (int i = 0; i < n; i += 4) sb.AppendFormat(" {0:X8}", BitConverter.ToUInt32(b, i)); W(sb.ToString()); }
  static IntPtr Proc(IntPtr h, uint m, IntPtr w, IntPtr l) {
    if (m == 0x4A) {
      IntPtr dwData = Marshal.ReadIntPtr(l, 0); int cb = Marshal.ReadInt32(l, IntPtr.Size); IntPtr p = Marshal.ReadIntPtr(l, IntPtr.Size * 2);
      W(string.Format("WM_COPYDATA dwData={0} cb={1} me={2}", dwData, cb, GetCurrentProcessId()));
      Dump("  bytes:", p, cb);
      if (cb >= 64) {
        long v48 = Marshal.ReadInt64(p, 48); uint v56 = (uint)Marshal.ReadInt32(p, 56);
        W(string.Format("  +48={0:X} +56={1}", v48, v56));
        if (v48 != 0) {
          foreach (uint pid in new uint[] { GetCurrentProcessId(), v56 }) {
            IntPtr view = SHLockShared(new IntPtr(v48), pid);
            if (view != IntPtr.Zero) { Dump("  SHLockShared(+48, " + pid + "):", view, 40); SHUnlockShared(view); }
            else W("  SHLockShared(+48, " + pid + ") failed");
          }
        }
      }
      return (IntPtr)1;
    }
    return DefWindowProcW(h, m, w, l);
  }
  public static void Run() {
    var c = new WNDCLASS { proc = keep, inst = GetModuleHandleW(IntPtr.Zero), name = "Shell_TrayWnd" };
    RegisterClassW(ref c);
    var hwnd = CreateWindowExW(0x88, "Shell_TrayWnd", "", 0x80000000, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, c.inst, IntPtr.Zero);
    ChangeWindowMessageFilterEx(hwnd, 0x4A, 1, IntPtr.Zero);
    W("fake tray " + hwnd + " in pid " + GetCurrentProcessId());
    MSG msg; while (GetMessageW(out msg, IntPtr.Zero, 0, 0) > 0) DispatchMessageW(ref msg);
  }
}
'@
if ($Tray) {
    Add-Type -TypeDefinition $code
    [CAP2]::LogPath = $Log
    [CAP2]::Run()
    return
}
Remove-Item $Log -ErrorAction SilentlyContinue
$child = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Tray', '-Log', $Log -PassThru -WindowStyle Hidden
Start-Sleep 6
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class SND {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
}
'@
"sender pid $PID, tray child pid $($child.Id)"
$d = New-Object SND+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); $d.hWnd = [IntPtr]0x123456; $d.uCallbackMessage = 0xC0DE; $d.uEdge = 1
$r = New-Object SND+RECT; $r.l = 0x11; $r.t = 0x22; $r.r = 0x33; $r.b = 0x44; $d.rc = $r
foreach ($m in 2, 3) { "send $m -> $([SND]::SHAppBarMessage($m, [ref]$d))" }
Start-Sleep 1
Stop-Process -Id $child.Id -Force
Get-Content $Log
