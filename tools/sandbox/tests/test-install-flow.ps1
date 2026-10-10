# R06/R07/R08 end to end with the real install.ps1 / uninstall.ps1 in -Sandbox mode: LOCALAPPDATA and
# APPDATA point at a throwaway folder, the package is built from the fake host/shell binaries, and
# the scripts skip everything outside it (fonts, cursor, PATH, autostart, uninstall entry, restore
# point, closing the real ii). The one user-visible registry write they still make is the GPU
# preference, keyed by a path inside the throwaway folder, which the uninstaller must remove again.
#   install -> verify -> upgrade -> upgrade again -> tampered package -> uninstall
. "$PSScriptRoot\..\lib\ii-test.ps1"
. "$PSScriptRoot\..\lib\ii-host.ps1"
. "$PSScriptRoot\..\..\package\ii-runtime.ps1"
. "$PSScriptRoot\..\..\package\ii-changes.ps1"
Require-IiHostBuild
$launcherExe = Join-Path $script:IiRepo 'host\build\ii-launcher.exe'
if (-not (Test-Path $launcherExe)) { Skip-Test 'ii-launcher.exe not built' }

$base = New-IiTestDir 'ii-flow'
$gpuSubKey = 'Software\Microsoft\DirectX\UserGpuPreferences'
$pkgSrc = Join-Path $script:IiRepo 'tools\package'

function New-Package([string]$Name, [string]$Version) {
    $pkg = Join-Path $base "pkg-$Name"
    $app = Join-Path $pkg 'app'
    New-Item -ItemType Directory -Force "$app\quickshell", "$app\ii", "$app\rescue", "$app\cursors", "$app\bin" | Out-Null
    Copy-Item $script:IiFakeShell "$app\ii-host.exe"
    Copy-Item $script:IiFakeShell "$app\quickshell\quickshell.exe"
    Set-Content "$app\ii\shell.qml" "// $Name"
    Set-Content "$app\VERSION" "$Version`nii-windows test"
    Set-Content "$app\rescue\ii-rescue.cmd" '@echo rescue'
    Set-Content "$app\cursors\placeholder.txt" 'x'
    Set-Content "$app\bin\fastfetch.cmd" '@echo fastfetch'
    [void](New-IiPayloadManifest $app)
    foreach ($f in 'install.ps1', 'uninstall.ps1', 'autostart-task.ps1', 'ii-ownership.ps1', 'ii-autostart.ps1', 'ii-changes.ps1', 'ii-runtime.ps1', 'install.cmd', 'uninstall.cmd') {
        Copy-Item (Join-Path $pkgSrc $f) $pkg
    }
    Copy-Item $launcherExe $pkg
    $pkg
}

function Invoke-Script([string]$Script, [string[]]$ScriptArgs, [string]$Lad, [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" " + ($ScriptArgs -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $Lad
    $psi.EnvironmentVariables['APPDATA'] = Join-Path $Lad 'Roaming'
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(240000)) { try { $p.Kill() } catch {}; return [pscustomobject]@{ Code = -1; Text = 'timeout' } }
    [pscustomobject]@{ Code = $p.ExitCode; Text = ($out.Result + $err.Result) }
}

function Get-GpuValues([string]$Prefix) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($gpuSubKey, $false)
    if (-not $key) { return @() }
    try { @($key.GetValueNames() | Where-Object { $_.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) }) } finally { $key.Close() }
}

try {
    $lad = Join-Path $base 'Local'
    $install = Join-Path $lad 'Programs\ii-windows'
    $data = Join-Path $lad 'ii-windows'
    New-Item -ItemType Directory -Force $lad, (Join-Path $lad 'Roaming') | Out-Null

    # ---- fresh install ----------------------------------------------------------------------------
    $v1 = New-Package 'v1' '0.9.1-20261010-aaaaaaa'
    $r = Invoke-Script (Join-Path $v1 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 "install.ps1 -Sandbox finishes ($($r.Text.Split("`n") | Select-Object -Last 2))"
    $cur = Read-IiCurrent $install
    Assert-True ($cur.active -eq '0.9.1-20261010-aaaaaaa' -and $cur.state -eq 'pending' -and $cur.previous -eq 'none') 'the new version is active and pending'
    foreach ($f in 'ii-launcher.exe', 'uninstall.ps1', 'ii-runtime.ps1', 'ii-changes.ps1', 'ii-autostart.ps1', 'rescue\ii-rescue.cmd', 'cursors\placeholder.txt', 'bin\fastfetch.cmd') {
        Assert-PathExists (Join-Path $install $f) "installed: $f"
    }
    Assert-PathExists (Join-Path $install "versions\$($cur.active)\ii-host.exe") 'the version is under versions\'
    Assert-PathMissing (Join-Path $install 'journal.txt') 'no open journal'
    $m = Get-Content (Join-Path $data 'install.json') -Raw | ConvertFrom-Json
    Assert-True ($m.schema -eq 2 -and $m.versionId -eq $cur.active) 'the manifest is schema 2 and names the version'
    $gpu1 = Join-Path $install "versions\$($cur.active)\quickshell\quickshell.exe"
    Assert-True (@($m.changes | Where-Object { $_.id -eq "gpu:$gpu1" }).Count -eq 1) 'the GPU preference is an owned change with its original recorded'
    Assert-Equal (Read-IiRegValue $gpuSubKey $gpu1).Value 'GpuPreference=1;' 'and was written'
    $firstInstalled = $cur.active

    # the launcher confirms it
    $p = Start-IiProcess (Join-Path $install 'ii-launcher.exe') @() (Join-Path $install 'x') @{ II_FAKE_HOST = 'ok'; II_FAKE_HOST_LIFETIME_MS = 600 }
    Assert-Equal (Wait-IiExit $p 60) 0 'the launcher starts the installed version'
    Assert-Equal (Read-IiCurrent $install).state 'verified' 'and it verifies itself'

    # ---- upgrade ----------------------------------------------------------------------------------------
    $v2 = New-Package 'v2' '0.9.2-20261011-bbbbbbb'
    $before = (Get-FileHash (Join-Path $install "versions\$firstInstalled\ii\shell.qml")).Hash
    $r = Invoke-Script (Join-Path $v2 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 'the upgrade finishes'
    $cur = Read-IiCurrent $install
    Assert-True ($cur.active -eq '0.9.2-20261011-bbbbbbb' -and $cur.previous -eq $firstInstalled -and $cur.state -eq 'pending') 'v2 pending, v1 is the way back'
    Assert-Equal (Get-FileHash (Join-Path $install "versions\$firstInstalled\ii\shell.qml")).Hash $before 'v1 was not touched by the upgrade'
    $m = Get-Content (Join-Path $data 'install.json') -Raw | ConvertFrom-Json
    Assert-Equal @($m.changes | Where-Object { $_.id -like 'gpu:*' }).Count 2 'both versions have their own owned GPU entry'

    # installing the same package again changes nothing
    $r = Invoke-Script (Join-Path $v2 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 'installing the same package again works'
    $m2 = Get-Content (Join-Path $data 'install.json') -Raw | ConvertFrom-Json
    Assert-Equal @($m2.changes | Where-Object { $_.id -like 'gpu:*' }).Count 2 'and records nothing twice'
    Assert-True ((@(Get-ChildItem (Join-Path $install 'versions') -Directory)).Count -eq 2) 'and creates no third version folder'

    # ---- a tampered package is refused and nothing changes --------------------------------------------------------------------------------
    $bad = New-Package 'bad' '0.9.3-20261012-ccccccc'
    Add-Content (Join-Path $bad 'app\ii\shell.qml') 'tampered after the manifest'
    $stateBefore = Get-Content (Join-Path $install 'current.txt') -Raw
    $r = Invoke-Script (Join-Path $bad 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-True ($r.Code -ne 0) 'the installer fails for a package that does not match its manifest'
    Assert-Equal (Get-Content (Join-Path $install 'current.txt') -Raw) $stateBefore 'current.txt is unchanged'
    Assert-True ((@(Get-ChildItem (Join-Path $install 'versions') -Directory)).Count -eq 2) 'and no half version was left'

    # ---- uninstall ---------------------------------------------------------------------------------------------------------------------------
    New-Item -ItemType Directory -Force (Join-Path $lad 'quickshell\other-config') | Out-Null
    Set-Content (Join-Path $lad 'quickshell\other-config\shell.qml') 'not ours'
    Assert-True (@(Get-GpuValues $lad).Count -ge 2) 'two GPU values exist before uninstalling'
    $r = Invoke-Script (Join-Path $install 'uninstall.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 "uninstall.ps1 -Sandbox finishes ($($r.Text.Split("`n") | Select-Object -Last 2))"
    Assert-Equal @(Get-GpuValues $lad).Count 0 'every GPU value ii wrote is gone'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-Path $install) -and $sw.Elapsed.TotalSeconds -lt 40) { Start-Sleep -Milliseconds 500 }   # the install folder is removed by a helper after the script exits
    Assert-PathMissing $install 'the install folder is gone'
    Assert-PathExists (Join-Path $lad 'quickshell\other-config\shell.qml') 'another Quickshell config survived'

    # ---- reinstall with -KeepConfig: config and keys outlive an uninstall ---------------------------------------------------------------------
    $r = Invoke-Script (Join-Path $v1 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 'a fresh install after the uninstall works'
    New-Item -ItemType Directory -Force (Join-Path $lad 'quickshell\illogical-impulse'), (Join-Path $data 'secrets') | Out-Null
    Set-Content (Join-Path $lad 'quickshell\illogical-impulse\config.json') '{"mine":true}'
    Set-Content (Join-Path $data 'secrets\k.bin') 'encrypted'
    $r = Invoke-Script (Join-Path $install 'uninstall.ps1') @('-Yes', '-Sandbox', '-KeepConfig') $lad
    Assert-Equal $r.Code 0 'uninstall -KeepConfig finishes'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-Path $install) -and $sw.Elapsed.TotalSeconds -lt 40) { Start-Sleep -Milliseconds 500 }
    Assert-PathExists (Join-Path $lad 'quickshell\illogical-impulse\config.json') 'the config survived -KeepConfig'
    Assert-PathExists (Join-Path $data 'secrets\k.bin') 'and so did the saved keys'
    Assert-PathExists (Join-Path $lad 'quickshell\other-config\shell.qml') 'and the other Quickshell config'
    $r = Invoke-Script (Join-Path $v1 'install.ps1') @('-Yes', '-Sandbox') $lad
    Assert-Equal $r.Code 0 'reinstalling over the kept data works'
    Assert-PathExists (Join-Path $lad 'quickshell\illogical-impulse\config.json') 'the config is still there after reinstalling'
    $r = Invoke-Script (Join-Path $install 'uninstall.ps1') @('-Yes', '-Sandbox') $lad
    $sw.Restart()
    while ((Test-Path $install) -and $sw.Elapsed.TotalSeconds -lt 40) { Start-Sleep -Milliseconds 500 }
    Assert-PathMissing (Join-Path $lad 'quickshell\illogical-impulse') 'a full uninstall removes the config'
    Assert-PathMissing (Join-Path $data 'secrets') 'and the keys'
    Assert-PathExists (Join-Path $lad 'quickshell\other-config\shell.qml') 'but still not the other Quickshell config'
    Assert-Equal @(Get-GpuValues $lad).Count 0 'and no GPU value is left'
}
finally {
    # Whatever happened, no GPU value pointing into the throwaway folder stays in the real registry.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($gpuSubKey, $true)
    if ($key) {
        foreach ($n in @($key.GetValueNames() | Where-Object { $_.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) })) { $key.DeleteValue($n, $false) }
        $key.Close()
    }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -like "$base*" } catch { $false } } | ForEach-Object { try { $_.Kill() } catch {} }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
