# Fetches the Bibata Modern Classic cursors for Windows (ful1e5/Bibata_Cursor v2.0.7, GPL-3.0),
# the cursor theme of illogical-impulse, into third_party\cursors\Bibata-Modern-Classic.
# The release's install.inf is not used: the installer applies the cursors itself (per user,
# with a backup of the current scheme).
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$url = 'https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic-Windows.zip'
$sha256 = 'B98ECA4077D6E7796FF7E710E4D220CA13439F1118160D1E7B3DB9E91FDEC2BE'
$dest = Join-Path $root 'third_party\cursors\Bibata-Modern-Classic'
$download = Join-Path $root 'third_party\cursors\Bibata-Modern-Classic-Windows.zip'

New-Item -ItemType Directory -Force (Split-Path $download) | Out-Null
if (-not (Test-Path $download) -or (Get-FileHash $download -Algorithm SHA256).Hash -ne $sha256) {
    Invoke-WebRequest $url -OutFile $download -UseBasicParsing
}
$hash = (Get-FileHash $download -Algorithm SHA256).Hash
if ($hash -ne $sha256) { Remove-Item $download; throw "Bibata download hash mismatch: $hash" }

Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
$unpack = Join-Path $env:TEMP "ii-bibata-$(Get-Random)"
Expand-Archive $download $unpack
# Only cursor files and the license text are kept.
New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem (Join-Path $unpack 'Bibata-Modern-Classic-Regular-Windows') -Include *.cur, *.ani -Recurse | Copy-Item -Destination $dest
Get-ChildItem $unpack -Recurse -Include LICENSE*, *.txt | Copy-Item -Destination $dest -ErrorAction SilentlyContinue
Remove-Item $unpack -Recurse -Force
"Bibata Modern Classic: $((Get-ChildItem $dest -Include *.cur, *.ani -Recurse).Count) cursors -> $dest"
