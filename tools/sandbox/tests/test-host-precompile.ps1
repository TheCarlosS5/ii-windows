# Plan 1.3: before it starts the real shell, ii-host compiles the QML into Qt's disk cache in a separate process when
# this config was never compiled or the cache was emptied, and not when both are in place. Real ii-host.exe and the
# real quickshell.exe (dist) on a tiny config that opens no window; the cache is a throwaway folder
# (QML_DISK_CACHE_PATH) and II_TEST_PRECOMPILE=1 lets a test host do it. Needs: cmake --build host\build-clang.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
Require-IiHostBuild
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$shell = "$repo\dist\quickshell\quickshell.exe"
if (-not (Test-Path $shell)) { Skip-Test 'dist\quickshell\quickshell.exe not deployed (tools\dev\deploy.ps1)' }

$base = New-IiTestDir 'ii-precompile'
$cfg = Join-Path $base 'cfg'
$cache = Join-Path $base 'qmlcache'
New-Item -ItemType Directory -Force $cfg, $cache | Out-Null
Set-Content (Join-Path $cfg 'shell.qml') "import QtQuick`nimport Quickshell`nShellRoot { Item {} }`n"
Set-Content (Join-Path $cfg 'Extra.qml') "import QtQuick`nItem { property int answer: 42 }`n"
$envs = @{ II_TEST_PRECOMPILE = 1; QML_DISK_CACHE_PATH = $cache }
try {
    # ---- a: never compiled: compiled first, in its own process, and remembered ----------------------------------
    $data = Join-Path $base 'a-data'
    $p = Start-IiHost $shell $cfg $data $envs
    Assert-True (Wait-IiLog $data 'compiling the QML first' 30) 'a config never compiled is compiled before the shell starts'
    Assert-True (Wait-IiLog $data 'QML compiled  in \d+ ms' 120) 'completely, in a separate process'
    Assert-True (@(Get-ChildItem $cache -Recurse -Filter *.qmlc).Count -ge 1) 'into the cache folder Qt uses'
    $ini = Get-Content (Join-Path $data 'state.ini') -Raw
    Assert-True ($ini -match '(?m)^compiledFor=' + [regex]::Escape($cfg) + '\s*$') 'and remembered for this config'
    Assert-True (Wait-IiLog $data 'shell: started pid' 20) 'then the shell starts'
    Send-IiWmClose $p.Id | Out-Null
    Wait-IiExit $p 20 | Out-Null
    Get-IiProcessesAt $shell | Where-Object { $_ } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

    # ---- b: compiled for this config and a full cache: no second compile ------------------------------------------
    foreach ($i in 1..300) { Set-Content (Join-Path $cache "filler-$i.qmlc") 'x' }
    $p = Start-IiHost $shell $cfg $data $envs
    Assert-True (Wait-IiLog $data '(?s)QML compiled.*shell: started pid.*shell: started pid' 30) 'the next start starts the shell'
    $log = Get-IiHostLog $data
    Assert-Equal ([regex]::Matches($log, 'compiling the QML first')).Count 1 'without compiling again'
    Send-IiWmClose $p.Id | Out-Null
    Wait-IiExit $p 20 | Out-Null
}
finally {
    Get-IiProcessesAt $shell | Where-Object { $_ } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
