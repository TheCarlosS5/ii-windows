# Fetches fastfetch for Windows (fastfetch-cli/fastfetch 2.69.0, MIT) into third_party\fastfetch.
# ii-windows ships it with its own config and logo (extras\fastfetch) as the `fastfetch` command.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$url = 'https://github.com/fastfetch-cli/fastfetch/releases/download/2.69.0/fastfetch-windows-amd64.zip'
$sha256 = 'ABA011C1C45D1A6BDCF52098DD0B9AFE990FE444180BC491E87F36670F1452EF'
$dest = Join-Path $root 'third_party\fastfetch'
$download = Join-Path $root 'third_party\fastfetch-windows-amd64.zip'

New-Item -ItemType Directory -Force (Split-Path $download) | Out-Null
if (-not (Test-Path $download) -or (Get-FileHash $download -Algorithm SHA256).Hash -ne $sha256) {
    Invoke-WebRequest $url -OutFile $download -UseBasicParsing
}
$hash = (Get-FileHash $download -Algorithm SHA256).Hash
if ($hash -ne $sha256) { Remove-Item $download; throw "fastfetch download hash mismatch: $hash" }

Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
$unpack = Join-Path $env:TEMP "ii-fastfetch-$(Get-Random)"
Expand-Archive $download $unpack
# The program, the DLLs it loads and its license; not flashfetch or the presets.
New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem $unpack -File | Where-Object { $_.Name -in 'fastfetch.exe', 'LICENSE' -or $_.Extension -eq '.dll' } | Copy-Item -Destination $dest
Remove-Item $unpack -Recurse -Force
"fastfetch: $((Get-ChildItem $dest).Name -join ', ') -> $dest"
