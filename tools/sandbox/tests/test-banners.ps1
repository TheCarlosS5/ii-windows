# INSIDE the sandbox: Windows' notification banners are off while ii-host runs and come back
# exactly as they were on clean exit, on a host crash (guard) and with the rescue script.
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path -LiteralPath 'C:\ii\host\build\ii-host.exe')) {
    throw 'This test must run inside the ii Windows Sandbox.'
}
$out = 'C:\xchg\outbox'
$hostExe = 'C:\ii\host\build\ii-host.exe'
$data = "$env:LOCALAPPDATA\ii-windows"
$settings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$ps = "$settings\{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
$other = "$settings\ii.test.App"   # an app whose user already turned banners off
$fresh = "$settings\ii.test.Fresh" # an app that first appears while ii runs
$script:fails = 0
function Check($name, $ok) { if ($ok) { "PASS $name" } else { "FAIL $name"; $script:fails++ } }
function Banner($key) { (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).ShowBanner }

Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$resolvedData = [IO.Path]::GetFullPath($data)
if (-not $resolvedData.StartsWith($env:USERPROFILE + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe test state path: $resolvedData"
}
Remove-Item -LiteralPath $resolvedData -Recurse -Force -ErrorAction SilentlyContinue
# A fresh Sandbox has no PowerShell notification registration until its first toast.
# Seed the existing-app case explicitly; $fresh below still tests late registration.
New-Item -Path $ps -Force | Out-Null
Set-ItemProperty -LiteralPath $ps -Name LastNotificationAddedTime -Value 1 -Type QWord
Remove-ItemProperty -LiteralPath $ps -Name ShowBanner -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $fresh -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $other)) { New-Item $other | Out-Null }
Set-ItemProperty -LiteralPath $other -Name ShowBanner -Value 0 -Type DWord
Set-ItemProperty -LiteralPath $other -Name Enabled -Value 1 -Type DWord

$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$cfg = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $cfg /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

function StartHost() {
    Start-Process $hostExe -ArgumentList '--shell', "`"$dist\quickshell.exe`"", '--config', "`"$cfg`"", '--no-hook'
    Start-Sleep 14
}

# --- 1. running: banners off, originals recorded
StartHost
Check 'powershell banner off while running' ((Banner $ps) -eq 0)
Check 'user-disabled app stays off' ((Banner $other) -eq 0)
Check 'backup file written' (Test-Path "$data\banners.txt")
New-Item $fresh | Out-Null
Set-ItemProperty -LiteralPath $fresh -Name LastNotificationAddedTime -Value 1 -Type QWord
Start-Sleep 3
Check 'app appearing later also gets banners off' ((Banner $fresh) -eq 0)

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Solo en ii</text><text>Windows no debe mostrar su banner</text></binding></visual></toast>')
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new($xml))
Start-Sleep 3
& C:\ii\tools\dev\screenshot.ps1 -Out "$out\banners-running.png" | Out-Null

# --- 2. clean exit (WM_CLOSE to the host window)
Add-Type -Namespace B -Name W -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);'
[B.W]::PostMessageW([B.W]::FindWindow('IiHostWindow', [NullString]::Value), 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep 4
Check 'clean exit: powershell value removed again' ($null -eq (Banner $ps))
Check 'clean exit: user-disabled app still off' ((Banner $other) -eq 0)
Check 'clean exit: fresh app value removed' ($null -eq (Banner $fresh))
Check 'clean exit: backup file gone' (-not (Test-Path "$data\banners.txt"))

# --- 3. host killed: the guard restores
StartHost
Check 'second run: banners off' ((Banner $ps) -eq 0)
Get-CimInstance Win32_Process -Filter "Name='ii-host.exe'" | Where-Object { $_.CommandLine -notmatch '--guard' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 4
Check 'guard: powershell value removed' ($null -eq (Banner $ps))
Check 'guard: backup file gone' (-not (Test-Path "$data\banners.txt"))

# --- 4. rescue script (host and guard gone, backup left behind)
StartHost
# Stop the guard first so it cannot recover before the rescue script is tested.
Get-CimInstance Win32_Process -Filter "Name='ii-host.exe'" | Where-Object { $_.CommandLine -match '--guard' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process ii-host, quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
Check 'rescue fixture: backup remains and banners are off' ((Test-Path "$data\banners.txt") -and (Banner $ps) -eq 0)
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\ii\tools\rescue\ii-rescue.ps1 | Out-Null
Check 'rescue: powershell value removed' ($null -eq (Banner $ps))
Check 'rescue: user-disabled app still off' ((Banner $other) -eq 0)
Check 'rescue: backup file gone' (-not (Test-Path "$data\banners.txt"))

Remove-Item -LiteralPath $other, $fresh -ErrorAction SilentlyContinue
"fails: $script:fails"
if ($script:fails -gt 0) { exit 1 }
