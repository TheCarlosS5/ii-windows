# End-to-end check of prototype A (run from anywhere with pwsh).
$root = 'C:\Users\Calos\Desktop\ii-windows'
$dev = "$root\tools\dev"
$here = "$root\prototypes\qs-bar"
$env:Path = "C:\Users\Calos\dev\Qt\6.12.0-msvc2022_64\bin;$env:Path"
$env:QML_IMPORT_PATH = "$root\quickshell\build\qml_modules"

"before:  " + (& "$dev\probe.ps1" workarea)
$psi = New-Object System.Diagnostics.ProcessStartInfo "$root\quickshell\build\quickshell.exe"
[void]$psi.ArgumentList.Add('-p'); [void]$psi.ArgumentList.Add("$here\shell.qml")
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep -Milliseconds 3000

"running: " + (& "$dev\probe.ps1" workarea)
& "$dev\screenshot.ps1" -Out "$here\shot-top.png" -H 140 | Out-Null
& "$dev\probe.ps1" hittest -X 960 -Y 20     # bar body: should be quickshell
& "$dev\probe.ps1" hittest -X 6 -Y 46       # rounded corner area: should pass through
& "$dev\probe.ps1" hittest -X 960 -Y 55     # below the bar inside the window: pass through
$p.Refresh()
"memory:  working set {0:N1} MB, private {1:N1} MB, cpu {2:N2} s after {3:N1} s" -f ($p.WorkingSet64 / 1MB), ($p.PrivateMemorySize64 / 1MB), $p.TotalProcessorTime.TotalSeconds, $sw.Elapsed.TotalSeconds
Start-Sleep -Milliseconds 5000
$p.Refresh()
"cpu idle: {0:N2} s total after {1:N1} s (animations running)" -f $p.TotalProcessorTime.TotalSeconds, $sw.Elapsed.TotalSeconds

$p.WaitForExit(40000) | Out-Null
"after:   " + (& "$dev\probe.ps1" workarea) + "  (exit code $($p.ExitCode))"
