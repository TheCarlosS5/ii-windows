# INSIDE the sandbox: with ii-host running the taskbar has an empty window region, so even when
# Windows shows it (desktop switch, auto-hide reveal) nothing is drawn or clickable; the rescue
# puts the full window back. Also the rescue script on its own.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class TR {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowRgnBox(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  // Explorer's taskbar (ii's tray window has the same class).
  public static IntPtr Explorer() {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var s = new StringBuilder(64); GetClassNameW(h, s, 64);
      if (s.ToString() == "Shell_TrayWnd") { uint pid; GetWindowThreadProcessId(h, out pid);
        if (System.Diagnostics.Process.GetProcessById((int)pid).ProcessName == "explorer") { found = h; return false; } }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static string Region() { RECT r; int t = GetWindowRgnBox(Explorer(), out r); return t + ":" + r.L + "," + r.T + "," + r.R + "," + r.B; }
}
'@
function Region { [TR]::Region() }  # type 0 none, 1 empty, 2 rectangle : box
$original = Region
"original region: $original"
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 25
Check 'with ii: taskbar region empty' ((Region).StartsWith('1:')) "(region=$(Region))"
# Windows shows the taskbar (as on a desktop switch): nothing must appear at the bottom.
$tray = [TR]::Explorer()
[TR]::ShowWindow($tray, 8) | Out-Null
Start-Sleep -Milliseconds 30
& "$dev\screenshot.ps1" -Out "$out\tr-1-shown.png" -Y 760 -H 63 | Out-Null
Start-Sleep 1
Check 'shown by Windows: host hides it again' (-not [TR]::IsWindowVisible($tray))
# Desktop switch, the real case.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class K {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    public static void Chord(params ushort[] keys) {
        var a = new IN[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++) foreach (var up in new[] { false, true }) {
            int idx = up ? keys.Length * 2 - 1 - i : i;
            a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0);
            a[idx].ki.flags = (up ? 2u : 0u) | ((keys[i] == 0x5B || keys[i] == 0x25 || keys[i] == 0x27) ? 1u : 0u);
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
}
'@
[K]::Chord(0x5B, 0x11, 0x44)          # new desktop
Start-Sleep -Milliseconds 150
& "$dev\screenshot.ps1" -Out "$out\tr-2-switch.png" -Y 760 -H 63 | Out-Null
Start-Sleep 2
[K]::Chord(0x5B, 0x11, 0x73)          # close it
Start-Sleep 2
Check 'after desktop switches: region still empty' ((Region).StartsWith('1:')) "(region=$(Region))"

& "$hostDir\ii-host.exe" --rescue
Start-Sleep 2
Check 'rescue: taskbar region back' ((Region) -eq $original) "(region=$(Region))"
Check 'rescue: taskbar visible' ([TR]::IsWindowVisible([TR]::Explorer()))
& "$dev\screenshot.ps1" -Out "$out\tr-3-rescued.png" -Y 760 -H 63 | Out-Null

# The rescue script alone (no binaries): region back too.
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 20
Get-Process ii-host -ErrorAction SilentlyContinue | Stop-Process -Force   # host and guard gone: only the script
Start-Sleep 1
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
Start-Sleep 2
Check 'rescue.ps1: taskbar region back' ((Region) -eq $original) "(region=$(Region))"
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
"fails: $script:fails"
