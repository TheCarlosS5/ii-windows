# Signs a release's release.json for the updater (plan 2026-10-31, B1). PowerShell 7.
#
#   sign-release.ps1 -File out\<name>-release.json [-KeyDir <folder>] [-Key current|backup]
#       writes <file>.sig: base64 of the 64-byte ECDSA P-256 signature (r||s, IEEE P1363) of the file's exact bytes
#   sign-release.ps1 -NewKeys [-KeyDir <folder>]
#       creates the key pairs "current" and "backup" (if missing) and prints their public keys as the C++ arrays
#       host/src/updater.cpp embeds
#   sign-release.ps1 -Verify -File <file>   checks <file>.sig against both public keys
#
# The private keys NEVER go into the repository: %USERPROFILE%\.ii-release-key by default. Keep a copy of that folder
# on a USB stick: without the key no update can be published for installed copies (they would have to install by hand).
# The backup key is for when the current one is lost or exposed: releases signed with it are still accepted.
param([string]$File = '', [string]$KeyDir = "$env:USERPROFILE\.ii-release-key", [ValidateSet('current', 'backup')][string]$Key = 'current',
      [switch]$NewKeys, [switch]$Verify)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'run with pwsh (PowerShell 7): the ECDsa APIs used here need .NET 5+' }

function Get-KeyPath([string]$name) { Join-Path $KeyDir "$name.pkcs8" }

function Show-PublicKey([string]$name) {
    $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
    $ecdsa.ImportPkcs8PrivateKey([IO.File]::ReadAllBytes((Get-KeyPath $name)), [ref]0)
    $q = $ecdsa.ExportParameters($false).Q
    $hex = { param($bytes) ($bytes | ForEach-Object { '0x{0:x2}' -f $_ }) -join ', ' }
    "// $name key"
    "{ {$(& $hex $q.X)},"
    "  {$(& $hex $q.Y)} },"
}

if ($NewKeys) {
    New-Item -ItemType Directory -Force $KeyDir | Out-Null
    foreach ($name in 'current', 'backup') {
        $path = Get-KeyPath $name
        if (Test-Path $path) { Write-Host "$name key already exists: $path (kept)"; continue }
        $ecdsa = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
        [IO.File]::WriteAllBytes($path, $ecdsa.ExportPkcs8PrivateKey())
        Write-Host "created $name key: $path"
    }
    # Only the user may read the folder.
    & icacls $KeyDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
    Show-PublicKey 'current'
    Show-PublicKey 'backup'
    exit 0
}

if (-not $File -or -not (Test-Path $File)) { throw 'give -File <release.json>' }
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $File))

if ($Verify) {
    $sig = [Convert]::FromBase64String((Get-Content "$File.sig" -Raw).Trim())
    foreach ($name in 'current', 'backup') {
        if (-not (Test-Path (Get-KeyPath $name))) { continue }
        $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
        $ecdsa.ImportPkcs8PrivateKey([IO.File]::ReadAllBytes((Get-KeyPath $name)), [ref]0)
        if ($ecdsa.VerifyData($bytes, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256)) { Write-Host "valid ($name key)"; exit 0 }
    }
    Write-Host 'NOT valid'; exit 1
}

$path = Get-KeyPath $Key
if (-not (Test-Path $path)) { throw "no $Key key at $path (sign-release.ps1 -NewKeys)" }
$ecdsa = [System.Security.Cryptography.ECDsa]::Create()
$ecdsa.ImportPkcs8PrivateKey([IO.File]::ReadAllBytes($path), [ref]0)
$signature = $ecdsa.SignData($bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
if ($signature.Length -ne 64) { throw "unexpected signature length $($signature.Length)" }
[IO.File]::WriteAllText("$File.sig", [Convert]::ToBase64String($signature))
Write-Host "signed ($Key key): $File.sig"
