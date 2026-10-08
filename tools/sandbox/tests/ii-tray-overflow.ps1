# INSIDE the sandbox: a tray icon Windows keeps hidden goes to ii's overflow menu (the arrow);
# once it is shown on the taskbar in Windows' settings (IsPromoted=1), it moves to the bar.
$out = 'C:\xchg\outbox'
$dev = 'C:\ii\tools\dev'
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$shell = Join-Path $local 'modules\ii\background\Background.qml'
$qml = Get-Content -LiteralPath $shell -Raw
$probe = Get-Content -LiteralPath 'C:\ii\tools\sandbox\tests\tray-probe.qml.inc' -Raw
[IO.File]::WriteAllText($shell, $qml.Replace('id: bgRoot', "id: bgRoot`n$probe"), (New-Object Text.UTF8Encoding $false))
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }
function State {
    $psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $local + '" ipc call trayTest state'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $text = $proc.StandardOutput.ReadToEndAsync()
    [void]$proc.WaitForExit(10000)
    return ($text.Result | ConvertFrom-Json)
}
$settings = 'HKCU:\Control Panel\NotifyIconSettings'
function TestEntries { Get-ChildItem $settings -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PSPath).ExecutablePath -like '*powershell.exe' } }
# A clean start: forget what Explorer remembered about earlier test icons.
TestEntries | Remove-Item -Recurse -Force

$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep 14
$app = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\ii\tools\sandbox\tests\tray-app.ps1', '-Seconds', '90', '-Name', 'oculto' -PassThru -WindowStyle Hidden
Start-Sleep 6
$s = State
"state: $($s | ConvertTo-Json -Compress)"
Check 'a new icon Windows hides goes to the overflow' (@($s.unpinned | Where-Object { $_ -like 'powershell*' }).Count -eq 1)
& "$dev\screenshot.ps1" -Out "$out\tray-overflow-bar.png" -H 60 | Out-Null

$entry = TestEntries | Select-Object -First 1
Check 'Explorer recorded the icon' ($null -ne $entry)
if ($entry) {
    Set-ItemProperty $entry.PSPath -Name IsPromoted -Value 1 -Type DWord
    Start-Sleep 2
    $s = State
    "state: $($s | ConvertTo-Json -Compress)"
    Check 'shown on the taskbar in Windows: moves to the bar' (@($s.pinned | Where-Object { $_ -like 'powershell*' }).Count -eq 1)
    & "$dev\screenshot.ps1" -Out "$out\tray-promoted-bar.png" -H 60 | Out-Null
    Set-ItemProperty $entry.PSPath -Name IsPromoted -Value 0 -Type DWord
    Start-Sleep 2
    Check 'hidden again: back to the overflow' (@((State).unpinned | Where-Object { $_ -like 'powershell*' }).Count -eq 1)
}
$app | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Process -Id $p.Id -Force
"fails: $script:fails"
