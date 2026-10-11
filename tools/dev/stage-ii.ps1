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
# Linux tools (keyring, ...) pointed at ii-shim directly.
& python -I "$root\tools\port\patch_ii_tools.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_tools.py failed" }
# Audit 2026-10-09, P0: battery suspend, booru, popups without a window per hover, widgets.
& python -I "$root\tools\port\patch_ii_p0.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_p0.py failed" }
# Desktops like Hyprland's workspaces: drag windows to other desktops, empty ones dropped.
& python -I "$root\tools\port\patch_ii_desktops.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_desktops.py failed" }
# Lock: ii's look around Windows' secure lock screen.
& python -I "$root\tools\port\patch_ii_lock.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_lock.py failed" }
# Panels slide in and out (Hyprland's compositor did that on Linux).
& python -I "$root\tools\port\patch_ii_anim.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_anim.py failed" }
# Settings: hide what does nothing on Windows (Codex).
& python -I "$root\tools\port\patch_ii_settings.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_settings.py failed" }
& python -I "$root\tools\port\patch_ii_ai.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_ai.py failed" }
# Shell side of the shortcuts shared/actions.json adds (Win+I -> ii's settings) (U02).
& python -I "$root\tools\port\patch_ii_shortcuts.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_shortcuts.py failed" }
# Live Linux routes: pin without the cursor dance, language list without find, cache folders (C12).
& python -I "$root\tools\port\patch_ii_c12.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_c12.py failed" }
# Timers: monotonic guard against clock changes, refresh only what is on screen (P11).
& python -I "$root\tools\port\patch_ii_timers.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_timers.py failed" }
# Secrets: the Gelbooru key moves from config.json to the per-user secret store (R11).
& python -I "$root\tools\port\patch_ii_secrets.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_secrets.py failed" }
"staged ii -> $dest ($n overlay files)"
