# INSIDE the sandbox: what exactly does shell32's SHAppBarMessage send to the taskbar window?
# Creates a topmost Shell_TrayWnd (as ii's tray does), calls SHAppBarMessage and dumps the
# WM_COPYDATA it receives.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class CAP {
  delegate IntPtr WndProc(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WNDCLASS { public uint style; public WndProc proc; public int cls; public int wnd; public IntPtr inst; public IntPtr icon; public IntPtr cursor; public IntPtr bg; public string menu; public string name; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern ushort RegisterClassW(ref WNDCLASS c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
  [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string t);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandleW(IntPtr n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
  static WndProc keep = Proc;
  public static StringBuilder Log = new StringBuilder();
  static IntPtr Proc(IntPtr h, uint m, IntPtr w, IntPtr l) {
    if (m == 0x4A) {
      IntPtr dwData = Marshal.ReadIntPtr(l, 0); int cb = Marshal.ReadInt32(l, IntPtr.Size); IntPtr p = Marshal.ReadIntPtr(l, IntPtr.Size * 2);
      byte[] b = new byte[cb]; Marshal.Copy(p, b, 0, cb);
      Log.AppendFormat("WM_COPYDATA wParam={0:X} dwData={1} cbData={2}\n", w.ToInt64(), dwData, cb);
      for (int i = 0; i < cb; i += 4) Log.AppendFormat("  +{0,3}: {1:X8}\n", i, i + 4 <= cb ? BitConverter.ToUInt32(b, i) : 0);
      long ptr = BitConverter.ToInt64(b, 48);
      if (ptr != 0) {
        byte[] t = new byte[48]; Marshal.Copy(new IntPtr(ptr), t, 0, 48);
        Log.Append("  pointer at +48 holds:\n");
        for (int i = 0; i < 48; i += 4) Log.AppendFormat("    +{0,3}: {1:X8}\n", i, BitConverter.ToUInt32(t, i));
        // Answer like Explorer would: move the rectangle, to see which offset the caller reads back.
        Marshal.WriteInt32(new IntPtr(ptr), 16, 0x7716); Marshal.WriteInt32(new IntPtr(ptr), 24, 0x7724);
      }
      return (IntPtr)1;
    }
    return DefWindowProcW(h, m, w, l);
  }
  public static IntPtr Create() {
    var c = new WNDCLASS { proc = keep, inst = GetModuleHandleW(IntPtr.Zero), name = "Shell_TrayWnd" };
    RegisterClassW(ref c);
    return CreateWindowExW(0x88, "Shell_TrayWnd", "", 0x80000000, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, c.inst, IntPtr.Zero);
  }
}
'@
$mine = [CAP]::Create()
"fake tray $mine; FindWindow -> $([CAP]::FindWindowW('Shell_TrayWnd', [NullString]::Value))"
$d = New-Object CAP+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); $d.hWnd = [IntPtr]0x123456; $d.uCallbackMessage = 0xC0DE; $d.uEdge = 1
$r = New-Object CAP+RECT; $r.l = 0x11; $r.t = 0x22; $r.r = 0x33; $r.b = 0x44; $d.rc = $r; $d.lParam = [IntPtr]0x55
"APPBARDATA size $($d.cbSize)"
foreach ($msg in 0, 2, 3, 10) { [void][CAP]::SHAppBarMessage($msg, [ref]$d); "-- message $msg -> caller rc=($($d.rc.l),$($d.rc.t),$($d.rc.r),$($d.rc.b))" }
[CAP]::Log.ToString()
[void][CAP]::DestroyWindow($mine)
