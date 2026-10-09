# INSIDE the sandbox: audit 2026-10-09 P0 fixes, with ii-host's keyboard hook live.
#   Alt+F4 / Win+Q on the desktop keep the wallpaper; the bar's wheel never creates desktops;
#   Win+number switches desktops (creating one at most); Win+S / Win+T don't show Windows' UI;
#   Win+Q closes the app in front; automatic battery suspend is off by default; no QML errors in
#   the files changed; a sharp Japanese clock at 150 % (screenshot).
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
$cfgDir = "$env:LOCALAPPDATA\quickshell\illogical-impulse"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
# Only what this test needs; ii fills in the defaults.
@'
{ "background": { "widgets": { "japaneseClock": { "enable": true, "vertical": false, "widgetScale": 1.5, "x": 120, "y": 260 } } } }
'@ | Set-Content "$cfgDir\config.json" -Encoding UTF8
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class P0 {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    public static string ForegroundClass() { var s = new StringBuilder(200); GetClassNameW(GetForegroundWindow(), s, 200); return s.ToString(); }
    public static uint ForegroundPid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
    static readonly ushort[] Ext = { 0x25, 0x26, 0x27, 0x28, 0x2E, 0x5B };
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
    // Visible windows of a process covering the whole primary screen (ii's wallpaper, and
    // full-screen panels such as the session menu).
    public static int FullScreenWindows(uint pid) {
        int n = 0, w = GetSystemMetrics(0), h = GetSystemMetrics(1);
        EnumWindows((hw, l) => {
            uint p; GetWindowThreadProcessId(hw, out p);
            RECT r;
            if (p == pid && IsWindowVisible(hw) && GetWindowRect(hw, out r) && r.L <= 0 && r.T <= 0 && r.R >= w && r.B >= h) n++;
            return true;
        }, IntPtr.Zero);
        return n;
    }
    public static int VisibleOfClass(string cls) {
        int n = 0;
        EnumWindows((hw, l) => { var s = new StringBuilder(200); GetClassNameW(hw, s, 200); if (IsWindowVisible(hw) && s.ToString() == cls) n++; return true; }, IntPtr.Zero);
        return n;
    }
    public static IntPtr FirstOfClass(string cls) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hw, l) => { var s = new StringBuilder(200); GetClassNameW(hw, s, 200); if (IsWindowVisible(hw) && s.ToString() == cls) { found = hw; return false; } return true; }, IntPtr.Zero);
        return found;
    }
    public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
    // Handles of the process's visible windows.
    public static long[] WindowsOf(uint pid) {
        var list = new System.Collections.Generic.List<long>();
        EnumWindows((hw, l) => { uint p; GetWindowThreadProcessId(hw, out p); if (p == pid && IsWindowVisible(hw)) list.Add(hw.ToInt64()); return true; }, IntPtr.Zero);
        return list.ToArray();
    }
    public static int ScreenW() { return GetSystemMetrics(0); }
    public static int ScreenH() { return GetSystemMetrics(1); }
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
# The shell's own log and process (the first run also opens the welcome screen, another quickshell).
function QsLog {
    Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime |
        Where-Object { (Get-Content $_.FullName -TotalCount 1) -match 'shell\.qml' } | Select-Object -Last 1
}
function ShellPid {
    $p = Get-CimInstance Win32_Process -Filter "Name='quickshell.exe'" | Where-Object { $_.CommandLine -notmatch 'welcome' } | Select-Object -First 1
    if ($p) { [uint32]$p.ProcessId } else { [uint32]0 }
}
function CloseWelcome {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'welcome\.qml' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Settle { Start-Sleep 2; Check 'no key left held down' (-not [P0]::AnyModifierDown()) }

$start = Get-Date
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
for ($i = 0; $i -lt 90 -and [P0]::FullScreenWindows((ShellPid)) -lt 1; $i++) { Start-Sleep 1 }
"wallpaper after $([int]((Get-Date) - $start).TotalSeconds) s"
Start-Sleep 8
CloseWelcome; Start-Sleep 1
& "$dev\screenshot.ps1" -Out "$out\p0-1-desktop.png" | Out-Null

# --- 1. The bar's wheel (r+1 / r-1) only moves through desktops that exist.
"desktops at start: $(Desktops)"
foreach ($i in 1..5) { & "$dev\send-shortcut.ps1" -Name 'hl:workspace r+1' -PressOnly | Out-Null; Start-Sleep -Milliseconds 400 }
Start-Sleep 2
Check 'wheel down x5 on one desktop creates none' ((Desktops).Count -eq 1) "($(Desktops))"

# --- 2. Win+number.
[P0]::Chord(0x5B, 0x32); Start-Sleep 3
$d = Desktops; Check 'Win+2 creates desktop 2 and goes there' ($d.Count -eq 2 -and $d.Current -eq 2) "($d)"
[P0]::Chord(0x5B, 0x35); Start-Sleep 3
$d = Desktops; Check 'Win+5 creates only one more' ($d.Count -eq 3 -and $d.Current -eq 3) "($d)"
foreach ($i in 1..4) { & "$dev\send-shortcut.ps1" -Name 'hl:workspace r+1' -PressOnly | Out-Null; Start-Sleep -Milliseconds 400 }
Start-Sleep 2
Check 'wheel past the last desktop creates none' ((Desktops).Count -eq 3) "($(Desktops))"
& "$dev\send-shortcut.ps1" -Name 'hl:workspace r-1' -PressOnly | Out-Null; Start-Sleep 3
Check 'wheel up goes back one' ((Desktops).Current -eq 2) "($(Desktops))"
[P0]::Chord(0x5B, 0x31); Start-Sleep 3
Check 'Win+1 goes to desktop 1' ((Desktops).Current -eq 1) "($(Desktops))"
[P0]::Chord(0x5B, 0x10, 0x33); Start-Sleep 2
Check 'Win+Shift+3 does nothing (no taskbar app)' ((Desktops).Current -eq 1) "(fg=$([P0]::ForegroundClass()))"
Settle
Check 'Start did not open' ([P0]::ForegroundClass() -notmatch 'Windows.UI.Core.CoreWindow') "(fg=$([P0]::ForegroundClass()))"

# --- 3. Win+S is ii's search, Win+T doesn't focus the hidden taskbar.
[P0]::Chord(0x5B, 0x53); Start-Sleep 2
$fg = [P0]::ForegroundClass()
Check 'Win+S does not open Windows search' ($fg -notmatch 'Windows.UI.Core.CoreWindow') "(fg=$fg, pid=$([P0]::ForegroundPid()) shell=$(ShellPid))"
& "$dev\screenshot.ps1" -Out "$out\p0-2-win-s.png" | Out-Null
[P0]::Chord(0x1B); Start-Sleep 1
[P0]::Chord(0x5B, 0x54); Start-Sleep 2
Check 'Win+T does not focus the taskbar' ([P0]::ForegroundClass() -ne 'Shell_TrayWnd') "(fg=$([P0]::ForegroundClass()))"
Settle

# --- 4. Win+Q closes the app in front.
Start-Process explorer.exe C:\; Start-Sleep 4
# Windows opened from a background script land behind: bring it to the front like a click would.
$cab = [P0]::FirstOfClass('CabinetWClass')
$r = [P0]::Rect($cab)
& "$dev\click.ps1" -X ([int](($r.L + $r.R) / 2)) -Y ($r.T + 12); Start-Sleep 1
$before = [P0]::VisibleOfClass('CabinetWClass')
"explorer windows: $before, fg=$([P0]::ForegroundClass())"
[P0]::Chord(0x5B, 0x51); Start-Sleep 3
Check 'Win+Q closes the Explorer window in front' ([P0]::VisibleOfClass('CabinetWClass') -eq $before - 1) "($([P0]::VisibleOfClass('CabinetWClass')) left)"
Settle

# --- 5. Alt+F4 and Win+Q on ii's desktop keep the wallpaper.
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }; Start-Sleep 2
$x = [int]([P0]::ScreenW() * 0.55); $y = [int]([P0]::ScreenH() * 0.45)
& "$dev\click.ps1" -X $x -Y $y; Start-Sleep 1
"desktop click: fg=$([P0]::ForegroundClass()) pid=$([P0]::ForegroundPid()) shell=$(ShellPid)"
[P0]::Chord(0x12, 0x73); Start-Sleep 3
$n = [P0]::FullScreenWindows((ShellPid))
& "$dev\screenshot.ps1" -Out "$out\p0-3-altf4.png" | Out-Null
Check 'Alt+F4 on the desktop keeps the wallpaper (and opens the session menu)' ($n -ge 2) "($n full-screen ii windows)"
[P0]::Chord(0x1B); Start-Sleep 2
Check 'Esc closes the session menu, wallpaper still there' ([P0]::FullScreenWindows((ShellPid)) -ge 1) "($([P0]::FullScreenWindows((ShellPid))))"
& "$dev\click.ps1" -X $x -Y $y; Start-Sleep 1
[P0]::Chord(0x5B, 0x51); Start-Sleep 2
Check 'Win+Q on the desktop keeps the wallpaper' ([P0]::FullScreenWindows((ShellPid)) -ge 1)
Settle
& "$dev\screenshot.ps1" -Out "$out\p0-4-end.png" | Out-Null

# --- 6. The bar's resources popup: one window, reused on the next hover.
function ShellWindows { [P0]::WindowsOf((ShellPid)) }
Add-Type -Namespace P0M -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);' -ErrorAction SilentlyContinue
[P0M.M]::SetCursorPos(700, 450) | Out-Null; Start-Sleep 1
$base = ShellWindows
[P0M.M]::SetCursorPos(405, 20) | Out-Null; Start-Sleep 2
$first = ShellWindows | Where-Object { $base -notcontains $_ }
& "$dev\screenshot.ps1" -Out "$out\p0-5-popup.png" -H 300 | Out-Null
[P0M.M]::SetCursorPos(700, 450) | Out-Null; Start-Sleep 2
$hiddenAgain = -not ((ShellWindows) | Where-Object { $first -contains $_ })
[P0M.M]::SetCursorPos(405, 20) | Out-Null; Start-Sleep 2
$second = ShellWindows | Where-Object { $base -notcontains $_ }
Check 'hovering the bar shows a popup window' (@($first).Count -ge 1) "($(@($first).Count) new)"
Check 'it hides when the pointer leaves' $hiddenAgain
Check 'the next hover reuses the same window' (@($first).Count -ge 1 -and -not (Compare-Object @($first) @($second))) "($first / $second)"
[P0M.M]::SetCursorPos(700, 450) | Out-Null; Start-Sleep 1

# --- 7. Config default and QML errors in the files touched.
$cfg = Get-Content "$cfgDir\config.json" -Raw | ConvertFrom-Json
# config.json only holds what changed: the defaults are in ii's Config.qml.
$defaults = Get-Content "$local\modules\common\Config.qml" -Raw
Check 'automatic battery suspend off by default' ($defaults -match 'property bool automaticSuspend: false')
Check 'gelbooru key fields exist' ($defaults -match 'property JsonObject gelbooru')
Check 'Japanese clock kept its size' ($cfg.background.widgets.japaneseClock.widgetScale -eq 1.5)
$log = (QsLog).FullName
$bad = Get-Content $log | Select-String 'DesktopCover|Booru|StyledPopup|PopupToolTip|JapaneseClock|AbstractBackgroundWidget|Battery|MediaWidget' |
    Select-String 'TypeError|ReferenceError|SyntaxError|Cannot|Unable|is not'
Check 'no QML errors in the changed files' (-not $bad) "($(@($bad).Count))"
$bad | Select-Object -First 10 | ForEach-Object { "  $($_.Line)" }
Get-Content $log | Select-String 'ERROR|TypeError|ReferenceError|Close request|Already on the last' | Select-Object -Last 20 | ForEach-Object { "log: $($_.Line)" }

& "$hostDir\ii-host.exe" --rescue
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
"fails: $script:fails"
