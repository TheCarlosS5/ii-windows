# Runs only INSIDE Windows Sandbox. Real folders, QML, shell icons and mouse input.
# Removing the Background loader must fail this test; no source-text assertions.
param([switch]$WithHost)
$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path -LiteralPath 'C:\ii\build\ii')) {
    throw 'This test must run inside the ii Windows Sandbox.'
}
$out = 'C:\xchg\outbox'
$local = Join-Path $env:USERPROFILE 'qs-config'
$dist = Join-Path $env:USERPROFILE 'ii-dist'
foreach ($target in @($local, $dist)) {
    $full = [IO.Path]::GetFullPath($target)
    if (-not $full.StartsWith($env:USERPROFILE + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe staging target: $full"
    }
}
Get-Process quickshell -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($window in @((New-Object -ComObject Shell.Application).Windows())) {
    try { $window.Quit() } catch { }
}
robocopy C:\ii\build\ii $local /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'QML copy failed' }
robocopy C:\ii\dist\quickshell $dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Binary copy failed' }
$shell = Join-Path $local 'modules\ii\background\Background.qml'
$qml = Get-Content -LiteralPath $shell -Raw
$probe = Get-Content -LiteralPath 'C:\ii\tools\sandbox\tests\desktop-probe.qml.inc' -Raw
[IO.File]::WriteAllText($shell, $qml.Replace('id: bgRoot', "id: bgRoot`n$probe"), (New-Object Text.UTF8Encoding $false))

$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$fixtureName = '00 Prueba ' + [char]0xE1 + ' & # %.iidesktoptest'
$fixture = Join-Path $desktop $fixtureName
# Only remove obsolete files created by earlier versions of this disposable test.
foreach ($oldName in @(('00 Prueba ' + [char]0xE1 + ' & # %.txt'), ('00 Prueba ' + [char]0xC3 + [char]0xA1 + ' & # %.txt'), '03 Bloc de notas.lnk')) {
    Remove-Item -LiteralPath (Join-Path $desktop $oldName) -Force -ErrorAction SilentlyContinue
}
$folder = Join-Path $desktop '01 Carpeta de estudio'
$publicFile = Join-Path $publicDesktop '02 Archivo compartido.txt'
$shortcut = Join-Path $desktop '03 Acceso de prueba.lnk'
$openedMarker = "$out\desktop-opened.txt"
$shortcutMarker = "$out\desktop-shortcut-opened.txt"
Remove-Item -LiteralPath $openedMarker, $shortcutMarker -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $fixture -Value 'Sandbox desktop fixture' -Encoding UTF8
New-Item -ItemType Directory -Path $folder -Force | Out-Null
Set-Content -LiteralPath $publicFile -Value 'Public desktop fixture' -Encoding UTF8
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = "$env:WINDIR\System32\cmd.exe"
$link.Arguments = '/c type nul > "' + $shortcutMarker + '"'
$link.WindowStyle = 7
$link.Save()
"shortcut fixture exists=$([IO.File]::Exists($shortcut)), target exists=$([IO.File]::Exists($link.TargetPath))"

# Disposable, sandbox-only file association: prove the opened path reaches its real handler.
$handler = Join-Path $env:USERPROFILE 'desktop-open-handler.ps1'
@'
param([string]$OpenedPath)
[IO.File]::WriteAllText('C:\xchg\outbox\desktop-opened.txt', $OpenedPath, [Text.Encoding]::UTF8)
'@ | Set-Content -LiteralPath $handler -Encoding UTF8
$association = 'HKCU:\Software\Classes\ii.DesktopTest\shell\open\command'
New-Item -Path $association -Force | Out-Null
$handlerCommand = '"' + "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" + '" -NoProfile -WindowStyle Hidden -File "' + $handler + '" "%1"'
Set-Item -LiteralPath $association -Value $handlerCommand
New-Item -Path 'HKCU:\Software\Classes\.iidesktoptest' -Force | Out-Null
Set-Item -LiteralPath 'HKCU:\Software\Classes\.iidesktoptest' -Value 'ii.DesktopTest'

$state = "$env:LOCALAPPDATA\quickshell\State\user\generated"
New-Item -ItemType Directory -Path $state -Force | Out-Null
Copy-Item -LiteralPath C:\ii\build\seed\colors.json -Destination "$state\colors.json" -Force
$pictures = Join-Path $env:USERPROFILE 'Pictures'
New-Item -ItemType Directory -Path $pictures -Force | Out-Null
Copy-Item -LiteralPath C:\ii\build\seed\wallpaper.jpg -Destination "$pictures\ii-wallpaper.jpg" -Force
$configPath = "$env:LOCALAPPDATA\quickshell\illogical-impulse\config.json"
New-Item -ItemType Directory -Path (Split-Path $configPath) -Force | Out-Null
@{ background = @{ wallpaperPath = ("$pictures\ii-wallpaper.jpg" -replace '\\', '/');
    widgets = @{ desktopIcons = @{ enable = $true; iconSize = 48 } } } } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configPath -Encoding UTF8

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$previewFile = Join-Path $desktop '05 Preview.png'
$preview = New-Object Drawing.Bitmap 64, 64
$graphics = [Drawing.Graphics]::FromImage($preview)
$graphics.Clear([Drawing.Color]::FromArgb(255, 30, 210, 80))
$preview.Save($previewFile, [Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $preview.Dispose()
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DesktopMouse {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] long pad; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int s);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    public static void Keys(params int[] seq) {
        var a = new IN[seq.Length];
        for (int i = 0; i < seq.Length; i++) {
            var vk = (ushort)Math.Abs(seq[i]); a[i].type = 1; a[i].ki.vk = vk;
            a[i].ki.flags = (seq[i] < 0 ? 2u : 0u) | (vk == 0x5B ? 1u : 0u);
        }
        SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(IN)));
    }
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, int x, int y, uint data, IntPtr extra);
    public static void Click(int x, int y, bool right) {
        SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
        mouse_event(right ? 8u : 2u, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        mouse_event(right ? 16u : 4u, 0, 0, 0, IntPtr.Zero);
    }
}
'@
$script:failures = 0
function Check([bool]$condition, [string]$description) {
    if ($condition) { "PASS $description" } else { "FAIL $description"; $script:failures++ }
}
function Snapshot {
    $psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
    $psi.Arguments = '-p "' + $local + '" ipc call desktopTest snapshot'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($psi)
    if (-not $process.WaitForExit(8000)) { $process.Kill(); throw 'Desktop IPC timed out' }
    $text = $process.StandardOutput.ReadToEnd()
    if ($process.ExitCode -ne 0) { throw "Desktop IPC failed: $($process.StandardError.ReadToEnd())" }
    return ($text | ConvertFrom-Json)
}
function FileEntry($snapshot, [string]$name) {
    return ($snapshot.files | Where-Object name -eq $name | Select-Object -First 1)
}
function ThumbnailVisible($snapshot, [string]$name) {
    $entry = FileEntry $snapshot '05 Preview.png'
    if (-not $entry) { return $false }
    $capture = Join-Path $out $name
    & C:\ii\tools\dev\screenshot.ps1 -Out $capture | Out-Null
    $bitmap = New-Object Drawing.Bitmap $capture
    try {
        $color = $bitmap.GetPixel([int]$entry.x, [int]$entry.y)
        return $color.R -eq 30 -and $color.G -eq 210 -and $color.B -eq 80
    } finally { $bitmap.Dispose() }
}

$psi = New-Object Diagnostics.ProcessStartInfo "$dist\quickshell.exe"
$psi.Arguments = '-p "' + $local + '"'
if ($WithHost) {
    $psi.FileName = 'C:\ii\host\build\ii-host.exe'
    $psi.Arguments = '--shell "' + $dist + '\quickshell.exe" --config "' + $local + '"'
}
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $env:USERPROFILE
$p = [Diagnostics.Process]::Start($psi)
try {
    Start-Sleep 16
    Check (-not $p.HasExited) 'shell stays running'
    $s = Snapshot
    $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$out\desktop-state.json" -Encoding UTF8
    Check $s.present 'desktop widget is attached to the real Background'
    if (-not $s.present) { throw 'Desktop widget missing (expected RED before integration)' }
    foreach ($name in @($fixtureName, '01 Carpeta de estudio', '02 Archivo compartido.txt', '03 Acceso de prueba.lnk')) {
        $entry = FileEntry $s $name
        Check ($null -ne $entry) "real desktop entry: $name"
        Check ($null -ne $entry -and $entry.iconStatus -eq 1) "Windows icon/thumbnail loaded: $name"
    }
    Check ($null -eq (FileEntry $s 'desktop.ini')) 'hidden desktop.ini is omitted'
    Check ((FileEntry $s '03 Acceso de prueba.lnk').label -eq '03 Acceso de prueba') 'shortcut extension is hidden'
    Check ($s.iconSize -eq 48) 'configured icon size is used'
    & C:\ii\tools\dev\screenshot.ps1 -Out "$out\desktop.png" | Out-Null
    $iconCapture = "$out\desktop-folder-icon.png"
    Remove-Item -LiteralPath $iconCapture -Force -ErrorAction SilentlyContinue
    & "$dist\quickshell.exe" -p $local ipc call desktopTest captureIcon '01 Carpeta de estudio' $iconCapture | Out-Null
    Start-Sleep 1
    if (Test-Path -LiteralPath $iconCapture) {
        $bitmap = New-Object Drawing.Bitmap $iconCapture
        Check ($bitmap.GetPixel(0, 0).A -eq 0) 'Windows folder icon keeps transparent corners'
        $bitmap.Dispose()
    } else { Check $false 'folder icon capture saved' }
    $previewCapture = "$out\desktop-preview-icon.png"
    Remove-Item -LiteralPath $previewCapture -Force -ErrorAction SilentlyContinue
    & "$dist\quickshell.exe" -p $local ipc call desktopTest captureIcon '05 Preview.png' $previewCapture | Out-Null
    Start-Sleep 1
    if (Test-Path -LiteralPath $previewCapture) {
        $bitmap = New-Object Drawing.Bitmap $previewCapture
        $color = $bitmap.GetPixel([int]($bitmap.Width / 2), [int]($bitmap.Height / 2))
        Check ($color.R -eq 30 -and $color.G -eq 210 -and $color.B -eq 80 -and $color.A -eq 255) 'image thumbnail shows the actual file pixels'
        $bitmap.Dispose()
    } else { Check $false 'image thumbnail capture saved' }

    if ($WithHost) {
        Check (ThumbnailVisible (Snapshot) 'desktop-wind-before.png') 'desktop thumbnail visible before Win+D'
        Start-Process explorer.exe -ArgumentList "/n,$env:WINDIR"
        Start-Sleep 3
        $app = @((New-Object -ComObject Shell.Application).Windows()) | Select-Object -First 1
        if (-not $app) { throw 'Explorer fixture window missing' }
        [DesktopMouse]::Keys(@(0x5B, 0x44, -0x44, -0x5B))
        Start-Sleep 2
        Check ([DesktopMouse]::IsIconic([IntPtr]$app.HWND)) 'Win+D minimizes the application'
        $s = Snapshot
        $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$out\desktop-wind-state.json" -Encoding UTF8
        Check (ThumbnailVisible $s 'desktop-wind-minimized.png') 'Win+D keeps ii desktop thumbnail visible'
        [DesktopMouse]::Keys(@(0x5B, 0x44, -0x44, -0x5B))
        Start-Sleep 2
        Check (-not [DesktopMouse]::IsIconic([IntPtr]$app.HWND)) 'second Win+D restores the application'
        $app.Quit(); Start-Sleep 1
        Check (ThumbnailVisible (Snapshot) 'desktop-wind-restored.png') 'desktop thumbnail visible after restoring the application'
    }
    $s = Snapshot

    $entry = FileEntry $s $fixtureName
    [DesktopMouse]::Click($entry.x, $entry.y, $false)
    Start-Sleep -Milliseconds 350
    Check ([bool](FileEntry (Snapshot) $entry.name).selected) 'left click selects the real item'
    [DesktopMouse]::Click($entry.x, $entry.y, $true)
    Start-Sleep -Milliseconds 350
    $s = Snapshot
    Check ($s.menu.visible -and $s.menu.target -eq $entry.path) 'right click opens the item menu'
    Check ($s.menu.backgroundAlpha -gt 0.99) 'menu has a readable surface with default transparency disabled'
    $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$out\desktop-menu-state.json" -Encoding UTF8
    & C:\ii\tools\dev\screenshot.ps1 -Out "$out\desktop-menu.png" | Out-Null
    [System.Windows.Forms.Clipboard]::Clear()
    [DesktopMouse]::Click(($s.menu.x + 100), ($s.menu.y + 6 + 2 * 42 + 20), $false)
    Start-Sleep -Milliseconds 500
    Check ([System.Windows.Forms.Clipboard]::GetText() -eq $fixture) 'copy path preserves accents and reserved characters'
    Check (-not (Snapshot).menu.visible) 'menu closes after an action'
    [DesktopMouse]::Click($entry.x, $entry.y, $true)
    Start-Sleep -Milliseconds 350
    $s = Snapshot
    [DesktopMouse]::Click(($s.menu.x + 100), ($s.menu.y + 6 + 42 + 20), $false)
    Start-Sleep 3
    $explorerWindows = @((New-Object -ComObject Shell.Application).Windows())
    $selectedWindow = $null
    foreach ($window in $explorerWindows) {
        try {
            if ($window.Document.SelectedItems().Count -gt 0 -and $window.Document.SelectedItems().Item(0).Path -eq $fixture) {
                $selectedWindow = $window; break
            }
        } catch { }
    }
    Check ($null -ne $selectedWindow) 'show in folder selects the exact file in Explorer'
    if ($selectedWindow) { $selectedWindow.Quit(); Start-Sleep 1 }

    $newFile = Join-Path $desktop '04 Nuevo archivo.txt'
    Set-Content -LiteralPath $newFile -Value 'Live update'
    Start-Sleep 2
    Check ($null -ne (FileEntry (Snapshot) '04 Nuevo archivo.txt')) 'new files appear without restarting'
    Remove-Item -LiteralPath $newFile
    Start-Sleep 2
    Check ($null -eq (FileEntry (Snapshot) '04 Nuevo archivo.txt')) 'deleted files disappear without restarting'

    $entry = FileEntry (Snapshot) $fixtureName
    [DesktopMouse]::Click($entry.x, $entry.y, $false)
    Start-Sleep -Milliseconds 70
    [DesktopMouse]::Click($entry.x, $entry.y, $false)
    Start-Sleep 3
    Check ((Test-Path -LiteralPath $openedMarker) -and (Get-Content -LiteralPath $openedMarker -Raw) -eq $fixture) 'double click opens the exact Unicode path, including # and %'

    $entry = FileEntry (Snapshot) '03 Acceso de prueba.lnk'
    [DesktopMouse]::Click($entry.x, $entry.y, $false)
    Start-Sleep -Milliseconds 70
    [DesktopMouse]::Click($entry.x, $entry.y, $false)
    Start-Sleep 3
    Check (Test-Path -LiteralPath $shortcutMarker) 'double click launches the Windows shortcut target and arguments'
    & "$dist\quickshell.exe" -p $local ipc call desktopTest enabled false | Out-Null
    Start-Sleep 1
    Check (-not (Snapshot).present) 'desktop icons can be disabled'
    & "$dist\quickshell.exe" -p $local ipc call desktopTest enabled true | Out-Null
    Start-Sleep 1
    Check (Snapshot).present 'desktop icons can be enabled again'

} catch {
    $script:failures++
    "FAIL $($_.Exception.Message)"
} finally {
    if ($WithHost) { & C:\ii\host\build\ii-host.exe --rescue | Out-Null }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    $log = Get-ChildItem "$env:TEMP\quickshell\by-id\*\log.log" | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) {
        Copy-Item -LiteralPath $log.FullName -Destination "$out\desktop.log" -Force
        Get-Content -LiteralPath $log.FullName | Where-Object { $_ -match 'DesktopIcons|desktopTest|ERROR|Failed to load' } | Select-Object -Last 15
    }
}
"desktop failures=$script:failures"
if ($script:failures -gt 0) { exit 1 }
