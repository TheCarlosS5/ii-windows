# Milestone 2 check, runs INSIDE the sandbox. Exercises ii-host end to end and prints PASS/FAIL lines.
$ErrorActionPreference = 'Continue'
$host_exe = 'C:\ii\host\build\ii-host.exe'
$out = 'C:\xchg\outbox'
$state = "$env:LOCALAPPDATA\ii-windows\state.ini"
Remove-Item "$env:LOCALAPPDATA\ii-windows" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$out\sink.log" -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class T {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public IntPtr lParam; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; [FieldOffset(8)] long pad1; [FieldOffset(16)] long pad2; [FieldOffset(24)] long pad3; [FieldOffset(32)] long pad4; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint b, out RECT r, uint c);
    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint m, ref APPBARDATA d);
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);

    public static string WorkArea() { RECT r; SystemParametersInfoW(0x30, 0, out r, 0); return r.L + "," + r.T + "->" + r.R + "," + r.B; }
    public static int AppBarState() { var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); return (int)SHAppBarMessage(4, ref d).ToUInt32(); }
    public static bool TaskbarVisible() { var h = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Shell_TrayWnd", null); return h != IntPtr.Zero && IsWindowVisible(h); }
    public static bool IconsVisible() {
        var views = new List<IntPtr>();
        var pm = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Progman", null);
        if (pm != IntPtr.Zero) views.Add(FindWindowEx(pm, IntPtr.Zero, "SHELLDLL_DefView", null));
        IntPtr w = IntPtr.Zero;
        while ((w = FindWindowEx(IntPtr.Zero, w, "WorkerW", null)) != IntPtr.Zero) views.Add(FindWindowEx(w, IntPtr.Zero, "SHELLDLL_DefView", null));
        foreach (var v in views) { if (v == IntPtr.Zero) continue; var l = FindWindowEx(v, IntPtr.Zero, "SysListView32", null); if (l != IntPtr.Zero) return IsWindowVisible(l); }
        return false;
    }
    public static void Keys(params int[] seq) {
        // positive = key down, negative = key up
        var list = new List<INPUT>();
        foreach (var k in seq) {
            var vk = (ushort)Math.Abs(k);
            uint flags = (k < 0 ? 2u : 0u) | ((vk == 0x5B || vk == 0x5C || vk == 0x23) ? 1u : 0u);
            list.Add(new INPUT { type = 1, ki = new KEYBDINPUT { vk = vk, flags = flags } });
        }
        SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT)));
    }
    // Any visible, uncloaked, non-empty top-level window owned by the named process?
    public static bool ProcessHasShownWindow(string processName) {
        var pids = new HashSet<uint>();
        foreach (var p in Process.GetProcessesByName(processName)) pids.Add((uint)p.Id);
        bool found = false;
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (!pids.Contains(pid) || !IsWindowVisible(h)) return true;
            int cloaked; DwmGetWindowAttribute(h, 14, out cloaked, 4);
            RECT r; GetWindowRect(h, out r);
            if (cloaked == 0 && r.R - r.L > 50 && r.B - r.T > 50) { found = true; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    static System.Drawing.Bitmap reference;
    static System.Drawing.Bitmap GrabCentre() {
        var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
        var rect = new System.Drawing.Rectangle(b.Width / 4, b.Height / 8, b.Width / 2, b.Height * 3 / 4);
        var bmp = new System.Drawing.Bitmap(rect.Width, rect.Height);
        using (var g = System.Drawing.Graphics.FromImage(bmp)) g.CopyFromScreen(rect.X, rect.Y, 0, 0, rect.Size);
        return bmp;
    }
    public static void MarkReference() { reference = GrabCentre(); }
    // Fraction of sampled pixels in the screen centre that changed since MarkReference().
    public static double ChangedSinceReference() {
        var now = GrabCentre(); int changed = 0, total = 0;
        for (int y = 0; y < now.Height; y += 7) for (int x = 0; x < now.Width; x += 7) {
            var a = reference.GetPixel(x, y); var c = now.GetPixel(x, y); total++;
            if (Math.Abs(a.R - c.R) + Math.Abs(a.G - c.G) + Math.Abs(a.B - c.B) > 60) changed++;
        }
        return (double)changed / total;
    }
    public static IntPtr Find(string cls) { return FindWindowEx(IntPtr.Zero, IntPtr.Zero, cls, null); }
    // Start and Search are XAML CoreWindows owned by StartMenuExperienceHost / SearchHost.
    public static bool StartOrSearchOpen() { return ProcessHasShownWindow("StartMenuExperienceHost") || ProcessHasShownWindow("SearchHost"); }
    public static string Foreground() { var h = GetForegroundWindow(); var c = new System.Text.StringBuilder(128); var t = new System.Text.StringBuilder(128); GetClassName(h, c, 128); GetWindowText(h, t, 128); return c + " '" + t + "'"; }
}
'@

$results = @()
function Check($name, $ok, $detail) {
    $line = "{0}  {1}  ({2})" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $detail
    $script:results += $line
    Write-Output $line
}
function Snapshot($label) { "[$label] workarea=$([T]::WorkArea()) abstate=$([T]::AppBarState()) taskbar=$([T]::TaskbarVisible()) icons=$([T]::IconsVisible())" }
function Shot($name) { & C:\ii\tools\dev\screenshot.ps1 -Out "$out\$name.png" | Out-Null }

$baseline = @{ wa = [T]::WorkArea(); ab = [T]::AppBarState() }
Snapshot 'baseline'
Shot 'm2-0-baseline'

# --- 0. negative control: without ii-host a lone Win press must open Start ---------------
[T]::MarkReference()
[T]::Keys(0x5B, -0x5B)
Start-Sleep 2
$changed = [T]::ChangedSinceReference()
$opened = $changed -gt 0.2
Shot 'm2-0b-start-control'
Check 'control: without host, Win opens Start (detector works)' $opened ("{0:P0} of the screen centre changed" -f $changed)
[T]::Keys(0x1B, -0x1B)
Start-Sleep 1.5
$changed = [T]::ChangedSinceReference()
Check 'control: Start closed again before the real tests' ($changed -lt 0.05) ("{0:P0} changed" -f $changed)

# --- 1. hide taskbar + icons ------------------------------------------------------------
$sink = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\fake-sink.ps1' -PassThru -WindowStyle Hidden
Start-Sleep 3
$hostProc = Start-Process $host_exe -PassThru
Start-Sleep 3
Snapshot 'host running'
Shot 'm2-1-hidden'
Check 'taskbar hidden' (-not [T]::TaskbarVisible()) ''
Check 'icons hidden' (-not [T]::IconsVisible()) ''
$wa = [T]::WorkArea()
Check 'work area covers screen bottom' ($wa -ne $baseline.wa) "before $($baseline.wa) now $wa"
Check 'guard running' ((Get-Process ii-host -ErrorAction SilentlyContinue).Count -eq 2) "$((Get-Process ii-host).Count) ii-host processes"

# --- 2. Win key alone -> shell search, no Start menu -------------------------------------
[T]::MarkReference()
[T]::Keys(0x5B, -0x5B)
Start-Sleep 2
$changed = [T]::ChangedSinceReference()
$startOpen = $changed -gt 0.2
Shot 'm2-1b-after-lone-win'
$sinkLog = Get-Content "$out\sink.log" -ErrorAction SilentlyContinue
Check 'lone Win: Start stays closed' (-not $startOpen) ("{0:P0} of the screen centre changed" -f $changed)
Check 'lone Win: shell got searchToggleRelease press+release' (($sinkLog -match 'pressed searchToggleRelease').Count -ge 1 -and ($sinkLog -match 'released searchToggleRelease').Count -ge 1) ($sinkLog -join ' | ')
Check 'lone Win: no interrupt' (($sinkLog -match 'searchToggleReleaseInterrupt').Count -eq 0) ''
Check 'taskbar still hidden after Win' (-not [T]::TaskbarVisible()) ''

# --- 3. Win+N -> sidebarRightToggle, no notification center ------------------------------
Remove-Item "$out\sink.log" -ErrorAction SilentlyContinue
[T]::MarkReference()
[T]::Keys(0x5B, 0x4E, -0x4E, -0x5B)
Start-Sleep 2
$changed = [T]::ChangedSinceReference()
$sinkLog = Get-Content "$out\sink.log" -ErrorAction SilentlyContinue
Check 'Win+N: shell got sidebarRightToggle' (($sinkLog -match 'pressed sidebarRightToggle').Count -eq 1) ($sinkLog -join ' | ')
Check 'Win+N: interrupt sent (search must not toggle)' (($sinkLog -match 'searchToggleReleaseInterrupt').Count -ge 1) ''
Check 'Win+N: nothing of Windows opened (Start / notifications)' ($changed -lt 0.05) ("{0:P0} changed" -f $changed)

# --- 4. Win+R (not mapped) -> Windows Run dialog still works ------------------------------
[T]::Keys(0x5B, 0x52, -0x52, -0x5B)
Start-Sleep 2
$run = [T]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32770', $null)
$fg = [T]::Foreground()
Check 'Win+R passes through to Windows' ($fg -match '#32770') "fg=$fg"
Shot 'm2-2-winr'
if ($fg -match '#32770') { [T]::Keys(0x1B, -0x1B); Start-Sleep 0.5 }

# --- 5. Explorer restart -> taskbar re-hidden --------------------------------------------
Get-Process explorer | Stop-Process -Force
Start-Sleep 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
# Explorer takes a few seconds to rebuild; require the hidden state to hold for 5 s in a row.
$hiddenAgain = $false; $stable = 0
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep 1
    $tray = [T]::Find('Shell_TrayWnd')
    $pm = [T]::Find('Progman')
    if ($tray -ne [IntPtr]::Zero -and $pm -ne [IntPtr]::Zero -and -not [T]::TaskbarVisible() -and -not [T]::IconsVisible()) { $stable++ } else { $stable = 0 }
    if ($stable -ge 5) { $hiddenAgain = $true; break }
}
Snapshot 'after explorer restart'
Check 'explorer restart: taskbar + icons hidden again' $hiddenAgain "after ${i}s"
Shot 'm2-3-after-explorer'

# --- 6. host killed -> guard restores ----------------------------------------------------
Stop-Process -Id $hostProc.Id -Force
Start-Sleep 3
Snapshot 'host killed'
Check 'guard: taskbar restored after host crash' ([T]::TaskbarVisible()) ''
Check 'guard: icons restored after host crash' ([T]::IconsVisible()) ''
Check 'guard: auto-hide state restored' ([T]::AppBarState() -eq $baseline.ab) "now $([T]::AppBarState()) baseline $($baseline.ab)"
Check 'guard exited' ((Get-Process ii-host -ErrorAction SilentlyContinue).Count -eq 0) ''

# --- 7. panic hotkey ---------------------------------------------------------------------
$hostProc = Start-Process $host_exe -PassThru
Start-Sleep 3
Check 'host re-hid taskbar' (-not [T]::TaskbarVisible()) ''
[T]::Keys(0x11, 0x12, 0x10, 0x52, -0x52, -0x10, -0x12, -0x11)   # Ctrl+Alt+Shift+R
Start-Sleep 3
Snapshot 'after panic'
Check 'panic: host exited' ($hostProc.HasExited) "exit=$($hostProc.ExitCode)"
Check 'panic: taskbar restored' ([T]::TaskbarVisible()) ''
Check 'panic: icons restored' ([T]::IconsVisible()) ''
Check 'panic: auto-hide restored' ([T]::AppBarState() -eq $baseline.ab) ''
Check 'panic: work area restored' ([T]::WorkArea() -eq $baseline.wa) "$([T]::WorkArea())"
$sinkLog = Get-Content "$out\sink.log" -ErrorAction SilentlyContinue

# --- 8. rescue script while host runs ----------------------------------------------------
$hostProc = Start-Process $host_exe -PassThru
Start-Sleep 3
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
Start-Sleep 2
Snapshot 'after rescue.ps1'
Check 'rescue.ps1: host stopped' ((Get-Process ii-host -ErrorAction SilentlyContinue).Count -eq 0) ''
Check 'rescue.ps1: taskbar + icons back' ([T]::TaskbarVisible() -and [T]::IconsVisible()) ''
Check 'rescue.ps1: auto-hide restored' ([T]::AppBarState() -eq $baseline.ab) ''
Shot 'm2-4-final'

Stop-Process -Id $sink.Id -Force -ErrorAction SilentlyContinue
"---- host.log"
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" -Tail 40
"---- summary"
$results
