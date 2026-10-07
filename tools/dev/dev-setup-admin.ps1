# One-time developer setup that needs administrator rights.
# Run elevated. Everything here is official Microsoft software and can be undone:
#   - Restore point:      Configuración > Sistema > Protección del sistema
#   - VS Build Tools:     Configuración > Aplicaciones > "Visual Studio Build Tools 2022" > Desinstalar
#   - Windows Sandbox:    Disable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
param([string]$Log = "$env:TEMP\ii-dev-setup-admin.log")

Start-Transcript -Path $Log -Append | Out-Null
$ErrorActionPreference = 'Continue'

Write-Host "== 1/3 Restore point"
try {
    Checkpoint-Computer -Description "ii-windows: before dev tools" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
} catch {
    Write-Host "Restore point failed ($_). System Protection is probably off on C:, enabling it and retrying"
    Enable-ComputerRestore -Drive "C:\"
    Checkpoint-Computer -Description "ii-windows: before dev tools" -RestorePointType MODIFY_SETTINGS
}
Get-ComputerRestorePoint | Select-Object -Last 3 | Format-Table -AutoSize | Out-Host

Write-Host "== 2/3 Windows Sandbox feature"
$f = Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
Write-Host "Sandbox state before: $($f.State)"
if ($f.State -ne 'Enabled') {
    Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart | Out-Host
}

Write-Host "== 3/3 Visual Studio Build Tools 2022 (C++ workload, Windows SDK, clang-cl)"
winget install --id Microsoft.VisualStudio.2022.BuildTools --source winget --accept-package-agreements --accept-source-agreements --silent --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.VC.ATL"
Write-Host "winget exit: $LASTEXITCODE"

Write-Host "== done"
Stop-Transcript | Out-Null
