Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class D {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  static string Cls(IntPtr h) { var s = new StringBuilder(128); GetClassName(h, s, 128); return s.ToString(); }
  static string Desc(IntPtr h) { RECT r; GetWindowRect(h, out r); return string.Format("0x{0:X} {1} vis={2} style=0x{3:X8} {4},{5} {6}x{7}", h.ToInt64(), Cls(h), IsWindowVisible(h), GetWindowLong(h, -16), r.L, r.T, r.R-r.L, r.B-r.T); }
  public static string Tree() {
    var sb = new StringBuilder();
    var pm = FindWindow("Progman", null);
    sb.AppendLine("Progman " + Desc(pm));
    // direct children in z-order
    for (var c = GetWindow(pm, 5); c != IntPtr.Zero; c = GetWindow(c, 2)) {
      sb.AppendLine("  child " + Desc(c));
      for (var g = GetWindow(c, 5); g != IntPtr.Zero; g = GetWindow(g, 2)) sb.AppendLine("    grandchild " + Desc(g));
    }
    EnumWindows((h, l) => { var cl = Cls(h); if (cl == "WorkerW" && IsWindowVisible(h)) sb.AppendLine("top-level visible WorkerW " + Desc(h)); return true; }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
'=== before'
[D]::Tree()
$pm = [D]::FindWindow('Progman', $null)
$r = [IntPtr]::Zero
[D]::SendMessageTimeout($pm, 0x052C, [IntPtr]0xD, [IntPtr]0x1, 0, 1000, [ref]$r) | Out-Null
Start-Sleep 1
'=== after 0x052C'
[D]::Tree()
