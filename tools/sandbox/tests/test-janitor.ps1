# Plan 2026-10-31, D4: ii-shim janitor keeps ii's caches bounded, on fake folders (II_DATA_DIR, II_JANITOR_LOCALAPPDATA,
# II_JANITOR_TEMP): nothing of the real user's is touched.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$shim = @("$repo\host\build\ii-shim.exe", "$repo\host\build-clang\ii-shim.exe") | Where-Object { Test-Path $_ } | Sort-Object { (Get-Item $_).LastWriteTime } | Select-Object -Last 1
if (-not $shim) { Skip-Test 'ii-shim.exe not built' }
$b = Join-Path $env:TEMP ('ii-janitor-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    foreach ($d in 'temp\ii-windows\mpris', 'temp\ii-windows\tray', 'local\quickshell\cache\by-shell\a', 'local\quickshell\cache\by-shell\b',
                   'local\quickshell\cache\by-shell\c', 'local\quickshell\cache\qmlcache', 'temp\quickshell\by-pid\1', 'data\update\old-1', 'data\update\0.7.0-x') {
        New-Item -ItemType Directory -Force "$b\$d" | Out-Null
    }
    1..3 | ForEach-Object { Set-Content "$b\temp\ii-windows\mpris\$_.img" 'x' }
    1..510 | ForEach-Object { Set-Content "$b\temp\ii-windows\tray\$_.png" 'x' }
    foreach ($n in 'a', 'b', 'c') {
        New-Item -ItemType Directory -Force "$b\local\quickshell\cache\by-shell\$n\qmltree\qs\modules\ii" | Out-Null # ii's own
        Set-Content "$b\local\quickshell\cache\by-shell\$n\f.qml" 'x'
    }
    New-Item -ItemType Directory -Force "$b\local\quickshell\cache\by-shell\other" | Out-Null # another shell's: never touched
    (Get-Item "$b\local\quickshell\cache\by-shell\other").LastWriteTime = (Get-Date).AddDays(-90)
    (Get-Item "$b\local\quickshell\cache\by-shell\a").LastWriteTime = (Get-Date).AddDays(-60)
    (Get-Item "$b\local\quickshell\cache\by-shell\b").LastWriteTime = (Get-Date).AddDays(-50)
    (Get-Item "$b\local\quickshell\cache\by-shell\c").LastWriteTime = (Get-Date).AddDays(-40)
    Set-Content "$b\local\quickshell\cache\qmlcache\old.qmlc" 'x'
    (Get-Item "$b\local\quickshell\cache\qmlcache\old.qmlc").LastWriteTime = (Get-Date).AddDays(-45)
    Set-Content "$b\local\quickshell\cache\qmlcache\new.qmlc" 'x'
    Set-Content "$b\temp\quickshell\by-pid\1\log.log" 'x'
    (Get-Item "$b\temp\quickshell\by-pid\1").LastWriteTime = (Get-Date).AddDays(-9)
    '{"status":"available","latest":{"id":"0.7.0-x"}}' | Set-Content "$b\data\update\state.json"

    $env:II_DATA_DIR = "$b\data"; $env:II_JANITOR_LOCALAPPDATA = "$b\local"; $env:II_JANITOR_TEMP = "$b\temp"
    $dry = & $shim janitor --dry-run
    Assert-True ($dry -match 'dry run') "a dry run says what it would do ($dry)"
    Assert-Equal (Get-ChildItem "$b\temp\ii-windows\tray").Count 510 'a dry run removes nothing'
    $out = & $shim janitor
    Write-Output $out
    Assert-PathMissing "$b\temp\ii-windows\mpris" "the covers' old folder is gone"
    Assert-Equal (Get-ChildItem "$b\temp\ii-windows\tray").Count 500 'the newest 500 tray icons stay'
    Assert-Equal ((Get-ChildItem "$b\local\quickshell\cache\by-shell").Name -join ',') 'b,c,other' "an old prepared tree of ii goes, the 2 newest always stay, another shell's is never touched"
    Assert-Equal ((Get-ChildItem "$b\local\quickshell\cache\qmlcache").Name -join ',') 'new.qmlc' 'compiled QML unused for 30 days goes'
    Assert-PathMissing "$b\temp\quickshell\by-pid\1" 'shell logs older than 7 days go'
    Assert-Equal ((Get-ChildItem "$b\data\update" -Directory).Name -join ',') '0.7.0-x' 'only the download of the version on offer stays'
} finally {
    Remove-Item Env:II_DATA_DIR, Env:II_JANITOR_LOCALAPPDATA, Env:II_JANITOR_TEMP -ErrorAction SilentlyContinue
    Remove-Item $b -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
