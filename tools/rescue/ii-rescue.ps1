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
Write-State 'hostClean' 1

# 6. optional clean Explorer restart
if ($RestartExplorer) {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
    Log 'explorer restarted'
}

Log 'rescue finished'
