# INSIDE a fresh sandbox: install the newest package as a new user would, then look at everything a
# newcomer sees (welcome window, tour, each panel) and collect the shell's QML errors.
# Screenshots land in the outbox as fresh-*.png.
param([string]$Zip = '')
$ErrorActionPreference = 'Continue'
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
if (-not $Zip) { $Zip = (Get-ChildItem C:\ii\out\ii-windows-*.zip | Sort-Object LastWriteTime | Select-Object -Last 1).FullName }
"package: $Zip"
Remove-Item "$out\fresh-*.png" -ErrorAction SilentlyContinue

$work = "$env:TEMP\ii-fresh"
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $Zip $work
$pkg = (Get-ChildItem $work -Directory | Select-Object -First 1).FullName
$t = Measure-Command { & powershell -NoProfile -ExecutionPolicy Bypass -File "$pkg\install.ps1" -Yes -StartNow *> "$out\fresh-install-log.txt" }
"install exit $LASTEXITCODE in $([int]$t.TotalSeconds) s"
Start-Sleep 25
& "$dev\screenshot.ps1" -Out "$out\fresh-01-welcome.png" | Out-Null

# The welcome window is its own quickshell (welcome.qml): close it like a user would, then the tour.
$welcome = Get-CimInstance Win32_Process -Filter "Name='quickshell.exe'" | Where-Object { $_.CommandLine -like '*welcome.qml*' }
"welcome window running: $([bool]$welcome)"
$welcome | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 4
& "$dev\screenshot.ps1" -Out "$out\fresh-02-tour.png" | Out-Null
$qs = Get-ChildItem "$env:LOCALAPPDATA\Programs\ii-windows\versions\*\quickshell\bin\ii-shim.exe" | Select-Object -First 1
& $qs.FullName qs ipc call tour close 2>&1 | Out-Null
Start-Sleep 1

$n = 3
foreach ($name in 'sidebarRightToggle', 'sidebarLeftToggle', 'searchToggle', 'overviewWorkspacesToggle', 'cheatsheetToggle', 'wallpaperSelectorToggle', 'mediaControlsToggle', 'sessionToggle') {
    & "$dev\send-shortcut.ps1" -Name $name | Out-Null
    Start-Sleep -Milliseconds 1800
    & "$dev\screenshot.ps1" -Out ("$out\fresh-{0:00}-{1}.png" -f $n, $name) | Out-Null
    & "$dev\send-shortcut.ps1" -Name $name | Out-Null
    Start-Sleep -Milliseconds 700
    $n++
}

# The main shell's log: every distinct QML problem.
$main = Get-CimInstance Win32_Process -Filter "Name='quickshell.exe'" | Where-Object { $_.CommandLine -notlike '*welcome.qml*' } | Select-Object -First 1
$log = Get-ChildItem "$env:TEMP\quickshell\by-pid\$($main.ProcessId)\log.log" -ErrorAction SilentlyContinue
if (-not $log) { $log = Get-ChildItem "$env:LOCALAPPDATA\Temp\quickshell\by-pid\$($main.ProcessId)\log.log" -ErrorAction SilentlyContinue }
"log: $($log.FullName)"
if ($log) {
    Get-Content $log.FullName | Where-Object { $_ -match 'WARN|ERROR' } | ForEach-Object { ($_ -replace '^\S+ \S+\s+', '') -replace 'file:///\S+/qmltree/qs/', '' } |
        Group-Object | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object { "{0,3}x {1}" -f $_.Count, $_.Name.Substring(0, [Math]::Min(230, $_.Name.Length)) }
}
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" | Select-String 'splash|gpu:|ready after|slow:|error|fail' | Select-Object -Last 15 | ForEach-Object { $_.Line }
