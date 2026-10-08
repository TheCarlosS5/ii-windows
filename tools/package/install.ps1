# ii-windows installer (per user, no administrator rights except the optional restore point).
#
#   install.cmd                 asks before each step that changes something
#   install.ps1 -Yes            no questions (restore point skipped unless -RestorePoint)
#   install.ps1 -NoCursor       keep the current mouse cursor
#   install.ps1 -NoAutostart    do not start ii with Windows
#   install.ps1 -StartNow       start ii right after installing
#
# Everything it creates or changes is written to install.json (shown by the uninstaller), and the
# registry keys it touches are exported to .reg files first.
param([switch]$Yes, [switch]$RestorePoint, [switch]$NoCursor, [switch]$NoAutostart, [switch]$StartNow)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $here 'app'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\ii-windows'
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $dataDir "backup\$stamp"
$version = (Get-Content (Join-Path $payload 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $version) { $version = 'dev' }

function Say($text) { Write-Host $text }
function Step($text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Ask($question, $default) {
    if ($Yes) { return $default }
    $hint = 'S/n'; if (-not $default) { $hint = 's/N' }
    $answer = Read-Host "$question [$hint]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim().ToLower().StartsWith('s') -or $answer.Trim().ToLower().StartsWith('y')
}

Add-Type -Namespace IiInstall -Name Win -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool PostMessageW(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint action, uint param, System.IntPtr data, uint flags);
'@

# --- checks ---------------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $payload 'quickshell\quickshell.exe'))) { throw "Paquete incompleto: falta app\quickshell" }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 22000) { throw "ii-windows necesita Windows 11 (build 22000 o superior); este equipo es build $build." }
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated -and -not $Yes) {
    Say 'Aviso: esta ventana tiene permisos de administrador. ii-windows se instala solo para tu usuario;'
    Say 'no hace falta ejecutarlo como administrador.'
}

Say "ii-windows $version - instalador"
Say ''
Say 'Se va a:'
Say "  - copiar la shell a $installDir"
Say '  - exportar antes a archivos .reg las claves de tu usuario (HKCU) que se tocan'
if (-not $NoCursor) { Say '  - poner el cursor Bibata (guardando el actual para el desinstalador)' }
if (-not $NoAutostart) { Say '  - iniciar ii con Windows (solo tu usuario)' }
Say '  - crear accesos en el menu Inicio: rescate y desinstalar'
Say 'Mientras ii corre: oculta la barra de tareas y los iconos del escritorio, y Windows sigue sus colores.'
Say 'Todo se deshace al salir de ii, con Ctrl+Alt+Shift+R, con el rescate o desinstalando.'
if (-not (Ask 'Continuar?' $true)) { Say 'Cancelado.'; exit 1 }

$manifest = [ordered]@{
    product = 'ii-windows'; version = $version; installed = (Get-Date).ToString('s')
    installDir = $installDir; dataDir = $dataDir; backupDir = $backupDir
    registry = @(); shortcuts = @(); cursor = $false; restorePoint = 'no'
}

# --- 1. restore point (optional, needs administrator) ------------------------------------------
Step 'Punto de restauracion'
$wantPoint = $RestorePoint -or ((-not $Yes) -and (Ask 'Crear un punto de restauracion del sistema? (pedira permiso de administrador)' $true))
if ($wantPoint) {
    $cmd = "try { Checkpoint-Computer -Description 'Antes de instalar ii-windows' -RestorePointType APPLICATION_INSTALL -ErrorAction Stop; exit 0 } catch { Write-Host `$_.Exception.Message; exit 1 }"
    try {
        $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-Command', $cmd
        if ($p.ExitCode -eq 0) { $manifest.restorePoint = 'creado'; Say 'Punto de restauracion creado (Windows crea como maximo uno cada 24 h).' }
        else { $manifest.restorePoint = 'fallo'; Say 'No se pudo crear (la Proteccion del sistema puede estar desactivada). Se sigue con las copias .reg.' }
    } catch {
        $manifest.restorePoint = 'cancelado'; Say 'Permiso no concedido: se sigue sin punto de restauracion, con las copias .reg.'
    }
} else { Say 'Omitido.' }

# --- 2. registry backup ------------------------------------------------------------------------
Step 'Copia de seguridad del registro'
New-Item -ItemType Directory -Force $backupDir | Out-Null
$keys = @(
    'HKCU\Control Panel\Cursors',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
    'HKCU\Software\Microsoft\Windows\DWM',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
)
foreach ($key in $keys) {
    $file = Join-Path $backupDir (($key -replace '^HKCU\\', '' -replace '[\\ ]', '_') + '.reg')
    # Through cmd: in Windows PowerShell, reg.exe's error text (a key that doesn't exist yet)
    # would stop the script. Only the exit code matters.
    & cmd.exe /c "reg.exe export `"$key`" `"$file`" /y >nul 2>&1"
    if ($LASTEXITCODE -eq 0) { Say "  $key" } else { Say "  $key (todavia no existe)" }
}
Say "Guardado en $backupDir"

# --- 3. files ----------------------------------------------------------------------------------
Step 'Archivos'
$hostWindow = [IiInstall.Win]::FindWindow('IiHostWindow', [NullString]::Value)
if ($hostWindow -ne [IntPtr]::Zero) {
    Say 'ii esta corriendo: se cierra para actualizar.'
    [IiInstall.Win]::PostMessageW($hostWindow, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep 4
}
Get-Process quickshell, ii-host -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$installDir*" } | Stop-Process -Force
New-Item -ItemType Directory -Force $installDir | Out-Null
& robocopy $payload $installDir /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "No se pudieron copiar los archivos (robocopy $LASTEXITCODE)" }
Copy-Item (Join-Path $here 'uninstall.ps1') $installDir -Force
Copy-Item (Join-Path $here 'uninstall.cmd') $installDir -Force
Say "Copiado a $installDir"

# --- 4. cursor ---------------------------------------------------------------------------------
$cursorKey = 'HKCU:\Control Panel\Cursors'
$cursorBackup = Join-Path $dataDir 'cursors.json'
if (-not $NoCursor) {
    Step 'Cursor Bibata'
    if (Ask 'Usar el cursor Bibata de illogical-impulse?' $true) {
        # The user's own scheme is recorded once; reinstalling must not record ours as theirs.
        if (-not (Test-Path $cursorBackup)) {
            # Every value with its exact type ("" is the scheme name, the key's default value).
            $key = Get-Item $cursorKey
            $saved = @(foreach ($name in $key.GetValueNames()) {
                $kind = $key.GetValueKind($name)
                $value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
                if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
                [ordered]@{ name = $name; kind = "$kind"; value = $value }
            })
            ConvertTo-Json -InputObject $saved -Depth 3 | Set-Content $cursorBackup -Encoding UTF8
        }
        $dir = Join-Path $installDir 'cursors\Bibata-Modern-Classic'
        $map = [ordered]@{
            Arrow = 'Pointer.cur'; Help = 'Help.cur'; AppStarting = 'Work.ani'; Wait = 'Busy.ani'
            Crosshair = 'Cross.cur'; precisionhair = 'Cross.cur'; IBeam = 'Text.cur'; NWPen = 'Handwriting.cur'
            No = 'Unavailable.cur'; SizeNS = 'Vert.cur'; SizeWE = 'Horz.cur'; SizeNWSE = 'Dgn1.cur'
            SizeNESW = 'Dgn2.cur'; SizeAll = 'Move.cur'; UpArrow = 'Alternate.cur'; Hand = 'Link.cur'
            Pin = 'Pin.cur'; Person = 'Person.cur'
        }
        foreach ($name in $map.Keys) {
            Set-ItemProperty $cursorKey -Name $name -Value (Join-Path $dir $map[$name]) -Type ExpandString
        }
        Set-ItemProperty $cursorKey -Name '(default)' -Value 'Bibata Modern Classic (ii-windows)'
        [IiInstall.Win]::SystemParametersInfoW(0x57, 0, [IntPtr]::Zero, 0x3) | Out-Null   # SPI_SETCURSORS
        $manifest.cursor = $true
        $manifest.registry += 'HKCU\Control Panel\Cursors (valores de cursor; los originales en cursors.json)'
        Say 'Cursor aplicado.'
    } else { Say 'Se mantiene el cursor actual.' }
}

# --- 5. autostart, shortcuts, uninstall entry ---------------------------------------------------
Step 'Inicio con Windows y accesos'
$hostExe = Join-Path $installDir 'ii-host.exe'
$command = "`"$hostExe`" --shell `"$installDir\quickshell\quickshell.exe`" --config `"$installDir\ii`""
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (-not $NoAutostart -and (Ask 'Iniciar ii automaticamente al entrar en Windows?' $true)) {
    Set-ItemProperty $runKey -Name 'ii-windows' -Value $command
    $manifest.registry += 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run\ii-windows'
    Say 'Se iniciara con Windows.'
}

$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ii-windows'
New-Item -ItemType Directory -Force $menu | Out-Null
$shell = New-Object -ComObject WScript.Shell
function Shortcut($name, $target, $arguments, $description) {
    $path = Join-Path $menu "$name.lnk"
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath = $target; $lnk.Arguments = $arguments; $lnk.Description = $description
    # Not the install folder: the uninstaller deletes it.
    $lnk.WorkingDirectory = $env:USERPROFILE; $lnk.IconLocation = "$hostExe,0"
    $lnk.Save()
    $manifest.shortcuts += $path
}
Shortcut 'Iniciar ii' $hostExe "--shell `"$installDir\quickshell\quickshell.exe`" --config `"$installDir\ii`"" 'Inicia la shell ii'
Shortcut 'Rescate de ii (restaurar Windows)' (Join-Path $installDir 'rescue\ii-rescue.cmd') '' 'Devuelve la barra de tareas, los iconos y todo lo demas'
Shortcut 'Desinstalar ii-windows' (Join-Path $installDir 'uninstall.cmd') '' 'Quita ii-windows y restaura Windows'

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows'
New-Item -Force $uninstallKey | Out-Null
$size = [int]((Get-ChildItem $installDir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
$entry = @{
    DisplayName = 'ii-windows (illogical-impulse para Windows)'; DisplayVersion = $version; Publisher = 'ii-windows'
    InstallLocation = $installDir; DisplayIcon = "$hostExe,0"
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$installDir\uninstall.ps1`""
}
foreach ($k in $entry.Keys) { Set-ItemProperty $uninstallKey -Name $k -Value $entry[$k] }
Set-ItemProperty $uninstallKey -Name NoModify -Value 1 -Type DWord
Set-ItemProperty $uninstallKey -Name NoRepair -Value 1 -Type DWord
Set-ItemProperty $uninstallKey -Name EstimatedSize -Value $size -Type DWord
$manifest.registry += 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows'
Say 'Accesos en el menu Inicio > ii-windows. Tambien aparece en Configuracion > Aplicaciones.'

# --- 6. manifest -------------------------------------------------------------------------------
$manifest.runtime = @(
    'Mientras ii corre (se deshace solo al salir, con el rescate o desinstalando):',
    '  barra de tareas oculta (y su autoocultar), iconos del escritorio ocultos,',
    '  banners de notificacion de Windows por app (HKCU, copia en banners.txt),',
    '  modo oscuro/claro y color de acento de Windows (HKCU, copia en theme.txt).',
    "Configuracion de ii: $env:LOCALAPPDATA\quickshell\illogical-impulse y $env:LOCALAPPDATA\quickshell\State"
)
New-Item -ItemType Directory -Force $dataDir | Out-Null
$manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dataDir 'install.json') -Encoding UTF8
Copy-Item (Join-Path $dataDir 'install.json') $installDir -Force

Step 'Listo'
Say 'Atajo de panico mientras ii corre: Ctrl+Alt+Shift+R'
Say 'Si algo falla: menu Inicio > ii-windows > Rescate de ii.'
if ($StartNow -or ((-not $Yes) -and (Ask 'Iniciar ii ahora?' $false))) {
    Start-Process $hostExe -ArgumentList '--shell', "`"$installDir\quickshell\quickshell.exe`"", '--config', "`"$installDir\ii`""
    Say 'ii iniciado.'
}
exit 0
