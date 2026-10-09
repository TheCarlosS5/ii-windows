# ii-windows uninstaller: stops ii, puts Windows back exactly as it was and removes what the
# installer added (listed in install.json, shown before anything is removed).
#
#   uninstall.cmd               shows the list and asks
#   uninstall.ps1 -Yes          no questions
#   uninstall.ps1 -KeepConfig   keep ii's settings and generated colors
param([switch]$Yes, [switch]$KeepConfig)

$ErrorActionPreference = 'Continue'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\ii-windows'
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$manifestPath = Join-Path $dataDir 'install.json'

function Say($text) { Write-Host $text }
function Ask($question, $default) {
    if ($Yes) { return $default }
    $hint = 'S/n'; if (-not $default) { $hint = 's/N' }
    $answer = Read-Host "$question [$hint]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim().ToLower().StartsWith('s') -or $answer.Trim().ToLower().StartsWith('y')
}

Add-Type -Namespace IiUninstall -Name Win -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool PostMessageW(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint action, uint param, System.IntPtr data, uint flags);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr SendMessageTimeoutW(System.IntPtr h, uint msg, System.IntPtr w, string l, uint flags, uint timeout, out System.IntPtr result);
'@

$manifest = $null
if (Test-Path $manifestPath) { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json }

Say 'ii-windows - desinstalador'
Say ''
Say 'Se va a:'
Say '  - cerrar ii y devolver la barra de tareas, los iconos, los banners y los colores de Windows'
if ($manifest -and $manifest.cursor) { Say '  - devolver tu cursor anterior' }
if ($manifest) { foreach ($r in $manifest.registry) { Say "  - quitar $r" } }
if ($manifest) { foreach ($s in $manifest.shortcuts) { Say "  - borrar el acceso $s" } }
Say "  - borrar la carpeta $installDir"
if (-not $KeepConfig) { Say "  - borrar la configuracion de ii ($env:LOCALAPPDATA\quickshell)" }
Say "Se conservan las copias del registro de la instalacion en $dataDir\backup"
if (-not (Ask 'Continuar?' $true)) { Say 'Cancelado.'; exit 1 }

# 1. stop ii cleanly (it restores everything it changed), then the rescue for anything left
$hostWindow = [IiUninstall.Win]::FindWindow('IiHostWindow', [NullString]::Value)
if ($hostWindow -ne [IntPtr]::Zero) {
    [IiUninstall.Win]::PostMessageW($hostWindow, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep 4
}
$rescue = Join-Path $installDir 'rescue\ii-rescue.ps1'
if (Test-Path $rescue) { & powershell -NoProfile -ExecutionPolicy Bypass -File $rescue | Out-Null }
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$installDir*" } | Stop-Process -Force
Say 'Windows restaurado.'

# 2. the user's own cursor scheme, exactly as recorded
$cursorBackup = Join-Path $dataDir 'cursors.json'
if (Test-Path $cursorBackup) {
    # Windows PowerShell returns a JSON array as one object: unroll it.
    $saved = @(Get-Content $cursorBackup -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    $writable = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
    $ok = $true
    try {
        # Values the installer added that were not there before go away ("" is the default value).
        foreach ($name in $writable.GetValueNames()) {
            if ($name -ne '' -and -not ($saved | Where-Object { $_.name -eq $name })) { $writable.DeleteValue($name, $false) }
        }
        foreach ($v in $saved) {
            $kind = [Microsoft.Win32.RegistryValueKind]([string]$v.kind)
            $value = $v.value
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $value = [Convert]::FromBase64String($value) }
            elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $value = [int]$value }
            elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $value = [long]$value }
            $writable.SetValue([string]$v.name, $value, $kind)
        }
    } catch {
        $ok = $false
        Say "No se pudo restaurar el cursor por completo: $($_.Exception.Message)"
    }
    $writable.Close()
    [IiUninstall.Win]::SystemParametersInfoW(0x57, 0, [IntPtr]::Zero, 0x3) | Out-Null
    if ($ok) {
        Remove-Item $cursorBackup
        Say 'Cursor anterior restaurado.'
    } else {
        # The backup stays, so the restore can be repeated.
        Say "Copia del cursor conservada en $cursorBackup"
    }
}

# 3. autostart, uninstall entry, shortcuts
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ii-windows' -ErrorAction SilentlyContinue
# The logon task: removing it may need administrator rights (it was created with them).
if (Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue) {
    try { Unregister-ScheduledTask -TaskName 'ii-windows' -Confirm:$false -ErrorAction Stop }
    catch {
        Say 'Windows pedira permiso de administrador para quitar la tarea de inicio.'
        $taskScript = Join-Path $installDir 'autostart-task.ps1'
        try { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$taskScript`" -Remove" -Verb RunAs -WindowStyle Hidden -Wait } catch {}
    }
    if (Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue) { Say 'No se pudo quitar la tarea "ii-windows": borrala en el Programador de tareas.' }
}
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows' -Recurse -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ii-windows') -Recurse -Force -ErrorAction SilentlyContinue
Say 'Inicio automatico, entrada de Aplicaciones y accesos quitados.'

# 3b. the fastfetch folder on the user's PATH: only that entry goes, the rest stays as it is
$pathEntry = Join-Path $installDir 'bin'
if ($manifest -and $manifest.pathEntry) { $pathEntry = [string]$manifest.pathEntry }
$envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
if ($envKey -and ($envKey.GetValueNames() -contains 'Path')) {
    $current = [string]$envKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $entries = @($current.Split(';') | Where-Object { $_ -ne '' })
    if ($entries -contains $pathEntry) {
        $kind = $envKey.GetValueKind('Path')
        $hasBefore = $manifest -and ($manifest.PSObject.Properties.Name -contains 'pathBefore')
        if ($hasBefore -and $manifest.pathAfter -and $current -eq [string]$manifest.pathAfter) {
            # Untouched since the install: exactly the value from before.
            if ($null -eq $manifest.pathBefore) { $envKey.DeleteValue('Path') } else { $envKey.SetValue('Path', [string]$manifest.pathBefore, $kind) }
        } else {
            # Changed since then: only our entry goes.
            $rest = @($entries | Where-Object { $_ -ne $pathEntry })
            if ($rest.Count -gt 0) { $envKey.SetValue('Path', ($rest -join ';'), $kind) } else { $envKey.DeleteValue('Path') }
        }
        $out = [IntPtr]::Zero
        [IiUninstall.Win]::SendMessageTimeoutW([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'Environment', 2, 3000, [ref]$out) | Out-Null
        Say 'Comando fastfetch quitado del PATH.'
    }
}
if ($envKey) { $envKey.Close() }
# 4. files (this script may live in the folder it deletes: finish from a temporary copy)
if (-not $KeepConfig) {
    Remove-Item (Join-Path $env:LOCALAPPDATA 'quickshell') -Recurse -Force -ErrorAction SilentlyContinue
    Say 'Configuracion de ii borrada.'
}
foreach ($f in 'state.ini', 'install.json', 'banners.txt', 'theme.txt') {
    Remove-Item (Join-Path $dataDir $f) -ErrorAction SilentlyContinue
}
$self = $MyInvocation.MyCommand.Path
if ($self -like "$installDir*") {
    $cleanup = Join-Path $env:TEMP 'ii-windows-cleanup.cmd'
    # Retries while the window that ran the uninstaller lets go of the folder.
    $lines = @('@echo off', 'cd /d "%TEMP%"', 'for /l %%i in (1,1,15) do (', "  if exist `"$installDir`" rmdir /s /q `"$installDir`"", "  if not exist `"$installDir`" goto done", '  ping -n 3 127.0.0.1 >nul', ')', ':done', 'del "%~f0"')
    $lines -join "`r`n" | Set-Content $cleanup -Encoding ASCII
    Start-Process cmd.exe -ArgumentList '/c', "`"$cleanup`"" -WindowStyle Hidden
} else {
    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
}
Say "Archivos quitados. Las copias del registro siguen en $dataDir\backup (puedes borrarlas)."
Say 'ii-windows desinstalado.'
exit 0
