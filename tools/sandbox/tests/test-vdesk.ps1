# R09: removing a virtual desktop is decided on what the caller saw and what is there right now.
# Two parts: the rule itself (ii-vdesk-test, no Explorer) and ii-shim vdesk's contract with the real
# Explorer on this PC - only commands that change nothing here: they ask for a removal on a stale
# or impossible view and must refuse with the documented exit code and leave the desktops as they were.
# Needs: cmake --build host\build --target ii-vdesk-test ; cmake --build host\build-clang --target ii-shim
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$rule = Join-Path $repo 'host\build\ii-vdesk-test.exe'
if (-not (Test-Path $rule)) { Skip-Test 'host\build\ii-vdesk-test.exe is not built' }
$text = & $rule | Out-String
Assert-True ($LASTEXITCODE -eq 0 -and $text -match ' 0 failed') "the removal rule's own checks pass ($($text.Trim().Split("`n")[-1].Trim()))"

$shim = Join-Path $repo 'host\build-clang\ii-shim.exe'
if (-not (Test-Path $shim)) { Write-Output 'ii-shim.exe not built: the Explorer contract was not run'; Complete-IiTest; return }

function Invoke-Vdesk {
    param([string[]]$Arguments)
    $out = & $shim vdesk @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out.Trim(); Last = ($out.Trim() -split "`r?`n")[-1] }
}

$probe = Invoke-Vdesk 'probe'
if ($probe.Code -eq 4) {
    # Older Windows / Explorer not ready: the contract is to say so, once, and not to guess.
    Assert-True ($probe.Out -match '(?m)^read no') 'an unavailable interface is reported as "read no"'
    Assert-True ($probe.Last -match '^fail ') 'and the last line says fail'
    Skip-Test 'this Windows has no usable desktop interface (probe exit 4); the rest needs one'
}
Assert-Equal $probe.Code 0 'probe succeeds when reading the desktops is verified'
Assert-True ($probe.Out -match '(?m)^build \d+\s*$') 'probe says which build it checked'
foreach ($cap in 'read', 'switch', 'remove', 'move') {
    Assert-True ($probe.Out -match "(?m)^$cap (yes|no)") "probe reports the $cap capability explicitly"
}
Assert-Equal $probe.Last 'ok' 'the last line of a good run is "ok"'

$list = Invoke-Vdesk 'list'
Assert-Equal $list.Code 0 'list succeeds'
$desktops = @($list.Out -split "`r?`n" | Where-Object { $_ -match '^desktop \d+ \{[0-9A-F-]{36}\}' })
Assert-True ($desktops.Count -ge 1) "list shows $($desktops.Count) desktop(s) with their ids"
Assert-Equal @($desktops | Where-Object { $_ -match ' current$' }).Count 1 'exactly one desktop is marked current'
Assert-True ($list.Out -match '(?m)^unknown-app-windows 0\s*$') 'every app window on screen could be placed on a desktop (otherwise removal would refuse as ambiguous)'

$ids = @($desktops | ForEach-Object { ($_ -split ' ')[2] })
$count0 = (Invoke-Vdesk 'count').Out.Split("`n")[0].Trim().Split(' ')[0]

# A removal decided on another inventory never happens, whatever the desktop.
$bogus = '{00000000-0000-0000-0000-0000000000AA}'
$r = Invoke-Vdesk 'remove-empty', $ids[-1], $bogus
Assert-Equal $r.Code 6 'a stale inventory cancels (exit 6)'
Assert-True ($r.Last -match 'inventory-changed') "and says why: $($r.Last)"
$r = Invoke-Vdesk 'remove-empty', $ids[-1]
Assert-Equal $r.Code 2 'a removal that does not say what it saw is a usage error (exit 2)'
if ($ids.Count -ge 2) {
    $r = Invoke-Vdesk 'remove-empty', $ids[-1], ($ids[0..($ids.Count - 2)] -join ',')
    Assert-Equal $r.Code 6 'an inventory missing the last desktop cancels (exit 6)'
}
# The matching inventory still refuses the cases the rule forbids: the only/first/current desktop.
$r = Invoke-Vdesk 'remove-empty', $ids[0], ($ids -join ',')
Assert-Equal $r.Code 6 'desktop 1 is never removed automatically (exit 6)'
Assert-True ($r.Last -match 'only-one|is-first') "reason: $($r.Last)"
$cur = ($desktops | Where-Object { $_ -match ' current$' } | Select-Object -First 1)
$curId = ($cur -split ' ')[2]
$r = Invoke-Vdesk 'remove-empty', $curId, ($ids -join ',')
Assert-Equal $r.Code 6 'the desktop the user is on is never removed (exit 6)'
$r = Invoke-Vdesk 'remove-empty', $bogus, ($ids -join ',')
Assert-Equal $r.Code 6 'an id that is not a desktop cancels (exit 6)'
Assert-True ($r.Last -match 'not-in-inventory') "reason: $($r.Last)"

# Impossible targets for the other operations fail closed, not silently.
Assert-Equal (Invoke-Vdesk 'switch', $bogus).Code 6 'switching to an unknown desktop id cancels (exit 6)'
Assert-Equal (Invoke-Vdesk 'switch', '999').Code 6 'switching to desktop 999 cancels (exit 6)'
Assert-Equal (Invoke-Vdesk 'remove', '999').Code 6 'removing desktop 999 cancels (exit 6)'
Assert-Equal (Invoke-Vdesk 'move', '1', $ids[0]).Code 6 'moving a window that does not exist cancels (exit 6)'
Assert-Equal (Invoke-Vdesk 'frobnicate').Code 2 'an unknown command is a usage error (exit 2)'
Assert-Equal (Invoke-Vdesk 'switch').Code 2 'a missing argument is a usage error (exit 2)'

$count1 = (Invoke-Vdesk 'count').Out.Split("`n")[0].Trim().Split(' ')[0]
Assert-Equal $count1 $count0 "none of the refusals changed the number of desktops ($count0)"
Complete-IiTest
