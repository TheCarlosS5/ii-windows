# Refresh dist\quickshell after a rebuild (exe + quickshell's own QML modules).
# Use -Full to rerun windeployqt (needed when new Qt modules are used).
param([switch]$Full)
$root = 'C:\Users\Calos\Desktop\ii-windows'
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
robocopy "$root\quickshell\build\qml_modules" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if (Test-Path "$root\third_party\fonts") {
    robocopy "$root\third_party\fonts" "$dist\fonts" /E /NFL /NDL /NJH /NJS /NP | Out-Null
}
if (Test-Path "$root\third_party\icons") {
    robocopy "$root\third_party\icons" "$dist\icons" /E /NFL /NDL /NJH /NJS /NP | Out-Null
}
# QML stand-ins for modules without a Windows backend yet
robocopy "$root\shim\qml" "$dist\qml" /E /NFL /NDL /NJH /NJS /NP | Out-Null
"deployed $((Get-Item "$dist\quickshell.exe").LastWriteTime)"
# ii-shim under the names of the Linux commands it stands in for
$shim = "$root\host\build\ii-shim.exe"
if (Test-Path $shim) {
    New-Item -ItemType Directory -Force "$dist\bin" | Out-Null
    foreach ($name in 'ii-shim', 'qalc', 'xdg-open', 'notify-send', 'playerctl', 'wpctl', 'pidof', 'killall', 'pkill', 'loginctl', 'bash', 'qs') {
        Copy-Item $shim "$dist\bin\$name.exe" -Force
    }
}
