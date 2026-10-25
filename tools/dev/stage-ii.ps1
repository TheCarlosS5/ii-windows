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
# The format version of config.json, so a build can tell a file from a newer ii (D01).
& python -I "$root\tools\port\patch_ii_config.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_config.py failed" }
# Timers: monotonic guard against clock changes, refresh only what is on screen (P11).
& python -I "$root\tools\port\patch_ii_timers.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_timers.py failed" }
# Secrets: the Gelbooru key moves from config.json to the per-user secret store (R11).
& python -I "$root\tools\port\patch_ii_secrets.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_secrets.py failed" }
# UX round 2026-10-15: dock options, bar, battery, defaults.
& python -I "$root\tools\port\patch_ii_ux.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_ux.py failed" }
& python -I "$root\tools\port\patch_ii_ux2.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_ux2.py failed" }
# Settings in sections that make sense, the About page, the guided tour.
& python -I "$root\tools\port\patch_ii_settings2.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_settings2.py failed" }
# The app store (winget): where it opens from and its Spanish.
& python -I "$root\tools\port\patch_ii_store.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_store.py failed" }
# Tray overflow by click, overview modes (Win = app grid), launch counter, external wallpapers.
& python -I "$root\tools\port\patch_ii_ux3.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_ux3.py failed" }
# Visual polish (2026-10-16): Spanish texts left in English, cut labels, cheatsheet keys, minimized windows.
& python -I "$root\tools\port\patch_ii_visual.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_visual.py failed" }
# Startup work on slow PCs (2026-10-17): app list built once, not once per app
& python -I "$root\tools\port\patch_ii_perf.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_perf.py failed" }
# Night round features (2026-10-17): what uses the PC the most, in the resources popup.
& python -I "$root\tools\port\patch_ii_night.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_night.py failed" }
# Round of 2026-10-18: a new install keeps Windows' wallpaper, the tour opens what it explains, lyrics on the desktop.
& python -I "$root\tools\port\patch_ii_ronda18.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_ronda18.py failed" }
# Plan of 2026-10-24: night light off by default, the wallpaper never falls back to upstream's, launcher created early.
& python -I "$root\tools\port\patch_ii_plan24.py" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "patch_ii_plan24.py failed" }
# Every folder/file the QML imports must be there and not empty (a submodule that was never
# initialised leaves an empty folder, and the shell then dies on start): refuse to stage such a tree.
$importCheck = & python -I "$root\tools\dev\check-qml-imports.py" $dest
if ($LASTEXITCODE -ne 0) { throw "the staged ii has imports that do not resolve (is the upstream submodule initialised? git -C upstream submodule update --init):`n$($importCheck -join "`n")" }
"staged ii -> $dest ($n overlay files)"
