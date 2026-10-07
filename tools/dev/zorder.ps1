# Visible top-level windows in z-order (top first), with owner process and TOPMOST flag.
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Diagnostics; using System.Runtime.InteropServices;
public static class Z {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public static string Dump() {
    var sb = new StringBuilder(); int i = 0;
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      int cloaked; DwmGetWindowAttribute(h, 14, out cloaked, 4);
      RECT r; GetWindowRect(h, out r);
      if (r.R - r.L <= 1 || r.B - r.T <= 1) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      string pn = "?"; try { pn = Process.GetProcessById((int)pid).ProcessName; } catch {}
      var c = new StringBuilder(64); GetClassName(h, c, 64);
      bool top = (GetWindowLong(h, -20) & 0x8) != 0;
      sb.AppendLine(string.Format("{0,3} 0x{1:X} {2,-12} {3,-28} {4} {5},{6} {7}x{8}{9}", i++, h.ToInt64(), pn, c, top ? "TOPMOST" : "normal ", r.L, r.T, r.R - r.L, r.B - r.T, cloaked != 0 ? " cloaked" : ""));
      return true; }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
[Z]::Dump()
