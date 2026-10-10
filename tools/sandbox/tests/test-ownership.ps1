# R04: the uninstaller's data removal only touches what ii owns.
# Runs against a throwaway LOCALAPPDATA built under %TEMP%; never reads or writes the real one.
# Invariants checked:
#   - another Quickshell config (and its state/cache) survives, with and without -KeepConfig
#   - ii's own config/state/cache/secrets go, or stay, exactly as the switches say
#   - a junction inside ii's tree is removed as a link; the folder it points to is untouched
#   - a junction in place of an owned folder is unlinked, never followed
#   - an install.json that names an outside path (or is garbage) cannot make anything else disappear
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\..\package\ii-ownership.ps1"

$base = Join-Path $env:TEMP ('ii-own-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$outside = Join-Path $base 'outside-user-data'
New-Item -ItemType Directory -Force $outside | Out-Null
Set-Content -LiteralPath (Join-Path $outside 'precious.txt') 'do not delete'

function New-FakeLocalAppData([string]$Name) {
    $lad = Join-Path $base $Name
    $qs = Join-Path $lad 'quickshell'
    $data = Join-Path $lad 'ii-windows'
    foreach ($d in @(
        "$qs\illogical-impulse", "$qs\State\user\generated", "$qs\cache\notifications",
        "$qs\other-config", "$qs\State\other-shell", "$qs\cache\by-shell\abc123",
        "$data\cache\appicons", "$data\secrets", "$data\backup\20260101-000000"
    )) { New-Item -ItemType Directory -Force $d | Out-Null }
    Set-Content "$qs\illogical-impulse\config.json" '{}'
    Set-Content "$qs\State\user\generated\colors.json" '{}'
    Set-Content "$qs\cache\notifications\notifications.json" '[]'
    Set-Content "$qs\other-config\shell.qml" 'import Quickshell'
    Set-Content "$qs\State\other-shell\state.json" '{}'
    Set-Content "$qs\cache\by-shell\abc123\keep.bin" 'x'
    Set-Content "$data\cache\appicons\a.png" 'x'
    Set-Content "$data\secrets\k.bin" 'x'
    Set-Content "$data\backup\20260101-000000\x.reg" 'x'
    return $lad
}

# 1. default uninstall (no switches)
$lad = New-FakeLocalAppData 'default'
$qs = "$lad\quickshell"
$msgs = Invoke-IiDataRemoval -LocalAppData $lad
Assert-PathMissing "$qs\illogical-impulse" 'ii config removed'
Assert-PathMissing "$qs\State\user" 'ii state removed'
Assert-PathMissing "$qs\cache\notifications" 'ii notification history removed'
Assert-PathMissing "$lad\ii-windows\cache" 'ii icon cache removed'
Assert-PathMissing "$lad\ii-windows\secrets" 'secrets removed when nothing says to keep them'
Assert-PathExists "$qs\other-config\shell.qml" 'another quickshell config survives'
Assert-PathExists "$qs\State\other-shell\state.json" "another shell's state survives"
Assert-PathExists "$qs\cache\by-shell\abc123\keep.bin" 'shared quickshell cache survives'
Assert-PathExists "$lad\ii-windows\backup\20260101-000000\x.reg" 'registry backups survive'

# 2. -KeepConfig keeps everything of ii's, secrets included, and still leaves others alone
$lad = New-FakeLocalAppData 'keepconfig'
$qs = "$lad\quickshell"
[void](Invoke-IiDataRemoval -LocalAppData $lad -KeepConfig)
Assert-PathExists "$qs\illogical-impulse\config.json" 'KeepConfig keeps the config'
Assert-PathExists "$qs\State\user\generated\colors.json" 'KeepConfig keeps generated state'
Assert-PathExists "$lad\ii-windows\secrets\k.bin" 'KeepConfig keeps secrets so a reinstall still works'
Assert-PathExists "$qs\other-config\shell.qml" 'another config survives KeepConfig too'

# 3. -KeepSecrets alone deletes the config but keeps the keys
$lad = New-FakeLocalAppData 'keepsecrets'
$qs = "$lad\quickshell"
[void](Invoke-IiDataRemoval -LocalAppData $lad -KeepSecrets)
Assert-PathMissing "$qs\illogical-impulse" 'KeepSecrets still removes the config'
Assert-PathExists "$lad\ii-windows\secrets\k.bin" 'KeepSecrets keeps the keys'

# 4. a junction inside an owned folder, pointing at user data outside
$lad = New-FakeLocalAppData 'junction-inside'
$qs = "$lad\quickshell"
& cmd.exe /c "mklink /J `"$qs\illogical-impulse\linked-out`" `"$outside`"" | Out-Null
Assert-PathExists "$qs\illogical-impulse\linked-out\precious.txt" 'fixture: the junction resolves to the outside folder'
[void](Invoke-IiDataRemoval -LocalAppData $lad)
Assert-PathMissing "$qs\illogical-impulse" 'owned folder with a junction inside is removed'
Assert-PathExists "$outside\precious.txt" 'the junction target was NOT walked or deleted'

# 5. the owned folder itself is a junction to outside
$lad = New-FakeLocalAppData 'junction-owned'
$qs = "$lad\quickshell"
Remove-Item -LiteralPath "$qs\illogical-impulse" -Recurse -Force
& cmd.exe /c "mklink /J `"$qs\illogical-impulse`" `"$outside`"" | Out-Null
[void](Invoke-IiDataRemoval -LocalAppData $lad)
Assert-PathMissing "$qs\illogical-impulse" 'the link itself is gone'
Assert-PathExists "$outside\precious.txt" 'its target is untouched'

# 6. an ancestor is a junction: the path resolves outside, so nothing under it is touched
$lad = New-FakeLocalAppData 'junction-ancestor'
$qs = "$lad\quickshell"
Remove-Item -LiteralPath "$qs\State" -Recurse -Force
New-Item -ItemType Directory -Force "$outside\user\generated" | Out-Null
Set-Content "$outside\user\generated\mine.txt" 'x'
& cmd.exe /c "mklink /J `"$qs\State`" `"$outside`"" | Out-Null
$r = Remove-IiOwnedTree -Path "$qs\State\user" -AllowedRoot $qs
Assert-True ($r.Removed -eq 0 -and $r.Skipped.Count -eq 1) 'a path through a link is refused and reported'
Assert-PathExists "$outside\user\generated\mine.txt" 'data behind the ancestor link survives'

# 7. refusals: outside the root, the root itself, a drive root, a sibling with a shared prefix
$lad = New-FakeLocalAppData 'refusals'
$qs = "$lad\quickshell"
Assert-True ((Remove-IiOwnedTree -Path $outside -AllowedRoot $qs).Removed -eq 0) 'a path outside the allowed root is refused'
Assert-True ((Remove-IiOwnedTree -Path $qs -AllowedRoot $qs).Removed -eq 0) 'the allowed root itself is refused'
Assert-True ((Remove-IiOwnedTree -Path 'C:\Windows' -AllowedRoot 'C:\').Removed -eq 0) 'a drive root is never an allowed root'
New-Item -ItemType Directory -Force "${qs}-sibling" | Out-Null
Assert-True (-not (Test-IiPathInside "${qs}-sibling" $qs)) 'quickshell-sibling is not inside quickshell'
Assert-True (-not (Test-IiPathInside "$qs\..\ii-windows" $qs)) 'dot-dot escapes are resolved before comparing'
Assert-PathExists $outside 'the outside fixture is still there'

# 8. a corrupt / hostile install.json cannot widen what is deleted: the removal never reads it
$lad = New-FakeLocalAppData 'manifest'
$qs = "$lad\quickshell"
Set-Content "$lad\ii-windows\install.json" ('{ "dataDir": "' + ($outside -replace '\\', '\\') + '", "installDir": "C:\\Windows", "owned": ["' + ($outside -replace '\\', '\\') + '"], "fonts": [ ')
[void](Invoke-IiDataRemoval -LocalAppData $lad)
Assert-PathExists "$outside\precious.txt" 'a manifest naming an outside folder deleted nothing there'
Assert-PathExists 'C:\Windows\System32' 'nothing system-wide was touched'

# 9. processes: only executables under the install dir are selected
$install = Join-Path $base 'Programs\ii-windows'
Assert-True (Test-IiPathInside "$install\quickshell\quickshell.exe" $install) 'an exe under the install dir is ours'
Assert-True (-not (Test-IiPathInside 'C:\Other\quickshell.exe' $install)) 'a quickshell.exe elsewhere is not ours'

Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
Complete-IiTest
