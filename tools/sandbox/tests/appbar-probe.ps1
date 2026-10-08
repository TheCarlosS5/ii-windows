# INSIDE the sandbox: when does Explorer honour an app bar reservation? Tries a hidden and a
# visible window, with the taskbar normal, auto-hidden and hidden (what ii-host does), and prints
# the work area after each step.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class AP {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string t);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLongW(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint p, ref RECT r, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr w, ref COPYDATASTRUCT l, uint flags, uint timeout, out IntPtr result);
  [DllImport("shlwapi.dll")] public static extern IntPtr SHAllocShared(IntPtr data, uint size, uint pid);
  [DllImport("shlwapi.dll")] public static extern IntPtr SHLockShared(IntPtr h, uint pid);
  [DllImport("shlwapi.dll")] public static extern bool SHUnlockShared(IntPtr p);
  [DllImport("shlwapi.dll")] public static extern bool SHFreeShared(IntPtr h, uint pid);
  // The same message quickshell's explorerAppBarMessage sends (APPBARMSGDATA3264).
  public static string Crafted(IntPtr tray, IntPtr wnd, uint message, uint edge, int l, int t, int r, int b) {
    uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
    byte[] abd = new byte[40];
    BitConverter.GetBytes(40).CopyTo(abd, 0); BitConverter.GetBytes((uint)wnd.ToInt64()).CopyTo(abd, 4);
    BitConverter.GetBytes(0x8127u).CopyTo(abd, 8); BitConverter.GetBytes(edge).CopyTo(abd, 12);
    BitConverter.GetBytes(l).CopyTo(abd, 16); BitConverter.GetBytes(t).CopyTo(abd, 20); BitConverter.GetBytes(r).CopyTo(abd, 24); BitConverter.GetBytes(b).CopyTo(abd, 28);
    IntPtr hShared = IntPtr.Zero;
    if (message == 2 || message == 3) { IntPtr tmp = Marshal.AllocHGlobal(40); Marshal.Copy(abd, 0, tmp, 40); hShared = SHAllocShared(tmp, 40, me); Marshal.FreeHGlobal(tmp); }
    byte[] m = new byte[56]; abd.CopyTo(m, 0);
    BitConverter.GetBytes(message).CopyTo(m, 40); BitConverter.GetBytes((uint)hShared.ToInt64()).CopyTo(m, 44); BitConverter.GetBytes(me).CopyTo(m, 48);
    IntPtr mem = Marshal.AllocHGlobal(56); Marshal.Copy(m, 0, mem, 56);
    var cds = new COPYDATASTRUCT { dwData = IntPtr.Zero, cbData = 56, lpData = mem };
    IntPtr result; IntPtr ok = SendMessageTimeoutW(tray, 0x4A, wnd, ref cds, 2, 5000, out result);
    Marshal.FreeHGlobal(mem);
    string rc = "";
    if (hShared != IntPtr.Zero) { IntPtr p = SHLockShared(hShared, me); if (p != IntPtr.Zero) { rc = string.Format(" rc=({0},{1},{2},{3})", Marshal.ReadInt32(p, 16), Marshal.ReadInt32(p, 20), Marshal.ReadInt32(p, 24), Marshal.ReadInt32(p, 28)); SHUnlockShared(p); } SHFreeShared(hShared, me); }
    return "sent=" + ok + " result=" + result + rc;
  }
  public static string Work() { var r = new RECT(); SystemParametersInfoW(0x30, 0, ref r, 0); return string.Format("({0},{1})-({2},{3})", r.l, r.t, r.r, r.b); }
}
'@
# Not Screen.WorkingArea: WinForms caches it until a message loop sees WM_SETTINGCHANGE.
function Work { [AP]::Work() }
function Pump($ms) { $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 } }

$tray = [AP]::FindWindowW('Shell_TrayWnd', [NullString]::Value)
$s = New-Object AP+APPBARDATA; $s.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($s); $s.hWnd = $tray
$origState = [AP]::SHAppBarMessage(4, [ref]$s).ToUInt32()
$width = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
"original taskbar state=$origState work=$(Work)"

function Try-Variant($label, [bool]$visible, [bool]$tool) {
    $f = New-Object System.Windows.Forms.Form
    $f.ShowInTaskbar = $false; $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'
    $f.Left = 0; $f.Top = 0; $f.Width = $width; $f.Height = 60; $f.TopMost = $true; $f.BackColor = 'DarkSlateBlue'
    $null = $f.Handle
    if ($tool) { $ex = [AP]::GetWindowLongW($f.Handle, -20); [void][AP]::SetWindowLongW($f.Handle, -20, $ex -bor 0x80 -bor 0x08000000 -bor 0x80000) }
    if ($visible) { $f.Show(); Pump 300 }
    $d = New-Object AP+APPBARDATA; $d.cbSize = $s.cbSize; $d.hWnd = $f.Handle; $d.uCallbackMessage = 0x8126
    $new = [AP]::SHAppBarMessage(0, [ref]$d)
    # $d.rc.x = ... would change a copy of the nested struct: assign a whole RECT.
    $r = New-Object AP+RECT; $r.r = $width; $r.b = 60
    $d.uEdge = 1; $d.rc = $r
    [void][AP]::SHAppBarMessage(2, [ref]$d)
    $r = $d.rc; $r.b = $r.t + 60; $d.rc = $r
    [void][AP]::SHAppBarMessage(3, [ref]$d); Pump 1200
    "$label (visible=$visible tool=$tool): NEW=$new rc=($($d.rc.l),$($d.rc.t),$($d.rc.r),$($d.rc.b)) work=$(Work)"
    [void][AP]::SHAppBarMessage(1, [ref]$d); Pump 800
    $f.Close(); $f.Dispose()
}

$f = New-Object System.Windows.Forms.Form; $f.ShowInTaskbar = $false; $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'
$f.Left = 0; $f.Top = 0; $f.Width = $width; $f.Height = 60; $f.TopMost = $true; $f.Show(); Pump 300
"F crafted NEW      $([AP]::Crafted($tray, $f.Handle, 0, 1, 0, 0, 0, 0))"
"F crafted QUERYPOS $([AP]::Crafted($tray, $f.Handle, 2, 1, 0, 0, $width, 60))"
"F crafted SETPOS   $([AP]::Crafted($tray, $f.Handle, 3, 1, 0, 0, $width, 60))"; Pump 1200
"F crafted work=$(Work)"
"F crafted REMOVE   $([AP]::Crafted($tray, $f.Handle, 1, 1, 0, 0, 0, 0))"; Pump 800
"F after remove work=$(Work)"
$f.Close(); $f.Dispose()
Try-Variant 'A taskbar normal' $false $false
Try-Variant 'B taskbar normal' $true $false
Try-Variant 'C taskbar normal' $true $true
$s.lParam = [IntPtr]1; [void][AP]::SHAppBarMessage(10, [ref]$s); Pump 1500
"auto-hide on: work=$(Work)"
Try-Variant 'D auto-hide' $true $true
[void][AP]::ShowWindow($tray, 0); Pump 800
Try-Variant 'E auto-hide + taskbar hidden' $true $true
[void][AP]::ShowWindow($tray, 5); Pump 800
$s.lParam = [IntPtr]$origState; [void][AP]::SHAppBarMessage(10, [ref]$s); Pump 1500
"restored state=$([AP]::SHAppBarMessage(4, [ref]$s)) work=$(Work)"
