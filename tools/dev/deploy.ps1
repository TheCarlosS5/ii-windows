# Refresh dist\quickshell after a rebuild (exe + quickshell's own QML modules).
# Use -Full to rerun windeployqt (needed when new Qt modules are used).
#   -Build <dir>   the Quickshell build folder (default: quickshell\build, else quickshell\build-r)
# Qt comes from $env:QTDIR (default %USERPROFILE%\dev\Qt). The C++ runtime comes from the Visual Studio
# Build Tools redistributable when it is installed, else from the portable MSVC ($env:II_MSVC_DIR, see
# vsenv-portable.ps1), so nothing here depends on where Visual Studio is.
param([switch]$Full, [string]$Build = '')
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$dist = "$root\dist\quickshell"
if (-not $Build) {
    $Build = @("$root\quickshell\build", "$root\quickshell\build-r") | Where-Object { Test-Path "$_\quickshell.exe" } | Select-Object -First 1
    if (-not $Build) { throw 'no quickshell.exe in quickshell\build or quickshell\build-r: build the fork first' }
}
if (-not (Test-Path "$Build\quickshell.exe")) { throw "no quickshell.exe in $Build" }
$qt = if ($env:QTDIR) { $env:QTDIR } else { "$env:USERPROFILE\dev\Qt" }
if ($Full -or -not (Test-Path "$dist\Qt6Core.dll")) {
    New-Item -ItemType Directory -Force $dist | Out-Null
    Copy-Item "$Build\quickshell.exe" $dist -Force
    $deploy = Join-Path $qt 'bin\windeployqt.exe'
    if (-not (Test-Path $deploy)) { throw "windeployqt not found at $deploy (set QTDIR)" }
    $env:Path = (Join-Path $qt 'bin') + ';' + $env:Path
    & $deploy --release --no-compiler-runtime --no-translations --qmldir "$root\upstream\dots\.config\quickshell\ii" --qmldir "$root\overlay" --qmldir "$root\prototypes" "$dist\quickshell.exe" | Select-Object -Last 1
    $crt = Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.*\x64\Microsoft.VC*.CRT' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($crt) {
        Copy-Item "$($crt.FullName)\*.dll" $dist -Force
    } else {
        $msvc = if ($env:II_MSVC_DIR) { $env:II_MSVC_DIR } else { "$env:USERPROFILE\dev\toolchain\msvc\msvc" }
        $toolDir = Get-ChildItem "$msvc\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1
        if (-not $toolDir) { throw 'no C++ runtime found (Visual Studio Build Tools redistributable or the portable MSVC)' }
        foreach ($n in 'concrt140', 'msvcp140', 'msvcp140_1', 'msvcp140_2', 'msvcp140_atomic_wait', 'msvcp140_codecvt_ids', 'vccorlib140', 'vcruntime140', 'vcruntime140_1', 'vcruntime140_threads') {
            $f = Join-Path $toolDir.FullName "bin\Hostx64\x64\$n.dll"
            if (Test-Path $f) { Copy-Item $f $dist -Force }
        }
    }
}
Copy-Item "$Build\quickshell.exe" $dist -Force
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
robocopy "$Build\qml_modules" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
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
        $env:Path = (Join-Path $qt 'bin') + ';' + $env:Path
        & python -I "$root\tools\dev\pack_icons.py" "$root\third_party\icons" $rcc | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'pack_icons.py failed (is Qt rcc on PATH? set QTDIR)' }
    }
}
# QML stand-ins for modules without a Windows backend yet
robocopy "$root\shim\qml" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
"deployed $((Get-Item "$dist\quickshell.exe").LastWriteTime) from $Build"
# ii-shim under the names of the Linux commands it stands in for (built with clang-cl: host\build-clang)
$shim = @("$root\host\build-clang\ii-shim.exe", "$root\host\build\ii-shim.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($shim) {
    New-Item -ItemType Directory -Force "$dist\bin" | Out-Null
    foreach ($name in 'ii-shim', 'qalc', 'xdg-open', 'notify-send', 'playerctl', 'wpctl', 'pidof', 'killall', 'pkill', 'loginctl', 'bash', 'qs', 'switchwall', 'test', 'magick', 'ddcutil', 'brightnessctl', 'cava', 'ydotool', 'secret-tool', 'cliphist', 'hyprpicker', 'trans', 'ls', 'mkdir', 'rm', 'which') {
        Copy-Item $shim "$dist\bin\$name.exe" -Force
    }
} else {
    throw 'ii-shim.exe not built (cmake --build host\build-clang --target ii-shim, with clang-cl on PATH)'
}
