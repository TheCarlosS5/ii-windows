# Dot-source to get an MSVC x64 toolchain from a *portable* extraction (no Visual Studio install,
# no administrator rights) plus cmake/ninja into the current PowerShell session.
#   . .\tools\dev\vsenv-portable.ps1                         (default: %USERPROFILE%\dev\toolchain\msvc\msvc)
#   $env:II_MSVC_DIR = 'D:\msvc'; . .\tools\dev\vsenv-portable.ps1
# The extraction is produced by mmozeiko's portable-msvc.py (--vs 2022 --target x64); this script
# only reads its setup_x64.bat, so any directory with that layout works.
if (-not $env:II_MSVC_DIR) { $env:II_MSVC_DIR = "$env:USERPROFILE\dev\toolchain\msvc\msvc" }
$setup = Join-Path $env:II_MSVC_DIR 'setup_x64.bat'
if (-not (Test-Path $setup)) { throw "portable MSVC not found: $setup (set II_MSVC_DIR)" }
if (-not $env:II_VSENV) {
    cmd /c "`"$setup`" && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] }
    }
    $env:II_VSENV = '1'
}
$pyScripts = (python -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))")
$env:Path = "$pyScripts;$env:Path"
