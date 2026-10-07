# Runs INSIDE the sandbox after qs.ps1 -Seed created config/colors: host + shell + an app window + Win+D.
$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
  public static void Keys(params int[] seq) { var a = new IN[seq.Length]; for (int i = 0; i < seq.Length; i++) { var vk = (ushort)Math.Abs(seq[i]); a[i].type = 1; a[i].ki.vk = vk; a[i].ki.flags = (seq[i] < 0 ? 2u : 0u) | (vk == 0x5B ? 1u : 0u); } SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN))); }
}
'@
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$out\scene-*.png" -ErrorAction SilentlyContinue
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

Start-Process C:\ii\host\build\ii-host.exe -ArgumentList '--shell', 'C:\ii\dist\quickshell\quickshell.exe', '--config', $local
Start-Sleep 18
& "$dev\screenshot.ps1" -Out "$out\scene-1-desktop.png" | Out-Null

# every visible shell window on its own
$i = 0
& "$dev\windows.ps1" -Process quickshell | Select-String 'QWindowIcon' | ForEach-Object {
    $f = $_.Line.Trim() -split '\s+'
    "window $($f[0]) visible=$($f[2]) rect=$($f[5]) $($f[6]) ex=$($f[8])"
    if ($f[2] -eq 'True') {
        & "$dev\capture-window.ps1" -Hwnd $f[0] -Out "$out\scene-win-$i-$($f[0]).png" | Out-Null
        $i++
    }
}

Start-Process explorer.exe -ArgumentList 'C:\Windows'
Start-Sleep 4
& "$dev\screenshot.ps1" -Out "$out\scene-2-app.png" | Out-Null
[K]::Keys(0x5B, 0x44, -0x44, -0x5B)   # Win+D
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\scene-3-wind.png" | Out-Null
[K]::Keys(0x5B, -0x5B)                # lone Win: ii search
Start-Sleep 2
& "$dev\screenshot.ps1" -Out "$out\scene-4-search.png" | Out-Null
[K]::Keys(0x1B, -0x1B)

$qs = Get-Process quickshell -ErrorAction SilentlyContinue
if ($qs) { 'quickshell: ws={0:N0} MB private={1:N0} MB' -f ($qs.WorkingSet64 / 1MB), ($qs.PrivateMemorySize64 / 1MB) } else { 'quickshell NOT running' }

Start-Process C:\ii\host\build\ii-host.exe -ArgumentList '--rescue' -Wait
$log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName | Where-Object { $_ -match 'ERROR|WARN' -and $_ -notmatch 'proc/|os-release|binary could not be found|polish' } | Select-Object -Last 30
