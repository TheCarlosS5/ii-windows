# Fetches Google's material-color-utilities (Apache-2.0) C++ sources at a pinned commit into
# third_party\material-color-utilities. Used by ii-shim's `switchwall` to build the Material 3
# palette from the wallpaper (the same algorithm ii uses on Linux), without Python.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$dest = Join-Path $root 'third_party\material-color-utilities'
$url = 'https://github.com/material-foundation/material-color-utilities'
$commit = '5b3618b16fdc3825e21d5679bafd144662088ea1'

if (Test-Path (Join-Path $dest '.git')) {
    $have = (git -C $dest rev-parse HEAD).Trim()
    if ($have -eq $commit) { "material-color-utilities already at $commit"; return }
} else {
    New-Item -ItemType Directory -Force $dest | Out-Null
    git -C $dest init -q
    git -C $dest remote add origin $url
}
# Only the C++ sources and the license.
git -C $dest sparse-checkout set --no-cone /cpp/ /LICENSE
git -C $dest fetch -q --depth 1 --filter=blob:none origin $commit
git -C $dest checkout -q --detach $commit
$have = (git -C $dest rev-parse HEAD).Trim()
if ($have -ne $commit) { throw "unexpected commit $have" }
"material-color-utilities $commit -> $dest"
