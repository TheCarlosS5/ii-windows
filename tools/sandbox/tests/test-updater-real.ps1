# Plan 2026-10-31, B10 / end of a round: the updater with the REAL package and the REAL signature. Takes the newest
# out\ii-windows-<id>.zip with the release.json that publish-release.ps1 -DryRun completed and signed with the author's
# key (out\ii-windows-<id>-release.final.json + .sig), serves them from a fake GitHub (http.cpp's fixtures) and runs
# ii-shim update check / download / install into a throwaway install root that has an older version. No test key:
# the signature is checked with the public keys built into ii-shim, as on a user's PC. Nothing touches the network
# or the real installation.
#   test-updater-real.ps1 [-Package out\ii-windows-<id>]
# Needs: make-package.ps1, then publish-release.ps1 -DryRun; PowerShell 7.
param([string]$Package = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Skip-Test 'needs PowerShell 7 (pwsh)' }
    & $pwsh.Source -NoProfile -File $PSCommandPath @PSBoundParameters
    exit $LASTEXITCODE
}
$shim = "$repo\host\build\ii-shim.exe"
if (-not (Test-Path $shim)) { Skip-Test 'ii-shim.exe not built' }
if (-not $Package) {
    $Package = Get-ChildItem "$repo\out" -Directory -Filter 'ii-windows-*' | Where-Object { Test-Path "$($_.FullName).zip" } |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $Package) { Skip-Test 'no package (tools\package\make-package.ps1)' }
$name = Split-Path $Package -Leaf
$id = $name -replace '^ii-windows-', ''
$zip = "$Package.zip"
$final = "$Package-release.final.json"
if (-not (Test-Path "$final.sig")) { Skip-Test "no signed release.json for $id (tools\package\publish-release.ps1 -DryRun)" }
$release = Get-Content $final -Raw | ConvertFrom-Json
Write-Output "package $id ($([math]::Round((Get-Item $zip).Length / 1MB)) MB), release $($release.version)"

$base = Join-Path $env:TEMP ('ii-updater-real-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $base 'data'
$root = Join-Path $base 'root'
$web = Join-Path $base 'web'
New-Item -ItemType Directory -Force $data, $root, $web | Out-Null
$oldId = '0.6.1-20261101-0000000'
New-Item -ItemType Directory -Force (Join-Path $root "versions\$oldId") | Out-Null
Set-Content (Join-Path $root "versions\$oldId\ii-host.exe") 'old host' -NoNewline
Set-Content (Join-Path $root 'current.txt') "active=$oldId`r`nprevious=none`r`nstate=verified`r`nattempts=0`r`n" -NoNewline
try {
    $u = 'https://github.example/v'
    $list = @([ordered]@{ tag_name = "v$($release.version)"; draft = $false; prerelease = $false; published_at = '2026-11-01T12:00:00Z'
        html_url = "$u/page"; assets = @(
            [ordered]@{ name = 'release.json'; browser_download_url = "$u/release.json"; size = (Get-Item $final).Length },
            [ordered]@{ name = 'release.json.sig'; browser_download_url = "$u/release.json.sig"; size = (Get-Item "$final.sig").Length },
            [ordered]@{ name = "$name.zip"; browser_download_url = "$u/package.zip"; size = (Get-Item $zip).Length }) })
    $listFile = Join-Path $web 'releases.json'
    [IO.File]::WriteAllText($listFile, (ConvertTo-Json -InputObject $list -Depth 6))
    $map = [ordered]@{
        'https://api.github.example/releases' = @{ status = 200; bodyFile = $listFile; etag = '"r1"' }
        "$u/release.json" = @{ status = 200; bodyFile = $final }
        "$u/release.json.sig" = @{ status = 200; bodyFile = "$final.sig" }
        "$u/package.zip" = @{ status = 200; bodyFile = $zip; contentLength = "$((Get-Item $zip).Length)" }
    }
    $fixtures = Join-Path $web 'fixtures.json'
    [IO.File]::WriteAllText($fixtures, ($map | ConvertTo-Json -Depth 5))
    function Invoke-Update([string[]]$Arguments) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo $shim, ((@('update') + $Arguments + '--test') -join ' ')
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.Environment['II_DATA_DIR'] = $data
        $psi.Environment['II_UPDATE_API'] = 'https://api.github.example/releases'
        $psi.Environment['II_UPDATE_ROOT'] = $root
        $psi.Environment['II_UPDATE_CURRENT'] = $oldId
        $psi.Environment['II_HTTP_TEST_RESPONSES'] = $fixtures
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit(600000) | Out-Null
        $script:lastOutput = $o.Result + $e.Result
        $p.ExitCode
    }
    function Get-State { Get-Content (Join-Path $data 'update\state.json') -Raw | ConvertFrom-Json }

    Assert-Equal (Invoke-Update @('check')) 0 'check runs'
    $s = Get-State
    Assert-Equal $s.status 'available' "the real release is offered (signature checked with the built-in key) $($script:lastOutput)"
    Assert-Equal $s.latest.version $release.version 'its version'
    Assert-Equal (Invoke-Update @('download')) 0 "download runs $($script:lastOutput)"
    Assert-Equal (Get-State).status 'downloaded' 'the 103 MB package is downloaded and its SHA256 matches'
    Assert-Equal (Invoke-Update @('install')) 0 "install runs $($script:lastOutput)"
    Assert-Equal (Get-State).status 'ready' 'installed, waiting for a restart'
    $new = Join-Path $root "versions\$id"
    Assert-PathExists (Join-Path $new 'ii-host.exe') 'the new version is next to the old one'
    Assert-PathExists (Join-Path $new 'quickshell\quickshell.exe') 'with its shell'
    Assert-PathExists (Join-Path $new 'ii\shell.qml') 'and its QML'
    # Every file of the payload manifest, as installed.
    $bad = 0; $count = 0
    foreach ($line in Get-Content (Join-Path $new 'payload.manifest')) {
        if ($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') { continue }
        $count++
        $file = Join-Path $new $Matches[2]
        if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $Matches[1].ToUpper()) { $bad++ }
    }
    Write-Output "payload: $count files checked, $bad different"
    Assert-True ($count -gt 2000 -and $bad -eq 0) 'every installed file matches the payload manifest'
    $current = Get-Content (Join-Path $root 'current.txt') -Raw
    # The launcher starts the new one at the next start and goes back to the previous if it does not come up.
    Assert-True ($current -match "(?m)^active=$([regex]::Escape($id))" -and $current -match "(?m)^previous=$([regex]::Escape($oldId))" -and
        $current -match '(?m)^state=pending') "current.txt: the new version pending, the old one as previous ($($current -replace "`r?`n", ' '))"
    Assert-PathExists (Join-Path $root "versions\$oldId\ii-host.exe") 'the old version is still there (rollback)'
} finally {
    Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
}
Complete-IiTest
