# INSIDE the sandbox: the taskbar's auto-hide setting survives ii-host + an Explorer restart
# exactly as it was, for a user with auto-hide off and for one with it on.
param([int]$Baseline = 0)  # 0 = auto-hide off, 1 = on
$ErrorActionPreference = 'Continue'
$hostExe = 'C:\ii\host\build\ii-host.exe'
$stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
Add-Type -Namespace TP -Name W -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public IntPtr lParam; }
[DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint m, ref APPBARDATA d);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);'
function Live() { $d = New-Object TP.W+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); [int](([TP.W]::SHAppBarMessage(4, [ref]$d)).ToUInt32()) -band 1 }
function Saved() { (Get-ItemProperty $stuck).Settings[8] -band 1 }
function SetLive($v) {
    $d = New-Object TP.W+APPBARDATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d)
    $d.hWnd = [TP.W]::FindWindow('Shell_TrayWnd', [NullString]::Value); $d.lParam = [IntPtr]$v
    [void][TP.W]::SHAppBarMessage(10, [ref]$d)
}
function RestartExplorer() {
    Get-Process explorer | Stop-Process -Force
    Start-Sleep 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
    for ($i = 0; $i -lt 20 -and -not [TP.W]::FindWindow('Shell_TrayWnd', [NullString]::Value); $i++) { Start-Sleep 1 }
    Start-Sleep 4
}
function StartHost() { Start-Process $hostExe -ArgumentList '--no-hook', '--keep-banners'; Start-Sleep 4 }

# Baseline: live and saved agree on $Baseline.
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$env:LOCALAPPDATA\ii-windows" -Recurse -Force -ErrorAction SilentlyContinue
SetLive $Baseline
$s = (Get-ItemProperty $stuck).Settings; $s[8] = ($s[8] -band 0xFE) -bor $Baseline; Set-ItemProperty $stuck -Name Settings -Value $s -Type Binary
RestartExplorer
Check "baseline auto-hide=$Baseline" ((Live) -eq $Baseline) "(live $(Live), saved $(Saved))"

# 1. clean exit, then Explorer restarts
StartHost
Check 'host running: auto-hide on' ((Live) -eq 1)
[void][TP.W]::PostMessageW([TP.W]::FindWindow('IiHostWindow', [NullString]::Value), 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep 3
Check 'clean exit: live restored' ((Live) -eq $Baseline) "(live $(Live))"
Check 'clean exit: saved restored' ((Saved) -eq $Baseline) "(saved $(Saved))"
RestartExplorer
Check 'clean exit + Explorer restart: still original' ((Live) -eq $Baseline) "(live $(Live))"

# 2. host killed (the guard restores), then Explorer restarts
StartHost
Get-CimInstance Win32_Process -Filter "Name='ii-host.exe'" | Where-Object { $_.CommandLine -notmatch '--guard' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 3
RestartExplorer
Check 'guard + Explorer restart: still original' ((Live) -eq $Baseline) "(live $(Live), saved $(Saved))"

# 3. everything killed, rescue script, then Explorer restarts
StartHost
Get-Process ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
RestartExplorer
Check 'rescue + Explorer restart: still original' ((Live) -eq $Baseline) "(live $(Live), saved $(Saved))"

"fails: $script:fails"
