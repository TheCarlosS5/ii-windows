# Turns a crash location into function, file and line (plan 2026-10-31, A3.2).
#
#   symbolize.ps1 <crash.json | module+0xoffset> [-Symbols <folder or ...-symbols.zip>]
#
# The crash JSON is what quickshell-windows' crash handler writes to %LOCALAPPDATA%\ii-windows\crashes. The symbols
# are the PDB + exe pairs make-package.ps1 puts in out\ii-windows-<version>-symbols(.zip) (also a release asset). With
# no -Symbols, the local build folders are tried (quickshell\build, host\build), which is only right for a crash of
# exactly that build. For a release without symbols (before 0.6.1) use tools\dev\crash-locate.py on its exe.
param([Parameter(Mandatory = $true, Position = 0)][string]$Where, [string]$Symbols = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$llvm = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\x64\bin'
if (-not (Test-Path "$llvm\llvm-symbolizer.exe")) { throw "llvm-symbolizer not found in $llvm" }

if (Test-Path -LiteralPath $Where -PathType Leaf) {
    $json = Get-Content -LiteralPath $Where -Raw | ConvertFrom-Json
    Write-Host "crash: $($json.code) $($json.kind) in $($json.subsystem), version $($json.version), $($json.uptimeSeconds) s after start"
    $Where = $json.where
}
if ($Where -notmatch '^(.+)\+0x([0-9A-Fa-f]+)$') { throw "expected module+0xoffset, got '$Where'" }
$module = $matches[1]
$offset = [Convert]::ToUInt64($matches[2], 16)

$dirs = @()
if ($Symbols) {
    if ($Symbols -like '*.zip') {
        $tmp = Join-Path $env:TEMP ('ii-symbols-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Expand-Archive -LiteralPath $Symbols -DestinationPath $tmp
        $dirs += $tmp
    } else { $dirs += $Symbols }
} else {
    $dirs += "$root\quickshell\build", "$root\host\build-clang", "$root\host\build"
}
$exe = $dirs | ForEach-Object { Join-Path $_ $module } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw "$module not found in: $($dirs -join ', ')" }
$headers = (& "$llvm\llvm-readobj.exe" --file-headers $exe) -join "`n"
if ($headers -notmatch 'ImageBase: 0x([0-9A-Fa-f]+)') { throw "cannot read the image base of $exe" }
$address = [Convert]::ToUInt64($matches[1], 16) + $offset
Write-Host ("{0} (image base + 0x{1:x} = 0x{2:x})" -f $exe, $offset, $address)
& "$llvm\llvm-symbolizer.exe" --obj=$exe --inlines --pretty-print ('0x{0:x}' -f $address)
