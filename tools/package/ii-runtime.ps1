# Installing and updating the runtime without ever leaving a half-replaced installation (R07).
# Dot-sourced by install.ps1 and the tests. Layout (see host/src/rollout.h):
#   <root>\ii-launcher.exe, current.txt, journal.txt, versions\<id>\...
#
# An update never writes into the active version. It builds the new version next to it:
#   1 verify the payload against its manifest (sha256 per file)
#   2 copy it to versions\<id>.staging-<n>, verify the copy again
#   3 rename the staging folder to versions\<id>            (one atomic directory rename)
#   4 point current.txt at it, state "pending"               (one atomic file replace)
# and a journal (journal.txt) records the step, so that an interrupted run is understood and cleaned
# on the next one. The previous version stays until the new one has verified itself (the launcher
# and the host do that on its first start; a version that fails is rolled back by the launcher).

. (Join-Path $PSScriptRoot 'ii-ownership.ps1')

$script:IiRequiredPayloadFiles = @('ii-host.exe', 'quickshell\quickshell.exe', 'ii\shell.qml', 'VERSION')

function Test-IiVersionId([string]$Id) { $Id -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' }

function Get-IiRelativePath([string]$Base, [string]$Full) {
    $b = ([IO.Path]::GetFullPath($Base)).TrimEnd('\') + '\'
    $f = [IO.Path]::GetFullPath($Full)
    $f.Substring($b.Length)
}

# payload.manifest: one "<sha256>  <relative path>" per file (not for itself).
function New-IiPayloadManifest([string]$Dir) {
    $lines = Get-ChildItem -LiteralPath $Dir -Recurse -File | Where-Object { $_.Name -ne 'payload.manifest' } | Sort-Object FullName | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, (Get-IiRelativePath $Dir $_.FullName)
    }
    [IO.File]::WriteAllLines((Join-Path $Dir 'payload.manifest'), [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    @($lines).Count
}

# Every listed file must exist with its hash; no unlisted file may be there; the required files must exist.
function Test-IiPayload([string]$Dir) {
    $problems = New-Object System.Collections.Generic.List[string]
    $manifest = Join-Path $Dir 'payload.manifest'
    if (-not (Test-Path -LiteralPath $manifest)) { return [pscustomobject]@{ Ok = $false; Problems = @('payload.manifest is missing') } }
    $expected = @{}
    foreach ($line in [IO.File]::ReadAllLines($manifest)) {
        if ($line -match '^([0-9A-Fa-f]{64})  (.+)$') { $expected[$Matches[2]] = $Matches[1].ToUpperInvariant() }
        elseif ($line.Trim()) { $problems.Add("unreadable manifest line: $line") }
    }
    foreach ($rel in $script:IiRequiredPayloadFiles) {
        if (-not $expected.ContainsKey($rel)) { $problems.Add("required file not in the manifest: $rel") }
    }
    foreach ($rel in $expected.Keys) {
        $path = Join-Path $Dir $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("missing: $rel"); continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected[$rel]) { $problems.Add("hash differs: $rel") }
    }
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Recurse -File) {
        $rel = Get-IiRelativePath $Dir $f.FullName
        if ($rel -ne 'payload.manifest' -and -not $expected.ContainsKey($rel)) { $problems.Add("not in the manifest: $rel") }
    }
    [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}

# --- current.txt (same format the launcher reads) ---------------------------------------------------

function Read-IiCurrent([string]$Root) {
    $path = Join-Path $Root 'current.txt'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $o = [ordered]@{ active = ''; previous = 'none'; state = 'verified'; attempts = 0 }
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        if ($line -match '^(active|previous|state|attempts)=(.*)$') { $o[$Matches[1]] = $Matches[2].Trim() }
    }
    if ($o.active -ne 'legacy' -and -not (Test-IiVersionId $o.active)) { return $null }
    [pscustomobject]$o
}

function Write-IiCurrent([string]$Root, [string]$Active, [string]$Previous, [string]$State, [int]$Attempts = 0) {
    if ($Active -ne 'legacy' -and -not (Test-IiVersionId $Active)) { throw "not a valid version id: $Active" }
    $path = Join-Path $Root 'current.txt'
    $tmp = "$path.tmp"
    $text = "active=$Active`r`nprevious=$Previous`r`nstate=$State`r`nattempts=$Attempts`r`nupdated=$((Get-Date).ToString('s'))`r`n"
    [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $path) {
        # Replace is atomic on NTFS: the old file or the new one, never half. (The backup argument
        # must be a real path: Windows PowerShell 5.1 turns $null into "".)
        [IO.File]::Replace($tmp, $path, "$path.bak")
        Remove-Item -LiteralPath "$path.bak" -Force -ErrorAction SilentlyContinue
    } else {
        [IO.File]::Move($tmp, $path)
    }
}

# --- journal ------------------------------------------------------------------------------------

function Write-IiJournal([string]$Root, [string]$Txn, [string]$Step, [string]$To, [string]$Staging = '') {
    $path = Join-Path $Root 'journal.txt'
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, "txn=$Txn`r`nstep=$Step`r`nto=$To`r`nstaging=$Staging`r`n", (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Read-IiJournal([string]$Root) {
    $path = Join-Path $Root 'journal.txt'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $o = @{}
    foreach ($line in [IO.File]::ReadAllLines($path)) { if ($line -match '^(\w+)=(.*)$') { $o[$Matches[1]] = $Matches[2] } }
    [pscustomobject]$o
}

# An earlier run was interrupted: remove what it left that nothing points to. The active and the
# previous version are never touched.
function Resolve-IiRuntimeJournal([string]$Root) {
    $notes = New-Object System.Collections.Generic.List[string]
    $versions = Join-Path $Root 'versions'
    $journal = Read-IiJournal $Root
    $current = Read-IiCurrent $Root
    if (Test-Path -LiteralPath $versions) {
        foreach ($d in Get-ChildItem -LiteralPath $versions -Directory -Filter '*.staging-*') {
            $r = Remove-IiOwnedTree -Path $d.FullName -AllowedRoot $versions
            $notes.Add("removed an unfinished copy: $($d.Name)")
        }
        if ($journal -and $journal.to -and (Test-IiVersionId $journal.to) -and $journal.step -in 'staged', 'renamed') {
            $inUse = $current -and ($current.active -eq $journal.to -or $current.previous -eq $journal.to)
            $dir = Join-Path $versions $journal.to
            if (-not $inUse -and (Test-Path -LiteralPath $dir)) {
                [void](Remove-IiOwnedTree -Path $dir -AllowedRoot $versions)
                $notes.Add("removed a version that was never activated: $($journal.to)")
            }
        }
    }
    if ($journal) {
        Remove-Item -LiteralPath (Join-Path $Root 'journal.txt') -Force -ErrorAction SilentlyContinue
        $notes.Add("journal cleared (it said: $($journal.step))")
    }
    $notes
}

# Test hook: II_TEST_FAULT makes a step fail on purpose (never set in a real install).
function Invoke-IiFault([string]$At) {
    if ($env:II_TEST_FAULT -eq $At) { throw "injected fault at $At" }
}

# Returns @{ Id; Active; Previous } or throws; on any failure the active version is untouched.
function Install-IiRuntime {
    param([Parameter(Mandatory)][string]$Payload, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$VersionId)
    if (-not (Test-IiVersionId $VersionId)) { throw "not a valid version id: $VersionId" }
    New-Item -ItemType Directory -Force $Root | Out-Null
    $versions = Join-Path $Root 'versions'
    New-Item -ItemType Directory -Force $versions | Out-Null
    $txn = [guid]::NewGuid().ToString('N').Substring(0, 8)

    [void](Resolve-IiRuntimeJournal $Root)

    # 1. the payload is what its manifest says
    $check = Test-IiPayload $Payload
    if (-not $check.Ok) { throw "the package does not match its manifest: $($check.Problems -join '; ')" }
    Invoke-IiFault 'after-verify-payload'

    # an id that already exists with different content gets a new name
    $final = Join-Path $versions $VersionId
    $id = $VersionId
    if (Test-Path -LiteralPath $final) {
        $existing = Test-IiPayload $final
        $same = $existing.Ok -and ((Get-FileHash (Join-Path $final 'payload.manifest')).Hash -eq (Get-FileHash (Join-Path $Payload 'payload.manifest')).Hash)
        if (-not $same) {
            $n = 2
            while (Test-Path -LiteralPath (Join-Path $versions "$VersionId-$n")) { $n++ }
            $id = "$VersionId-$n"
            $final = Join-Path $versions $id
        }
    }

    $reuse = Test-Path -LiteralPath $final
    $staging = Join-Path $versions "$id.staging-$txn"
    try {
        if (-not $reuse) {
            Write-IiJournal $Root $txn 'copying' $id $staging
            # 2. copy next to the active version, then verify the copy
            New-Item -ItemType Directory -Force $staging | Out-Null
            $files = @(Get-ChildItem -LiteralPath $Payload -Recurse -File)
            $copied = 0
            foreach ($f in $files) {
                $dest = Join-Path $staging (Get-IiRelativePath $Payload $f.FullName)
                New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
                [IO.File]::Copy($f.FullName, $dest, $false)
                $copied++
                if ($env:II_TEST_FAULT -eq 'copy-interrupted' -and $copied -ge 3) { throw 'injected fault: the copy was interrupted' }
                if ($env:II_TEST_FAULT -eq 'disk-full' -and $copied -ge 2) { throw 'injected fault: There is not enough space on the disk.' }
            }
            $check = Test-IiPayload $staging
            if (-not $check.Ok) { throw "the copy does not match the manifest: $($check.Problems -join '; ')" }
            Write-IiJournal $Root $txn 'staged' $id $staging
            Invoke-IiFault 'after-staged'
            if ($env:II_TEST_FAULT -eq 'hang-after-staged') { Start-Sleep -Seconds 600 }   # a killed installer
            # 3. one atomic rename
            if ($env:II_TEST_FAULT -eq 'file-locked') { $lock = [IO.File]::Open((Join-Path $staging 'VERSION'), 'Open', 'Read', 'None') }
            try { [IO.Directory]::Move($staging, $final) } finally { if ($lock) { $lock.Close() } }
            Write-IiJournal $Root $txn 'renamed' $id ''
        }
        Invoke-IiFault 'after-rename'
        # 4. the pointer
        $old = Read-IiCurrent $Root
        $previous = if ($old) { $old.active } else { 'none' }
        if ($previous -eq $id) { $previous = $old.previous }
        if (-not $old -and (Test-Path -LiteralPath (Join-Path $Root 'ii-host.exe'))) { $previous = 'legacy' }   # a flat pre-versions install
        Invoke-IiFault 'before-pointer'
        Write-IiCurrent $Root $id $previous 'pending' 0
        Remove-Item -LiteralPath (Join-Path $Root 'journal.txt') -Force -ErrorAction SilentlyContinue
        [pscustomobject]@{ Id = $id; Active = $id; Previous = $previous }
    } catch {
        # Whatever failed, the active version was not touched; remove what this run made.
        if (Test-Path -LiteralPath $staging) { [void](Remove-IiOwnedTree -Path $staging -AllowedRoot $versions) }
        Write-IiJournal $Root $txn 'aborted' $id ''
        throw
    }
}

# After the new version has verified itself, older ones can go. Keeps the active and the previous.
function Remove-IiOldVersions([string]$Root, [int]$Keep = 2) {
    $versions = Join-Path $Root 'versions'
    $current = Read-IiCurrent $Root
    if (-not $current -or $current.state -ne 'verified' -or -not (Test-Path -LiteralPath $versions)) { return @() }
    $keepIds = @($current.active, $current.previous)
    $removed = @()
    foreach ($d in Get-ChildItem -LiteralPath $versions -Directory | Where-Object { $_.Name -notin $keepIds -and $_.Name -notlike '*.staging-*' }) {
        $r = Remove-IiOwnedTree -Path $d.FullName -AllowedRoot $versions
        if ($r.Removed -gt 0) { $removed += $d.Name }
    }
    $removed
}

# Manual or scripted rollback to the previous version.
function Invoke-IiRollback([string]$Root) {
    $current = Read-IiCurrent $Root
    if (-not $current -or $current.previous -eq 'none') { throw 'there is no previous version to go back to' }
    $prevDir = if ($current.previous -eq 'legacy') { $Root } else { Join-Path (Join-Path $Root 'versions') $current.previous }
    if (-not (Test-Path -LiteralPath (Join-Path $prevDir 'ii-host.exe'))) { throw "the previous version ($($current.previous)) is not on disk" }
    Write-IiCurrent $Root $current.previous $current.active 'rolled-back' 0
    $current.previous
}
