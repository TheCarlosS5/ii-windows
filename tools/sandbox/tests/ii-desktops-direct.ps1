# INSIDE the sandbox (Windows 11 24H2+): desktops through `ii-shim vdesk` - direct switches, the
# empty last desktop dropped when left, Win+Shift+number moves the window in front, closing a
# desktop from the strip without visiting it.
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
[ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IVirtualDesktopManager {
    [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr hwnd, out int onCurrent);
    [PreserveSig] int GetWindowDesktopId(IntPtr hwnd, out Guid id);
}
public static class VD {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    public static void Chord(params ushort[] keys) {
        var a = new IN[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++) foreach (var up in new[] { false, true }) {
            int idx = up ? keys.Length * 2 - 1 - i : i;
            a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0);
            a[idx].ki.flags = (up ? 2u : 0u) | (keys[i] == 0x5B ? 1u : 0u);
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
    public static bool AnyModifierDown() {
        foreach (var vk in new[] { 0x5B, 0x5C, 0x11, 0x10, 0x12 }) if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        return false;
    }
    static IVirtualDesktopManager mgr = (IVirtualDesktopManager)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")));
    public static string DesktopOf(IntPtr h) { Guid g; return mgr.GetWindowDesktopId(h, out g) == 0 ? g.ToString() : "?"; }
}
'@
function Desktops {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops'
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $ids = @()
    if ($p.VirtualDesktopIDs) { for ($i = 0; $i -lt $p.VirtualDesktopIDs.Length; $i += 16) { $ids += [Guid]::new([byte[]]$p.VirtualDesktopIDs[$i..($i + 15)]).ToString() } }
    if (-not $ids) { $ids = @('only') }
    $cur = 1
    if ($p.CurrentVirtualDesktop) { $c = [Guid]::new([byte[]]$p.CurrentVirtualDesktop).ToString(); $cur = [Array]::IndexOf($ids, $c) + 1 }
    [pscustomobject]@{ Count = $ids.Count; Current = $cur; Ids = $ids }
}
function ShellLog {
    Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime |
        Where-Object { (Get-Content $_.FullName -TotalCount 1) -match 'shell\.qml' } | Select-Object -Last 1
}

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 25
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'welcome\.qml' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$log = (ShellLog).FullName
Check 'vdesk available on this Windows' ((Get-Content $log) -match 'Direct desktop control: switch yes') ((Get-Content $log | Select-String 'Direct desktop').Line)

[VD]::Chord(0x5B, 0x32); Start-Sleep 3
[VD]::Chord(0x5B, 0x33); Start-Sleep 3
$d = Desktops; Check 'Win+2, Win+3: three desktops, on the third' ($d.Count -eq 3 -and $d.Current -eq 3) "($($d.Count)/$($d.Current))"
[VD]::Chord(0x5B, 0x31); Start-Sleep 4
$d = Desktops; Check 'Win+1 from 3 goes straight to 1, the empty last desktop is dropped' ($d.Count -eq 2 -and $d.Current -eq 1) "($($d.Count)/$($d.Current))"

# A console window (Explorer doesn't always open a window this early in the Sandbox).
$console = Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', '$host.UI.RawUI.WindowTitle = ''ii-vd-test''' -PassThru
$cab = [IntPtr]::Zero
for ($i = 0; $i -lt 20 -and $cab -eq [IntPtr]::Zero; $i++) { Start-Sleep 1; $cab = [VD]::FindWindow('ConsoleWindowClass', 'ii-vd-test') }
"test window: $cab"
# Bring it to the front (windows opened from a background script land behind).
Add-Type -Namespace TD -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r); public struct RECT { public int L, T, R, B; }' -ErrorAction SilentlyContinue
$r = New-Object TD.W+RECT; [TD.W]::GetWindowRect($cab, [ref]$r) | Out-Null
& "$dev\click.ps1" -X ([int](($r.L + $r.R) / 2)) -Y ($r.T + 12); Start-Sleep 1
$d = Desktops
Check 'test window opened on desktop 1' ([VD]::DesktopOf($cab) -eq $d.Ids[0])
"foreground before Win+Shift+2: $([VD]::GetForegroundWindow()) (test window $cab)"
[VD]::Chord(0x5B, 0x10, 0x32); Start-Sleep 3
$d = Desktops
if ([VD]::DesktopOf($cab) -ne $d.Ids[1]) {
    # Tell the shortcut apart from the move itself.
    & "$dist\bin\ii-shim.exe" vdesk move ([int64]$cab) 2
    "manual vdesk move: exit $LASTEXITCODE, now on desktop $([Array]::IndexOf((Desktops).Ids, [VD]::DesktopOf($cab)) + 1)"
}
Check 'Win+Shift+2 moves it to desktop 2 and stays on 1' ([VD]::DesktopOf($cab) -eq $d.Ids[1] -and $d.Current -eq 1) "(desktop $([Array]::IndexOf($d.Ids, [VD]::DesktopOf($cab)) + 1), current $($d.Current))"
[VD]::Chord(0x5B, 0x32); Start-Sleep 3
[VD]::Chord(0x5B, 0x31); Start-Sleep 4
$d = Desktops; Check 'a desktop with a window is not dropped when left' ($d.Count -eq 2 -and $d.Current -eq 1) "($($d.Count)/$($d.Current))"

# The strip's x: close desktop 2 from desktop 1, without visiting it; its window comes here.
& "$dev\send-shortcut.ps1" -Name 'hl:hl.dsp.ii.desktop.close({ workspace = 2 })' -PressOnly | Out-Null; Start-Sleep 4
$d = Desktops
Check 'closing desktop 2 from desktop 1 stays on 1' ($d.Count -eq 1 -and $d.Current -eq 1) "($($d.Count)/$($d.Current))"
Check 'its window moved to the remaining desktop' ([VD]::DesktopOf($cab) -eq $d.Ids[0] -or $d.Ids[0] -eq 'only')
Check 'no key left held down' (-not [VD]::AnyModifierDown())
& "$dev\screenshot.ps1" -Out "$out\vdd-end.png" | Out-Null
Get-Content $log | Select-String 'desktops|Desktops|vdesk|workspace|move' | Select-Object -Last 15 | ForEach-Object { "log: $($_.Line.Substring(24))" }
Stop-Process -Id $console.Id -Force -ErrorAction SilentlyContinue
& "$hostDir\ii-host.exe" --rescue
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
"fails: $script:fails"
