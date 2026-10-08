"""Exact-match hardware integration; only writes the generated ii staging tree."""
import hashlib
import os
from pathlib import Path
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

ROOT = Path(os.environ.get('II_STAGE_DIR') or Path(__file__).resolve().parents[2] / 'build' / 'ii')
brightness = ROOT / 'services' / 'Brightness.qml'
source = brightness.read_text(encoding='utf-8')
if hashlib.sha256(source.encode()).hexdigest() != 'd2812d48e4ae521000fbd35cb272ea573c3f69e089084c16d920b4668b0acb0a':
    raise RuntimeError('Brightness.qml upstream changed; review the Windows replacement')
brightness.write_text('''pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root
    reloadableId: "brightness"
    signal brightnessChanged()
    property var ddcMonitors: []
    property list<BrightnessMonitor> monitors: []
    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }
    function refresh() {
        if (!listProc.running) listProc.running = true;
    }
    function rebuild() {
        const old = Array.from(monitors);
        monitors = Quickshell.screens.map(screen => monitorComp.createObject(root, {screen}));
        old.forEach(m => m.destroy());
        refresh();
    }
    Component.onCompleted: rebuild()
    Connections {
        target: Quickshell
        function onScreensChanged() { root.rebuild(); }
    }
    function increaseBrightness() {
        const monitor = monitors.find(m => m.screen.name === Hyprland.focusedMonitor?.name);
        if (monitor?.ready) monitor.setBrightness(monitor.brightness + 0.05);
    }
    function decreaseBrightness() {
        const monitor = monitors.find(m => m.screen.name === Hyprland.focusedMonitor?.name);
        if (monitor?.ready) monitor.setBrightness(monitor.brightness - 0.05);
    }
    Process {
        id: listProc
        command: ["ii-shim", "brightness-win", "list"]
        stdout: StdioCollector { id: listOutput }
        onExited: (code, status) => {
            let values = [];
            if (code === 0) {
                try { values = JSON.parse(listOutput.text); } catch (error) {}
            }
            root.ddcMonitors = values;
            root.monitors.forEach(m => {
                // A read must never overwrite a slider while a write is pending.
                if (m.writeProc.running || m.setTimer.running || m.pending) return;
                m.ready = false;
                const entry = values.find(v => v.screen === m.screen.name && v.available && v.max > 0);
                if (!entry) return;
                m.busNum = entry.id;
                m.isDdc = entry.id.startsWith("ddc-");
                m.rawMaxBrightness = entry.max;
                m.brightness = Math.max(0, Math.min(1, entry.current / entry.max));
                m.ready = true;
            });
        }
    }
    // Also refresh after an external brightness change or resume. No writes here.
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.refresh() }
    component BrightnessMonitor: QtObject {
        id: monitor
        required property ShellScreen screen
        property bool ready: false
        property bool isDdc: false
        property string busNum: ""
        property int rawMaxBrightness: 100
        property real brightness: 0
        property real brightnessMultiplier: 1
        readonly property real multipliedBrightness: brightness
        readonly property bool animateChanges: false
        property bool pending: false
        onBrightnessChanged: {
            if (!ready) return;
            root.brightnessChanged();
            pending = true;
            setTimer.restart();
        }
        function setBrightness(value: real) {
            if (ready) brightness = Math.max(0, Math.min(1, value));
        }
        function setBrightnessMultiplier(value: real) { brightnessMultiplier = value; }
        function syncBrightness() {
            if (!ready || writeProc.running || !pending) return;
            pending = false;
            writeProc.command = ["ii-shim", "brightness-win", "set", busNum,
                String(Math.max(1, Math.round(brightness * 100)))];
            writeProc.running = true;
        }
        readonly property Timer setTimer: Timer {
            interval: 300
            onTriggered: monitor.syncBrightness()
        }
        readonly property Process writeProc: Process {
            onExited: (code, status) => {
                if (code !== 0) { monitor.ready = false; monitor.pending = false; }
                else if (monitor.pending) monitor.setTimer.restart();
            }
        }
    }
    Component { id: monitorComp; BrightnessMonitor {} }
    IpcHandler {
        target: "brightness"
        function increment() { root.increaseBrightness(); }
        function decrement() { root.decreaseBrightness(); }
    }
    GlobalShortcut { name: "brightnessIncrease"; description: "Increase brightness"; onPressed: root.increaseBrightness() }
    GlobalShortcut { name: "brightnessDecrease"; description: "Decrease brightness"; onPressed: root.decreaseBrightness() }
}
''', encoding='utf-8', newline='\n')

# Lift the temporary sidebar restrictions without editing patch_ii_sidebar.py.
sidebar = ROOT / 'modules' / 'ii' / 'sidebarRight'
sliders = sidebar / 'QuickSliders.qml'
sidebar_patched = 'Physical brightness needs a separate DDC/CI backend.' in sliders.read_text(encoding='utf-8')
def integrate_hardware_ui():
    edit(str(sliders), [
        ('active: false // Physical brightness needs a separate DDC/CI backend.' if sidebar_patched else 'active: Config.options.sidebar.quickSliders.showBrightness',
         'active: Config.options.sidebar.quickSliders.showBrightness && !!root.brightnessMonitor?.ready'),
        ('stopIndicatorValues: Hyprsunset.gamma !== 100 && root.brightnessMonitor?.brightness !== 0 ? [0.3 + root.brightnessMonitor?.brightness * 0.7] : []', 'stopIndicatorValues: []'),
        ('value: Hyprsunset.gamma === 100? 0.3 + root.brightnessMonitor?.brightness * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3', 'value: root.brightnessMonitor?.brightness ?? 0'),
        ('tooltipContent: Hyprsunset.gamma === 100 ? `${Math.round(root.brightnessMonitor?.brightness * 100)}%` : `${Translation.tr("Gamma")} ${Hyprsunset.gamma}%`', 'tooltipContent: `${Math.round((root.brightnessMonitor?.brightness ?? 0) * 100)}%`'),
    ])
    text = sliders.read_text(encoding='utf-8')
    start = text.index('                onMoved: {')
    end = text.index('\n            }\n        }', start)
    expected = '''                onMoved: {
                    if (value >= 0.3) {
                        // 0.3 - 1.0 brightness
                        root.brightnessMonitor.setBrightness((value - 0.3) / 0.7);
                        if (Hyprsunset.gamma !== 100) {
                            Hyprsunset.setGamma(100);
                        }
                    } else {
                        // 0 - 0.3 gamma
                        if (root.brightnessMonitor.brightness !== 0) {
                            root.brightnessMonitor.setBrightness(0);
                        }
                        Hyprsunset.setGamma((value / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
                    }
                }'''
    if text[start:end] != expected:
        raise RuntimeError('QuickSliders brightness handler changed')
    edit(str(sliders), [(expected, '                onMoved: root.brightnessMonitor?.setBrightness(value)')])
    if not sidebar_patched:
        guarded = 'if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;'
        edit(str(ROOT / 'modules' / 'common' / 'models' / 'quickToggles' / 'BluetoothToggle.qml'), [
            ('statusText: BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")',
             'statusText: !BluetoothStatus.available ? Translation.tr("Not available") : BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")'),
            ('Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled', guarded),
        ])
        edit(str(sidebar / 'quickToggles' / 'classicStyle' / 'BluetoothToggle.qml'), [
            ('Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled', guarded),
            ('Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`])', 'Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"])'),
        ])
        edit(str(sidebar / 'SidebarRightContent.qml'), [('''            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }''', '''            const adapter = Bluetooth.defaultAdapter;
            if (adapter) adapter.discovering = shown && adapter.enabled;''')])
        edit(str(sidebar / 'bluetoothDevices' / 'BluetoothDialog.qml'), [
            ('    StyledListView {', '''    StyledText {
        visible: !BluetoothStatus.available
        text: Translation.tr("Not available")
        Layout.alignment: Qt.AlignHCenter
    }
    StyledListView {
        visible: BluetoothStatus.available'''),
            ('Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);', 'Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"]);'),
        ])
        return
    edit(str(ROOT / 'modules' / 'common' / 'models' / 'quickToggles' / 'BluetoothToggle.qml'), [
        ('statusText: Translation.tr("Not available")', 'statusText: !BluetoothStatus.available ? Translation.tr("Not available") : BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")'),
        ('Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"])', '''if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
        else Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"]);'''),
    ])
    edit(str(sidebar / 'quickToggles' / 'classicStyle' / 'BluetoothToggle.qml'), [
        ('        root.altAction()', '        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;\n        else root.altAction();'),
        ('Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`])', 'Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"])'),
    ])
    edit(str(sidebar / 'SidebarRightContent.qml'), [
        ('            // No Bluetooth backend on Windows yet. The dialog offers Windows Settings.', '''            const adapter = Bluetooth.defaultAdapter;
            if (adapter) adapter.discovering = shown && adapter.enabled;'''),
    ])
    edit(str(sidebar / 'bluetoothDevices' / 'BluetoothDialog.qml'), [
        ('        visible: false', '        visible: BluetoothStatus.available'),
        ('        shown: true', '        shown: !BluetoothStatus.available'),
    ])
integrate_hardware_ui()
print('patched Windows brightness and native Bluetooth UI')
