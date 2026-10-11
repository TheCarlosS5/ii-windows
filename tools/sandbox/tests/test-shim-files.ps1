# C12: the file commands ii-shim answers to (mkdir, rm, reset-dir, which) do their job on the user's
# own folders and refuse everything else. Runs the clang-cl build of ii-shim with a FAKE profile: the
# environment it sees (LOCALAPPDATA, APPDATA, TEMP, USERPROFILE) points into a throwaway folder, so even
# a regression in its safety rules can only ever touch that folder, never the real profile.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$shim = Join-Path $repo 'host\build-clang\ii-shim.exe'
if (-not (Test-Path $shim)) { Skip-Test 'ii-shim not built with clang-cl (cmake -S host -B host\build-clang -DCMAKE_CXX_COMPILER=clang-cl ...)' }

$base = Join-Path $env:TEMP ('ii-shimfiles-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$profile = Join-Path $base 'Profile'
$local = Join-Path $profile 'AppData\Local'
$roaming = Join-Path $profile 'AppData\Roaming'
$temp = Join-Path $local 'Temp'
New-Item -ItemType Directory -Force $local, $roaming, $temp | Out-Null
$outside = Join-Path $base 'Outside'                      # a sibling of the fake profile: not one of "the user's folders"
New-Item -ItemType Directory -Force $outside | Out-Null
Set-Content (Join-Path $outside 'sentinel.txt') 'must survive'

function Shim([string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $shim
    $psi.Arguments = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['USERPROFILE'] = $profile
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $local
    $psi.EnvironmentVariables['APPDATA'] = $roaming
    $psi.EnvironmentVariables['TEMP'] = $temp
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out.Trim() }
}
try {
    # mkdir -p
    $deep = Join-Path $local 'x\b\c d\e'
    $r = Shim @('mkdir', '-p', $deep)
    Assert-True ($r.Code -eq 0 -and (Test-Path $deep)) 'mkdir -p creates a nested folder (a space in the path is fine)'
    Assert-Equal (Shim @('mkdir', '-p', $deep)).Code 0 'and is happy when it already exists'
    $r = Shim @('mkdir', '-p', (Join-Path $outside 'new'))
    Assert-True ($r.Code -ne 0 -and -not (Test-Path (Join-Path $outside 'new'))) 'a folder outside the user''s own folders is refused and not created'

    # rm
    $file = Join-Path $local 'marker.txt'; Set-Content $file 'x'
    Assert-True ((Shim @('rm', $file)).Code -eq 0 -and -not (Test-Path $file)) 'rm deletes a file'
    Assert-True ((Shim @('rm', $file)).Code -ne 0) 'a missing file is an error without -f'
    Assert-Equal (Shim @('rm', '-f', $file)).Code 0 'and not with -f'
    Assert-True ((Shim @('rm', (Join-Path $local 'x'))).Code -ne 0 -and (Test-Path (Join-Path $local 'x'))) 'rm without -r does not delete a folder'
    $deepFolder = Join-Path (Join-Path $local 'x') 'b'
    Assert-True ((Shim @('rm', '-rf', $deepFolder)).Code -eq 0 -and -not (Test-Path $deepFolder)) 'rm -rf deletes a folder tree (two levels below a user folder or deeper)'
    Assert-True ((Shim @('rm', '-rf', (Join-Path $local 'x'))).Code -ne 0 -and (Test-Path (Join-Path $local 'x'))) 'but not a folder directly inside one (like quickshell inside LOCALAPPDATA)'

    # top-level folders and everything outside are refused
    foreach ($forbidden in $local, $roaming, $profile, $temp, (Join-Path $profile 'Documents')) {
        New-Item -ItemType Directory -Force $forbidden | Out-Null
        Set-Content (Join-Path $forbidden 'keep.txt') 'x'
        $r = Shim @('rm', '-rf', $forbidden)
        Assert-True ($r.Code -ne 0 -and (Test-Path (Join-Path $forbidden 'keep.txt'))) "rm -rf of the top-level folder '$(Split-Path $forbidden -Leaf)' is refused"
    }
    $r = Shim @('rm', '-rf', $outside)
    Assert-True ($r.Code -ne 0 -and (Test-Path (Join-Path $outside 'sentinel.txt'))) 'rm -rf outside the user''s folders is refused'
    $r = Shim @('rm', '-rf', (Join-Path $local '..\..\..\Outside'))
    Assert-True ($r.Code -ne 0 -and (Test-Path (Join-Path $outside 'sentinel.txt'))) 'a path that climbs out with .. is refused'

    # a junction inside a folder that is emptied
    $tree = Join-Path $local 'tree\inner'; New-Item -ItemType Directory -Force $tree | Out-Null
    & cmd.exe /c "mklink /J `"$tree\link`" `"$outside`"" | Out-Null
    $r = Shim @('reset-dir', $tree)
    Assert-True ($r.Code -eq 0 -and (Test-Path (Join-Path $outside 'sentinel.txt'))) 'emptying a folder that holds a junction removes the link, never what it points to'

    # reset-dir
    $cache = Join-Path $local 'cache\covers'; New-Item -ItemType Directory -Force $cache | Out-Null; Set-Content (Join-Path $cache 'old.png') 'x'
    $r = Shim @('reset-dir', $cache)
    Assert-True ($r.Code -eq 0 -and (Test-Path $cache) -and -not (Test-Path (Join-Path $cache 'old.png'))) 'reset-dir leaves an empty folder'
    Assert-True ((Shim @('reset-dir', (Join-Path $local 'fresh\one'))).Code -eq 0 -and (Test-Path (Join-Path $local 'fresh\one'))) 'and creates it when it did not exist'
    $r = Shim @('reset-dir', $temp)
    Assert-True ($r.Code -ne 0 -and (Test-Path (Join-Path $temp 'keep.txt'))) 'but will not wipe %TEMP% itself'

    # which
    $r = Shim @('which', 'cmd')
    Assert-True ($r.Code -eq 0 -and $r.Out -like '*cmd.exe') 'which finds a program on PATH'
    Assert-True ((Shim @('which', 'definitely-not-a-program-ii')).Code -ne 0) 'and exits 1 for one that is not there'
    Assert-True ((Shim @('which', 'a\b')).Code -ne 0) 'and does not take a path'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
