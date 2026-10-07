# Small Win32 probes used by the prototypes' checks.
#   probe.ps1 workarea                      -> work area of the primary monitor
#   probe.ps1 exstyle -Hwnd 0x1234          -> extended style of a window
#   probe.ps1 hittest -X 5 -Y 50 [-Process quickshell]
#        moves the cursor there for ~150 ms, reports the window under the point and the
#        exstyle of the process's windows, then puts the cursor back.
param([Parameter(Mandatory, Position = 0)][string]$Probe, [string]$Hwnd = '', [int]$X = 0, [int]$Y = 0, [string]$Process = 'quickshell')
Add-Type -Namespace Native -Name Probe -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
[DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint b, out RECT r, uint c);
[DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern System.IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern System.IntPtr GetAncestor(System.IntPtr h, uint f);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
[Native.Probe]::SetProcessDPIAware() | Out-Null
switch ($Probe) {
    'workarea' {
        $r = New-Object Native.Probe+RECT
        [Native.Probe]::SystemParametersInfoW(0x30, 0, [ref]$r, 0) | Out-Null
        "workarea $($r.L),$($r.T) -> $($r.R),$($r.B)"
    }
    'exstyle' {
        '0x{0:X8}' -f [Native.Probe]::GetWindowLong([IntPtr][Convert]::ToInt64($Hwnd, 16), -20)
    }
    'hittest' {
        $old = New-Object Native.Probe+POINT
        [Native.Probe]::GetCursorPos([ref]$old) | Out-Null
        [Native.Probe]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 150
        $pt = New-Object Native.Probe+POINT; $pt.X = $X; $pt.Y = $Y
        $h = [Native.Probe]::GetAncestor([Native.Probe]::WindowFromPoint($pt), 2)
        [Native.Probe]::SetCursorPos($old.X, $old.Y) | Out-Null
        $wpid = [uint32]0; [Native.Probe]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
        $c = New-Object System.Text.StringBuilder 256; [Native.Probe]::GetClassName($h, $c, 256) | Out-Null
        $owner = (Get-Process -Id $wpid -ErrorAction SilentlyContinue).ProcessName
        "point ($X,$Y) -> window 0x{0:X} class={1} process={2}" -f $h.ToInt64(), $c, $owner
    }
}
