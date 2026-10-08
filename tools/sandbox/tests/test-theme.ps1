# INSIDE the sandbox: Windows follows ii's palette while ii-host runs (dark/light, accent, title
# bars) and every value is back exactly as before on clean exit, via the guard and via rescue.
$ErrorActionPreference = 'Continue'
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
$hostExe = 'C:\ii\host\build\ii-host.exe'
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }

$values = @(
    @('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme'),
    @('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'SystemUsesLightTheme'),
    @('Software\Microsoft\Windows\DWM', 'AccentColor'),
    @('Software\Microsoft\Windows\DWM', 'ColorizationColor'),
    @('Software\Microsoft\Windows\DWM', 'ColorizationAfterglow'),
    @('Software\Microsoft\Windows\DWM', 'ColorPrevalence'),
    @('Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'AccentPalette'),
    @('Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'AccentColorMenu'),
    @('Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'StartColorMenu')
)
function Snapshot() {
    ($values | ForEach-Object {
        $v = (Get-ItemProperty -LiteralPath "HKCU:\$($_[0])" -Name $_[1] -ErrorAction SilentlyContinue).($_[1])
        if ($null -eq $v) { 'absent' } elseif ($v -is [byte[]]) { ($v | ForEach-Object { $_.ToString('x2') }) -join '' } else { "$v" }
    }) -join ' | '
}
function Value($i) { (Get-ItemProperty -LiteralPath "HKCU:\$($values[$i][0])" -Name $values[$i][1] -ErrorAction SilentlyContinue).($values[$i][1]) }
function StartHost() { Start-Process $hostExe -ArgumentList '--no-hook', '--keep-banners'; Start-Sleep 5 }
function Stop-Clean() {
    Add-Type -Namespace TT -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);' -ErrorAction SilentlyContinue
    [void][TT.W]::PostMessageW([TT.W]::FindWindow('IiHostWindow', [NullString]::Value), 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep 4
}

Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$env:LOCALAPPDATA\ii-windows" -Recurse -Force -ErrorAction SilentlyContinue
& "$dist\bin\switchwall.exe" --mode dark --image "$env:USERPROFILE\Pictures\Wallpapers\sunset.png" | Out-Null
$baseline = Snapshot
"baseline: $baseline"

# 1. running: dark, accent, title bars
StartHost
Check 'dark mode while running' ((Value 0) -eq 0 -and (Value 1) -eq 0)
Check 'title bars use the accent' ((Value 5) -eq 1)
$accent = Get-Content "$env:LOCALAPPDATA\quickshell\State\user\generated\color.txt"
"source color $accent, DWM AccentColor 0x$('{0:x8}' -f (Value 2))"
Check 'backup written before changing' (Test-Path "$env:LOCALAPPDATA\ii-windows\theme.txt")
Start-Process explorer.exe "$env:USERPROFILE"
Start-Sleep 3
& "$dev\screenshot.ps1" -Out "$out\theme-dark.png" | Out-Null

# 2. ii goes light -> Windows follows
& "$dist\bin\switchwall.exe" --mode light --noswitch | Out-Null
Start-Sleep 5
Check 'light mode follows the palette' ((Value 0) -eq 1)
& "$dev\screenshot.ps1" -Out "$out\theme-light.png" | Out-Null

# 3. clean exit
Stop-Clean
Check 'clean exit: every value as before' ((Snapshot) -eq $baseline) "($(Snapshot))"
Check 'clean exit: backup removed' (-not (Test-Path "$env:LOCALAPPDATA\ii-windows\theme.txt"))
& "$dev\screenshot.ps1" -Out "$out\theme-restored.png" | Out-Null

# 4. host killed: the guard restores
StartHost
Get-CimInstance Win32_Process -Filter "Name='ii-host.exe'" | Where-Object { $_.CommandLine -notmatch '--guard' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 4
Check 'guard: every value as before' ((Snapshot) -eq $baseline)

# 5. everything killed: the rescue script restores
StartHost
Get-Process ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
Check 'rescue: every value as before' ((Snapshot) -eq $baseline) "($(Snapshot))"

Get-Process explorer | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.CloseMainWindow() | Out-Null }
"fails: $script:fails"
