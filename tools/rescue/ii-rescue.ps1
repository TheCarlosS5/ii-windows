# ii-windows rescue: puts the normal Windows desktop back, no matter what state ii left it in.
# Works on its own (does not need ii-host.exe or quickshell).
# Note: window titles are passed as [NullString]::Value; PowerShell turns $null into "" for
# string parameters, and "" only matches windows with an empty title.
#
#   ii-rescue.ps1                    stop ii, show taskbar + desktop icons, restore taskbar auto-hide
#   ii-rescue.ps1 -RestartExplorer   same, then restart Explorer (also clears leftover reserved space)
#
# If even the keyboard shortcut is gone: Ctrl+Shift+Esc (Task Manager) > Run new task >
#   powershell -ExecutionPolicy Bypass -File "<path>\ii-rescue.ps1" -RestartExplorer
param([switch]$RestartExplorer)

$ErrorActionPreference = 'Continue'
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$stateFile = Join-Path $dataDir 'state.ini'
$logFile = Join-Path $dataDir 'host.log'
New-Item -ItemType Directory -Force $dataDir | Out-Null
function Log($m) { $line = "{0:yyyy-MM-dd HH:mm:ss.fff} [rescue.ps1] {1}" -f (Get-Date), $m; Add-Content $logFile $line; Write-Output $m }

Add-Type -Namespace IiRescue -Name Win -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindowEx(System.IntPtr parent, System.IntPtr after, string cls, string title);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public System.IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public System.IntPtr lParam; }
[DllImport("shell32.dll")] public static extern System.UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr SendMessageTimeout(System.IntPtr h, uint msg, System.UIntPtr w, string l, uint flags, uint timeout, out System.UIntPtr result);
'@

function Find-All($cls) {
    $list = @(); $h = [IntPtr]::Zero
    while (($h = [IiRescue.Win]::FindWindowEx([IntPtr]::Zero, $h, $cls, [NullString]::Value)) -ne [IntPtr]::Zero) { $list += $h }
    $list
}

function Read-State($key, $default) {
    if (-not (Test-Path $stateFile)) { return $default }
    $m = Select-String -Path $stateFile -Pattern "^$key=(-?\d+)" | Select-Object -First 1
    if ($m) { [int]$m.Matches[0].Groups[1].Value } else { $default }
}

function Write-State($key, $value) {
    if (-not (Test-Path $stateFile)) { "[restore]" | Set-Content $stateFile }
    $content = Get-Content $stateFile
    if ($content -match "^$key=") { $content = $content -replace "^$key=.*", "$key=$value" } else { $content += "$key=$value" }
    $content | Set-Content $stateFile
}

Log 'rescue started'

# 1. stop ii (host first, so it cannot re-hide anything)
foreach ($name in 'ii-host', 'quickshell') {
    Get-Process $name -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_ -Force; Log "stopped $name ($($_.Id))" }
}

# 2. taskbars visible
# Gamma originals must survive even when the host binary is missing. Same journal/mutex as
# ii-host; use monitor interface IDs so a display-number reassignment cannot tint another screen.
$gammaFile = Join-Path $dataDir 'gamma.bin'
if (Test-Path -LiteralPath $gammaFile) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
namespace IiRescue {
    public static class GammaRecovery {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct DISPLAY_DEVICE {
            public uint cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string description;
            public uint flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string key;
        }
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE data, uint flags);
        [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateDC(string driver, string device, string output, IntPtr init);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern bool SetDeviceGammaRamp(IntPtr dc, [In] ushort[] ramp);
        [DllImport("gdi32.dll")] static extern bool GetDeviceGammaRamp(IntPtr dc, [Out] ushort[] ramp);
        static Dictionary<string,string> Displays() {
            var result = new Dictionary<string,string>();
            var adapter = new DISPLAY_DEVICE(); adapter.cb = (uint)Marshal.SizeOf(adapter);
            for (uint i = 0; EnumDisplayDevices(null, i, ref adapter, 0); ++i) {
                if ((adapter.flags & 1) == 0 || (adapter.flags & 8) != 0) continue;
                var monitor = new DISPLAY_DEVICE(); monitor.cb = (uint)Marshal.SizeOf(monitor);
                if (EnumDisplayDevices(adapter.name, 0, ref monitor, 1) && !String.IsNullOrEmpty(monitor.id)) result[monitor.id] = adapter.name;
            }
            return result;
        }
        public static bool Restore(string file) {
            using (var mutex = new Mutex(false, @"Local\ii-windows-nightlight")) {
                bool held = false;
                try {
                    try { held = mutex.WaitOne(10000); } catch (AbandonedMutexException) { held = true; }
                    if (!held) return false;
                    if (!File.Exists(file)) return true; // guard already restored it
                    var saved = new Dictionary<string,ushort[]>();
                    using (var reader = new BinaryReader(File.OpenRead(file), Encoding.Unicode)) {
                        if (reader.ReadUInt32() != 0x49494731) return false;
                        uint count = reader.ReadUInt32(); if (count > 64) return false;
                        for (uint n = 0; n < count; ++n) {
                            uint length = reader.ReadUInt32(); if (length == 0 || length > 1024) return false;
                            var bytes = reader.ReadBytes((int)length * 2); if (bytes.Length != length * 2) return false;
                            string id = Encoding.Unicode.GetString(bytes); if (id.IndexOf('\0') >= 0 || saved.ContainsKey(id)) return false;
                            var ramp = new ushort[768]; for (int i = 0; i < ramp.Length; ++i) ramp[i] = reader.ReadUInt16();
                            saved.Add(id, ramp);
                        }
                        if (reader.BaseStream.Position != reader.BaseStream.Length) return false;
                    }
                    var displays = Displays(); bool ok = true;
                    foreach (var entry in saved) {
                        string name; if (!displays.TryGetValue(entry.Key, out name)) { ok = false; continue; }
                        var dc = CreateDC("DISPLAY", name, null, IntPtr.Zero);
                        if (dc == IntPtr.Zero) { ok = false; continue; }
                        try {
                            var readback = new ushort[768];
                            if (!SetDeviceGammaRamp(dc, entry.Value) || !GetDeviceGammaRamp(dc, readback)) { ok = false; continue; }
                            for (int i = 0; i < 768; ++i) if (Math.Abs((int)readback[i] - entry.Value[i]) > 256) { ok = false; break; }
                        } finally { DeleteDC(dc); }
                    }
                    if (ok) File.Delete(file);
                    return ok;
                } catch { return false; }
                finally { if (held) mutex.ReleaseMutex(); }
            }
        }
    }
}
'@
    if ([IiRescue.GammaRecovery]::Restore($gammaFile)) { Log 'original display gamma restored' }
    else { Log 'gamma restore incomplete; original backup retained for another rescue (disconnected display/driver)' }
}

foreach ($h in @(Find-All 'Shell_TrayWnd') + @(Find-All 'Shell_SecondaryTrayWnd')) {
    [IiRescue.Win]::ShowWindow($h, 8) | Out-Null   # SW_SHOWNA
}
Log 'taskbars shown'

# 3. auto-hide back to what it was before ii touched it
$original = Read-State 'taskbarOriginalState' -1
if ((Read-State 'taskbarHidden' 0) -ne 0 -and $original -ge 0) {
    $tray = [IiRescue.Win]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, 'Shell_TrayWnd', [NullString]::Value)
    $abd = New-Object IiRescue.Win+APPBARDATA
    $abd.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($abd)
    $abd.hWnd = $tray
    $abd.lParam = [IntPtr]$original
    [IiRescue.Win]::SHAppBarMessage(10, [ref]$abd) | Out-Null   # ABM_SETSTATE
    # Explorer saves that state lazily; write it to its settings too so it sticks.
    $stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $settings = (Get-ItemProperty $stuck -ErrorAction SilentlyContinue).Settings
    if ($settings -and $settings.Length -gt 8) {
        $settings[8] = if ($original -band 1) { $settings[8] -bor 1 } else { $settings[8] -band 0xFE }
        Set-ItemProperty $stuck -Name Settings -Value $settings -Type Binary
    }
    Log "taskbar auto-hide state restored to $original"
}
Write-State 'taskbarHidden' 0

# 4. desktop icons visible
$views = @()
$progman = [IiRescue.Win]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, 'Progman', [NullString]::Value)
if ($progman -ne [IntPtr]::Zero) { $views += [IiRescue.Win]::FindWindowEx($progman, [IntPtr]::Zero, 'SHELLDLL_DefView', [NullString]::Value) }
foreach ($w in Find-All 'WorkerW') { $views += [IiRescue.Win]::FindWindowEx($w, [IntPtr]::Zero, 'SHELLDLL_DefView', [NullString]::Value) }
foreach ($v in $views | Where-Object { $_ -ne [IntPtr]::Zero }) {
    $list = [IiRescue.Win]::FindWindowEx($v, [IntPtr]::Zero, 'SysListView32', [NullString]::Value)
    if ($list -ne [IntPtr]::Zero) { [IiRescue.Win]::ShowWindow($list, 8) | Out-Null }
}
Write-State 'iconsHidden' 0
Log 'desktop icons shown'

# 5. Windows' notification banners back to each app's original setting
$bannerFile = Join-Path $dataDir 'banners.txt'
if (Test-Path $bannerFile) {
    $settings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $done = @{}
    foreach ($line in Get-Content $bannerFile -Encoding UTF8) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2 -or $done.ContainsKey($parts[1])) { continue }
        $done[$parts[1]] = $true
        # -LiteralPath: AUMIDs can contain wildcard characters such as [ ]
        $key = Join-Path $settings $parts[1]
        if (-not (Test-Path -LiteralPath $key)) { continue }
        if ([int]$parts[0] -lt 0) { Remove-ItemProperty -LiteralPath $key -Name ShowBanner -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -LiteralPath $key -Name ShowBanner -Value ([int]$parts[0]) -Type DWord }
    }
    Remove-Item $bannerFile
    Log "notification banners restored ($($done.Count) apps)"
}
Write-State 'bannersHidden' 0

# 6. Windows' dark/light mode and accent color back to what they were
$themeFile = Join-Path $dataDir 'theme.txt'
if (Test-Path $themeFile) {
    $done = @{}
    foreach ($line in Get-Content $themeFile -Encoding UTF8) {
        $parts = $line -split "`t"
        if ($parts.Count -lt 4) { continue }
        $id = $parts[0] + "`t" + $parts[1]
        if ($done.ContainsKey($id)) { continue }
        $done[$id] = $true
        $key = Join-Path 'HKCU:' $parts[0]
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $type = [int]$parts[2]
        if ($type -lt 0) { Remove-ItemProperty -LiteralPath $key -Name $parts[1] -ErrorAction SilentlyContinue; continue }
        $bytes = [byte[]]@(for ($i = 0; $i + 1 -lt $parts[3].Length; $i += 2) { [Convert]::ToByte($parts[3].Substring($i, 2), 16) })
        if ($type -eq 4) { Set-ItemProperty -LiteralPath $key -Name $parts[1] -Value ([BitConverter]::ToUInt32($bytes, 0)) -Type DWord }
        else { Set-ItemProperty -LiteralPath $key -Name $parts[1] -Value $bytes -Type Binary }
    }
    Remove-Item $themeFile
    $r = [UIntPtr]::Zero
    [IiRescue.Win]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r) | Out-Null
    Log "theme restored ($($done.Count) values)"
}
Write-State 'themeApplied' 0
Write-State 'hostClean' 1

# 7. optional clean Explorer restart
if ($RestartExplorer) {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
    Log 'explorer restarted'
}

Log 'rescue finished'
