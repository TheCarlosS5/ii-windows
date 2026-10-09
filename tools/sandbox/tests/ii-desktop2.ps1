# Runs only INSIDE Windows Sandbox. Desktop icons, second round: keyboard focus without rising
# over apps, selection (click, Ctrl, rectangle, keyboard), drag to move (saved and restored),
# drop on a folder, in-place rename, Recycle Bin, clipboard copy/paste, new folder from the
# desktop menu, Explorer's native menu and property sheet, sort and overflow.
$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path -LiteralPath 'C:\ii\build\ii')) {
    throw 'This test must run inside the ii Windows Sandbox.'
}
$out = 'C:\xchg\outbox'
$local = Join-Path $env:USERPROFILE 'qs-config'
$dist = Join-Path $env:USERPROFILE 'ii-dist'
Get-Process quickshell, ii-shim -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($window in @((New-Object -ComObject Shell.Application).Windows())) { try { $window.Quit() } catch { } }
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'QML copy failed' }
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Binary copy failed' }
$env:Path = "$dist\bin;$dist;" + $env:Path
$shell = Join-Path $local 'modules\ii\background\Background.qml'
$qml = Get-Content -LiteralPath $shell -Raw
$probe = Get-Content -LiteralPath 'C:\ii\tools\sandbox\tests\desktop2-probe.qml.inc' -Raw
[IO.File]::WriteAllText($shell, $qml.Replace('id: bgRoot', "id: bgRoot`n$probe"), (New-Object Text.UTF8Encoding $false))

# A clean desktop with known files.
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
Get-ChildItem -LiteralPath $desktop -Force | Where-Object { $_.Name -ne 'desktop.ini' } | Remove-Item -Recurse -Force
# Other tests leave files on the shared (Public) desktop too; the sandbox is disposable.
Get-ChildItem -LiteralPath (Join-Path $env:PUBLIC 'Desktop') -Force | Where-Object { $_.Name -ne 'desktop.ini' } | Remove-Item -Recurse -Force
$a = Join-Path $desktop 'Alfa ñ #1.txt'
$b = Join-Path $desktop 'Beta.txt'
$c = Join-Path $desktop 'Gamma.txt'
$folder = Join-Path $desktop 'Carpeta destino'
foreach ($f in $a, $b, $c) { Set-Content -LiteralPath $f -Value "fixture $f" }
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$layout = "$env:LOCALAPPDATA\quickshell\State\user\desktop-layout.json"
Remove-Item -LiteralPath $layout -Force -ErrorAction SilentlyContinue

$state = "$env:LOCALAPPDATA\quickshell\State\user\generated"
New-Item -ItemType Directory -Path $state -Force | Out-Null
# Not a first run: the welcome window would cover the desktop the clicks below are aimed at.
Set-Content -LiteralPath "$env:LOCALAPPDATA\quickshell\State\user\first_run.txt" -Value 'ii-windows test' -Encoding UTF8
Copy-Item -LiteralPath C:\ii\build\seed\colors.json -Destination "$state\colors.json" -Force
$pictures = Join-Path $env:USERPROFILE 'Pictures'
New-Item -ItemType Directory -Path $pictures -Force | Out-Null
Copy-Item -LiteralPath C:\ii\build\seed\wallpaper.jpg -Destination "$pictures\ii-wallpaper.jpg" -Force
$configPath = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
New-Item -ItemType Directory -Path (Split-Path $configPath) -Force | Out-Null
@{ background = @{ wallpaperPath = ("$pictures\ii-wallpaper.jpg" -replace '\\', '/');
    widgets = @{ desktopIcons = @{ enable = $true; iconSize = 48 } } } } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configPath -Encoding UTF8

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class In {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, int x, int y, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public struct RECT { public int Left, Top, Right, Bottom; }
    static readonly ushort[] Extended = { 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0x24, 0x23, 0x5D };
    static void Key(ushort vk, bool up) {
        var a = new IN[1]; a[0].type = 1; a[0].ki.vk = vk; a[0].ki.scan = (ushort)MapVirtualKey(vk, 0);
        a[0].ki.flags = (up ? 2u : 0u) | (Array.IndexOf(Extended, vk) >= 0 ? 1u : 0u);
        SendInput(1, a, Marshal.SizeOf(typeof(IN)));
    }
    // Press `vk` with modifiers (0x11 Ctrl, 0x10 Shift, 0x12 Alt).
    public static void Press(ushort vk, params ushort[] mods) {
        foreach (var m in mods) { Key(m, false); System.Threading.Thread.Sleep(20); }
        Key(vk, false); System.Threading.Thread.Sleep(30); Key(vk, true);
        foreach (var m in mods) { System.Threading.Thread.Sleep(20); Key(m, true); }
        System.Threading.Thread.Sleep(150);
    }
    public static void Type(string text) {
        foreach (var ch in text) {
            var a = new IN[2];
            for (int i = 0; i < 2; i++) { a[i].type = 1; a[i].ki.scan = ch; a[i].ki.flags = 4u | (i == 1 ? 2u : 0u); }
            SendInput(2, a, Marshal.SizeOf(typeof(IN)));
            System.Threading.Thread.Sleep(25);
        }
    }
    static void Abs(int x, int y, uint extra) {
        int w = System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width, h = System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height;
        mouse_event(0x8001u | extra, (int)((x + 0.5) * 65535 / w), (int)((y + 0.5) * 65535 / h), 0, IntPtr.Zero);
    }
    public static void Click(int x, int y, bool right, params ushort[] mods) {
        foreach (var m in mods) Key(m, false);
        SetCursorPos(x, y); Abs(x, y, 0); System.Threading.Thread.Sleep(150);
        mouse_event(right ? 8u : 2u, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        mouse_event(right ? 16u : 4u, 0, 0, 0, IntPtr.Zero);
        foreach (var m in mods) Key(m, true);
        System.Threading.Thread.Sleep(250);
    }
    public static void DoubleClick(int x, int y) {
        SetCursorPos(x, y); Abs(x, y, 0); System.Threading.Thread.Sleep(150);
        for (int i = 0; i < 2; i++) { mouse_event(2u, 0, 0, 0, IntPtr.Zero); mouse_event(4u, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); }
        System.Threading.Thread.Sleep(250);
    }
    public static void Drag(int x1, int y1, int x2, int y2) {
        SetCursorPos(x1, y1); Abs(x1, y1, 0); System.Threading.Thread.Sleep(200);
        mouse_event(2u, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(150);
        for (int i = 1; i <= 25; i++) {
            Abs(x1 + (x2 - x1) * i / 25, y1 + (y2 - y1) * i / 25, 0);
            System.Threading.Thread.Sleep(30);
        }
        System.Threading.Thread.Sleep(300);
        Abs(x2, y2, 0);
        System.Threading.Thread.Sleep(200);
        mouse_event(4u, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(600);
    }
    public static string ClassOf(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static string TitleOf(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
    public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
    // Is `upper` above `lower` in the z-order?
    public static bool Above(IntPtr upper, IntPtr lower) {
        for (var w = GetWindow(lower, 3); w != IntPtr.Zero; w = GetWindow(w, 3)) if (w == upper) return true;
        return false;
    }
    // Visible top-level windows of a process with a class name.
    public static IntPtr[] Windows(uint pid, string cls) {
        var list = new System.Collections.Generic.List<IntPtr>();
        for (var w = GetWindow(GetForegroundWindow(), 0); w != IntPtr.Zero; w = GetWindow(w, 2)) {
            if (IsWindowVisible(w) && Pid(w) == pid && (String.IsNullOrEmpty(cls) || ClassOf(w) == cls)) list.Add(w);
        }
        return list.ToArray();
    }
}
'@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

$script:failures = 0
function Check([bool]$condition, [string]$description) {
    if ($condition) { "PASS $description" } else { "FAIL $description"; $script:failures++ }
}
function Snapshot {
    $psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $local + '" ipc call desktopTest snapshot'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($psi)
    # Read while it runs: a large reply fills the pipe and the child waits for us.
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Desktop IPC timed out' }
    if ($process.ExitCode -ne 0) { throw "Desktop IPC failed: $($errTask.Result)" }
    return ($outTask.Result | ConvertFrom-Json)
}
function Entry($s, [string]$name) { $s.files | Where-Object name -eq $name | Select-Object -First 1 }
# The sandbox follows the host's language: accept ii's Spanish too.
$es = @{ 'New folder' = 'Nueva carpeta'; 'Sort by' = 'Ordenar por'; 'Change wallpaper' = 'Cambiar fondo'; 'Rename' = 'Cambiar nombre';
    'Properties' = 'Propiedades'; 'More options' = 'Más opciones' }
function MenuEntry($s, [string]$text) { $s.menu.entries | Where-Object { ($_.text -eq $text -or $_.text -eq $es[$text]) -and $_.visible } | Select-Object -First 1 }
function Shot([string]$name) { & C:\ii\tools\dev\screenshot.ps1 -Out "$out\$name" | Out-Null }
function StartShell {
    $psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $local + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
    $psi.EnvironmentVariables['PATH'] = $env:Path
    $proc = [Diagnostics.Process]::Start($psi)
    Start-Sleep 14
    return $proc
}
function BackgroundWindow([int]$procId) {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    foreach ($w in [In]::Windows($procId, $null)) {
        $r = New-Object In+RECT
        [void][In]::GetWindowRect($w, [ref]$r)
        if ($r.Left -eq 0 -and $r.Top -eq 0 -and $r.Right -eq $screen.Width -and $r.Bottom -eq $screen.Height -and [In]::TitleOf($w) -match 'background') { return $w }
    }
    foreach ($w in [In]::Windows($procId, $null)) {
        $r = New-Object In+RECT
        [void][In]::GetWindowRect($w, [ref]$r)
        if ($r.Left -eq 0 -and $r.Top -eq 0 -and $r.Right -eq $screen.Width -and $r.Bottom -eq $screen.Height) { return $w }
    }
    return [IntPtr]::Zero
}
$recycle = (New-Object -ComObject Shell.Application).Namespace(10)
function InRecycleBin([string]$name) { @($recycle.Items() | Where-Object { $_.Name -eq $name -or $_.Name -eq [IO.Path]::GetFileNameWithoutExtension($name) }).Count -gt 0 }

$p = StartShell
try {
    Check (-not $p.HasExited) 'shell stays running'
    $s = Snapshot
    $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$out\desktop2-state.json" -Encoding UTF8
    Check $s.present 'desktop icons present'
    if (-not $s.present) { throw 'no desktop icons' }
    "grid: $($s.columns) x $($s.rows)"
    Check ((Entry $s 'Carpeta destino').cell -eq 0) 'folders first, in the first cell'
    Check ((Entry $s 'Alfa ñ #1.txt').cell -eq 1) 'files after, by name'
    Shot 'desktop2-start.png'

    # An app window that overlaps nothing important, to check the z-order.
    Start-Process explorer.exe -ArgumentList "/n,$env:WINDIR"
    Start-Sleep 3
    $app = @((New-Object -ComObject Shell.Application).Windows()) | Select-Object -First 1
    $appHwnd = [IntPtr]$app.HWND
    [void][In]::MoveWindow($appHwnd, 900, 200, 700, 500, $true)
    Start-Sleep 1
    $bg = BackgroundWindow $p.Id
    Check ($bg -ne [IntPtr]::Zero) 'background window found'
    if ($bg -eq [IntPtr]::Zero) {
        foreach ($w in [In]::Windows($p.Id, $null)) {
            $r = New-Object In+RECT; [void][In]::GetWindowRect($w, [ref]$r)
            "  window $([In]::ClassOf($w)) '$([In]::TitleOf($w))' $($r.Left),$($r.Top),$($r.Right),$($r.Bottom)"
        }
        "  screen $([System.Windows.Forms.Screen]::PrimaryScreen.Bounds)"
    }

    # 1. Click: selection, keyboard focus, and the desktop stays under the app.
    $e = Entry $s 'Alfa ñ #1.txt'
    [In]::Click($e.x, $e.y, $false)
    Start-Sleep -Milliseconds 400
    $s = Snapshot
    Check ((Entry $s 'Alfa ñ #1.txt').selected) 'click selects'
    Check ([In]::Pid([In]::GetForegroundWindow()) -eq $p.Id) 'click gives the shell the keyboard'
    Check $s.activeFocus 'desktop has active focus'
    Check ([In]::Above($appHwnd, $bg)) 'activated desktop stays below the app window'
    Shot 'desktop2-focus.png'

    # 2. Keyboard: arrows, Ctrl+A, Escape, type-ahead.
    [In]::Press(0x28)   # Down
    $s = Snapshot
    Check ($s.currentPath -like '*Beta.txt' -and (Entry $s 'Beta.txt').selected -and -not (Entry $s 'Alfa ñ #1.txt').selected) 'Down moves the selection'
    [In]::Press(0x28, 0x10)   # Shift+Down
    $s = Snapshot
    Check ($s.selectionCount -eq 2) 'Shift+Down extends the selection'
    [In]::Press(0x41, 0x11)   # Ctrl+A
    $s = Snapshot
    Check ($s.selectionCount -eq 4) 'Ctrl+A selects everything'
    [In]::Press(0x1B)
    Check ((Snapshot).selectionCount -eq 0) 'Esc clears the selection'
    [In]::Type('gam')
    $s = Snapshot
    Check ($s.currentPath -like '*Gamma.txt' -and (Entry $s 'Gamma.txt').selected) 'typing a name jumps to it'

    # 3. Ctrl+click and the selection rectangle.
    $ea = Entry $s 'Alfa ñ #1.txt'; $eb = Entry $s 'Beta.txt'
    [In]::Click($ea.x, $ea.y, $false)
    [In]::Click($eb.x, $eb.y, $false, 0x11)
    Check ((Snapshot).selectionCount -eq 2) 'Ctrl+click adds to the selection'
    [In]::Click(700, 700, $false)
    Check ((Snapshot).selectionCount -eq 0) 'click on empty desktop clears'
    [In]::Drag(($ea.x + 70), ($ea.y - 30), ($eb.x - 60), ($eb.y + 30))
    $s = Snapshot
    Check ($s.selectionCount -eq 2 -and (Entry $s 'Alfa ñ #1.txt').selected -and (Entry $s 'Beta.txt').selected) 'selection rectangle selects the icons it touches'
    Shot 'desktop2-band.png'

    # 4. Drag an icon to another cell; saved and restored after a restart.
    $eg = Entry $s 'Gamma.txt'
    [In]::Click($eg.x, $eg.y, $false)
    $targetX = $eg.x + 4 * 92; $targetY = $eg.y + 2 * 100
    [In]::Drag($eg.x, $eg.y, $targetX, $targetY)
    Start-Sleep 1
    $s = Snapshot
    $moved = Entry $s 'Gamma.txt'
    "Gamma cell $($eg.cell) -> $($moved.cell) at $($moved.x),$($moved.y)"
    Check ($moved.cell -ne $eg.cell -and [math]::Abs($moved.x - $targetX) -lt 50 -and [math]::Abs($moved.y - $targetY) -lt 50) 'drag moves the icon to the drop cell'
    Check (Test-Path -LiteralPath $layout) 'layout saved'
    Check ((Entry $s 'Alfa ñ #1.txt').cell -eq 1) 'other icons keep their place'
    Shot 'desktop2-dragged.png'

    # 5. Drop on a folder moves the file into it.
    $eb = Entry $s 'Beta.txt'; $ef = Entry $s 'Carpeta destino'
    [In]::Click($eb.x, $eb.y, $false)
    [In]::Drag($eb.x, $eb.y, $ef.x, $ef.y)
    Start-Sleep 2
    Check ((Test-Path -LiteralPath (Join-Path $folder 'Beta.txt')) -and -not (Test-Path -LiteralPath $b)) 'drop on a folder moves the file into it'

    # 6. F2 rename in place.
    $s = Snapshot
    $ea = Entry $s 'Alfa ñ #1.txt'
    [In]::Click($ea.x, $ea.y, $false)
    [In]::Press(0x71)   # F2
    $s = Snapshot
    Check ($s.renamingPath -like '*Alfa*') 'F2 starts renaming'
    Shot 'desktop2-rename.png'
    [In]::Type('Renombrado ñ')
    [In]::Press(0x0D)
    Start-Sleep 2
    $renamed = Join-Path $desktop 'Renombrado ñ.txt'
    Check ((Test-Path -LiteralPath $renamed) -and -not (Test-Path -LiteralPath $a)) 'rename keeps the extension'
    $s = Snapshot
    Check ((Entry $s 'Renombrado ñ.txt').cell -eq $ea.cell) 'renamed icon keeps its cell'

    # 7. Ctrl+C / Ctrl+V on the desktop makes a copy; Delete sends it to the Recycle Bin.
    $er = Entry $s 'Renombrado ñ.txt'
    [In]::Click($er.x, $er.y, $false)
    [In]::Press(0x43, 0x11)
    Start-Sleep 1
    $drop = [System.Windows.Forms.Clipboard]::GetFileDropList()
    Check ($drop.Count -eq 1 -and $drop[0] -eq $renamed) 'Ctrl+C puts the file on the clipboard'
    [In]::Press(0x56, 0x11)
    Start-Sleep 3
    $copies = @(Get-ChildItem -LiteralPath $desktop -Filter 'Renombrado*' | Where-Object Name -ne 'Renombrado ñ.txt')
    Check ($copies.Count -eq 1) "Ctrl+V pastes a copy ($($copies.Name))"
    if ($copies.Count -ge 1) {
        $s = Snapshot
        $ec = Entry $s $copies[0].Name
        [In]::Click($ec.x, $ec.y, $false)
        [In]::Press(0x2E)   # Delete
        Start-Sleep 3
        Check (-not (Test-Path -LiteralPath $copies[0].FullName)) 'Delete removes the file'
        Check (InRecycleBin $copies[0].Name) 'deleted file is in the Recycle Bin'
    }

    # 8. Desktop menu: New folder, renamed in place.
    [In]::Click(700, 700, $true)
    Start-Sleep -Milliseconds 500
    $s = Snapshot
    $nf = MenuEntry $s 'New folder'
    Check ($s.menu.shown -and $null -ne $nf) 'desktop menu offers New folder'
    Check ($null -ne (MenuEntry $s 'Sort by') -and $null -ne (MenuEntry $s 'Change wallpaper')) 'desktop menu keeps its own entries'
    Shot 'desktop2-menu.png'
    if ($nf) {
        [In]::Click($nf.x, $nf.y, $false)
        Start-Sleep 2
        $s = Snapshot
        Check ($s.renamingPath -like '*New folder*' -or $s.renamingPath -like '*Nueva carpeta*') "new folder is created and being renamed ($($s.renamingPath))"
        [In]::Type('Mi carpeta')
        [In]::Press(0x0D)
        Start-Sleep 2
        Check (Test-Path -LiteralPath (Join-Path $desktop 'Mi carpeta')) 'new folder renamed'
        $nfEntry = Entry (Snapshot) 'Mi carpeta'
        "new folder at $($nfEntry.x),$($nfEntry.y)"
        # y=700 is under the last row on the sandbox's screen: the nearest cell is in the last row.
        Check ($null -ne $nfEntry -and [math]::Abs($nfEntry.x - 700) -lt 100 -and [math]::Abs($nfEntry.y - [math]::Min(700, 52 + ($s.rows - 1) * 100 + 24)) -lt 100) 'new folder appears where the menu was opened'
    }

    # 9. Item menu → More options: Explorer's own menu, from ii-shim.
    $s = Snapshot
    $er = Entry $s 'Renombrado ñ.txt'
    [In]::Click($er.x, $er.y, $true)
    Start-Sleep -Milliseconds 500
    $s = Snapshot
    $more = MenuEntry $s 'More options'
    Check ($null -ne (MenuEntry $s 'Rename') -and $null -ne (MenuEntry $s 'Properties')) 'item menu has Rename and Properties'
    Shot 'desktop2-itemmenu.png'
    if ($more) {
        [In]::Click($more.x, $more.y, $false)
        Start-Sleep 3
        $shim = Get-Process ii-shim -ErrorAction SilentlyContinue | Select-Object -First 1
        $popup = if ($shim) { [In]::Windows([uint32]$shim.Id, '#32768') } else { @() }
        Check ($popup.Count -ge 1) 'Explorer context menu is shown'
        Shot 'desktop2-nativemenu.png'
        [In]::Press(0x1B); [In]::Press(0x1B)
        Start-Sleep 2
        Check (-not (Get-Process ii-shim -ErrorAction SilentlyContinue)) 'dismissed menu ends ii-shim'
    }

    # 10. Alt+Enter: Windows' property sheet.
    $s = Snapshot
    $er = Entry $s 'Renombrado ñ.txt'
    [In]::Click($er.x, $er.y, $false)
    [In]::Press(0x0D, 0x12)
    Start-Sleep 4
    $shim = Get-Process ii-shim -ErrorAction SilentlyContinue | Select-Object -First 1
    $sheet = if ($shim) { @([In]::Windows([uint32]$shim.Id, '#32770')) } else { @() }
    Check ($sheet.Count -ge 1) "Alt+Enter opens the property sheet ($(if ($sheet.Count) { [In]::TitleOf($sheet[0]) }))"
    Shot 'desktop2-properties.png'
    foreach ($w in $sheet) { [void][In]::PostMessage($w, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) }
    Start-Sleep 4
    Check (-not (Get-Process ii-shim -ErrorAction SilentlyContinue)) 'closing the sheet ends ii-shim'

    # 11. Restart: positions survive.
    $before = Entry (Snapshot) 'Gamma.txt'
    Stop-Process -Id $p.Id -Force
    Start-Sleep 1
    $p = StartShell
    $after = Entry (Snapshot) 'Gamma.txt'
    Check ($after.cell -eq $before.cell) "dragged position restored after restart ($($before.cell) -> $($after.cell))"

    # 12. Sort by name resets the arrangement.
    [In]::Click(700, 700, $true)
    Start-Sleep -Milliseconds 500
    $s = Snapshot
    $nameChoice = $s.menu.choices | Where-Object { $_.text -eq 'Name' -or $_.text -eq 'Nombre' } | Select-Object -First 1
    if ($nameChoice) {
        [In]::Click($nameChoice.x, $nameChoice.y, $false)
        Start-Sleep 1
    }
    Shot 'desktop2-sorted.png'
    $s = Snapshot
    Check ($s.sortMode -eq 'name' -and (Entry $s 'Gamma.txt').cell -lt 5) 'Sort by name rearranges the icons'

    # 13. Many files: the last cell shows the rest.
    $many = Join-Path $desktop 'many'
    $total = $s.rows * $s.columns + 5
    1..$total | ForEach-Object { Set-Content -LiteralPath (Join-Path $desktop ("z{0:D3}.txt" -f $_)) -Value 'x' }
    Start-Sleep 5
    $s = Snapshot
    Check ($s.overflowCount -gt 0) "overflow tile counts the rest ($($s.overflowCount))"
    Shot 'desktop2-overflow.png'
    Get-ChildItem -LiteralPath $desktop -Filter 'z*.txt' | Remove-Item -Force
    Start-Sleep 3
    Check ((Snapshot).overflowCount -eq 0) 'overflow clears'
    $app.Quit()
} catch {
    $script:failures++
    "FAIL $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Get-Process ii-shim -ErrorAction SilentlyContinue | Stop-Process -Force
    $log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) {
        Copy-Item -LiteralPath $log.FullName -Destination "$out\desktop2.log" -Force
        Get-Content -LiteralPath $log.FullName | Where-Object { $_ -match 'DesktopIcons|DesktopMenu|desktopTest|ERROR|Failed to load|TypeError|ReferenceError' } | Select-Object -Last 20
    }
}
"desktop2 failures=$script:failures"
if ($script:failures -gt 0) { exit 1 }
