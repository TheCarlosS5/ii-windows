Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
  public static void Type(string text) { foreach (var ch in text) { var a = new IN[2]; a[0].type = 1; a[0].ki.scan = ch; a[0].ki.flags = 4; a[1] = a[0]; a[1].ki.flags = 6; SendInput(2, a, Marshal.SizeOf(typeof(IN))); System.Threading.Thread.Sleep(40); } }
}
'@
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo 'C:\ii\dist\quickshell\quickshell.exe'
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 16
& C:\ii\tools\dev\send-shortcut.ps1 -Name overviewWorkspacesToggle | Out-Null
Start-Sleep 1.5
Add-Type -Namespace F -Name G -MemberDefinition '[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint p); [DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);'
$fg = [F.G]::GetForegroundWindow(); $fpid = 0; [F.G]::GetWindowThreadProcessId($fg, [ref]$fpid) | Out-Null
"foreground: 0x{0:X} pid={1} ({2}) ex=0x{3:X8}" -f $fg.ToInt64(), $fpid, (Get-Process -Id $fpid).ProcessName, [F.G]::GetWindowLong($fg, -20)
& C:\ii	ools\dev\zorder.ps1 | Select-Object -First 3
[K]::Type('calc')
Start-Sleep 1.5
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\launcher-calc.png | Out-Null
[K]::Type("`b`b`b`bterm")
Start-Sleep 1.5
& C:\ii\tools\dev\screenshot.ps1 -Out C:\xchg\outbox\launcher-term.png | Out-Null
Stop-Process -Id $p.Id -Force
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'winapps|Indexed|icon' } | Select-Object -First 10
