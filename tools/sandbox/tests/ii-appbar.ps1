# INSIDE the sandbox: the full shell under ii-host (taskbar hidden, ii's tray) must reserve the
# bar's space, keep it across an Explorer restart, and never leave Explorer unresponsive.
$out = 'C:\xchg\outbox'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$hostDir = "$env:USERPROFILE\ii-hostbin"
New-Item -ItemType Directory -Force $hostDir | Out-Null
Copy-Item C:\ii\host\build\ii-host.exe $hostDir -Force

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Diagnostics;
public static class AB {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint p, ref RECT r, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowExW(IntPtr p, IntPtr a, string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public static IntPtr TrayOf(string owner) {
    IntPtr h = IntPtr.Zero;
    while ((h = FindWindowExW(IntPtr.Zero, h, "Shell_TrayWnd", null)) != IntPtr.Zero) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (Process.GetProcessById((int)pid).ProcessName == owner) return h;
    }
    return IntPtr.Zero;
  }
  public static int Top() { var r = new RECT(); SystemParametersInfoW(0x30, 0, ref r, 0); return r.t; }
  public static IntPtr ExplorerTray() {
    IntPtr h = IntPtr.Zero;
    while ((h = FindWindowExW(IntPtr.Zero, h, "Shell_TrayWnd", null)) != IntPtr.Zero) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (Process.GetProcessById((int)pid).ProcessName == "explorer") return h;
    }
    return IntPtr.Zero;
  }
  // Explorer's taskbar thread answers a WM_NULL within 1 s, or it is (about to be) hung.
  public static long Ping() {
    var sw = Stopwatch.StartNew(); IntPtr r;
    var ok = SendMessageTimeoutW(ExplorerTray(), 0, IntPtr.Zero, IntPtr.Zero, 2, 5000, out r);
    return ok == IntPtr.Zero ? -1 : sw.ElapsedMilliseconds;
  }
}
'@
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
function Watch($seconds, $label) {
    $tops = @(); $pings = @()
    for ($i = 0; $i -lt $seconds; $i += 2) { $tops += [AB]::Top(); $pings += [AB]::Ping(); Start-Sleep 2 }
    # Write-Host: a function's plain output would end up in the returned value.
    Write-Host "$label work-area tops: $($tops -join ' ')"
    Write-Host "$label explorer ping ms: $($pings -join ' ')"
    @{ tops = $tops; pings = $pings }
}

"work-area top before: $([AB]::Top())"
$app = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '240', '-Name', 'appbar-test' -PassThru -WindowStyle Hidden
$h = Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" -PassThru
Start-Sleep 25
$a = Watch 40 'running'
Check 'bar reserves its space' ($a.tops[-1] -ge 30) "(top=$($a.tops[-1]))"
Check 'Explorer always answered' (-not ($a.pings | Where-Object { $_ -lt 0 -or $_ -gt 1000 })) "(max $(($a.pings | Measure-Object -Maximum).Maximum) ms)"

# Another app's app bar while ii's tray is the one FindWindow returns (SHAppBarMessage goes
# through ii's forwarder): does its reservation take effect?
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class AB2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint p, ref RECT r, uint f);
  public static int Left() { var r = new RECT(); SystemParametersInfoW(0x30, 0, ref r, 0); return r.l; }
}
"@
$f = New-Object System.Windows.Forms.Form; $f.ShowInTaskbar = $false; $f.FormBorderStyle = 'None'; $null = $f.Handle
$d = New-Object AB2+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); $d.hWnd = $f.Handle; $d.uCallbackMessage = 0x8128
$new = [AB2]::SHAppBarMessage(0, [ref]$d)
$r = New-Object AB2+RECT; $r.r = 30; $r.b = 600; $d.uEdge = 0; $d.rc = $r
[void][AB2]::SHAppBarMessage(2, [ref]$d); $r = $d.rc; $r.r = $r.l + 30; $d.rc = $r
[void][AB2]::SHAppBarMessage(3, [ref]$d); Start-Sleep 2
Check "another app's left app bar through ii's tray" ([AB2]::Left() -ge 30) "(NEW=$new rc=($($d.rc.l),$($d.rc.t),$($d.rc.r),$($d.rc.b)) work left=$([AB2]::Left()))"
[void][AB2]::SHAppBarMessage(1, [ref]$d); Start-Sleep 1; $f.Dispose()

Get-Process explorer | Stop-Process -Force
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
Start-Sleep 15
$b = Watch 30 'after explorer restart'
Check 'space reserved again after Explorer restart' ($b.tops[-1] -ge 30) "(top=$($b.tops[-1]))"
Check 'Explorer answered after restart' (-not ($b.pings | Select-Object -Last 8 | Where-Object { $_ -lt 0 -or $_ -gt 1000 }))
& C:\ii\tools\dev\screenshot.ps1 -Out "$out\appbar.png" | Out-Null

& "$hostDir\ii-host.exe" --rescue
Start-Sleep 4
Check 'rescue gives the space back' ([AB]::Top() -eq 0) "(top=$([AB]::Top()))"
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Select-String 'appbar|tray' | ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -First 30
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
"fails: $script:fails"
