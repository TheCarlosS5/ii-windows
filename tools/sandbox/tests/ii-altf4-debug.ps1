# INSIDE the sandbox: which step crashes the shell - opening the session menu by shortcut, closing
# it with Esc, or Alt+F4 on the desktop.
$dev = 'C:\ii\tools\dev'
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
            a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0); a[idx].ki.flags = up ? 2u : 0u;
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
}
'@
function ShellPid { (Get-CimInstance Win32_Process -Filter "Name='quickshell.exe'" | Where-Object { $_.CommandLine -notmatch 'welcome' } | Select-Object -First 1).ProcessId }
function Step($what) { Start-Sleep 4; "$what -> shell pid $(ShellPid)" }
Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 25
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'welcome\.qml' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
"start: shell pid $(ShellPid)"
& "$dev\send-shortcut.ps1" -Name sessionToggle | Out-Null; Step 'sessionToggle (shortcut)'
& "$dev\screenshot.ps1" -Out "$out\dbg-1-session.png" | Out-Null
[K]::Chord(0x1B); Step 'Esc'
& "$dev\send-shortcut.ps1" -Name sessionToggle | Out-Null; Step 'sessionToggle again'
& "$dev\send-shortcut.ps1" -Name sessionToggle | Out-Null; Step 'sessionToggle to close'
& "$dev\click.ps1" -X 830 -Y 370; Start-Sleep 1
& "$dev\send-shortcut.ps1" -Name sessionToggle | Out-Null; Step 'desktop focused, then sessionToggle (shortcut)'
[K]::Chord(0x1B); Step 'Esc'
& "$dev\click.ps1" -X 830 -Y 370; Start-Sleep 1
[K]::Chord(0x12, 0x73); Step 'Alt+F4 on the desktop'
& "$dev\screenshot.ps1" -Out "$out\dbg-2-altf4.png" | Out-Null
[K]::Chord(0x1B); Step 'Esc after Alt+F4'
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" | Select-String 'exited|started pid' | Select-Object -Last 5 | ForEach-Object { $_.Line }
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Where-Object { (Get-Content $_.FullName -TotalCount 1) -match 'shell\.qml' }
foreach ($f in $log) { "== $($f.Name)"; Get-Content $f.FullName | Select-String 'Ignored|session|Session|ERROR|crash' | Select-Object -Last 8 | ForEach-Object { $_.Line } }
& "$hostDir\ii-host.exe" --rescue
