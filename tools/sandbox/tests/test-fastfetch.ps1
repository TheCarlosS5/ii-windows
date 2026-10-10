# F01: the `fastfetch` command shows an "ii" logo and never overrides what the user asks for.
# Precedence: command line > the user's config (II_FASTFETCH_CONFIG or %LOCALAPPDATA%\ii-windows\fastfetch.jsonc)
# > ii's default. Runs the real fastfetch.exe (read-only) from a throwaway layout; nothing is installed.
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$candidates = @("$repo\third_party\fastfetch", "$env:LOCALAPPDATA\Programs\ii-windows\fastfetch")
$source = $candidates | Where-Object { Test-Path (Join-Path $_ 'fastfetch.exe') } | Select-Object -First 1
if (-not $source) { Skip-Test 'no fastfetch.exe to run (tools\dev\fetch_fastfetch.ps1)' }

$base = Join-Path $env:TEMP ('ii-fastfetch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$root = Join-Path $base 'Programs\ii-windows'
New-Item -ItemType Directory -Force "$root\fastfetch", "$root\bin" | Out-Null
try {
    # fastfetch.exe with its DLLs, then ii's files from the repo (what the package would put there)
    Get-ChildItem $source -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Copy-Item -Destination "$root\fastfetch"
    foreach ($f in 'ii.jsonc', 'ii-logo.txt', 'ii-logo-ascii.txt') { Copy-Item "$repo\extras\fastfetch\$f" "$root\fastfetch" }
    Copy-Item "$repo\extras\fastfetch\fastfetch.cmd" "$root\bin"
    $cmd = "$root\bin\fastfetch.cmd"

    function Run-Ff([string[]]$Arguments = @(), [hashtable]$Env = @{}) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = '/d /c ""' + $cmd + '" ' + ($Arguments -join ' ') + '"'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $base 'Local'
        $psi.EnvironmentVariables['WT_SESSION'] = 'test'             # as in Windows Terminal
        foreach ($k in 'II_FASTFETCH_CONFIG', 'II_FASTFETCH_ASCII', 'NO_COLOR') { [void]$psi.EnvironmentVariables.Remove($k) }
        foreach ($k in $Env.Keys) { if ($null -eq $Env[$k]) { [void]$psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = [string]$Env[$k] } }
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; return [pscustomobject]@{ Code = -1; Text = 'timeout' } }
        [pscustomobject]@{ Code = $p.ExitCode; Text = $out.Result + $err.Result }
    }

    # (this file is ASCII on purpose: Windows PowerShell 5.1 reads BOM-less files as ANSI)
    $FULL = [string][char]0x2588 * 4
    $DOT = [string][char]0x2584 + [char]0x2588 + [char]0x2588 + [char]0x2584

    # --- the default: ii's logo and config --------------------------------------------------------
    $r = Run-Ff @('--pipe')
    Assert-Equal $r.Code 0 'fastfetch runs'
    Assert-True ($r.Text.Contains($DOT) -and $r.Text.Contains($FULL)) 'the default logo is the "ii" monogram (Unicode in Windows Terminal)'
    Assert-True ($r.Text -match 'illogical impulse .{1,3} ii-windows dev') 'the shell line names the port and its version'
    $logoRows = @($r.Text -split "`r?`n" | Where-Object { $_.Contains($FULL) })
    Assert-True ($logoRows.Count -eq 5) 'two stems of five rows: a readable "ii", not the old spark'

    # --- no Unicode: the ASCII variant ---------------------------------------------------------------
    $r = Run-Ff @('--pipe') @{ II_FASTFETCH_ASCII = '1' }
    Assert-True ($r.Text.Contains('####') -and -not $r.Text.Contains($FULL)) 'II_FASTFETCH_ASCII=1 uses the plain-ASCII logo'
    $r = Run-Ff @('--pipe') @{ WT_SESSION = $null }                  # a console that is not UTF-8 (chcp is not 65001 here)
    $cp = (& cmd /c chcp) -replace '[^\d]', ''
    if ($cp -ne '65001') { Assert-True ($r.Text.Contains('####')) 'a console that is not UTF-8 gets the ASCII logo' }

    # --- the user's options win --------------------------------------------------------------------------
    $r = Run-Ff @('--pipe', '--logo', 'none')
    Assert-True (-not $r.Text.Contains($FULL) -and -not $r.Text.Contains('####')) 'the user asked for no logo: none is added'
    Assert-True ($r.Text -match 'illogical impulse') 'but ii''s modules still are (only the logo was overridden)'

    $mine = Join-Path $base 'mine.jsonc'
    Set-Content $mine '{ "logo": { "type": "none" }, "modules": [ { "type": "custom", "format": "MY-OWN-CONFIG" } ] }'
    $r = Run-Ff @('-c', "`"$mine`"", '--pipe')
    Assert-True ($r.Text.Contains('MY-OWN-CONFIG')) '-c <file>: the user''s config is used'
    Assert-True (-not $r.Text.Contains('illogical impulse') -and -not $r.Text.Contains($FULL)) 'and neither ii''s modules nor its logo are forced on it'

    $r = Run-Ff @('--pipe') @{ II_FASTFETCH_CONFIG = $mine }
    Assert-True ($r.Text.Contains('MY-OWN-CONFIG') -and -not $r.Text.Contains($FULL)) 'II_FASTFETCH_CONFIG selects a config (and ii''s logo is not forced over it)'

    New-Item -ItemType Directory -Force (Join-Path $base 'Local\ii-windows') | Out-Null
    Set-Content (Join-Path $base 'Local\ii-windows\fastfetch.jsonc') '{ "logo": { "type": "none" }, "modules": [ { "type": "custom", "format": "FROM-USER-FILE" } ] }'
    $r = Run-Ff @('--pipe')
    Assert-True ($r.Text.Contains('FROM-USER-FILE')) '%LOCALAPPDATA%\ii-windows\fastfetch.jsonc is picked up'
    $r = Run-Ff @('--pipe') @{ II_FASTFETCH_CONFIG = $mine }
    Assert-True ($r.Text.Contains('MY-OWN-CONFIG')) 'and II_FASTFETCH_CONFIG outranks it'
    Remove-Item (Join-Path $base 'Local\ii-windows\fastfetch.jsonc')

    # --- installed with versions: the active version's folder and name ----------------------------------------
    New-Item -ItemType Directory -Force "$root\versions\0.9-test\fastfetch" | Out-Null
    Copy-Item "$root\fastfetch\*" "$root\versions\0.9-test\fastfetch" -Recurse
    Set-Content "$root\current.txt" "active=0.9-test`r`nprevious=none`r`nstate=verified`r`nattempts=0"
    $r = Run-Ff @('--pipe')
    Assert-True ($r.Text -match 'ii-windows 0\.9-test') 'with current.txt the active version is used and named'

    # --- fastfetch missing: a clear message, no hang ----------------------------------------------------------------
    Remove-Item "$root\versions" -Recurse -Force; Remove-Item "$root\current.txt"; Remove-Item "$root\fastfetch\fastfetch.exe"
    $r = Run-Ff @()
    Assert-True ($r.Code -ne 0 -and $r.Text -match 'not part of this ii-windows installation') 'without fastfetch.exe the command says so and fails fast'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
