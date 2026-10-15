# The development loop in one go: stop the running ii (staging over files a running shell holds fails),
# stage the QML, check it loads (smoke), start the dev shell on the private runtime.
#   redev.ps1 [-Scale 1.25] [-WaitSec 35] [-NoSmoke] [-Shot out.png]
# Needs the private runtime (tools\dev\make-devrt.ps1) once, and again after a host/shim build.
param([double]$Scale = 0, [int]$WaitSec = 35, [switch]$NoSmoke, [string]$Shot = '')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$rt = "$env:USERPROFILE\dev\ii-dev-runtime"
& "$PSScriptRoot\run-dev.ps1" -Stop | Out-Null
$staged = & pwsh -NoProfile -File "$PSScriptRoot\stage-ii.ps1" 2>&1
if ($LASTEXITCODE -ne 0) { $staged | Select-Object -Last 12 | Out-String | Write-Output; throw 'stage-ii failed' }
$staged | Select-Object -Last 1
if (-not $NoSmoke) {
    $out = & pwsh -NoProfile -File "$PSScriptRoot\smoke-shell.ps1" -Quickshell "$rt\quickshell\quickshell.exe" -TimeoutSec 90 2>&1
    $out | Select-Object -First 8 | Out-String | Write-Output
    if ($LASTEXITCODE -ne 0) { throw 'smoke failed: the QML does not load' }
}
$args2 = @{ Runtime = $rt; WaitSec = $WaitSec }
if ($Scale -gt 0) { $args2.Scale = $Scale }
if ($Shot) { $args2.Shot = $Shot }
& "$PSScriptRoot\run-dev.ps1" @args2 | Out-Null
Get-Content "$env:LOCALAPPDATA\ii-windows\host.log" | Select-String 'bench' | Select-Object -Last 6 | ForEach-Object { $_.Line }
