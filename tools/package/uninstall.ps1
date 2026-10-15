# ii-windows uninstaller: stops ii, puts Windows back exactly as it was and removes what the
# installer added (listed in install.json, shown before anything is removed).
#
#   uninstall.cmd               shows the list and asks
#   uninstall.ps1 -Yes          no questions
#   uninstall.ps1 -KeepConfig   keep ii's settings, generated colors, notification history and saved keys
#   uninstall.ps1 -KeepSecrets  delete the rest but keep the saved keys (DPAPI) for a reinstall
#   uninstall.ps1 -Sandbox      for tests only (see install.ps1 -Sandbox): files and recorded changes of a
#                               throwaway LOCALAPPDATA; never closes the real ii, never touches its
#                               task, uninstall entry or Windows Terminal profiles
# Only ii's own folders are ever deleted (see ii-ownership.ps1); other Quickshell configurations in
# %LOCALAPPDATA%\quickshell are never touched, with or without -KeepConfig.
param([switch]$Yes, [switch]$KeepConfig, [switch]$KeepSecrets, [switch]$Sandbox)

$ErrorActionPreference = 'Continue'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\ii-windows'
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$manifestPath = Join-Path $dataDir 'install.json'
$ownership = Join-Path $PSScriptRoot 'ii-ownership.ps1'
if (-not (Test-Path -LiteralPath $ownership)) { throw "Falta ii-ownership.ps1 junto al desinstalador; no se borra nada sin la lista de lo que es de ii." }
. $ownership
$changesLib = Join-Path $PSScriptRoot 'ii-changes.ps1'
if (-not (Test-Path -LiteralPath $changesLib)) { throw "Falta ii-changes.ps1 junto al desinstalador; no se deshace nada del registro sin saber que es de ii." }
. $changesLib

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
# Manifests from before changes[] (0.1.3 and earlier): the GPU preference and the Run entry become
# owned changes when they are provably still ii's.
if ($manifest) { Import-IiLegacyChanges $manifest }

Say 'ii-windows - desinstalador'
Say ''
Say 'Se va a:'
Say '  - cerrar ii y devolver la barra de tareas, los iconos, los banners y los colores de Windows'
if ($manifest -and $manifest.cursor) { Say '  - devolver tu cursor anterior' }
if ($manifest) { foreach ($r in $manifest.registry) { Say "  - quitar $r" } }
if ($manifest) { foreach ($s in $manifest.shortcuts) { Say "  - borrar el acceso $s" } }
if ($manifest) { foreach ($font in $manifest.fonts) { Say "  - borrar la fuente $($font.file)" } }
Say '  - borrar los perfiles y colores de ii en Windows Terminal'
Say "  - borrar la carpeta $installDir"
foreach ($owned in (Get-IiOwnedPaths $env:LOCALAPPDATA)) {
    $kept = switch ($owned.Kind) { 'secrets' { $KeepConfig -or $KeepSecrets } default { [bool]$KeepConfig } }
    if (Test-Path -LiteralPath $owned.Path) {
        if ($kept) { Say "  - conservar $($owned.What) ($($owned.Path))" } else { Say "  - borrar $($owned.What) ($($owned.Path))" }
    }
}
Say '  - no se toca nada mas de Quickshell: otras configuraciones suyas siguen como estaban'
Say "Se conservan las copias del registro de la instalacion en $dataDir\backup"
if (-not (Ask 'Continuar?' $true)) { Say 'Cancelado.'; exit 1 }

# 1. stop ii cleanly (it restores everything it changed), then the rescue for anything left
$hostWindow = if ($Sandbox) { [IntPtr]::Zero } else { [IiUninstall.Win]::FindWindow('IiHostWindow', [NullString]::Value) }
if ($hostWindow -ne [IntPtr]::Zero) {
    [IiUninstall.Win]::PostMessageW($hostWindow, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep 4
}
$rescue = Join-Path $installDir 'rescue\ii-rescue.ps1'
if ((Test-Path $rescue) -and -not $Sandbox) { & powershell -NoProfile -ExecutionPolicy Bypass -File $rescue | Out-Null }
Get-IiInstalledProcesses $installDir | Stop-Process -Force
Say 'Windows restaurado.'

# 2. everything ii changed in the registry that was not its own: each value goes back to its
# original only if it is still what ii put there. A value the user changed afterwards stays theirs.
$haveCursorChanges = $false
if ($manifest -and $manifest.changes) {
    foreach ($change in @($manifest.changes | Where-Object { $_ })) {
        if ($change.id -like 'cursor:*') { $haveCursorChanges = $true }
        $result = Restore-IiOwnedRegValue $manifest ([string]$change.id)
        switch ($result) {
            'restored'     { Say "Devuelto a su valor anterior: $($change.id)" }
            'deleted'      { Say "Quitado (no existia antes de ii): $($change.id)" }
            'user-changed' { Say "Lo cambiaste despues de instalar ii; se respeta tu valor: $($change.id)" }
        }
    }
    if ($haveCursorChanges) { [IiUninstall.Win]::SystemParametersInfoW(0x57, 0, [IntPtr]::Zero, 0x3) | Out-Null }   # SPI_SETCURSORS
}

# Installs from before changes[] recorded the whole cursor key in cursors.json. Only the values that
# still point into ii's own folder are put back; a cursor chosen since stays.
$cursorBackup = Join-Path $dataDir 'cursors.json'
if ((Test-Path $cursorBackup) -and -not $haveCursorChanges) {
    $saved = @(Get-Content $cursorBackup -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    $writable = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
    $ok = $true
    $ours = {
        param($name)
        $raw = [string]$writable.GetValue($name, '', 'DoNotExpandEnvironmentNames')
        if ($name -eq '') { return $raw -eq 'Bibata Modern Classic (ii-windows)' }
        return [bool]$raw -and $raw.StartsWith($installDir + '\', [StringComparison]::OrdinalIgnoreCase)
    }
    try {
        foreach ($name in $writable.GetValueNames()) {
            if ($name -ne '' -and -not ($saved | Where-Object { $_.name -eq $name }) -and (& $ours $name)) { $writable.DeleteValue($name, $false) }
        }
        foreach ($v in $saved) {
            if (-not (& $ours ([string]$v.name))) { Say "Cursor cambiado despues de instalar ii; se respeta: $($v.name)"; continue }
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

# 2b. the wallpaper Windows had before ii (ii makes the picture chosen in it Windows' wallpaper too; the first
# time it noted what Windows had, in wallpaper-sync.ini)
if (-not $Sandbox) {
    $switchwall = Get-ChildItem -LiteralPath $installDir -Recurse -Filter switchwall.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($switchwall) {
        & $switchwall.FullName --restore-windows | Out-Null
        if ($LASTEXITCODE -eq 0) { Say 'Fondo de pantalla de Windows devuelto.' }
    }
}

# 3. autostart, uninstall entry, shortcuts
# The logon task: only ours (per user, \ii-windows\Logon-<SID>), plus the old flat \ii-windows task if
# it is provably this user's and this installation's. Another user's task, or one with that name
# from somewhere else, stays. Removing it may need administrator rights.
$autostartLib = Join-Path $PSScriptRoot 'ii-autostart.ps1'
if ($Sandbox) {
    Say 'Sandbox: la tarea de inicio no se toca.'
} elseif (Test-Path -LiteralPath $autostartLib) {
    . $autostartLib
    $ownSid = Get-IiUserSid
    try {
        $removed = Remove-IiAutostart -Sid $ownSid -InstallDir $installDir
        foreach ($t in $removed.Removed) { Say "Tarea de inicio quitada: $t" }
        foreach ($t in $removed.Kept) { Say "Tarea de inicio de otro usuario o instalacion: se conserva ($t)" }
    } catch {
        Say 'Windows pedira permiso de administrador para quitar la tarea de inicio.'
        $taskScript = Join-Path $installDir 'autostart-task.ps1'
        try { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$taskScript`" -Remove -InstallDir `"$installDir`"" -Verb RunAs -WindowStyle Hidden -Wait } catch {}
    }
    $stillThere = Get-IiTaskOwnership (Get-IiLogonTask $script:IiTaskFolder "Logon-$ownSid") $ownSid $installDir
    if ($stillThere -eq 'own') { Say 'No se pudo quitar la tarea de inicio: borrala en el Programador de tareas (carpeta ii-windows).' }
} else {
    Say 'Falta ii-autostart.ps1: la tarea de inicio no se toca (no se puede demostrar que es de este usuario).'
}
if (-not $Sandbox) { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows' -Recurse -ErrorAction SilentlyContinue }
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
# 3c. only the fonts recorded as ours; a font the user already had was never recorded
$fontsDir = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'))
$fontsKeyPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$remainingFonts = @()
if ($manifest -and $manifest.fonts) {
    foreach ($font in $manifest.fonts) {
        $removed = $true
        $file = [IO.Path]::GetFullPath([string]$font.file)
        if ([IO.Path]::GetDirectoryName($file) -ne $fontsDir) {
            Say "Fuente fuera de la carpeta de fuentes de usuario; se conserva: $file"
            $remainingFonts += $font
            continue
        }
        $key = Get-Item -LiteralPath $fontsKeyPath -ErrorAction SilentlyContinue
        $registered = if ($key) { $key.GetValue([string]$font.valueName) } else { $null }
        if ($key) { $key.Close() }
        # If the user replaced this registration, keep their new value.
        if ($registered -eq $file) {
            try { Remove-ItemProperty -LiteralPath $fontsKeyPath -Name ([string]$font.valueName) -ErrorAction Stop }
            catch { $removed = $false; Say "No se pudo quitar el registro de $($font.valueName): $($_.Exception.Message)" }
        }
        if (Test-Path -LiteralPath $file) {
            try { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
            catch { $removed = $false; Say "No se pudo borrar la fuente $file (puede estar en uso); no se programa su borrado: $($_.Exception.Message)" }
        }
        if (-not $removed) { $remainingFonts += $font }
    }
}
if ($remainingFonts.Count -gt 0) {
    $manifest.fonts = $remainingFonts
    try {
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$manifestPath.tmp" -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath "$manifestPath.tmp" -Destination $manifestPath -Force -ErrorAction Stop
    } catch { Say "No se pudo actualizar la lista de fuentes: $($_.Exception.Message)" }
    Say "La lista de fuentes pendientes se conserva en $manifestPath para reintentar su retirada."
}

# Terminal fragments live outside the install folder, even when -KeepConfig is used.
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\ii-windows'
if ((Test-Path -LiteralPath $fragmentDir) -and -not $Sandbox) {
    try { Remove-Item -LiteralPath $fragmentDir -Recurse -Force -ErrorAction Stop }
    catch { Say "No se pudo borrar la carpeta de Windows Terminal ${fragmentDir}: $($_.Exception.Message)" }
}

# 4. files (this script may live in the folder it deletes: finish from a temporary copy)
foreach ($line in (Invoke-IiDataRemoval -LocalAppData $env:LOCALAPPDATA -KeepConfig:$KeepConfig -KeepSecrets:$KeepSecrets)) { Say $line }
foreach ($f in 'state.ini', 'install.json', 'banners.txt', 'theme.txt', 'wallpaper-sync.ini') {
    if ($f -eq 'install.json' -and $remainingFonts.Count -gt 0) { continue }
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
