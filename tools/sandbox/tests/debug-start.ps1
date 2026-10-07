Add-Type -TypeDefinition @'
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text;
public static class S {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
  public static void Win() { var a = new INPUT[2]; a[0].type = 1; a[0].ki.vk = 0x5B; a[0].ki.flags = 1; a[1] = a[0]; a[1].ki.flags = 3; SendInput(2, a, Marshal.SizeOf(typeof(INPUT))); }
  public static string Dump() {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      string pn = ""; try { pn = Process.GetProcessById((int)pid).ProcessName; } catch {}
      if (pn != "StartMenuExperienceHost" && pn != "SearchHost" && pn != "ShellExperienceHost" && pn != "explorer") return true;
      var c = new StringBuilder(128); GetClassName(h, c, 128); var t = new StringBuilder(128); GetWindowText(h, t, 128);
      if (!c.ToString().Contains("CoreWindow") && !c.ToString().Contains("Xaml")) return true;
      int cl; DwmGetWindowAttribute(h, 14, out cl, 4); RECT r; GetWindowRect(h, out r);
      sb.AppendLine(pn + " " + c + " '" + t + "' vis=" + IsWindowVisible(h) + " cloak=" + cl + " " + r.L + "," + r.T + " " + (r.R-r.L) + "x" + (r.B-r.T));
      return true; }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
'--- closed'; [S]::Dump()
[S]::Win(); Start-Sleep 2
'--- after Win'; [S]::Dump()
[S]::Win(); Start-Sleep 1.5
'--- after second Win'; [S]::Dump()
