# INSIDE a fresh sandbox: install the package, use it, uninstall, and check Windows is exactly as before.
param([string]$Zip = '')
$ErrorActionPreference = 'Continue'
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
if (-not $Zip) { $Zip = (Get-ChildItem C:\ii\out\ii-windows-*.zip | Sort-Object LastWriteTime | Select-Object -Last 1).FullName }
"package: $Zip"

Add-Type -Namespace TI -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'
function TaskbarVisible() {
    $h = [IntPtr]::Zero
    while (($h = [TI.W]::FindWindowEx([IntPtr]::Zero, $h, 'Shell_TrayWnd', [NullString]::Value)) -ne [IntPtr]::Zero) {
        $procId = 0; [void][TI.W]::GetWindowThreadProcessId($h, [ref]$procId)
        if ((Get-Process -Id $procId).ProcessName -eq 'explorer') { return [TI.W]::IsWindowVisible($h) }
    }
    $false
}
function Snapshot() {
    $c = Get-ItemProperty 'HKCU:\Control Panel\Cursors'
    $t = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $d = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM'
    $run = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).'ii-windows'
    $userPath = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('Path', '<none>', 'DoNotExpandEnvironmentNames')
    $gpu = @((Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -like '*quickshell*' }).Count
    $fontKey = Get-Item 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
    $fonts = @(if ($fontKey) {
        foreach ($name in ($fontKey.GetValueNames() | Sort-Object)) {
            [ordered]@{ name = $name; kind = [string]$fontKey.GetValueKind($name); value = $fontKey.GetValue($name, $null, 'DoNotExpandEnvironmentNames') }
        }
        $fontKey.Close()
    }) | ConvertTo-Json -Compress -Depth 3
    "cursor=$($c.Arrow)|$($c.'(default)')|$($c.Wait) theme=$($t.AppsUseLightTheme)/$($t.SystemUsesLightTheme) dwm=$($d.AccentColor)/$($d.ColorPrevalence) run=$run taskbar=$(TaskbarVisible) path=$userPath gpu=$gpu fonts=$fonts"
}

Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$baseline = Snapshot
"baseline: $baseline"

# --- install ---
$work = "$env:TEMP\ii-install-test"
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $Zip $work
$pkg = (Get-ChildItem $work -Directory | Select-Object -First 1).FullName
$t = Measure-Command { & powershell -NoProfile -ExecutionPolicy Bypass -File "$pkg\install.ps1" -Yes -StartNow *> "$out\install-log.txt" }
"install exit $LASTEXITCODE in $([int]$t.TotalSeconds) s"
Start-Sleep 20
$dir = "$env:LOCALAPPDATA\Programs\ii-windows"
Check 'files installed' (Test-Path "$dir\quickshell\quickshell.exe")
Check 'ii-host running from the install folder' ([bool](Get-Process ii-host -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir*" }))
Check 'quickshell running' ([bool](Get-Process quickshell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir*" }))
Check 'taskbar hidden while running' (-not (TaskbarVisible))
$task = Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue
Check 'autostart: logon task with --boot' ($task -and $task.Actions[0].Arguments -like '--boot --shell "*quickshell.exe" --config "*\ii"' -and $task.Principal.RunLevel -eq 'Limited') "($($task.Actions[0].Arguments))"
Check 'autostart: no Run entry when the task exists' (-not (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).'ii-windows')
Check 'Bibata cursor applied' ((Get-ItemProperty 'HKCU:\Control Panel\Cursors').Arrow -like "*Bibata*")
Check 'Apps & features entry' (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows')
Check 'Start menu shortcuts' ((Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ii-windows" -Filter *.lnk).Count -eq 4)
Check 'registry exported before changes' ((Get-ChildItem "$env:LOCALAPPDATA\ii-windows\backup" -Recurse -Filter *.reg).Count -ge 5)
Check 'manifest written' (Test-Path "$env:LOCALAPPDATA\ii-windows\install.json")
$manifest = Get-Content "$env:LOCALAPPDATA\ii-windows\install.json" -Raw | ConvertFrom-Json
$fonts = @($manifest.fonts)
$fontFiles = @(Get-ChildItem "$pkg\app\quickshell\fonts" -Filter 'JetBrainsMonoNerdFont-*.ttf' -File)
Check 'all packaged terminal fonts recorded' ($fontFiles.Count -gt 0 -and $fonts.Count -eq $fontFiles.Count)
$fontKeyPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
foreach ($font in $fonts) {
    $fontKey = Get-Item -LiteralPath $fontKeyPath -ErrorAction SilentlyContinue
    $registered = if ($fontKey) { $fontKey.GetValue([string]$font.valueName) } else { $null }
    if ($fontKey) { $fontKey.Close() }
    Check "font registered: $($font.valueName)" ($registered -eq $font.file)
    Check "font file present: $($font.valueName)" (Test-Path -LiteralPath $font.file -PathType Leaf)
}
$fragmentDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\ii-windows"
# The fragment is written by switchwall at the first wallpaper change (the welcome screen sets one).
"Terminal fragment present: $(Test-Path "$fragmentDir\ii-windows.json")"
$gpuPref = (Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue)."$env:LOCALAPPDATA\Programs\ii-windows\quickshell\quickshell.exe"
Check 'power-saving GPU for the shell' ($gpuPref -eq 'GpuPreference=1;') "($gpuPref)"
$userPath = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
Check 'fastfetch folder appended to the user PATH' ($userPath.Split(';')[-1] -eq "$dir\bin") "($userPath)"
$ff = & cmd.exe /c "`"$dir\bin\fastfetch.cmd`" --pipe true" 2>&1 | Out-String
Check 'fastfetch runs with ii''s config and logo' ($ff -match 'illogical impulse' -and $ff.Contains([string][char]0x2588 * 4)) ("(" + ($ff -split "`n")[0].Trim() + ")")
& powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\rescue\ii-report.ps1" -NoBrowser | Out-Null
$rep = Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Filter 'ii-windows-reporte-*.txt' | Select-Object -Last 1
$repText = if ($rep) { Get-Content $rep.FullName -Raw } else { '' }
Check 'report written, without the user or PC name' ($rep -and $repText -match 'Version:' -and $repText -notmatch [regex]::Escape($env:USERNAME) -and $repText -notmatch [regex]::Escape($env:COMPUTERNAME))
if ($rep) { Move-Item $rep.FullName "$out\report-sample.txt" -Force }
& "$dev\screenshot.ps1" -Out "$out\installed.png" | Out-Null

# --- uninstall, from the installed copy (as the Start menu shortcut does) ---
& powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\uninstall.ps1" -Yes *> "$out\uninstall-log.txt"
"uninstall exit $LASTEXITCODE"
Start-Sleep 20
Check 'processes stopped' (-not (Get-Process ii-host, quickshell -ErrorAction SilentlyContinue))
Check 'install folder removed' (-not (Test-Path $dir))
Check 'logon task removed' (-not (Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue))
Check 'shortcuts removed' (-not (Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ii-windows"))
Check 'Apps & features entry removed' (-not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows'))
foreach ($font in $fonts) {
    $fontKey = Get-Item -LiteralPath $fontKeyPath -ErrorAction SilentlyContinue
    Check "font registration removed: $($font.valueName)" (-not $fontKey -or $fontKey.GetValueNames() -notcontains $font.valueName)
    if ($fontKey) { $fontKey.Close() }
    Check "font file removed: $($font.valueName)" (-not (Test-Path -LiteralPath $font.file))
}
Check 'Terminal fragment folder removed' (-not (Test-Path -LiteralPath $fragmentDir))
$after = Snapshot
Check 'Windows exactly as before' ($after -eq $baseline) "($after)"
& "$dev\screenshot.ps1" -Out "$out\uninstalled.png" | Out-Null
"fails: $script:fails"
