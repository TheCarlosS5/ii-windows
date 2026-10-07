# Capture one window to PNG even when it is covered by other windows (PrintWindow + PW_RENDERFULLCONTENT).
# usage: capture-window.ps1 -Hwnd 0x1234 -Out shot.png
#        capture-window.ps1 -Process quickshell -Class Qt6120QWindowIcon -Out shot.png   (first visible match)
param([string]$Hwnd = '', [string]$Process = '', [string]$Class = '', [Parameter(Mandatory)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Native -Name Cap -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr h, System.IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
'@
[Native.Cap]::SetProcessDPIAware() | Out-Null
$target = [IntPtr]::Zero
if ($Hwnd) { $target = [IntPtr][Convert]::ToInt64($Hwnd, 16) }
else {
    $pids = @{}; Get-Process $Process -ErrorAction SilentlyContinue | ForEach-Object { $pids[[uint32]$_.Id] = $true }
    $script:found = [IntPtr]::Zero
    $cb = [Native.Cap+EnumProc]{
        param($h, $l)
        $wpid = [uint32]0; [Native.Cap]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
        if (-not $pids.ContainsKey($wpid) -or -not [Native.Cap]::IsWindowVisible($h)) { return $true }
        $c = New-Object System.Text.StringBuilder 256; [Native.Cap]::GetClassName($h, $c, 256) | Out-Null
        if ($Class -and $c.ToString() -ne $Class) { return $true }
        $script:found = $h; return $false
    }
    [Native.Cap]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    $target = $script:found
}
if ($target -eq [IntPtr]::Zero) { Write-Error 'window not found'; exit 1 }
$r = New-Object Native.Cap+RECT; [Native.Cap]::GetWindowRect($target, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[Native.Cap]::PrintWindow($target, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc); $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
"captured 0x{0:X} {1}x{2} -> {3}" -f $target.ToInt64(), ($r.R - $r.L), ($r.B - $r.T), $Out
