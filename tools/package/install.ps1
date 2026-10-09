# ii-windows installer (per user, no administrator rights except the optional restore point).
#
#   install.cmd                 asks before each step that changes something
#   install.ps1 -Yes            no questions (restore point skipped unless -RestorePoint)
#   install.ps1 -NoCursor       keep the current mouse cursor
#   install.ps1 -NoAutostart    do not start ii with Windows
#   install.ps1 -StartNow       start ii right after installing
#   install.ps1 -NoFastfetch    do not add the `fastfetch` command (ii's config) to the user's PATH
#
# Everything it creates or changes is written to install.json (shown by the uninstaller), and the
# registry keys it touches are exported to .reg files first.
param([switch]$Yes, [switch]$RestorePoint, [switch]$NoCursor, [switch]$NoAutostart, [switch]$StartNow, [switch]$NoFastfetch)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $here 'app'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\ii-windows'
$dataDir = Join-Path $env:LOCALAPPDATA 'ii-windows'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $dataDir "backup\$stamp"
$version = [string](Get-Content (Join-Path $payload 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
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
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr SendMessageTimeoutW(System.IntPtr h, uint msg, System.IntPtr w, string l, uint flags, uint timeout, out System.IntPtr result);
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
if (-not $NoAutostart) { Say '  - iniciar ii con Windows (solo tu usuario; una tarea al entrar, pide permiso de administrador una vez)' }
if (-not $NoFastfetch) { Say '  - agregar el comando fastfetch con el estilo de ii (al final de tu PATH de usuario)' }
Say '  - instalar la fuente JetBrains Mono Nerd Font para la terminal (opcional, solo tu usuario)'
Say '  - crear accesos en el menu Inicio: rescate, reportar un problema y desinstalar'
Say 'Mientras ii corre: oculta la barra de tareas y los iconos del escritorio, y Windows sigue sus colores.'
Say 'Todo se deshace al salir de ii, con Ctrl+Alt+Shift+R, con el rescate o desinstalando.'
if (-not (Ask 'Continuar?' $true)) { Say 'Cancelado.'; exit 1 }

$manifest = [ordered]@{
    product = 'ii-windows'; version = $version; installed = (Get-Date).ToString('s')
    installDir = $installDir; dataDir = $dataDir; backupDir = $backupDir
    registry = @(); shortcuts = @(); fonts = @(); cursor = $false; restorePoint = 'no'
}

# Keep ownership across updates; an already registered font is otherwise left alone.
$previousManifestPath = Join-Path $dataDir 'install.json'
if (Test-Path -LiteralPath $previousManifestPath) {
    $previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
    if ($previousManifest.fonts) {
        $manifest.fonts = @($previousManifest.fonts)
        foreach ($font in $manifest.fonts) {
            $manifest.registry += "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts\$($font.valueName)"
        }
    }
}

# Persist ownership before another installation step can fail; keep the previous JSON intact.
function SaveManifest() {
    $path = Join-Path $dataDir 'install.json'
    $temp = "$path.tmp"
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temp -Encoding UTF8
    # Move-Item, not File.Replace(..., $null): PowerShell 5.1 passes $null as "".
    Move-Item -LiteralPath $temp -Destination $path -Force
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
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings',
    'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
    'HKCU\Environment'
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
Copy-Item (Join-Path $here 'autostart-task.ps1') $installDir -Force
Say "Copiado a $installDir"

# --- 3b. power-saving GPU for the shell ----------------------------------------------------------
# On laptops with two GPUs (iGPU + NVIDIA/AMD) a shell that lands on the dedicated one keeps it
# awake all day and copies every frame between GPUs. Same setting as Settings > System > Display >
# Graphics, per user; only written if the user never chose one for this file.
$gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$shellExe = Join-Path $installDir 'quickshell\quickshell.exe'
$gpuCurrent = (Get-ItemProperty $gpuKey -Name $shellExe -ErrorAction SilentlyContinue).$shellExe
if (-not $gpuCurrent) {
    New-Item -Force $gpuKey -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty $gpuKey -Name $shellExe -Value 'GpuPreference=1;'
    $manifest.gpuPreference = $shellExe
    $manifest.registry += "HKCU\Software\Microsoft\DirectX\UserGpuPreferences\$shellExe (GPU de ahorro de energia)"
}

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

# --- 4b. fastfetch command -----------------------------------------------------------------------
$binDir = Join-Path $installDir 'bin'
if (-not $NoFastfetch -and (Test-Path (Join-Path $binDir 'fastfetch.cmd'))) {
    Step 'fastfetch'
    if (Ask 'Agregar el comando fastfetch con el estilo de ii? (si ya tienes otro fastfetch, el tuyo sigue mandando)' $true) {
        # Appended, never prepended: a fastfetch the user installed keeps winning. The raw value
        # keeps its %VARIABLES% and its type.
        $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        $current = [string]$envKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        $kind = if ($envKey.GetValueNames() -contains 'Path') { $envKey.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $entries = @($current.Split(';') | Where-Object { $_ -ne '' })
        if ($entries -notcontains $binDir) {
            # The exact value before and after, so the uninstaller can put it back byte for byte.
            $manifest.pathBefore = if ($envKey.GetValueNames() -contains 'Path') { $current } else { $null }
            $updated = if ($current -eq '') { $binDir } elseif ($current.EndsWith(';')) { $current + $binDir } else { "$current;$binDir" }
            $envKey.SetValue('Path', $updated, $kind)
            $manifest.pathAfter = $updated
            $out = [IntPtr]::Zero
            [IiInstall.Win]::SendMessageTimeoutW([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'Environment', 2, 3000, [ref]$out) | Out-Null
        }
        $envKey.Close()
        $manifest.pathEntry = $binDir
        $manifest.registry += "HKCU\Environment\Path (se agrego $binDir)"
        Say 'Listo: abre una terminal nueva y escribe fastfetch.'
    } else { Say 'Omitido.' }
}
# --- 4c. per-user terminal fonts -----------------------------------------------------------------
# Read the TTF name table (full name, ID 4); no font loading or administrator rights needed.
function FontFullName($path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $u16 = { param($at) ([int]$bytes[$at] -shl 8) -bor [int]$bytes[$at + 1] }
    $u32 = { param($at) ([int]$bytes[$at] -shl 24) -bor ([int]$bytes[$at + 1] -shl 16) -bor ([int]$bytes[$at + 2] -shl 8) -bor [int]$bytes[$at + 3] }
    $table = -1
    for ($i = 0; $i -lt (& $u16 4); $i++) {
        $at = 12 + $i * 16
        if ([Text.Encoding]::ASCII.GetString($bytes, $at, 4) -eq 'name') { $table = & $u32 ($at + 8); break }
    }
    if ($table -lt 0) { throw "Fuente sin tabla name: $path" }
    $strings = $table + (& $u16 ($table + 4))
    $fallback = $null
    for ($i = 0; $i -lt (& $u16 ($table + 2)); $i++) {
        $at = $table + 6 + $i * 12
        $platform = & $u16 $at
        if ((& $u16 ($at + 6)) -ne 4 -or $platform -notin 0, 3) { continue }
        $length = & $u16 ($at + 8)
        $offset = & $u16 ($at + 10)
        $name = [Text.Encoding]::BigEndianUnicode.GetString($bytes, ($strings + $offset), $length)
        if ($platform -eq 3 -and (& $u16 ($at + 4)) -eq 0x409) { return $name }
        $fallback = $name
    }
    if (-not $fallback) { throw "Fuente sin nombre completo: $path" }
    return $fallback
}

Step 'Fuente JetBrains Mono Nerd Font para la terminal'
if (Ask 'Instalar la fuente JetBrains Mono Nerd Font para la terminal? (solo tu usuario)' $true) {
    $fontsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontsKeyPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $fontFiles = @(Get-ChildItem -LiteralPath (Join-Path $payload 'quickshell\fonts') -Filter 'JetBrainsMonoNerdFont-*.ttf' -File)
    if ($fontFiles.Count -gt 0) {
        New-Item -ItemType Directory -Force $fontsDir | Out-Null
        if (-not (Test-Path -LiteralPath $fontsKeyPath)) { New-Item -Force $fontsKeyPath | Out-Null }
        $fontsKey = Get-Item -LiteralPath $fontsKeyPath
        try {
            foreach ($font in $fontFiles) {
                $copied = $false
                $registeredByUs = $false
                $valueName = (FontFullName $font.FullName) + ' (TrueType)'
                $file = Join-Path $fontsDir $font.Name
                $registered = $fontsKey.GetValueNames() -contains $valueName
                foreach ($name in $fontsKey.GetValueNames()) {
                    $registeredFile = [string]$fontsKey.GetValue($name)
                    if ($registeredFile -and [IO.Path]::GetFileName($registeredFile) -eq $font.Name) { $registered = $true }
                }
                if ($registered -or (Test-Path -LiteralPath $file)) {
                    Say "  $($font.Name): ya existe; se conserva."
                    continue
                }
                try {
                    [IO.File]::Copy($font.FullName, $file, $false)
                    $copied = $true
                    New-ItemProperty -LiteralPath $fontsKeyPath -Name $valueName -Value $file -PropertyType String | Out-Null
                    $registeredByUs = $true
                    $manifest.fonts = @($manifest.fonts | Where-Object { $_.file -ne $file }) + @([ordered]@{ file = $file; valueName = $valueName })
                    $registryEntry = "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts\$valueName"
                    if ($manifest.registry -notcontains $registryEntry) { $manifest.registry += $registryEntry }
                    SaveManifest
                    Say "  $valueName"
                } catch {
                    if ($registeredByUs) {
                        Remove-ItemProperty -LiteralPath $fontsKeyPath -Name $valueName -ErrorAction SilentlyContinue
                        $manifest.fonts = @($manifest.fonts | Where-Object { $_.file -ne $file })
                        $manifest.registry = @($manifest.registry | Where-Object { $_ -ne $registryEntry })
                    }
                    if ($copied) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
                    Say "No se pudo instalar $($font.Name): $($_.Exception.Message)"
                }
            }
        } finally { $fontsKey.Close() }
    } else { Say 'No hay fuentes JetBrains Mono Nerd Font en el paquete.' }
} else { Say 'Omitido.' }

# --- 5. autostart, shortcuts, uninstall entry ---------------------------------------------------
Step 'Inicio con Windows y accesos'
$hostExe = Join-Path $installDir 'ii-host.exe'
$command = "`"$hostExe`" --shell `"$installDir\quickshell\quickshell.exe`" --config `"$installDir\ii`""
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (-not $NoAutostart -and (Ask 'Iniciar ii automaticamente al entrar en Windows?' $true)) {
    # Best: a logon task. Windows starts it right away (the Run key waits several seconds, while
    # Explorer's wallpaper and taskbar show). Creating it needs administrator rights once; ii
    # itself still runs as you, without them. --boot: high priority and ii's wallpaper at once
    # while it loads.
    $bootArgs = "--boot --shell `"$installDir\quickshell\quickshell.exe`" --config `"$installDir\ii`""
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $taskScript = Join-Path $installDir 'autostart-task.ps1'
    $taskOk = $false
    Say 'Windows pedira permiso de administrador para crear la tarea de inicio (solo esta vez).'
    try {
        $taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$taskScript`" -Create -User `"$user`" -HostExe `"$hostExe`" -Arguments `"$($bootArgs.Replace('"', '\"'))`""
        $proc = Start-Process powershell.exe -ArgumentList $taskArgs -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        $taskOk = $proc.ExitCode -eq 0 -and $null -ne (Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue)
    } catch { $taskOk = $false }
    if ($taskOk) {
        Remove-ItemProperty $runKey -Name 'ii-windows' -ErrorAction SilentlyContinue
        $manifest.task = 'ii-windows'
        Say 'Se iniciara con Windows (tarea "ii-windows", al entrar).'
    } else {
        # Without administrator rights: the Run key (starts some seconds later).
        Set-ItemProperty $runKey -Name 'ii-windows' -Value "`"$hostExe`" $bootArgs"
        $manifest.registry += 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run\ii-windows'
        Say 'Se iniciara con Windows (sin la tarea: unos segundos despues de entrar).'
    }
}

# Updating with -NoAutostart: a logon task from an earlier install stays and stays recorded.
if (-not $manifest.task -and (Get-ScheduledTask -TaskName 'ii-windows' -ErrorAction SilentlyContinue)) { $manifest.task = 'ii-windows' }

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
Shortcut 'Reportar un problema de ii' (Join-Path $installDir 'rescue\ii-report.cmd') '' 'Guarda un diagnostico en el Escritorio y abre el formulario de fallos'
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
SaveManifest
Copy-Item (Join-Path $dataDir 'install.json') $installDir -Force

Step 'Listo'
Say 'Atajo de panico mientras ii corre: Ctrl+Alt+Shift+R'
Say 'Si algo falla: menu Inicio > ii-windows > Rescate de ii.'
if ($StartNow -or ((-not $Yes) -and (Ask 'Iniciar ii ahora?' $false))) {
    Start-Process $hostExe -ArgumentList '--shell', "`"$installDir\quickshell\quickshell.exe`"", '--config', "`"$installDir\ii`""
    Say 'ii iniciado.'
}
exit 0
