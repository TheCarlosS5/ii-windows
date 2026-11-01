# Removes the ghost scheduled task \ii-windows that `schtasks` lists as "no se puede cargar la tarea: ii-windows" and
# cannot delete ("Acceso denegado", also as administrator). It was left by installs before the R06 fix: the old task
# \ii-windows and the new folder \ii-windows\ had the same name, and its XML file under C:\Windows\System32\Tasks went
# away while its entry in the Task Scheduler's registry (TaskCache) stayed. Those keys belong to SYSTEM, so this script
# does the cleanup through a one-time task that runs as SYSTEM, and deletes that task afterwards.
#
# Only the entry named exactly "ii-windows" is touched: its Tree key and the Tasks/Logon/Boot/Plain/Maintenance entries
# with its Id. If \ii-windows\ is also a folder (the current ii's own logon task lives in it), the folder and its task
# stay: only the ghost task's values are removed from that key.
#
#   Run from an administrator PowerShell:  powershell -ExecutionPolicy Bypass -File tools\dev\fix-ghost-task.ps1
param([switch]$WhatIf)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Abre PowerShell como administrador y vuelve a ejecutar este script.' -ForegroundColor Yellow
    exit 1
}

$work = Join-Path $env:ProgramData 'ii-windows-fix'
New-Item -ItemType Directory -Force $work | Out-Null
$log = Join-Path $work 'fix-ghost-task.log'
Remove-Item $log -ErrorAction SilentlyContinue
$dry = if ($WhatIf) { '$true' } else { '$false' }

# What SYSTEM runs (written out as a file so nothing needs quoting on the task's command line).
$inner = @"
`$ErrorActionPreference = 'Stop'
`$dry = $dry
`$log = '$log'
function Say([string]`$text) { Add-Content -Path `$log -Value `$text -Encoding UTF8 }
try {
    `$cache = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache'
    `$tree = "`$cache\Tree\ii-windows"
    `$file = Join-Path `$env:SystemRoot 'System32\Tasks\ii-windows'
    if (-not (Test-Path `$tree)) { Say 'No hay entrada \ii-windows en el registro: nada que hacer.'; exit 0 }
    `$props = Get-ItemProperty `$tree
    `$id = `$props.Id
    `$subkeys = @(Get-ChildItem `$tree -ErrorAction SilentlyContinue)
    Say ("Entrada \ii-windows: Id=" + `$id + ", subcarpetas=" + `$subkeys.Count + ", archivo XML=" + (Test-Path `$file -PathType Leaf))
    if (`$id) {
        foreach (`$kind in 'Tasks', 'Logon', 'Boot', 'Plain', 'Maintenance') {
            `$k = "`$cache\`$kind\`$id"
            if (Test-Path `$k) { Say "  borrar `$kind\`$id"; if (-not `$dry) { Remove-Item `$k -Recurse -Force } }
        }
    }
    if (`$subkeys.Count -gt 0) {
        # Also the folder \ii-windows\ of the current ii: keep it, take away only the ghost task's values.
        foreach (`$v in 'Id', 'Index') {
            if (`$null -ne `$props.`$v) { Say "  quitar el valor `$v de Tree\ii-windows (la carpeta se queda)"; if (-not `$dry) { Remove-ItemProperty `$tree -Name `$v -Force } }
        }
    } else {
        Say '  borrar Tree\ii-windows'
        if (-not `$dry) { Remove-Item `$tree -Recurse -Force }
    }
    if (Test-Path `$file -PathType Leaf) { Say "  borrar `$file"; if (-not `$dry) { Remove-Item `$file -Force } }
    Say (`$(if (`$dry) { 'Simulacion: no se cambio nada.' } else { 'Listo.' }))
} catch { Say ('ERROR: ' + `$_.Exception.Message); exit 1 }
"@
$innerPath = Join-Path $work 'fix-ghost-task-system.ps1'
Set-Content -Path $innerPath -Value $inner -Encoding UTF8

$helper = 'ii-windows-fix-ghost'
$action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$innerPath`""
schtasks /create /tn $helper /sc once /st 00:00 /sd 01/01/2030 /ru SYSTEM /rl HIGHEST /tr $action /f | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'No se pudo crear la tarea auxiliar.' -ForegroundColor Red; exit 1 }
try {
    schtasks /run /tn $helper | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    while (-not ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match 'Listo\.|Simulacion|nada que hacer|ERROR') -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
    }
} finally {
    schtasks /delete /tn $helper /f | Out-Null
    Remove-Item $innerPath -ErrorAction SilentlyContinue
}
if (Test-Path $log) { Get-Content $log } else { Write-Host 'La tarea auxiliar no dejó registro (¿no se ejecutó?).' -ForegroundColor Red; exit 1 }
Write-Host ''
Write-Host 'Comprobación (no debería salir "no se puede cargar la tarea: ii-windows"; si sale, reinicia Windows y vuelve a mirar):'
schtasks /query /fo LIST 2>&1 | Select-String 'ii-windows'
