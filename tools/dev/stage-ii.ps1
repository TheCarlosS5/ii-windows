# Builds the runnable ii config: pristine upstream ii + our Windows overlay on top.
#   upstream/dots/.config/quickshell/ii   (end-4, untouched, so updates merge cleanly)
# + overlay/ii                            (files added or replaced for Windows)
# = build/ii                              (what quickshell runs)
$root = 'C:\Users\Calos\Desktop\ii-windows'
$src = "$root\upstream\dots\.config\quickshell\ii"
$overlay = "$root\overlay\ii"
$dest = "$root\build\ii"

New-Item -ItemType Directory -Force $dest | Out-Null
robocopy $src $dest /MIR /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
if (Test-Path $overlay) {
    robocopy $overlay $dest /E /NFL /NDL /NJH /NJS /NP | Out-Null
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
"staged ii -> $dest ($n overlay files)"
