# Plan 2026-10-31, B10: the updater (ii-shim update) against a fake GitHub (http.cpp's fixture mode), with a throwaway
# signing key. Nothing touches the network or the real installation: an isolated data folder and install root.
# Needs: cmake --build host\build --target ii-shim; PowerShell 7 (ECDsa).
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$shim = @("$repo\host\build\ii-shim.exe", "$repo\host\build-clang\ii-shim.exe") | Where-Object { Test-Path $_ } | Sort-Object { (Get-Item $_).LastWriteTime } | Select-Object -Last 1
if (-not $shim) { Skip-Test 'ii-shim.exe not built' }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # The suite runs tests in Windows PowerShell 5.1; this one needs .NET's ECDsa: run it again in pwsh.
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Skip-Test 'needs PowerShell 7 (pwsh)' }
    & $pwsh.Source -NoProfile -File $PSCommandPath
    exit $LASTEXITCODE
}

$base = Join-Path $env:TEMP ('ii-updater-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $base 'data'
$root = Join-Path $base 'root'
$web = Join-Path $base 'web'
New-Item -ItemType Directory -Force $data, $root, $web | Out-Null

# A throwaway key: its public point goes to the updater through II_UPDATE_TEST_KEY (only honoured with II_DATA_DIR).
$key = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
$q = $key.ExportParameters($false).Q
$testKey = (($q.X + $q.Y) | ForEach-Object { $_.ToString('x2') }) -join ''
function Sign([string]$Path) {
    $sig = $key.SignData([IO.File]::ReadAllBytes($Path), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    [IO.File]::WriteAllText("$Path.sig", [Convert]::ToBase64String($sig))
}

# The installed version (0.6.1) in the versions layout.
$oldId = '0.6.1-20261102-aaaaaaa'
$old = Join-Path $root "versions\$oldId"
New-Item -ItemType Directory -Force $old | Out-Null
Set-Content (Join-Path $old 'ii-host.exe') 'old host' -NoNewline
Set-Content (Join-Path $root 'current.txt') "active=$oldId`r`nprevious=none`r`nstate=verified`r`nattempts=0`r`n" -NoNewline

# A package of 0.7.0 like make-package.ps1 makes: <name>\app\... with payload.manifest, <name>\ii-launcher.exe.
$newId = '0.7.0-20261108-bbbbbbb'
$name = "ii-windows-$newId"
$pkg = Join-Path $base "pkg\$name"
$app = Join-Path $pkg 'app'
New-Item -ItemType Directory -Force (Join-Path $app 'quickshell'), (Join-Path $app 'ii') | Out-Null
Set-Content (Join-Path $app 'ii-host.exe') 'new host' -NoNewline
Set-Content (Join-Path $app 'quickshell\quickshell.exe') 'new shell' -NoNewline
Set-Content (Join-Path $app 'ii\shell.qml') 'ShellRoot {}' -NoNewline
Set-Content (Join-Path $app 'VERSION') "$newId`nii-windows test" -NoNewline
Set-Content (Join-Path $pkg 'ii-launcher.exe') 'new launcher' -NoNewline
$lines = Get-ChildItem $app -Recurse -File | Sort-Object FullName | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.FullName.Substring($app.Length + 1) }
[IO.File]::WriteAllLines((Join-Path $app 'payload.manifest'), [string[]]$lines)
$zip = Join-Path $web "$name.zip"
Compress-Archive -Path $pkg -DestinationPath $zip
$zipSha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$zipSize = (Get-Item $zip).Length

function New-Release([string]$Version, [string]$Id, [string]$Sha, [string]$Dir, [switch]$Prerelease) {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $json = [ordered]@{ schema = 1; version = $Version; id = $Id; channel = 'stable'; minFrom = '0.6.0'; critical = $true; needsInstaller = $false
        package = [ordered]@{ name = "ii-windows-$Id.zip"; size = $zipSize; sha256 = $Sha }; notes = @{ es = "## Novedades de $Version" } } | ConvertTo-Json -Depth 5
    $path = Join-Path $Dir 'release.json'
    [IO.File]::WriteAllText($path, $json)
    Sign $path
    $path
}
function Set-Web([object[]]$Releases, [hashtable]$Extra = @{}) {
    $list = @()
    $map = [ordered]@{}
    $i = 0
    foreach ($r in $Releases) {
        $i++
        $u = "https://github.example/r$i"
        $list += [ordered]@{ tag_name = "v$($r.Version)"; draft = $false; prerelease = [bool]$r.Prerelease; published_at = '2026-11-08T22:00:00Z'; html_url = "$u/page"
            assets = @(
                [ordered]@{ name = 'release.json'; browser_download_url = "$u/release.json"; size = 1 },
                [ordered]@{ name = 'release.json.sig'; browser_download_url = "$u/release.json.sig"; size = 1 },
                [ordered]@{ name = "ii-windows-$($r.Id).zip"; browser_download_url = "$u/package.zip"; size = $zipSize }) }
        $map["$u/release.json"] = @{ status = 200; bodyFile = $r.Json }
        $map["$u/release.json.sig"] = @{ status = 200; bodyFile = "$($r.Json).sig" }
        $map["$u/package.zip"] = @{ status = 200; bodyFile = $r.Zip; contentLength = "$((Get-Item $r.Zip).Length)" }
    }
    $listFile = Join-Path $web 'releases.json'
    [IO.File]::WriteAllText($listFile, (ConvertTo-Json -InputObject @($list) -Depth 6))
    $map['https://api.github.example/releases'] = @{ status = 200; bodyFile = $listFile; etag = '"v1"' }
    foreach ($k in $Extra.Keys) { $map[$k] = $Extra[$k] }
    $fixtures = Join-Path $web 'fixtures.json'
    [IO.File]::WriteAllText($fixtures, ($map | ConvertTo-Json -Depth 5))
    $fixtures
}
function Invoke-Update([string[]]$Arguments, [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $shim, ((@('update') + $Arguments + '--test') -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['II_DATA_DIR'] = $data
    $psi.Environment['II_UPDATE_API'] = 'https://api.github.example/releases'
    $psi.Environment['II_UPDATE_ROOT'] = $root
    $psi.Environment['II_UPDATE_CURRENT'] = $oldId
    $psi.Environment['II_UPDATE_TEST_KEY'] = $testKey
    $psi.Environment['II_HTTP_TEST_RESPONSES'] = $script:fixtures
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit(120000) | Out-Null
    $script:lastOutput = $o.Result + $e.Result
    $p.ExitCode
}
function Get-State { Get-Content (Join-Path $data 'update\state.json') -Raw | ConvertFrom-Json }

try {
    $good = @{ Version = '0.7.0'; Id = $newId; Json = (New-Release '0.7.0' $newId $zipSha (Join-Path $web 'good')); Zip = $zip }
    $script:fixtures = Set-Web @($good)

    # ---- a newer signed release is offered --------------------------------------------------------------------------
    Assert-Equal (Invoke-Update @('check')) 0 'check runs'
    $s = Get-State
    Assert-Equal $s.status 'available' 'a newer signed release is available'
    Assert-Equal $s.latest.version '0.7.0' 'its version'
    Assert-Equal $s.latest.critical $true 'critical comes from release.json'
    Assert-True ($s.latest.notes -match 'Novedades de 0.7.0') 'the notes come with it'
    Assert-Equal $s.etag '"v1"' 'the ETag is kept'

    # ---- a second check with the same ETag: 304, the cached list is used ------------------------------------------------
    Assert-Equal (Invoke-Update @('check')) 0 'check with If-None-Match'
    Assert-Equal (Get-State).status 'available' 'still available after a 304'

    # ---- metered connection: the download waits, unless the user forces it ---------------------------------------------
    Assert-Equal (Invoke-Update @('download') @{ II_UPDATE_TEST_METERED = '1' }) 3 'download on a metered connection waits'
    Assert-Equal (Get-State).status 'waiting-network' 'and says so'
    Assert-Equal (Invoke-Update @('download', '--force') @{ II_UPDATE_TEST_METERED = '1' }) 0 'the user can force it'
    Assert-Equal (Get-State).status 'downloaded' 'downloaded and SHA-256 checked'
    Assert-PathExists (Join-Path $data "update\$newId\$name.zip") 'the package is kept for the install'

    # ---- install next to the active version, pending ---------------------------------------------------------------------
    Assert-Equal (Invoke-Update @('install')) 0 'install runs'
    Assert-Equal (Get-State).status 'ready' 'ready: it applies at the next start of ii'
    Assert-PathExists (Join-Path $root "versions\$newId\ii-host.exe") 'the new version is in versions\'
    Assert-PathExists (Join-Path $root "versions\$oldId\ii-host.exe") 'the old version is untouched'
    $current = Get-Content (Join-Path $root 'current.txt') -Raw
    Assert-True ($current -match "active=$newId" -and $current -match "previous=$oldId" -and $current -match 'state=pending') "current.txt points at the new version, pending ($($current -replace "`r?`n", ' '))"
    Assert-Equal ((Get-Content (Join-Path $root 'ii-launcher.exe') -Raw)) 'new launcher' 'the newer launcher is put in place'
    Assert-PathMissing (Join-Path $root 'journal.txt') 'no journal left'
    Assert-Equal (@(Get-ChildItem (Join-Path $root 'versions') -Directory -Filter '*.staging-*')).Count 0 'no staging folder left'

    # ---- a tampered release.json is ignored ----------------------------------------------------------------------------
    Set-Content (Join-Path $data 'update\state.json') '{"schema":1,"status":"idle"}'
    Set-Content (Join-Path $root 'current.txt') "active=$oldId`r`nprevious=none`r`nstate=verified`r`nattempts=0`r`n" -NoNewline
    $evil = New-Release '0.7.0' $newId $zipSha (Join-Path $web 'evil')
    [IO.File]::WriteAllText($evil, ([IO.File]::ReadAllText($evil) -replace '"critical": true', '"critical": false'))
    $script:fixtures = Set-Web @(@{ Version = '0.7.0'; Id = $newId; Json = $evil; Zip = $zip })
    Assert-Equal (Invoke-Update @('check')) 1 'check fails on a bad signature'
    $s = Get-State
    Assert-Equal $s.status 'error' 'error state'
    Assert-True ($s.error -match 'no valid signature') "the reason is the signature ($($s.error))"
    Assert-True (-not $s.latest) 'nothing is offered'

    # ---- a package whose hash differs is not kept ------------------------------------------------------------------------
    Set-Content (Join-Path $data 'update\state.json') '{"schema":1,"status":"idle"}'
    $wrongHash = New-Release '0.7.0' $newId ('0' * 64) (Join-Path $web 'wronghash')
    $script:fixtures = Set-Web @(@{ Version = '0.7.0'; Id = $newId; Json = $wrongHash; Zip = $zip })
    Remove-Item (Join-Path $data "update\$newId") -Recurse -Force -ErrorAction SilentlyContinue
    Assert-Equal (Invoke-Update @('check')) 0 'check with a wrong hash in release.json'
    Assert-Equal (Invoke-Update @('download', '--force')) 1 'the download is refused'
    Assert-True ((Get-State).error -match 'damaged') 'as damaged'
    Assert-PathMissing (Join-Path $data "update\$newId\$name.zip") 'and not kept'

    # ---- an older release is never offered; a skipped one neither; a prerelease only on beta ----------------------------
    Set-Content (Join-Path $data 'update\state.json') '{"schema":1,"status":"idle"}'
    $older = New-Release '0.6.0' '0.6.0-20261025-ccccccc' $zipSha (Join-Path $web 'older')
    $script:fixtures = Set-Web @(@{ Version = '0.6.0'; Id = '0.6.0-20261025-ccccccc'; Json = $older; Zip = $zip })
    Assert-Equal (Invoke-Update @('check')) 0 'check with only an older release'
    Assert-Equal (Get-State).status 'idle' 'nothing offered (never a lower version)'

    $script:fixtures = Set-Web @($good)
    Assert-Equal (Invoke-Update @('skip', '0.7.0')) 0 'skip 0.7.0'
    Assert-Equal (Invoke-Update @('check')) 0 'check after skipping'
    Assert-Equal (Get-State).status 'idle' 'a skipped version is not offered again'

    Set-Content (Join-Path $data 'update\state.json') '{"schema":1,"status":"idle"}'
    $beta = New-Release '0.8.0' '0.8.0-20261120-ddddddd' $zipSha (Join-Path $web 'beta')
    $script:fixtures = Set-Web @(@{ Version = '0.8.0'; Id = '0.8.0-20261120-ddddddd'; Json = $beta; Zip = $zip; Prerelease = $true })
    Assert-Equal (Invoke-Update @('check')) 0 'check with only a prerelease'
    Assert-Equal (Get-State).status 'idle' 'the stable channel ignores prereleases'

    # ---- GitHub's rate limit: wait, do not insist --------------------------------------------------------------------
    Set-Content (Join-Path $data 'update\state.json') '{"schema":1,"status":"idle"}'
    $script:fixtures = Set-Web @($good) @{ 'https://api.github.example/releases' = @{ status = 403; retryAfter = '120' } }
    Assert-Equal (Invoke-Update @('check')) 1 'a rate-limited check fails'
    $s = Get-State
    Assert-True ($s.error -match 'limit') 'and says it is the limit'
    Assert-Equal "$($s.retryAfterSeconds)" '120' 'and when to try again'
} finally {
    Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
