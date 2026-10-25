# Plan 1.4: signs ii-windows' own executables (Authenticode, SHA-256, RFC 3161 timestamp) so SmartScreen and the
# antivirus see who made them. make-package.ps1 runs it on app\ before the payload manifest is written (a signature
# changes the file) and on the launcher next to the installer.
#
#   sign.ps1 -Path <folder or file> [...]
#
# The certificate is never in the repository. One of:
#   II_SIGN_THUMBPRINT   a code-signing certificate in the user's or machine's store (a hardware token, Azure Trusted
#                        Signing's local client, a certificate from a CA)
#   II_SIGN_PFX + II_SIGN_PFX_PASSWORD   a .pfx file (CI secrets, e.g. SignPath Foundation's or your own)
#   II_SIGN_TIMESTAMP    timestamp server (default http://timestamp.digicert.com)
# Without any of them nothing is signed and the build says so: an unsigned build is fine for testing, not for a
# release (docs/PUBLICAR.md).
#
# Only ii-windows' own programs are signed: ii-host, ii-launcher, ii-shim (and its copies under the Linux names),
# quickshell.exe. Qt's DLLs, fastfetch and the MSVC runtime keep their makers' signatures.
param([Parameter(Mandatory = $true)][string[]]$Path)
$ErrorActionPreference = 'Stop'

$own = @('ii-host.exe', 'ii-launcher.exe', 'ii-shim.exe', 'quickshell.exe')
$files = foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Recurse -File -Filter *.exe | Where-Object {
            # ii-shim's copies (notify-send.exe, hyprpicker.exe...) are the same program: same size and bytes as ii-shim
            $_.Name -in $own -or ($_.DirectoryName -like '*\bin' -and (Test-Path (Join-Path $_.DirectoryName 'ii-shim.exe')) -and
                $_.Length -eq (Get-Item (Join-Path $_.DirectoryName 'ii-shim.exe')).Length)
        }
    } elseif (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
}
$files = @($files | Sort-Object FullName -Unique)

$thumb = $env:II_SIGN_THUMBPRINT
$pfx = $env:II_SIGN_PFX
if (-not $thumb -and -not $pfx) {
    Write-Host "sign: NOT SIGNED ($($files.Count) programs): set II_SIGN_THUMBPRINT or II_SIGN_PFX for a release (docs/PUBLICAR.md)"
    return
}

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
if (-not $signtool) { throw 'signtool.exe not found (Windows SDK: "Windows SDK Signing Tools for Desktop Apps")' }
$timestamp = if ($env:II_SIGN_TIMESTAMP) { $env:II_SIGN_TIMESTAMP } else { 'http://timestamp.digicert.com' }

$signArgs = @('sign', '/fd', 'SHA256', '/tr', $timestamp, '/td', 'SHA256', '/d', 'ii-windows', '/du', 'https://github.com/TheCarlosS5/ii-windows')
if ($thumb) { $signArgs += @('/sha1', $thumb) } else { $signArgs += @('/f', $pfx); if ($env:II_SIGN_PFX_PASSWORD) { $signArgs += @('/p', $env:II_SIGN_PFX_PASSWORD) } }
foreach ($f in $files) {
    & $signtool.FullName @signArgs $f.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $($f.FullName)" }
    $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
    if ($sig.Status -ne 'Valid') { throw "signature of $($f.Name) is $($sig.Status)" }
}
Write-Host "sign: signed and verified $($files.Count) programs"
