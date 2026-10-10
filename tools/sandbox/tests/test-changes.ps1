# R08: ownership of external changes survives upgrades and never overwrites the user's later choice.
# Works on a throwaway key under HKCU (Software\ii-windows-test\<guid>), never on a real setting.
# Matrix: value absent / pre-existing / owned by ii / changed by the user afterwards, for String,
# DWord, ExpandString and Binary values, upgrade, repeated install and uninstall, legacy manifest.
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\..\package\ii-changes.ps1"

$root = "Software\ii-windows-test\$([guid]::NewGuid().ToString('N').Substring(0, 8))"
function NewManifest { [pscustomobject]@{ changes = @() } }
function Cur([string]$name) { Read-IiRegValue $root $name }
function RoundTrip($m) { ($m | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }   # what the manifest does on disk between runs

try {
    $gpu = 'GpuPreference=1;'

    # --- absent -> ours -> restored = absent again ---------------------------------------------------
    $m = NewManifest
    Assert-Equal (Set-IiOwnedRegValue $m 'a' $root 'ExeA' $gpu 'String') 'applied' 'an absent value is created and recorded'
    Assert-Equal (Cur 'ExeA').Value $gpu 'and has the value ii wanted'
    $m = RoundTrip $m
    Assert-Equal (Restore-IiOwnedRegValue $m 'a') 'deleted' 'uninstall deletes it, because it did not exist before'
    Assert-True (-not (Cur 'ExeA').Exists) 'it is gone'
    Assert-Equal @($m.changes).Count 0 'and the record is dropped'

    # --- pre-existing and equal to ours: still not ours -------------------------------------------
    Write-IiRegValue $root 'ExeB' $gpu 'String'
    $m = NewManifest
    Assert-Equal (Set-IiOwnedRegValue $m 'b' $root 'ExeB' $gpu 'String') 'foreign-existing' 'a value that already exists is left alone even if it equals the recommended one'
    Assert-Equal @($m.changes).Count 0 'and nothing is recorded'
    Assert-Equal (Restore-IiOwnedRegValue $m 'b') 'nothing-recorded' 'so uninstall has nothing to undo'
    Assert-Equal (Cur 'ExeB').Value $gpu 'and the user value is still there'

    # --- pre-existing, explicitly taken over, then restored exactly --------------------------------
    Write-IiRegValue $root 'Scheme' 'Windows Default' 'String'
    $m = NewManifest
    Assert-Equal (Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata' 'String' -TakeOver) 'taken-over' 'taking over records the original first'
    $m = RoundTrip $m
    Assert-Equal (Restore-IiOwnedRegValue $m 'c') 'restored' 'uninstall puts the original back'
    Assert-Equal (Cur 'Scheme').Value 'Windows Default' 'exactly'

    # --- upgrade: ii's own value is not mistaken for the user's original -----------------------------
    Write-IiRegValue $root 'Scheme' 'Windows Default' 'String'
    $m = NewManifest
    [void](Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata' 'String' -TakeOver)
    $m = RoundTrip $m
    Assert-Equal (Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata' 'String' -TakeOver) 'kept-ours' 'reinstalling the same thing changes nothing'
    Assert-Equal (Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata 2' 'String' -TakeOver) 'updated-ours' 'a newer value of ours is applied over ours'
    Assert-Equal @($m.changes).Count 1 'still one record'
    $m = RoundTrip $m
    Assert-Equal (Restore-IiOwnedRegValue $m 'c') 'restored' 'uninstall after two installs'
    Assert-Equal (Cur 'Scheme').Value 'Windows Default' 'restores the REAL original, not ii first value'

    # --- the user changes it after ii: their choice survives upgrade and uninstall --------------------
    Write-IiRegValue $root 'Scheme' 'Windows Default' 'String'
    $m = NewManifest
    [void](Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata' 'String' -TakeOver)
    Write-IiRegValue $root 'Scheme' 'My Own Cursors' 'String'          # the user, later
    $m = RoundTrip $m
    Assert-Equal (Set-IiOwnedRegValue $m 'c' $root 'Scheme' 'Bibata' 'String' -TakeOver) 'user-choice' 'an upgrade does not overwrite the later user choice'
    Assert-Equal (Cur 'Scheme').Value 'My Own Cursors' 'it is still theirs'
    Assert-Equal (Restore-IiOwnedRegValue $m 'c') 'user-changed' 'uninstall leaves it alone too'
    Assert-Equal (Cur 'Scheme').Value 'My Own Cursors' 'still theirs after uninstall'
    Assert-Equal @($m.changes).Count 0 'and ii stops claiming it'

    # --- the user deleted it: stays deleted ---------------------------------------------------------------
    $m = NewManifest
    [void](Set-IiOwnedRegValue $m 'd' $root 'ExeD' $gpu 'String')
    Remove-IiRegValue $root 'ExeD'
    $m = RoundTrip $m
    Assert-Equal (Set-IiOwnedRegValue $m 'd' $root 'ExeD' $gpu 'String') 'user-choice' 'a value the user deleted is not put back by an upgrade'
    Assert-True (-not (Cur 'ExeD').Exists) 'still deleted'

    # --- types survive the round trip: DWord, ExpandString, Binary ------------------------------------------
    Write-IiRegValue $root 'Dw' 5 'DWord'
    Write-IiRegValue $root 'Ex' '%USERPROFILE%\bin' 'ExpandString'
    Write-IiRegValue $root 'Bin' ([byte[]](1, 2, 3, 250)) 'Binary'
    $m = NewManifest
    [void](Set-IiOwnedRegValue $m 'dw' $root 'Dw' 9 'DWord' -TakeOver)
    [void](Set-IiOwnedRegValue $m 'ex' $root 'Ex' '%USERPROFILE%\bin;%USERPROFILE%\ii' 'ExpandString' -TakeOver)
    [void](Set-IiOwnedRegValue $m 'bin' $root 'Bin' ([byte[]](9, 9)) 'Binary' -TakeOver)
    $m = RoundTrip $m
    foreach ($id in 'dw', 'ex', 'bin') { Assert-Equal (Restore-IiOwnedRegValue $m $id) 'restored' "$id restored" }
    Assert-True ((Cur 'Dw').Kind -eq 'DWord' -and (Cur 'Dw').Value -eq 5) 'DWord comes back as a DWord'
    Assert-True ((Cur 'Ex').Kind -eq 'ExpandString' -and (Cur 'Ex').Value -eq '%USERPROFILE%\bin') 'ExpandString comes back unexpanded and as ExpandString'
    Assert-True ((Cur 'Bin').Kind -eq 'Binary' -and ([Convert]::ToBase64String((Cur 'Bin').Value) -eq [Convert]::ToBase64String([byte[]](1, 2, 3, 250)))) 'Binary comes back byte for byte'

    # --- repeating install/uninstall accumulates nothing --------------------------------------------------------
    $m = NewManifest
    for ($i = 0; $i -lt 3; $i++) {
        [void](Set-IiOwnedRegValue $m 'r' $root 'ExeR' $gpu 'String')
        $m = RoundTrip $m
        [void](Restore-IiOwnedRegValue $m 'r')
    }
    Assert-True (-not (Cur 'ExeR').Exists) 'three install/uninstall cycles leave the value absent'
    Assert-Equal @($m.changes).Count 0 'and no stale records'

    # --- a manifest from before changes[] existed (only gpuPreference) -------------------------------------------
    $exe = 'C:\Users\Someone\AppData\Local\Programs\ii-windows\quickshell\quickshell.exe'
    Write-IiRegValue $root $exe $gpu 'String'
    $legacy = [pscustomobject]@{ product = 'ii-windows'; gpuPreference = $exe }
    Import-IiLegacyChanges $legacy $root
    Assert-Equal @($legacy.changes).Count 1 'the old gpuPreference becomes an owned change'
    $legacy = RoundTrip $legacy
    Assert-Equal (Restore-IiOwnedRegValue $legacy "gpu:$exe") 'deleted' 'and uninstall removes it (it was never there before)'
    Write-IiRegValue $root $exe 'GpuPreference=2;' 'String'             # the user chose high performance since
    $legacy2 = [pscustomobject]@{ product = 'ii-windows'; gpuPreference = $exe }
    Import-IiLegacyChanges $legacy2 $root
    Assert-Equal @($legacy2.changes).Count 0 'an old manifest whose value the user changed is not claimed'
    Assert-Equal (Cur $exe).Value 'GpuPreference=2;' 'and their value stands'
}
finally {
    try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($root.Split('\')[0] + '\' + $root.Split('\')[1], $false) } catch {}
    try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey('Software\ii-windows-test', $false) } catch {}
}
Complete-IiTest
