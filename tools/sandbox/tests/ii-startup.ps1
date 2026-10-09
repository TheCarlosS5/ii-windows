# INSIDE the sandbox: how long ii takes to load its QML, cold and warm, with the real-file QML tree
# (compiled cache kept between starts) and the old qs: way (QS_NO_QMLTREE=1); and whether both
# produce the same warnings (the tree must not change behaviour).
$out = 'C:\xchg\outbox'
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Stop-Process -Force
$local = "$env:USERPROFILE\qs-config"
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$dist = "$env:USERPROFILE\ii-dist"
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
# Clean caches: the first start is a cold one.
Remove-Item "$env:LOCALAPPDATA\quickshell\cache\qmlcache", "$env:LOCALAPPDATA\quickshell\cache\by-shell" -Recurse -Force -ErrorAction SilentlyContinue
$script:fails = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS $name $detail" } else { "FAIL $name $detail"; $script:fails++ } }

function Run($label, [switch]$NoTree) {
    if ($NoTree) { $env:QS_NO_QMLTREE = '1' } else { Remove-Item Env:QS_NO_QMLTREE -ErrorAction SilentlyContinue }
    $before = @(Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $p = Start-Process "$dist\quickshell.exe" -ArgumentList '-p', "`"$local`"" -PassThru
    $log = $null
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep 1
        $log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Where-Object { $before -notcontains $_.FullName -and (Get-Content $_.FullName -TotalCount 1) -match 'shell\.qml' } | Select-Object -First 1
        if ($log -and (Select-String -Path $log.FullName -Pattern 'Configuration Loaded' -Quiet)) { break }
    }
    Start-Sleep 6
    $lines = Get-Content $log.FullName
    $t = { param($l) [datetime]::ParseExact($l.Substring(0, 23), 'yyyy-MM-dd HH:mm:ss.fff', $null) }
    $start = & $t ($lines | Select-Object -First 1)
    $loaded = & $t ($lines | Select-String 'Configuration Loaded' | Select-Object -First 1).Line
    $secs = ($loaded - $start).TotalSeconds
    $tree = ($lines | Select-String 'qmltree' | ForEach-Object { $_.Line.Substring(24) }) -join ' '
    Stop-Process -Id $p.Id -Force; Start-Sleep 2
    Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
    $warn = $lines | Select-String 'WARN|ERROR' | ForEach-Object { ($_.Line.Substring(24) -replace 'file:///[^\s\]]*/qs/', '@' -replace '\d+:\d+:\d+\.\d+', '') }
    [pscustomobject]@{ Label = $label; Seconds = $secs; Tree = $tree; Warnings = @($warn | Sort-Object -Unique) }
}

$cold = Run 'tree, cold'
$warm = Run 'tree, warm'
$warm2 = Run 'tree, warm again'
$old = Run 'qs: (old way)' -NoTree
foreach ($r in $cold, $warm, $warm2, $old) { "{0}: QML loaded in {1:N1} s {2}" -f $r.Label, $r.Seconds, $r.Tree }
$qmlc = @(Get-ChildItem "$env:LOCALAPPDATA\quickshell\cache\qmlcache" -Filter *.qmlc -ErrorAction SilentlyContinue).Count
"compiled QML files in the cache: $qmlc"
Check 'the compiled cache is used (hundreds of files)' ($qmlc -gt 300) "($qmlc)"
Check 'warm start is not slower than the old way' ($warm2.Seconds -le $old.Seconds * 1.1) ("({0:N1} s vs {1:N1} s)" -f $warm2.Seconds, $old.Seconds)
# commandPrefix / ToolbarTabBar warnings come and go with load order (upstream ii, both ways).
$onlyTree = $warm2.Warnings | Where-Object { $old.Warnings -notcontains $_ -and $_ -notmatch 'commandPrefix|ToolbarTabBar' }
$onlyOld = $old.Warnings | Where-Object { $warm2.Warnings -notcontains $_ }
Check 'no warnings that the old way does not have' (-not $onlyTree) "($(@($onlyTree).Count))"
$onlyTree | Select-Object -First 15 | ForEach-Object { "  tree only: $_" }
$onlyOld | Select-Object -First 15 | ForEach-Object { "  old only: $_" }
"fails: $script:fails"
