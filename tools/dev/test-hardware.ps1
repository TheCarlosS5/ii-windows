# Console-only, read-only hardware checks. No setters, discovery, consent or settings UI.
param([ValidateRange(1, 60)][int]$TimeoutSeconds = 15)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
. "$root\tools\dev\vsenv.ps1" *> $null
$crt = Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.*\x64\Microsoft.VC*.CRT' | Select-Object -Last 1
$env:PATH = "$($crt.FullName);$env:PATH"
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class IiHardwareErrorMode { [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode); }'
[IiHardwareErrorMode]::SetErrorMode(0x8003) | Out-Null
function Read-Command([string]$Exe, [string[]]$Arguments, [switch]$Silent) {
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Exe
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
    $p = [System.Diagnostics.Process]::Start($info)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        $p.Kill($true)
        throw "Read-only query timed out: $Exe $Arguments"
    }
    $result = [pscustomobject]@{ Text = $stdout.Result.TrimEnd(); Error = $stderr.Result.TrimEnd(); Code = $p.ExitCode }
    if (-not $Silent -or $result.Code -ne 0) {
        "COMMAND: $([IO.Path]::GetFileName($Exe)) $($Arguments -join ' ')" | Write-Host
        if (-not $Silent) {
            if ($result.Text) { $result.Text | Write-Host } else { '<empty stdout>' | Write-Host }
        }
        if ($result.Error) { "stderr: $($result.Error)" | Write-Host }
        "exit=$($result.Code)" | Write-Host
    }
    $p.Dispose()
    return $result
}
$shim = "$root\host\build\ii-shim.exe"
$probe = "$root\quickshell\build\ii-hardware-test.exe"
if (-not (Test-Path $probe)) { throw "Missing headless hardware probe: $probe" }
$status = Read-Command $probe @('--read-only')
if ($status.Code -ne 0) { throw 'Native battery/Bluetooth query failed' }
$json = $status.Text | ConvertFrom-Json
if (-not $json.qmlApi -or $json.normalizationChecks -ne 7 -or $json.bluetoothMembershipChecks -ne 4) { throw 'Headless QML API/state checks missing' }
if ($json.battery.available -eq $false -and $json.battery.isLaptopBattery -ne $false) { throw 'Absent battery must not be a laptop battery' }
if ($json.bluetooth.adapters -eq 0 -and $json.bluetooth.defaultAdapter -ne $null) { throw 'Absent radio must have a null defaultAdapter' }
$selfTest = Read-Command $shim @('brightness-win', 'self-test')
if ($selfTest.Code -ne 0) { throw 'Brightness coalescing/timeout tests failed' }
$list = Read-Command $shim @('brightness-win', 'list')
if ($list.Code -ne 0) { throw 'Windows brightness query failed' }
foreach ($monitor in ($list.Text | ConvertFrom-Json)) {
    if ($monitor.available -and ($monitor.max -le 0 -or $monitor.current -lt 0 -or $monitor.current -gt $monitor.max)) { throw 'Invalid brightness range' }
}
$detect = Read-Command $shim @('ddcutil', 'detect', '--brief')
if ($detect.Code -ne 0) { throw 'DDC enumeration failed' }
$buses = [regex]::Matches($detect.Text, '/dev/i2c-([^\r\n]+)')
if ($buses.Count -eq 0) {
    'DDC: no monitor exposed by this process (unavailable)' | Write-Host
    $absent = Read-Command $shim @('ddcutil', '-b', 'unavailable', 'getvcp', '10', '--brief')
    if ($absent.Code -ne 1 -or $absent.Text) { throw 'An absent brightness target must fail quietly without a value' }
}
foreach ($bus in $buses) {
    $read = Read-Command $shim @('ddcutil', '-b', $bus.Groups[1].Value.Trim(), 'getvcp', '10', '--brief')
    if ($read.Code -eq 0 -and $read.Text -notmatch '^VCP 10 C \d+ \d+$') { throw 'Unparseable brightness reply' }
    if ($read.Code -ne 0) { 'DDC: monitor became unavailable' | Write-Host }
}
$qmlFiles = @('services/Brightness.qml', 'modules/ii/sidebarRight/QuickSliders.qml',
    'modules/ii/sidebarRight/SidebarRightContent.qml', 'modules/ii/sidebarRight/bluetoothDevices/BluetoothDialog.qml',
    'modules/common/models/quickToggles/BluetoothToggle.qml', 'modules/ii/sidebarRight/quickToggles/classicStyle/BluetoothToggle.qml')
foreach ($file in $qmlFiles) {
    $syntax = Read-Command "$env:QTDIR\bin\qmlformat.exe" @('--ignore-settings', "$root\build\ii\$file") -Silent
    if ($syntax.Code -ne 0) { throw "QML syntax failed: $file" }
}
"QML parsed=$($qmlFiles.Count) failures=0" | Write-Host
foreach ($module in 'Quickshell/Bluetooth', 'Quickshell/Services/UPower') {
    if (Test-Path "$root/shim/qml/$module/qmldir") { throw "Retired placeholder still present: $module" }
    $directory = Get-Content "$root/quickshell/build/qml_modules/$module/qmldir" -Raw
    if ($directory -notmatch 'plugin quickshell-win32-') { throw "Native module not generated: $module" }
}
'native modules=2 remaining shim modules=4' | Write-Host
'hardware failures=0' | Write-Host
