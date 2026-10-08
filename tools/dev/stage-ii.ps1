# Builds the runnable ii config: pristine upstream ii + our Windows overlay on top.
#   upstream/dots/.config/quickshell/ii   (end-4, untouched, so updates merge cleanly)
# + overlay/ii                            (files added or replaced for Windows)
# = build/ii                              (what quickshell runs)
#   -Dest <dir>   stage somewhere else (a private copy while build/ii is in use)
#   -NoSidebar    skip patch_ii_sidebar.py and the sidebar overlay files (unfinished work)
param([switch]$NoSidebar, [string]$Dest = '')
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$src = "$root\upstream\dots\.config\quickshell\ii"
$overlay = "$root\overlay\ii"
$dest = if ($Dest) { $Dest } else { "$root\build\ii" }
# The patch scripts edit this directory.
$env:II_STAGE_DIR = $dest

New-Item -ItemType Directory -Force $dest | Out-Null
robocopy $src $dest /MIR /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
if (Test-Path $overlay) {
    $exclude = if ($NoSidebar) { @('/XD', "$overlay\modules\ii\sidebarRight") } else { @() }
    robocopy $overlay $dest /E /NFL /NDL /NJH /NJS /NP @exclude | Out-Null
    $n = (Get-ChildItem $overlay -Recurse -File).Count
} else { $n = 0 }
# Small exact-match edits (Windows defaults); fails loudly if upstream moved the code.
& python -I "$root\tools\port\patch_ii.py" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "patch_ii.py failed" }
# Network fetches (curl/jq through bash upstream) go through ii-shim instead.
if (Test-Path "$root\tools\port\patch_ii_net.py") {
    & python -I "$root\tools\port\patch_ii_net.py" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "patch_ii_net.py failed" }
}
# Right sidebar on Windows (night light, power profile, header, toggles).
if (-not $NoSidebar -and (Test-Path "$root\tools\port\patch_ii_sidebar.py")) {
    & python -I "$root\tools\port\patch_ii_sidebar.py" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "patch_ii_sidebar.py failed" }
}
& python -I "$root\tools\port\patch_ii_brightness.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_brightness.py failed" }
# Desktop widgets: more widgets, edit mode, sizes, spectrum, their settings.
& python -I "$root\tools\port\patch_ii_widgets.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_widgets.py failed" }
"staged ii -> $dest ($n overlay files)"
