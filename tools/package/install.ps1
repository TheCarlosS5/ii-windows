# ii-windows installer (per user, no administrator rights except the optional restore point).
#
#   install.cmd                 asks before each step that changes something
#   install.ps1 -Yes            no questions (restore point skipped unless -RestorePoint)
#   install.ps1 -NoCursor       keep the current mouse cursor
#   install.ps1 -NoAutostart    do not start ii with Windows
#   install.ps1 -StartNow       start ii right after installing
#   install.ps1 -NoFastfetch    do not add the `fastfetch` command (ii's config) to the user's PATH
#   install.ps1 -Sandbox        for tests only: with LOCALAPPDATA/APPDATA pointed at a throwaway folder it
#                               installs files, runtime and manifest and touches nothing else of the user's
#                               (no fonts, cursor, PATH, autostart, uninstall entry, restore point, and it
#                               never closes the ii that is really running)
#
# Everything it creates or changes is written to install.json (shown by the uninstaller), and the
# registry keys it touches are exported to .reg files first.
param([switch]$Yes, [switch]$RestorePoint, [switch]$NoCursor, [switch]$NoAutostart, [switch]$StartNow, [switch]$NoFastfetch, [switch]$Sandbox)

$ErrorActionPreference = 'Stop'
if ($Sandbox) { $NoCursor = $true; $NoAutostart = $true; $NoFastfetch = $true; $RestorePoint = $false; $StartNow = $false }
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

. (Join-Path $here 'ii-ownership.ps1')
. (Join-Path $here 'ii-changes.ps1')
. (Join-Path $here 'ii-runtime.ps1')
. (Join-Path $here 'ii-autostart.ps1')
# One id per package; it names the version folder under <install>\versions.
$versionId = ($version -replace '[^A-Za-z0-9._-]', '-')
$launcher = Join-Path $installDir 'ii-launcher.exe'

$manifest = [ordered]@{
    schema = 2
    product = 'ii-windows'; version = $version; versionId = $versionId; installed = (Get-Date).ToString('s')
    installDir = $installDir; dataDir = $dataDir; backupDir = $backupDir
    registry = @(); shortcuts = @(); fonts = @(); changes = @(); cursor = $false; restorePoint = 'no'
}

# Keep ownership across updates; an already registered font is otherwise left alone.
$previousManifestPath = Join-Path $dataDir 'install.json'
if (Test-Path -LiteralPath $previousManifestPath) {
    $previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
    # Manifests from before changes[] knew only the GPU preference and the Run key: they become
    # owned changes (with "absent" as their original) when they are provably still ii's.
    Import-IiLegacyChanges $previousManifest
    $manifest.changes = @($previousManifest.changes | Where-Object { $_ })
    foreach ($carry in 'pathBefore', 'pathAfter', 'pathEntry', 'task') {
        if ($previousManifest.PSObject.Properties.Name -contains $carry) { $manifest[$carry] = $previousManifest.$carry }
    }
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
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
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
$hostWindow = if ($Sandbox) { [IntPtr]::Zero } else { [IiInstall.Win]::FindWindow('IiHostWindow', [NullString]::Value) }
if ($hostWindow -ne [IntPtr]::Zero) {
    Say 'ii esta corriendo: se cierra para actualizar.'
    [IiInstall.Win]::PostMessageW($hostWindow, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep 4
}
Get-IiInstalledProcesses $installDir | Stop-Process -Force
New-Item -ItemType Directory -Force $installDir | Out-Null

# The new version is built NEXT TO the running one and switched on with one atomic step: an
# interrupted or failed update leaves the version that works selected (see ii-runtime.ps1).
# Versions that were already confirmed to work and are neither active nor the way back go first.
$before = Read-IiCurrent $installDir
if ($before -and $before.state -eq 'verified') {
    foreach ($old in (Remove-IiOldVersions $installDir)) {
        $oldExe = Join-Path $installDir "versions\$old\quickshell\quickshell.exe"
        [void](Restore-IiOwnedRegValue $manifest "gpu:$oldExe")
        Say "Version antigua quitada: $old"
    }
}
$runtime = Install-IiRuntime -Payload $payload -Root $installDir -VersionId $versionId
$versionDir = Join-Path $installDir "versions\$($runtime.Id)"
# Stable pieces, the same whatever version is active: the launcher, the scripts, the rescue, the
# cursors and the command shims that point at the active version.
foreach ($stable in 'ii-launcher.exe') {
    $src = Join-Path $here $stable
    if (Test-Path $src) { Copy-Item $src $installDir -Force }
}
foreach ($script in 'uninstall.ps1', 'uninstall-gui.ps1', 'uninstall.cmd', 'autostart-task.ps1', 'ii-ownership.ps1', 'ii-autostart.ps1', 'ii-changes.ps1', 'ii-runtime.ps1') {
    Copy-Item (Join-Path $here $script) $installDir -Force
}
foreach ($folder in 'rescue', 'cursors', 'bin') {
    if (Test-Path (Join-Path $versionDir $folder)) {
        & robocopy (Join-Path $versionDir $folder) (Join-Path $installDir $folder) /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "No se pudo copiar $folder (robocopy $LASTEXITCODE)" }
    }
}
Say "Version $($runtime.Id) copiada y verificada en $installDir\versions; se activa al arrancar (si no arranca, se vuelve a la anterior: $($runtime.Previous))."
$manifest.runtime = @([ordered]@{ active = $runtime.Id; previous = $runtime.Previous })

# --- 3b. power-saving GPU for the shell ----------------------------------------------------------
# On laptops with two GPUs (iGPU + NVIDIA/AMD) a shell that lands on the dedicated one keeps it
# awake all day and copies every frame between GPUs. Same setting as Settings > System > Display >
# Graphics, per user; only written if the user never chose one for this file.
$gpuSubKey = 'Software\Microsoft\DirectX\UserGpuPreferences'
$shellExe = Join-Path $versionDir 'quickshell\quickshell.exe'
# A value that already exists is the user's choice and is left alone; one that is ii's own from an
# earlier install keeps its true original (absent) and is not mistaken for the user's.
# Only where the power-saving GPU is the one with the screen (ii-host --gpu-policy asks DirectX: exit
# 10). On a desktop whose monitor is on the graphics card it made ii draw on the integrated GPU and
# Windows copied every frame across: the wallpaper stalled and colours changed late. There nothing
# is forced, and a value an earlier ii wrote is taken back.
$gpuPolicy = 11
try {
    $probe = Start-Process -FilePath (Join-Path $versionDir 'ii-host.exe') -ArgumentList '--gpu-policy' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    $gpuPolicy = $probe.ExitCode
} catch { }
if ($gpuPolicy -eq 10) {
    $gpuResult = Set-IiOwnedRegValue $manifest "gpu:$shellExe" $gpuSubKey $shellExe 'GpuPreference=1;' 'String'
    if ($gpuResult -in 'applied', 'kept-ours', 'updated-ours') {
        $manifest.registry += "HKCU\$gpuSubKey\$shellExe (GPU de ahorro de energia)"
    } elseif ($gpuResult -eq 'foreign-existing') {
        Say 'La preferencia de GPU de este programa ya existe (es tuya): se respeta.'
    }
} else {
    foreach ($change in @(@($manifest.changes) | Where-Object { $_ -and $_.id -like 'gpu:*' })) {
        [void](Restore-IiOwnedRegValue $manifest $change.id)
    }
    Say 'GPU: Windows elige la tarjeta de ii (la pantalla no esta en la grafica de ahorro).'
}
# GPU values for versions of ii that are gone (their folder under versions\ was removed): nobody else
# writes values for files inside ii's own folder, and Windows keeps them for ever otherwise.
$gpuKeyItem = Get-Item "HKCU:\$gpuSubKey" -ErrorAction SilentlyContinue
if ($gpuKeyItem) {
    foreach ($exe in @($gpuKeyItem.GetValueNames())) {
        if ($exe -like "$installDir\versions\*" -and -not (Test-Path -LiteralPath $exe)) {
            Remove-ItemProperty -Path "HKCU:\$gpuSubKey" -Name $exe -ErrorAction SilentlyContinue
            $manifest.changes = @(@($manifest.changes) | Where-Object { $_ -and $_.id -ne "gpu:$exe" })
        }
    }
}

# --- 4. cursor ---------------------------------------------------------------------------------
$cursorKey = 'HKCU:\Control Panel\Cursors'
$cursorBackup = Join-Path $dataDir 'cursors.json'
if (-not $NoCursor) {
    Step 'Cursor Bibata'
    if (Ask 'Usar el cursor Bibata de illogical-impulse?' $true) {
        # The user's own scheme is recorded per value the first time ii takes it, with its exact type;
        # reinstalling never records ii's own cursors as the user's, and a cursor the user changed
        # afterwards is not overwritten (see ii-changes.ps1).
        $dir = Join-Path $installDir 'cursors\Bibata-Modern-Classic'
        $map = [ordered]@{
            Arrow = 'Pointer.cur'; Help = 'Help.cur'; AppStarting = 'Work.ani'; Wait = 'Busy.ani'
            Crosshair = 'Cross.cur'; precisionhair = 'Cross.cur'; IBeam = 'Text.cur'; NWPen = 'Handwriting.cur'
            No = 'Unavailable.cur'; SizeNS = 'Vert.cur'; SizeWE = 'Horz.cur'; SizeNWSE = 'Dgn1.cur'
            SizeNESW = 'Dgn2.cur'; SizeAll = 'Move.cur'; UpArrow = 'Alternate.cur'; Hand = 'Link.cur'
            Pin = 'Pin.cur'; Person = 'Person.cur'
        }
        $kept = @()
        foreach ($name in $map.Keys) {
            $r = Set-IiOwnedRegValue $manifest "cursor:$name" 'Control Panel\Cursors' $name (Join-Path $dir $map[$name]) 'ExpandString' -TakeOver
            if ($r -eq 'user-choice') { $kept += $name }
        }
        # ("" is the scheme name: the key's default value.)
        [void](Set-IiOwnedRegValue $manifest 'cursor:scheme' 'Control Panel\Cursors' '' 'Bibata Modern Classic (ii-windows)' 'String' -TakeOver)
        [IiInstall.Win]::SystemParametersInfoW(0x57, 0, [IntPtr]::Zero, 0x3) | Out-Null   # SPI_SETCURSORS
        $manifest.cursor = $true
        $manifest.registry += 'HKCU\Control Panel\Cursors (valores de cursor; los originales en changes[] de install.json)'
        if ($kept.Count -gt 0) { Say "Cursores que cambiaste tu despues y se respetan: $($kept -join ', ')" }
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
if (-not $Sandbox -and (Ask 'Instalar la fuente JetBrains Mono Nerd Font para la terminal? (solo tu usuario)' $true)) {
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
# Everything that starts ii goes through the launcher, which picks the active version (and goes
# back a version if a new one fails its first start). It supplies --shell/--config itself.
$hostExe = $launcher
$runSubKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
if (-not $NoAutostart -and (Ask 'Iniciar ii automaticamente al entrar en Windows?' $true)) {
    # Best: a logon task. Windows starts it right away (the Run key waits several seconds, while
    # Explorer's wallpaper and taskbar show). Creating it needs administrator rights once; ii
    # itself still runs as you, without them. --boot: high priority and ii's wallpaper at once
    # while it loads.
    $bootArgs = '--boot'
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $sid = Get-IiUserSid
    $taskOk = $false
    $taskConflicts = @()
    # The task is owned per user (\ii-windows\Logon-<SID>): see ii-autostart.ps1. Try as you are;
    # only if Windows refuses, ask for administrator rights once.
    try {
        $r = Install-IiAutostart -Sid $sid -User $user -HostExe $hostExe -Arguments $bootArgs -InstallDir $installDir -Version $version
        $taskOk = $r.Registered
        $taskConflicts = @($r.Conflicts)
    } catch {
        Say 'Windows pedira permiso de administrador para crear la tarea de inicio (solo esta vez).'
        try {
            $resultFile = Join-Path $env:TEMP "ii-autostart-$PID.json"
            $taskScript = Join-Path $installDir 'autostart-task.ps1'
            $taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$taskScript`" -Create -User `"$user`" -HostExe `"$hostExe`" -InstallDir `"$installDir`" -Version `"$version`" -ResultFile `"$resultFile`" -Arguments `"$($bootArgs.Replace('"', '\"'))`""
            $proc = Start-Process powershell.exe -ArgumentList $taskArgs -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            if (Test-Path $resultFile) {
                $r = Get-Content $resultFile -Raw | ConvertFrom-Json
                $taskOk = [bool]$r.Registered
                $taskConflicts = @($r.Conflicts)
                Remove-Item $resultFile -ErrorAction SilentlyContinue
            }
        } catch { $taskOk = $false }
    }
    foreach ($c in $taskConflicts) { Say $c }
    if ($taskOk) {
        [void](Restore-IiOwnedRegValue $manifest 'run:ii-windows')   # the Run entry of an older install is superseded by the task
        $manifest.task = [ordered]@{ path = $script:IiTaskFolder; name = "Logon-$sid"; sid = $sid }
        Say 'Se iniciara con Windows (tarea propia de tu usuario, al entrar).'
    } else {
        # Without administrator rights: the Run key (starts some seconds later).
        [void](Set-IiOwnedRegValue $manifest 'run:ii-windows' $runSubKey 'ii-windows' "`"$hostExe`" $bootArgs" 'String')
        $manifest.registry += 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run\ii-windows'
        Say 'Se iniciara con Windows (sin la tarea: unos segundos despues de entrar).'
    }
}

# Updating with -NoAutostart: our logon task from an earlier install stays and stays recorded.
$ownSid = Get-IiUserSid
if (-not $manifest.task -and (Get-IiTaskOwnership (Get-IiLogonTask $script:IiTaskFolder "Logon-$ownSid") $ownSid $installDir) -eq 'own') {
    $manifest.task = [ordered]@{ path = $script:IiTaskFolder; name = "Logon-$ownSid"; sid = $ownSid }
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
Shortcut 'Iniciar ii' $hostExe '' 'Inicia la shell ii'
Shortcut 'Rescate de ii (restaurar Windows)' (Join-Path $installDir 'rescue\ii-rescue.cmd') '' 'Devuelve la barra de tareas, los iconos y todo lo demas'
Shortcut 'Reportar un problema de ii' (Join-Path $installDir 'rescue\ii-report.cmd') '' 'Guarda un diagnostico en el Escritorio y abre el formulario de fallos'
Shortcut 'Desinstalar ii-windows' (Join-Path $installDir 'uninstall.cmd') '' 'Quita ii-windows y restaura Windows'

if (-not $Sandbox) {
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows'
    New-Item -Force $uninstallKey | Out-Null
    $size = [int]((Get-ChildItem $installDir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
    $entry = @{
        DisplayName = 'ii-windows (illogical-impulse para Windows)'; DisplayVersion = $version; Publisher = 'ii-windows'
        InstallLocation = $installDir; DisplayIcon = "$hostExe,0"
        UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\uninstall-gui.ps1`""
    }
    foreach ($k in $entry.Keys) { Set-ItemProperty $uninstallKey -Name $k -Value $entry[$k] }
    Set-ItemProperty $uninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty $uninstallKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty $uninstallKey -Name EstimatedSize -Value $size -Type DWord
    $manifest.registry += 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ii-windows'
}
Say 'Accesos en el menu Inicio > ii-windows. Tambien aparece en Configuracion > Aplicaciones.'

# --- 6. manifest -------------------------------------------------------------------------------
$manifest.whileRunning = @(
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
    # The launcher picks the active version and, if it fails its first start, goes back to the previous one.
    Start-Process $launcher
    Say 'ii iniciado.'
}
exit 0
