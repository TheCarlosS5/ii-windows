# INSIDE the sandbox: Windows' virtual desktops in ii (bar dots, desktop strip in the overview,
# switch / create / close), with ii-host's keyboard hook live as on the real PC.
#   -Click "x,y;x,y"  optional clicks (screen pixels) on the overview's strip, after the keyboard part
param([string]$Clicks = '')
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
Remove-Item "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json" -ErrorAction SilentlyContinue
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class VD {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    public static string ForegroundClass() { var s = new StringBuilder(200); GetClassNameW(GetForegroundWindow(), s, 200); return s.ToString(); }
    static readonly ushort[] Ext = { 0x25, 0x26, 0x27, 0x28, 0x2E, 0x5B };
    // A user's key chord (untagged: ii-host's hook sees it like a real key press).
    public static void Chord(params ushort[] keys) {
        var a = new IN[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++) {
            foreach (var up in new[] { false, true }) {
                int idx = up ? keys.Length * 2 - 1 - i : i;
                a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0);
                a[idx].ki.flags = (up ? 2u : 0u) | (Array.IndexOf(Ext, keys[i]) >= 0 ? 1u : 0u);
            }
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
    public static bool AnyModifierDown() {
        foreach (var vk in new[] { 0x5B, 0x5C, 0x11, 0x10, 0x12 }) if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        return false;
    }
}
'@
function Desktops {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops'
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $ids = if ($p.VirtualDesktopIDs) { $p.VirtualDesktopIDs.Length / 16 } else { 1 }
    $cur = 0
    if ($p.CurrentVirtualDesktop -and $p.VirtualDesktopIDs) {
        $c = [Guid]::new([byte[]]$p.CurrentVirtualDesktop)
        for ($i = 0; $i -lt $ids; $i++) { if ([Guid]::new([byte[]]$p.VirtualDesktopIDs[($i * 16)..($i * 16 + 15)]) -eq $c) { $cur = $i } }
    }
    [pscustomobject]@{ Count = $ids; Current = $cur + 1 }
}
function QsLog { Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1 }
function Overview { & "$dev\send-shortcut.ps1" -Name overviewWorkspacesToggle | Out-Null; Start-Sleep 2 }

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
Start-Process explorer.exe C:\; Start-Sleep 3
"start: $(Desktops)"
& "$dev\screenshot.ps1" -Out "$out\vd-1-bar.png" -H 60 | Out-Null
Overview
& "$dev\screenshot.ps1" -Out "$out\vd-2-overview.png" | Out-Null
Overview

# User presses Win+Ctrl+D: a new desktop, Windows switches to it.
[VD]::Chord(0x5B, 0x11, 0x44); Start-Sleep 3
$d = Desktops
Check 'Win+Ctrl+D makes a second desktop' ($d.Count -eq 2 -and $d.Current -eq 2) "($d)"
Check 'no key left held down' (-not [VD]::AnyModifierDown())
Check 'Start did not open' ([VD]::ForegroundClass() -notmatch 'Windows.UI.Core.CoreWindow') "(fg=$([VD]::ForegroundClass()))"
& "$dev\screenshot.ps1" -Out "$out\vd-3-bar-2.png" -H 60 | Out-Null
Overview
& "$dev\screenshot.ps1" -Out "$out\vd-4-overview-2.png" | Out-Null
# With the overview open, the user goes back to desktop 1 (Win+Ctrl+Left): the overview should stay.
[VD]::Chord(0x5B, 0x11, 0x25); Start-Sleep 3
Check 'Win+Ctrl+Left goes back' ((Desktops).Current -eq 1) "($(Desktops))"
& "$dev\screenshot.ps1" -Out "$out\vd-5-overview-back.png" | Out-Null

if ($Clicks) {
    $n = 6
    foreach ($c in $Clicks.Split(';')) {
        $xy = $c.Split(',')
        & "$dev\click.ps1" -X ([int]$xy[0]) -Y ([int]$xy[1]) -Button ($(if ($xy.Count -gt 2) { $xy[2] } else { 'Left' }))
        Start-Sleep 3
        "after click $c : $(Desktops)"
        & "$dev\screenshot.ps1" -Out "$out\vd-$n-click.png" | Out-Null
        $n++
    }
}
Overview

# Win+Ctrl+F4 closes the current desktop.
if ((Desktops).Count -lt 2) { [VD]::Chord(0x5B, 0x11, 0x44); Start-Sleep 3 }
$before = (Desktops).Count
[VD]::Chord(0x5B, 0x11, 0x73); Start-Sleep 3
Check 'Win+Ctrl+F4 closes a desktop' ((Desktops).Count -eq $before - 1) "($(Desktops))"
& "$dev\screenshot.ps1" -Out "$out\vd-9-bar-end.png" -H 60 | Out-Null

Get-Content (QsLog).FullName | Select-String 'desktops|Desktops|workspace|ERROR|WARN|TypeError|ReferenceError' |
    ForEach-Object { $_.Line.Substring([Math]::Min(11, $_.Line.Length)) } | Select-Object -Last 30
& "$hostDir\ii-host.exe" --rescue
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
"fails: $script:fails"
