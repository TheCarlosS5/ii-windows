# INSIDE the sandbox: how Windows records virtual desktops (registry, read only) as they are
# created, switched and closed with Windows' own shortcuts, and whether ii's windows stay.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class VK {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
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
}
'@
function Reg {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops'
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $ids = if ($p.VirtualDesktopIDs) { ($p.VirtualDesktopIDs.Length / 16) } else { 'none' }
    $cur = if ($p.CurrentVirtualDesktop) { [Guid]::new([byte[]]$p.CurrentVirtualDesktop) } else { 'none' }
    $sess = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo' -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty "$($_.PSPath)\VirtualDesktops" -ErrorAction SilentlyContinue).CurrentVirtualDesktop } | Where-Object { $_ } | Select-Object -First 1
    $sessCur = if ($sess) { [Guid]::new([byte[]]$sess) } else { 'none' }
    "  ids=$ids current=$cur sessionCurrent=$sessCur desktops=$((Get-ChildItem "$k\Desktops" -ErrorAction SilentlyContinue).Count)"
}
$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 14
Start-Process explorer.exe -ArgumentList "/n,$env:WINDIR"
Start-Sleep 3
'start'; Reg
[VK]::Chord(0x5B, 0x11, 0x44); Start-Sleep 2      # Win+Ctrl+D: new desktop
'after Win+Ctrl+D'; Reg
& "$dev\screenshot.ps1" -Out "$out\vd-new.png" -H 80 | Out-Null
[VK]::Chord(0x5B, 0x11, 0x44); Start-Sleep 2
'after second Win+Ctrl+D'; Reg
[VK]::Chord(0x5B, 0x11, 0x25); Start-Sleep 2      # Win+Ctrl+Left
'after Win+Ctrl+Left'; Reg
[VK]::Chord(0x5B, 0x11, 0x25); Start-Sleep 2
'after second Win+Ctrl+Left (first desktop, with the Explorer window)'; Reg
& "$dev\screenshot.ps1" -Out "$out\vd-first.png" | Out-Null
[VK]::Chord(0x5B, 0x11, 0x27); Start-Sleep 2      # Win+Ctrl+Right
& "$dev\screenshot.ps1" -Out "$out\vd-second.png" | Out-Null
[VK]::Chord(0x5B, 0x11, 0x73); Start-Sleep 2      # Win+Ctrl+F4: close current
'after Win+Ctrl+F4'; Reg
[VK]::Chord(0x5B, 0x11, 0x73); Start-Sleep 2
'after second Win+Ctrl+F4'; Reg
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
Stop-Process -Id $p.Id -Force
'done'
