# INSIDE the sandbox: does Explorer persist ABM_SETSTATE to StuckRects3 right away?
Add-Type -Namespace SR -Name W -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public IntPtr lParam; }
[DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint m, ref APPBARDATA d);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);'
function Live() { $d = New-Object SR.W+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); [int](([SR.W]::SHAppBarMessage(4, [ref]$d)).ToUInt32()) }
function Saved() { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3').Settings[8] }
function SetState($v) {
    $d = New-Object SR.W+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d)
    $d.hWnd = [SR.W]::FindWindow('Shell_TrayWnd', [NullString]::Value); $d.lParam = [IntPtr]$v
    [void][SR.W]::SHAppBarMessage(10, [ref]$d)
}
"start: live=$(Live) saved=0x{0:X2}" -f (Saved)
SetState 0; Start-Sleep 1
"after set 0: live=$(Live) saved=0x{0:X2}" -f (Saved)
Start-Sleep 5
"5s later: live=$(Live) saved=0x{0:X2}" -f (Saved)
SetState 1; Start-Sleep 1
"after set 1 (autohide): live=$(Live) saved=0x{0:X2}" -f (Saved)
SetState 0; Start-Sleep 1
"after set 0 again: live=$(Live) saved=0x{0:X2}" -f (Saved)
