# What ii-windows owns on disk, and a deleter that can only touch that (R04).
# Dot-sourced by uninstall.ps1 (and by the tests, against a throwaway LOCALAPPDATA).
#
# The rule: ii deletes only paths that are on a fixed list below, resolved under a fixed root,
# and never follows a junction or symbolic link out of it. install.json is NOT a source of paths
# to delete: a corrupt or hand-edited manifest therefore cannot point the uninstaller anywhere.
#
# %LOCALAPPDATA%\quickshell is shared with every other Quickshell configuration the user has, so
# the folder as a whole is never removed; only ii's own subfolders in it are.

function Get-IiFullPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) { $full = $full.TrimEnd('\') }
    return $full
}

# True when $Path is below $Root (never equal to it, never a sibling with the same prefix).
function Test-IiPathInside([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $p = Get-IiFullPath $Path
        $r = Get-IiFullPath $Root
    } catch { return $false }
    if ($r.Length -le [IO.Path]::GetPathRoot($r).Length) { return $false } # a drive root is never an allowed root
    return $p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-IiReparsePoint([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch { return $false }
}

# The paths ii owns under a given %LOCALAPPDATA%. Kind decides which switches keep them:
#   config / state   -KeepConfig keeps them
#   secrets          kept by -KeepSecrets or -KeepConfig (API keys stay usable after a reinstall)
#   cache            always regenerable, removed unless -KeepConfig
function Get-IiOwnedPaths([string]$LocalAppData) {
    $qs = Join-Path $LocalAppData 'quickshell'
    $data = Join-Path $LocalAppData 'ii-windows'
    @(
        [pscustomobject]@{ Kind = 'config';  Root = $qs;   Path = (Join-Path $qs 'illogical-impulse');          What = 'configuracion de ii' }
        [pscustomobject]@{ Kind = 'state';   Root = $qs;   Path = (Join-Path $qs 'State\user');                 What = 'colores generados y estado de ii' }
        [pscustomobject]@{ Kind = 'state';   Root = $qs;   Path = (Join-Path $qs 'cache\notifications');        What = 'historial de avisos de ii' }
        [pscustomobject]@{ Kind = 'cache';   Root = $data; Path = (Join-Path $data 'cache');                    What = 'cache de iconos de ii' }
        [pscustomobject]@{ Kind = 'secrets'; Root = $data; Path = (Join-Path $data 'secrets');                  What = 'claves guardadas (DPAPI)' }
    )
}

# Deletes a file or folder tree, but only below $AllowedRoot, and without ever recursing through a
# link. A link found inside the tree is removed as a link; what it points to is left alone.
# Returns @{ Removed = <count>; Skipped = <reasons[]>; Errors = <messages[]> }.
function Remove-IiOwnedTree([string]$Path, [string]$AllowedRoot) {
    $result = [pscustomobject]@{ Removed = 0; Skipped = @(); Errors = @() }
    if (-not (Test-IiPathInside $Path $AllowedRoot)) {
        $result.Skipped += "fuera de la carpeta permitida, no se toca: $Path"
        return $result
    }
    $full = Get-IiFullPath $Path
    # An ancestor that is a link would make $Path resolve somewhere else entirely.
    $cursor = Split-Path $full -Parent
    $rootFull = Get-IiFullPath $AllowedRoot
    while ($cursor -and $cursor.Length -gt $rootFull.Length) {
        if (Test-IiReparsePoint $cursor) {
            $result.Skipped += "el camino pasa por un enlace ($cursor), no se toca: $Path"
            return $result
        }
        $cursor = Split-Path $cursor -Parent
    }
    if (-not (Test-Path -LiteralPath $full)) { return $result }

    $walk = {
        param([string]$Node)
        $attrs = [IO.File]::GetAttributes($Node)
        $isLink = [bool]($attrs -band [IO.FileAttributes]::ReparsePoint)
        $isDir = [bool]($attrs -band [IO.FileAttributes]::Directory)
        try {
            if ($isLink) {
                # Directory.Delete(path) on a junction/symlink removes the link, not its target.
                if ($isDir) { [IO.Directory]::Delete($Node) } else { [IO.File]::Delete($Node) }
                $result.Removed++
            } elseif ($isDir) {
                foreach ($child in [IO.Directory]::GetFileSystemEntries($Node)) { & $walk $child }
                [IO.Directory]::Delete($Node)
                $result.Removed++
            } else {
                if ($attrs -band [IO.FileAttributes]::ReadOnly) { [IO.File]::SetAttributes($Node, [IO.FileAttributes]::Normal) }
                [IO.File]::Delete($Node)
                $result.Removed++
            }
        } catch { $result.Errors += "${Node}: $($_.Exception.Message)" }
    }
    & $walk $full
    return $result
}

# Removes an empty folder and nothing else (Directory.Delete without recursion fails if it has content).
function Remove-IiEmptyDir([string]$Path, [string]$AllowedRoot) {
    if (-not (Test-IiPathInside $Path $AllowedRoot)) { return }
    try { if ((Test-Path -LiteralPath $Path) -and -not (Test-IiReparsePoint $Path)) { [IO.Directory]::Delete($Path) } } catch {}
}

# The data side of an uninstall. Returns the list of messages to show.
function Invoke-IiDataRemoval([string]$LocalAppData, [switch]$KeepConfig, [switch]$KeepSecrets) {
    $messages = @()
    foreach ($owned in (Get-IiOwnedPaths $LocalAppData)) {
        $keep = switch ($owned.Kind) {
            'config'  { [bool]$KeepConfig }
            'state'   { [bool]$KeepConfig }
            'cache'   { [bool]$KeepConfig }
            'secrets' { [bool]($KeepConfig -or $KeepSecrets) }
        }
        if ($keep) { if (Test-Path -LiteralPath $owned.Path) { $messages += "Se conserva: $($owned.What) ($($owned.Path))" }; continue }
        $r = Remove-IiOwnedTree -Path $owned.Path -AllowedRoot $owned.Root
        if ($r.Removed -gt 0) { $messages += "Borrado: $($owned.What)" }
        foreach ($s in $r.Skipped) { $messages += $s }
        foreach ($e in $r.Errors) { $messages += "No se pudo borrar: $e" }
    }
    # Folders shared with other programs are only tidied when nothing is left in them.
    $qs = Join-Path $LocalAppData 'quickshell'
    Remove-IiEmptyDir (Join-Path $qs 'State') $qs
    Remove-IiEmptyDir (Join-Path $qs 'cache') $qs
    Remove-IiEmptyDir $qs $LocalAppData
    return $messages
}

# Processes of this installation only: the executable must live under $InstallDir.
function Get-IiInstalledProcesses([string]$InstallDir, [string[]]$Names = @('quickshell', 'ii-host')) {
    Get-Process -Name $Names -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch {}
        $p -and (Test-IiPathInside $p $InstallDir)
    }
}
