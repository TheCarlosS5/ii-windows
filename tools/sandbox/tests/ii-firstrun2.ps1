# INSIDE the sandbox: a first run (no config, no marker) opens ii's welcome screen; the emoji
# search (":" in the launcher) has results; Win+Ctrl+R restarts the shell through ii-host.
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
Remove-Item "$env:LOCALAPPDATA\quickshell" -Recurse -Force -ErrorAction SilentlyContinue   # config + state: a first run
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }

Start-Process "$hostDir\ii-host.exe" -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$local`"" | Out-Null
Start-Sleep 30
$procs = @(Get-Process quickshell -ErrorAction SilentlyContinue)
Check 'first run opens the welcome screen (a second shell process)' ($procs.Count -ge 2) "($($procs.Count) quickshell)"
& "$dev\screenshot.ps1" -Out "$out\fr-1-welcome.png" | Out-Null
$marker = Get-ChildItem "$env:LOCALAPPDATA\quickshell" -Recurse -Filter first_run.txt -ErrorAction SilentlyContinue | Select-Object -First 1
Check 'first run marker written' ($null -ne $marker) "($($marker.FullName))"
# close the welcome window
$procs | Sort-Object StartTime | Select-Object -Skip 1 | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1

# Emojis
& "$dev\send-shortcut.ps1" -Name overviewEmojiToggle | Out-Null
Start-Sleep 2
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('heart')
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\fr-2-emoji.png" | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep 1

# Win+Ctrl+R restarts the shell
$before = (Get-Process quickshell | Sort-Object StartTime | Select-Object -First 1).Id
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KR {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    public static void Chord(params ushort[] keys) {
        var a = new IN[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++) foreach (var up in new[] { false, true }) {
            int idx = up ? keys.Length * 2 - 1 - i : i;
            a[idx].type = 1; a[idx].ki.vk = keys[i]; a[idx].ki.scan = (ushort)MapVirtualKey(keys[i], 0);
            a[idx].ki.flags = (up ? 2u : 0u) | (keys[i] == 0x5B ? 1u : 0u);
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
}
'@
[KR]::Chord(0x5B, 0x11, 0x52)
Start-Sleep 15
$after = (Get-Process quickshell -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -First 1).Id
Check 'Win+Ctrl+R restarts the shell' ($after -and $after -ne $before) "($before -> $after)"
& "$dev\screenshot.ps1" -Out "$out\fr-3-restarted.png" -H 60 | Out-Null
& "$hostDir\ii-host.exe" --rescue
"fails: $script:fails"
