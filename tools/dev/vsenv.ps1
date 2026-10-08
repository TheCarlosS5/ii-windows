# Dot-source to get the MSVC x64 toolchain + Qt + CMake/Ninja into the current PowerShell session.
#   . .\tools\dev\vsenv.ps1     (Qt from $env:QTDIR, default %USERPROFILE%\dev\Qt\6.12.0-msvc2022_64)
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
if (-not $env:II_VSENV) {
    cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] }
    }
    $env:II_VSENV = '1'
}
if (-not $env:QTDIR) { $env:QTDIR = "$env:USERPROFILE\dev\Qt\6.12.0-msvc2022_64" }
$llvm = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\x64\bin'
$pyScripts = (python -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))")
$env:Path = "$env:QTDIR\bin;$llvm;$pyScripts;$env:Path"
$env:CMAKE_PREFIX_PATH = $env:QTDIR
