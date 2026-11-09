# Native probes for a slow Explorer query, idle DWM thumbnails and a shared spectrum process.
# Uses a temporary QML tree and deterministic audio data; no audio capture or user config writes.
param([string]$Quickshell = '')
. "$PSScriptRoot\..\lib\ii-test.ps1"
$repo = (Resolve-Path "$PSScriptRoot\..\..\..").Path
if (-not $Quickshell) { $Quickshell = "$repo\dist\quickshell\quickshell.exe" }
if (-not (Test-Path $Quickshell)) { Skip-Test 'build and deploy Quickshell first' }
if (-not (Test-Path "$repo\host\build\ii-fake-cava.exe")) { Skip-Test 'build ii-fake-cava first' }
$base = Join-Path $env:TEMP ('ii-performance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $base | Out-Null
function Run-Probe([string]$Name, [string]$Qml, [hashtable]$Env = @{}) {
    $dir = Join-Path $base $Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content "$dir\shell.qml" $Qml -Encoding UTF8
    $psi = New-Object Diagnostics.ProcessStartInfo $Quickshell, "-p `"$dir`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Environment['II_DATA_DIR'] = $dir
    $psi.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $psi.Environment['QS_DISABLE_FILE_WATCHER'] = '1'
    $psi.Environment['PATH'] = "$base\bin;" + $psi.Environment['PATH']
    foreach ($key in $Env.Keys) { $psi.Environment[$key] = [string]$Env[$key] }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(20000)) { $p.Kill(); throw "$Name timed out" }
    $log = $out.Result + "`n" + $err.Result
    Set-Content "$repo\build\performance-$Name.log" $log
    Assert-Equal $p.ExitCode 0 "$Name exits normally (see build/performance-$Name.log)"
    [pscustomobject]@{ Log = $log; Seconds = $sw.Elapsed.TotalSeconds; Dir = $dir }
}
$form = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ii-performance-probe'; $form.Width = 240; $form.Height = 100
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $run = Run-Probe 'explorer' @'
import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    property int ticks: 0
    Component.onCompleted: console.info("windows", ToplevelManager.toplevels.values.length)
    Timer { interval: 100; running: true; repeat: true; onTriggered: {
        parent.ticks++;
        if (parent.ticks === 20) { console.info("GUI responsive during Explorer query"); Qt.quit(); }
    } }
}
'@ @{ QS_TEST_DESKTOP_QUERY_DELAY_MS = 10000 }
    Assert-True ($run.Log -match 'test query delayed 10000') 'a native Explorer query is in flight'
    Assert-True ($run.Log -match 'GUI responsive during Explorer query') 'the GUI timer runs during the query'
    Assert-True ($run.Seconds -lt 8) 'shutdown also avoids waiting for Explorer'
    Write-Output ("Explorer delay 10 s: GUI probe and shutdown completed in {0:N2} s" -f $run.Seconds)

    New-Item -ItemType Directory -Force "$base\model\services" | Out-Null
    Copy-Item "$repo\overlay\ii\services\HyprlandData.qml" "$base\model\services"
    $run = Run-Probe 'model' @'
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    Timer { interval: 1200; running: true; onTriggered: {
        const probe = HyprlandData.windowList.find(w => w.title === "ii-performance-probe");
        console.info(probe && HyprlandData.windowByAddress[probe.address] && HyprlandData.monitors.length > 0
            ? "PASS native window model" : "FAIL native window model");
        Qt.quit();
    } }
}
'@
    Assert-True ($run.Log -match 'PASS native window model' -and $run.Log -notmatch 'ReferenceError|TypeError|FAIL') 'the actual QML model loads and publishes the native probe'

    $run = Run-Probe 'thumbnails' @'
import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    id: root
    property var probe: ToplevelManager.toplevels.values.find(t => t.title === "ii-performance-probe") ?? null
    FloatingWindow {
        visible: true; implicitWidth: 360; implicitHeight: 220
        Loader {
            id: previews; anchors.fill: parent
            sourceComponent: Item {
                Repeater { model: 12; delegate: ScreencopyView {
                    required property int index
                    x: (index % 4) * 85; y: Math.floor(index / 4) * 65
                    width: 80; height: width * sourceSize.height / Math.max(1, sourceSize.width); captureSource: root.probe
                } }
            }
        }
        Timer { interval: 3200; running: true; onTriggered: previews.active = false }
        Timer { interval: 3500; running: true; onTriggered: Qt.quit() }
    }
}
'@ @{ QS_THUMBNAIL_STATS = 1; QT_LOGGING_RULES = 'quickshell.win32.compat.debug=true' }
    $stats = [regex]::Matches($run.Log, 'thumbnail updates: submitted (\d+) unchanged (\d+)')
    Assert-Equal $stats.Count 12 'all twelve thumbnail probes were destroyed cleanly'
    $submitted = 0; $unchanged = 0
    foreach ($match in $stats) {
        $submitted += [int]$match.Groups[1].Value
        $unchanged += [int]$match.Groups[2].Value
    }
    Assert-True ($submitted -ge 12 -and $submitted -lt 100) 'initial thumbnail properties reach DWM'
    Assert-True (([regex]::Matches($run.Log, 'visible 1 opacity')).Count -ge 12) 'all thumbnails are actually visible in DWM'
    Assert-True ($unchanged -gt 500) 'steady timer/render updates skip DWM'
    Write-Output "12 idle thumbnails: $submitted DWM submissions; $unchanged identical updates skipped"

    New-Item -ItemType Directory -Force "$base\spectrum\services", "$base\spectrum\modules\common\functions", "$base\bin" | Out-Null
    Copy-Item "$repo\overlay\ii\services\AudioSpectrum*.qml" "$base\spectrum\services"
    Copy-Item "$repo\host\build\ii-fake-cava.exe" "$base\bin\cava.exe"
    # The Windows backend prepends its own bin to PATH. Inject only the deterministic executable
    # into the copied service; all subscription, parsing and lifecycle code remains production code.
    $audioFile = "$base\spectrum\services\AudioSpectrum.qml"
    $audio = Get-Content $audioFile -Raw
    $fakeCommand = '["' + "$base/bin/cava.exe".Replace('\', '/') + '",'
    Set-Content $audioFile ($audio.Replace('["cava",', $fakeCommand)) -Encoding UTF8
    Set-Content "$base\spectrum\GlobalStates.qml" "pragma Singleton`nimport QtQuick`nQtObject { property bool screenLocked: false }"
    Set-Content "$base\spectrum\modules\common\Config.qml" "pragma Singleton`nimport QtQuick`nQtObject { property QtObject options: QtObject { property QtObject appearance: QtObject { property bool reduceMotion: false } } }"
    Set-Content "$base\spectrum\modules\common\Directories.qml" "pragma Singleton`nimport QtQuick`nQtObject { property string scriptPath: `".`" }"
    Set-Content "$base\spectrum\modules\common\functions\FileUtils.qml" "pragma Singleton`nimport QtQuick`nQtObject { function trimFileProtocol(value) { return value; } }"
    $run = Run-Probe 'spectrum' @'
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
    id: root
    property int step: 0
    property var temporary: null
    AudioSpectrumClient { id: left; active: true }
    AudioSpectrumClient { id: right; active: true }
    Component { id: factory; AudioSpectrumClient { active: true } }
    function check(ok, message) { console.info(ok ? "PASS" : "FAIL", message); }
    Timer { interval: 700; running: true; repeat: true; onTriggered: {
        root.step++;
        switch (root.step) {
        case 1: root.check(AudioSpectrum.consumers.length === 2 && AudioSpectrum.points.length === 4, "both monitors receive one stream"); left.active = false; break;
        case 2: root.check(AudioSpectrum.consumers.length === 1 && AudioSpectrum.points.length === 4, "one covered monitor leaves stream running"); Config.options.appearance.reduceMotion = true; break;
        case 3: root.check(AudioSpectrum.points.length === 0, "light mode stops stream"); Config.options.appearance.reduceMotion = false; break;
        case 4: root.check(AudioSpectrum.points.length === 4, "normal mode resumes stream"); GlobalStates.screenLocked = true; break;
        case 5: root.check(AudioSpectrum.points.length === 0, "lock stops stream"); GlobalStates.screenLocked = false; break;
        case 6: root.check(AudioSpectrum.points.length === 4, "unlock resumes stream"); right.active = false; break;
        case 7: root.check(AudioSpectrum.consumers.length === 0 && AudioSpectrum.points.length === 0, "last monitor stops stream"); root.temporary = factory.createObject(root); break;
        case 8: root.check(AudioSpectrum.points.length === 4, "dynamic subscriber receives stream"); root.temporary.destroy(); break;
        case 9: root.check(AudioSpectrum.consumers.length === 0 && AudioSpectrum.points.length === 0, "destroyed subscriber releases stream"); Qt.quit(); break;
        }
    } }
}
'@
    Assert-True ($run.Log -notmatch 'FAIL|ReferenceError|TypeError|failed to load') 'native spectrum checks report no failure'
    Assert-Equal ([regex]::Matches($run.Log, 'PASS ')).Count 9 'all spectrum lifecycle checks ran'
    Assert-Equal (@(Get-ChildItem $run.Dir -Filter 'cava-*.started')).Count 4 'one producer per active period, independent of monitor count'
}
finally {
    if ($form) { $form.Close(); $form.Dispose() }
    Get-Process -Name cava -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq "$base\bin\cava.exe" } | Stop-Process -Force
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-IiTest
