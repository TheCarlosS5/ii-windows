# List top-level windows (optionally of one process name) with class, rect, visibility and styles.
# usage: windows.ps1 [-Process quickshell]
param([string]$Process = '')
Add-Type -Namespace Native -Name Win -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
'@
$pids = @{}
if ($Process) { Get-Process $Process -ErrorAction SilentlyContinue | ForEach-Object { $pids[[uint32]$_.Id] = $true } }
$rows = New-Object System.Collections.ArrayList
$cb = [Native.Win+EnumProc]{
    param($h, $l)
    $wpid = [uint32]0; [Native.Win]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
    if ($Process -and -not $pids.ContainsKey($wpid)) { return $true }
    $c = New-Object System.Text.StringBuilder 256; [Native.Win]::GetClassName($h, $c, 256) | Out-Null
    $t = New-Object System.Text.StringBuilder 256; [Native.Win]::GetWindowText($h, $t, 256) | Out-Null
    $r = New-Object Native.Win+RECT; [Native.Win]::GetWindowRect($h, [ref]$r) | Out-Null
    [void]$rows.Add([pscustomobject]@{
        hwnd = '0x{0:X}' -f $h.ToInt64(); pid = $wpid; visible = [Native.Win]::IsWindowVisible($h)
        class = $c.ToString(); title = $t.ToString(); rect = "$($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T)"
        style = '0x{0:X8}' -f [Native.Win]::GetWindowLong($h, -16); exstyle = '0x{0:X8}' -f [Native.Win]::GetWindowLong($h, -20)
    })
    return $true
}
[Native.Win]::EnumWindows($cb, [System.IntPtr]::Zero) | Out-Null
$rows | Format-Table -AutoSize | Out-String -Width 250
