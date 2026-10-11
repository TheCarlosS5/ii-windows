# Refresh dist\quickshell after a rebuild (exe + quickshell's own QML modules).
# Use -Full to rerun windeployqt (needed when new Qt modules are used).
param([switch]$Full)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$dist = "$root\dist\quickshell"
if ($Full -or -not (Test-Path "$dist\Qt6Core.dll")) {
    . "$root\tools\dev\vsenv.ps1" *> $null
    New-Item -ItemType Directory -Force $dist | Out-Null
    Copy-Item "$root\quickshell\build\quickshell.exe" $dist -Force
    windeployqt --release --no-compiler-runtime --no-translations --qmldir "$root\upstream\dots\.config\quickshell\ii" --qmldir "$root\overlay" --qmldir "$root\prototypes" "$dist\quickshell.exe" | Select-Object -Last 1
    $crt = Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.*\x64\Microsoft.VC*.CRT' | Select-Object -Last 1
    Copy-Item "$($crt.FullName)\*.dll" $dist -Force
}
Copy-Item "$root\quickshell\build\quickshell.exe" $dist -Force
# Remove files from the retired QML placeholders before copying native qmldirs.
# Literal file paths only: preserve other modules and never delete a directory.
foreach ($module in @(
    @{ Path = 'Quickshell\Bluetooth'; Files = @('Bluetooth', 'BluetoothAdapter', 'BluetoothAdapterState', 'BluetoothDevice', 'BluetoothDeviceState') },
    @{ Path = 'Quickshell\Services\UPower'; Files = @('UPower', 'UPowerDevice', 'UPowerDeviceState', 'UPowerDeviceType', 'PowerProfiles', 'PowerProfile', 'PerformanceDegradationReason') }
)) {
    foreach ($name in $module.Files) {
        Remove-Item -LiteralPath "$dist\qml\$($module.Path)\$name.qml" -Force -ErrorAction SilentlyContinue
    }
}
robocopy "$root\quickshell\build\qml_modules" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if (Test-Path "$root\third_party\fonts") {
    # Every font is loaded into the shell's memory at startup: skip the ones no QML uses
    # (Material Symbols Outlined, 10 MB; Rubik).
    robocopy "$root\third_party\fonts" "$dist\fonts" /MIR /XF 'MaterialSymbolsOutlined*' 'Rubik*' /NFL /NDL /NJH /NJS /NP | Out-Null
    # /MIR keeps excluded files that are already there.
    Get-ChildItem "$dist\fonts" -File | Where-Object { $_.Name -like 'MaterialSymbolsOutlined*' -or $_.Name -like 'Rubik*' } | Remove-Item -Force
}
if (Test-Path "$root\third_party\icons") {
    # One compressed resource instead of ~40k files (Quickshell registers icons.rcc at startup).
    Remove-Item "$dist\icons" -Recurse -Force -ErrorAction SilentlyContinue
    $rcc = "$dist\icons.rcc"
    $newest = (Get-ChildItem "$root\third_party\icons" -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
    if (-not (Test-Path $rcc) -or (Get-Item $rcc).LastWriteTime -lt $newest) {
        & python -I "$root\tools\dev\pack_icons.py" "$root\third_party\icons" $rcc | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'pack_icons.py failed (is Qt rcc on PATH? dot-source vsenv.ps1)' }
    }
}
# QML stand-ins for modules without a Windows backend yet
robocopy "$root\shim\qml" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
"deployed $((Get-Item "$dist\quickshell.exe").LastWriteTime)"
# ii-shim under the names of the Linux commands it stands in for
$shim = "$root\host\build\ii-shim.exe"
if (Test-Path $shim) {
    New-Item -ItemType Directory -Force "$dist\bin" | Out-Null
    foreach ($name in 'ii-shim', 'qalc', 'xdg-open', 'notify-send', 'playerctl', 'wpctl', 'pidof', 'killall', 'pkill', 'loginctl', 'bash', 'qs', 'switchwall', 'test', 'magick', 'ddcutil', 'brightnessctl', 'cava', 'ydotool', 'secret-tool', 'cliphist', 'hyprpicker', 'trans', 'ls', 'mkdir', 'rm', 'which') {
        Copy-Item $shim "$dist\bin\$name.exe" -Force
    }
}
