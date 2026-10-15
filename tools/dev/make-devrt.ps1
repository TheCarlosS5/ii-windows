# A private runtime for trying new builds without touching the installed (verified) version:
# a copy of the installed quickshell folder where the ii-shim aliases and ii-host are the ones just built
# in host\build (and quickshell.exe the one in quickshell\build when there is one).
#   make-devrt.ps1 [-Dest <dir>]      default %USERPROFILE%\dev\ii-dev-runtime
# Then: run-dev.ps1 -Runtime <dir>
param([string]$Dest = "$env:USERPROFILE\dev\ii-dev-runtime", [switch]$NewQuickshell)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$inst = "$env:LOCALAPPDATA\Programs\ii-windows"
$cur = (Get-Content "$inst\current.txt" | Where-Object { $_ -like 'active=*' }) -replace 'active=', ''
$src = "$inst\versions\$cur"
if (-not (Test-Path "$src\quickshell\quickshell.exe")) { throw "no installed runtime at $src" }
New-Item -ItemType Directory -Force $Dest | Out-Null
robocopy "$src\quickshell" "$Dest\quickshell" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$shimNew = "$root\host\build\ii-shim.exe"
if (-not (Test-Path $shimNew)) { throw "build the host first (host\build\ii-shim.exe)" }
# Every exe in bin that is a copy of the shim gets the new one.
$oldShim = (Get-FileHash "$Dest\quickshell\bin\ii-shim.exe" -Algorithm SHA256).Hash
$n = 0
Get-ChildItem "$Dest\quickshell\bin" -Filter *.exe | ForEach-Object {
    if ((Get-FileHash $_.FullName -Algorithm SHA256).Hash -eq $oldShim) { Copy-Item $shimNew $_.FullName -Force; $n++ }
}
Copy-Item "$src\ii-host.exe" "$Dest\ii-host.exe" -Force
if (Test-Path "$root\host\build\ii-host.exe") { Copy-Item "$root\host\build\ii-host.exe" "$Dest\ii-host.exe" -Force }
$qsNew = "$root\quickshell\build\quickshell.exe"
$qsOld = "$src\quickshell\quickshell.exe"
if ($NewQuickshell -and (Test-Path $qsNew)) { Copy-Item $qsNew "$Dest\quickshell\quickshell.exe" -Force; "quickshell.exe: new build" }
"dev runtime at $Dest ($n shim aliases refreshed)"
