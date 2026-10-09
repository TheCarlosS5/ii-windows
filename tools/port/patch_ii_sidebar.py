"""Exact-match Windows sidebar patches. Only modifies the generated staging tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.normpath(os.path.join(ROOT, *parts))


def model(name):
    return path('modules', 'common', 'models', 'quickToggles', name + '.qml')


# Keep upstream's schedule/manual-override evaluation; replace only its Linux transport.
edit(path('services', 'Hyprsunset.qml'), [
    ('readonly property real gammaLowerLimit: 25', 'readonly property real gammaLowerLimit: 55'),
    ('    property bool temperatureActive: false', '''    property bool temperatureActive: false
    property bool requestedTemperature: false
    property bool available: false
    property int effectiveTemperature: 6500
    property int effectiveGamma: 100
    property int minimumTemperature: 3500
    property bool minimumVerified: false
    property int errorCode: 0
    onFromChanged: { reEvaluate(); ensureState(); }
    onToChanged: { reEvaluate(); ensureState(); }'''),
    ('''    function startHyprsunset() {
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
    }''', '''    function startHyprsunset() { fetchState(); }'''),
    ('''        root.startHyprsunset();
        root.ensureState();''', '''        root.reEvaluate();
        root.ensureState();
        root.fetchState();'''),
    ('''        root.temperatureActive = true;''', '''        root.requestedTemperature = true;'''),
    ('''        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);''', '''        root.fetchState();'''),
    ('''        root.temperatureActive = false;
        // console.log("[Hyprsunset] Disabling");
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.defaultColorTemperature}`]);''', '''        root.requestedTemperature = false;
        root.fetchState();'''),
    ('''        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);''', '''        root.fetchState();'''),
    ('''        fetchProc.running = true;''', '''        syncTimer.restart();'''),
    ('''    Process {
        id: fetchProc
        running: true
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (output != root.defaultColorTemperature); // 6000 is the default when off
                // console.log("[Hyprsunset] Fetched state:", output, "->", root.temperatureActive);
            }
        }
    }''', '''    Timer {
        id: syncTimer
        interval: 100
        onTriggered: {
            if (fetchProc.running) { restart(); return; }
            fetchProc.command = root.requestedTemperature || root.gamma !== 100
                ? ["ii-shim", "nightlight", `${Math.max(1200, Math.min(6500, root.requestedTemperature ? root.colorTemperature : 6500))}`, `${root.gamma}`]
                : ["ii-shim", "nightlight", "off"];
            fetchProc.running = true;
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.fetchState()
    }
    Process {
        id: fetchProc
        command: ["ii-shim", "nightlight", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.available = state.available;
                    root.temperatureActive = state.active;
                    root.effectiveTemperature = state.kelvin;
                    root.effectiveGamma = state.gamma;
                    root.minimumTemperature = state.minimumKelvin;
                    root.minimumVerified = state.minimumVerified;
                    root.errorCode = state.error;
                } catch (e) { root.available = false; root.temperatureActive = false; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.temperatureActive = false;
        }
    }'''),
    ('''        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;''', '''        if (root.manualActive === undefined) {
            root.manualActive = root.requestedTemperature;'''),
    ('''            if (!root.temperatureActive) return;
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);''', '''            if (root.requestedTemperature) root.fetchState();'''),
])

# SystemInfo reads Windows edition/build without Linux files or private APIs.
edit(path('services', 'SystemInfo.qml'), [(
    '''pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Provides some system info: distro, username.
 */
Singleton {
    id: root
    property string distroName: "Unknown"
    property string distroId: "unknown"
    property string distroIcon: "linux-symbolic"
    property string username: "user"
    property string homeUrl: ""
    property string documentationUrl: ""
    property string supportUrl: ""
    property string bugReportUrl: ""
    property string privacyPolicyUrl: ""
    property string logo: ""
    property string desktopEnvironment: ""
    property string windowingSystem: ""

    Timer {
        triggeredOnStart: true
        interval: 1
        running: true
        repeat: false
        onTriggered: {
            getUsername.running = true
            fileOsRelease.reload()
            const textOsRelease = fileOsRelease.text()

            // Extract the friendly name (PRETTY_NAME field, fallback to NAME)
            const prettyNameMatch = textOsRelease.match(/^PRETTY_NAME=['"](.+?)['"]/m)
            const nameMatch = textOsRelease.match(/^NAME=['"](.+?)['"]/m)
            distroName = prettyNameMatch ? prettyNameMatch[1] : (nameMatch ? nameMatch[1].replace(/Linux/i, "").trim() : "Unknown")

            // Extract the ID
            const idMatch = textOsRelease.match(/^ID=['"]?(.+?)['"]?$/m)
            distroId = idMatch ? idMatch[1] : "unknown"

            // Extract additional URLs and logo
            const homeUrlMatch = textOsRelease.match(/^HOME_URL=['"](.+?)['"]/m)
            homeUrl = homeUrlMatch ? homeUrlMatch[1] : ""
            const documentationUrlMatch = textOsRelease.match(/^DOCUMENTATION_URL=['"](.+?)['"]/m)
            documentationUrl = documentationUrlMatch ? documentationUrlMatch[1] : ""
            const supportUrlMatch = textOsRelease.match(/^SUPPORT_URL=['"](.+?)['"]/m)
            supportUrl = supportUrlMatch ? supportUrlMatch[1] : ""
            const bugReportUrlMatch = textOsRelease.match(/^BUG_REPORT_URL=['"](.+?)['"]/m)
            bugReportUrl = bugReportUrlMatch ? bugReportUrlMatch[1] : ""
            const privacyPolicyUrlMatch = textOsRelease.match(/^PRIVACY_POLICY_URL=['"](.+?)['"]/m)
            privacyPolicyUrl = privacyPolicyUrlMatch ? privacyPolicyUrlMatch[1] : ""
            const logoFieldMatch = textOsRelease.match(/^LOGO=['"]?(.+?)['"]?$/m)
            logo = logoFieldMatch ? logoFieldMatch[1] : ""

            // Update the distroIcon property based on distroId
            switch (distroId) {
                case "artix":
                case "arch": distroIcon = "arch-symbolic"; break;
                case "manjaro": distroIcon = "manjaro-symbolic"; break;
                case "endeavouros": distroIcon = "endeavouros-symbolic"; break;
                case "cachyos": distroIcon = "cachyos-symbolic"; break;
                case "nixos": distroIcon = "nixos-symbolic"; break;
                case "fedora": distroIcon = "fedora-symbolic"; break;
                case "linuxmint":
                case "ubuntu":
                case "zorin":
                case "popos": distroIcon = "ubuntu-symbolic"; break;
                case "debian":
                case "raspbian":
                case "kali": distroIcon = "debian-symbolic"; break;
                case "funtoo":
                case "gentoo": distroIcon = "gentoo-symbolic"; break;
                default: distroIcon = "linux-symbolic"; break;
            }
            if (textOsRelease.toLowerCase().includes("nyarch")) {
                distroIcon = "nyarch-symbolic"
            }

            if (logo.trim().length === 0) {
                logo = distroIcon
            }

        }
    }

    Process {
        id: getUsername
        command: ["whoami"]
        stdout: SplitParser {
            onRead: data => {
                root.username = data.trim()
            }
        }
    }

    Process {
        id: getDesktopEnvironment
        running: true
        command: ["bash", "-c", "echo $XDG_CURRENT_DESKTOP,$WAYLAND_DISPLAY"]
        stdout: StdioCollector {
            id: deCollector
            onStreamFinished: {
                const [desktop, wayland] = deCollector.text.split(",")
                root.desktopEnvironment = desktop.trim()
                root.windowingSystem = wayland.trim().length > 0 ? "Wayland" : "X11" // Are there others? 🤔
            }
        }
    }

    FileView {
        id: fileOsRelease
        path: "/etc/os-release"
    }
}''',
    '''pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string distroName: "Windows"
    property string distroId: "windows"
    property string distroIcon: ""
    property string username: "user"
    property string homeUrl: "https://www.microsoft.com/windows"
    property string documentationUrl: "https://learn.microsoft.com/windows"
    property string supportUrl: "https://support.microsoft.com/windows"
    property string bugReportUrl: ""
    property string privacyPolicyUrl: "https://privacy.microsoft.com/privacystatement"
    property string logo: ""
    property string desktopEnvironment: "Windows"
    property string windowingSystem: "Win32"
    Process {
        running: true
        command: ["whoami"]
        stdout: StdioCollector { onStreamFinished: root.username = text.trim() }
    }
    Process {
        running: true
        command: ["ii-shim", "system-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.distroName = JSON.parse(text).name; } catch (e) {}
            }
        }
    }
}
''',
)])

# Header and Bluetooth dialog must not invoke Linux or dereference a missing adapter.
edit(path('modules', 'ii', 'sidebarRight', 'SidebarRightContent.qml'), [
    ('''            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }''', '''            // No Bluetooth backend on Windows yet. The dialog offers Windows Settings.'''),
    ('''                CustomIcon {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer0
                }''', '''                MaterialSymbol {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: 25
                    text: "desktop_windows"
                    color: Appearance.colors.colOnLayer0
                }'''),
    # Uptime stays in sight, as in ii; the Windows edition shows on hover. (StyledToolTip
    # follows its parent's `hovered`: icons and texts have none, so it needs a HoverHandler or
    # it is always shown.)
    ('                    text: Translation.tr("Up %1").arg(DateTime.uptime)', '''                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                    HoverHandler { id: uptimeHover }
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: uptimeHover.hovered
                        text: SystemInfo.distroName
                    }'''),
    ('                    Quickshell.execDetached(["hyprctl", "reload"])\n', ''),
    ('Translation.tr("Reload Hyprland & Quickshell")', 'Translation.tr("Reload Quickshell")'),
    ('                root.showWifiDialog = false;', '                root.showNightLightDialog = false;\n                root.showWifiDialog = false;'),
])

# Hide incompatible toggles even if an older config selected them. Keep raw Config indices.
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'AndroidQuickPanel.qml'), [
    ('["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang"]',
     '["network", "bluetooth", "idleInhibitor", "nightLight", "darkMode", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile"]'),
    ('    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []', '''    readonly property list<var> toggles: {
        if (!Config.ready) return [];
        const selected = Config.options.sidebar.quickToggles.android.toggles;
        const visible = selected.map((t, i) => t ? ({ type: t.type, size: t.size, configIndex: i }) : null)
            .filter(t => t && availableToggleTypes.includes(t.type));
        return visible.map((t, i) => ({ type: t.type, size: t.size, configIndex: t.configIndex,
            previousConfigIndex: i > 0 ? visible[i - 1].configIndex : -1,
            nextConfigIndex: i + 1 < visible.length ? visible[i + 1].configIndex : -1 }));
    }'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'androidStyle', 'AndroidToggleDelegateChooser.qml'), [
    ('buttonIndex: root.startingIndex + index', 'buttonIndex: modelData.configIndex ?? -1', 17),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'androidStyle', 'AndroidQuickToggleButton.qml'), [
    ('toggleList.find(toggle => toggle.type === buttonType)', 'toggleList.find(toggle => toggle && toggle.type === buttonType)', 3),
    ('            const targetIndex = index + offset;', '''            const targetIndex = offset < 0 ? root.buttonData.previousConfigIndex : root.buttonData.nextConfigIndex;'''),
])

# Classic layout doesn't instantiate unsupported daemon/compositor models.
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'ClassicQuickPanel.qml'), [
    ('        NightLight {}', '        NightLight { altAction: () => root.openNightLightDialog() }'),
    ('        GameMode {}\n', ''), ('        EasyEffectsToggle {}\n', ''), ('        CloudflareWarp {}\n', ''),
])

# Radio absent: explicit unavailable label, but allow opening the dialog/settings.
edit(model('BluetoothToggle'), [
    ('statusText: BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")', 'statusText: Translation.tr("Not available")'),
    ('available: BluetoothStatus.available', 'available: true'),
    ('        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled', '        Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"])'),
    ('import Quickshell.Bluetooth', 'import Quickshell\nimport Quickshell.Bluetooth'),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'classicStyle', 'BluetoothToggle.qml'), [
    ('    visible: BluetoothStatus.available', '    visible: true'),
    ('        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled', '        root.altAction()'),
])
edit(path('modules', 'ii', 'sidebarRight', 'bluetoothDevices', 'BluetoothDialog.qml'), [
    ('''    WindowDialogSeparator {}''', '''    PagePlaceholder {
        Layout.fillWidth: true
        Layout.fillHeight: true
        shown: true
        icon: "bluetooth_disabled"
        title: Translation.tr("Not available")
    }
    WindowDialogSeparator {}'''),
    ('    StyledListView {', '    StyledListView {\n        visible: false'),
    ('Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);', 'Quickshell.execDetached(["xdg-open", "ms-settings:bluetooth"]);'),
])

# Native Wi-Fi when present; on Ethernet/no adapter the action opens network settings.
edit(path('services', 'Network.qml'), [
    ('    property bool wifiEnabled: Win.Network.wifiEnabled', '    readonly property bool wifiAvailable: Win.Network.wifiAvailable\n    property bool wifiEnabled: Win.Network.wifiEnabled'),
])
edit(model('NetworkToggle'), [
    ('import QtQuick', 'import QtQuick\nimport Quickshell'),
    ('    toggled: Network.wifiStatus !== "disabled"', '    toggled: Network.ethernet || Network.wifiEnabled'),
    ('    mainAction: () => Network.toggleWifi()', '''    mainAction: () => {
        if (Network.ethernet || !Network.wifiAvailable)
            Quickshell.execDetached(["xdg-open", "ms-settings:network-status"]);
        else Network.toggleWifi();
    }'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'classicStyle', 'NetworkToggle.qml'), [
    ('    toggled: Network.wifiStatus !== "disabled"', '    toggled: Network.ethernet || Network.wifiEnabled'),
    ('    onClicked: Network.toggleWifi()', '''    onClicked: {
        if (Network.ethernet || !Network.wifiAvailable) Quickshell.execDetached(["xdg-open", "ms-settings:network-status"]);
        else Network.toggleWifi();
    }'''),
])
edit(path('modules', 'ii', 'sidebarRight', 'wifiNetworks', 'WifiDialog.qml'), [
    ('    WindowDialogSeparator {}', '''    StyledText {
        Layout.fillWidth: true
        visible: Network.friendlyWifiNetworks.length === 0 && !Network.wifiScanning
        text: !Network.wifiAvailable ? Translation.tr("Not available") : Translation.tr("No networks found")
    }
    WindowDialogSeparator {}'''),
    ('Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);',
     'Quickshell.execDetached(["xdg-open", Network.ethernet ? "ms-settings:network-ethernet" : "ms-settings:network-status"]);'),
])

# Safe null handling: unavailable audio endpoints disable toggles/sliders.
for name, endpoint in [('AudioToggle', 'sink'), ('MicToggle', 'source')]:
    edit(model(name), [('QuickToggleModel {', f'QuickToggleModel {{\n    available: Audio.{endpoint}?.audio !== undefined && Audio.{endpoint}?.audio !== null')])
edit(path('modules', 'ii', 'sidebarRight', 'QuickSliders.qml'), [
    ('active: Config.options.sidebar.quickSliders.showBrightness', 'active: false // Physical brightness needs a separate DDC/CI backend.'),
    ('active: Config.options.sidebar.quickSliders.showVolume', 'active: Config.options.sidebar.quickSliders.showVolume && !!Audio.sink?.audio'),
    ('active: Config.options.sidebar.quickSliders.showMic', 'active: Config.options.sidebar.quickSliders.showMic && !!Audio.source?.audio'),
])

# Documented settings page replaces the fork's private IPolicyConfig default-device setter.
edit(path('modules', 'ii', 'sidebarRight', 'volumeMixer', 'VolumeDialogContent.qml'), [
    ('''            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }''', '''            Quickshell.execDetached(["xdg-open", "ms-settings:sound"]);
            deviceSelector.currentIndex = Qt.binding(() => root.devices.findIndex(n => n.id === (root.isSink ? Pipewire.defaultAudioSink?.id : Pipewire.defaultAudioSource?.id)));'''),
])

# Night-light toggle is disabled when host support is absent, with observable error/status.
edit(model('NightLightToggle'), [
    ('QuickToggleModel {', 'QuickToggleModel {\n    available: Hyprsunset.available'),
    ('Translation.tr("Night Light | Right-click to configure")', 'Translation.tr("Night Light | Right-click to configure") + ` · ≥ ${Hyprsunset.minimumTemperature} K · ${Hyprsunset.effectiveTemperature} K (${Hyprsunset.errorCode})`'),
])
edit(path('modules', 'ii', 'sidebarRight', 'quickToggles', 'classicStyle', 'NightLight.qml'), [
    ('    id: nightLightButton', '    id: nightLightButton\n    enabled: Hyprsunset.available'),
    ('Translation.tr("Night Light | Right-click to toggle Auto mode")', 'Hyprsunset.available ? Translation.tr("Night Light | Right-click to configure") : Translation.tr("Not available") + " (ii-host)"'),
])

# Game mode has no compositor equivalent; open its documented Windows settings page.
edit(model('GameModeToggle'), [
    ('import Quickshell.Io', 'import Quickshell\nimport Quickshell.Io'),
    ('    toggled: !confOpt.value', '    toggled: false\n    hasStatusText: false'),
    ('''    mainAction: () => {
        root.toggled = !root.toggled;
        if (root.toggled) {
            HyprlandConfig.setMany({
                "animations:enabled": 0,
                "decoration:shadow:enabled": 0,
                "decoration:blur:enabled": 0,
                "general:gaps_in": 0,
                "general:gaps_out": 0,
                "general:border_size": 1,
                "decoration:rounding": 0,
                "general:allow_tearing": 1
            });
        } else {
            HyprlandConfig.resetMany([ //
                "animations:enabled", //
                "decoration:shadow:enabled", //
                "decoration:blur:enabled", //
                "general:gaps_in", //
                "general:gaps_out", //
                "general:border_size", //
                "decoration:rounding", //
                "general:allow_tearing", //
            ]);
        }
    }''', '''    mainAction: () => {
        Quickshell.execDetached(["xdg-open", "ms-settings:gaming-gamemode"]);
    }'''),
    ('''    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
    }''', ''),
])

# Windows' own capture and accessible keyboard avoid Linux tools/QML key injection.
edit(model('ScreenSnipToggle'), [
    ('Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);',
     'Quickshell.execDetached(["xdg-open", "ms-screenclip://capture/image?rectangle"]);'),
])
edit(model('OnScreenKeyboardToggle'), [
    ('    toggled: GlobalStates.oskOpen', '    toggled: false\n    hasStatusText: false'),
    ('        GlobalStates.oskOpen = !GlobalStates.oskOpen', '        GlobalStates.sidebarRightOpen = false;\n        Quickshell.execDetached(["xdg-open", "ms-settings:easeofaccess-keyboard"]);'),
])

# Pomodoro uses Windows' configured system sound, no ffplay/files from /usr/share.
edit(path('services', 'Audio.qml'), [
    ('import qs.modules.common', 'import qs.modules.common\nimport Quickshell.Io'),
    ('        Audio.sink.audio.muted = !Audio.sink.audio.muted', '        if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted'),
    ('        Audio.source.audio.muted = !Audio.source.audio.muted', '        if (Audio.source?.audio) Audio.source.audio.muted = !Audio.source.audio.muted'),
    ('''    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }''', '''    Process { id: systemSound }
    function playSystemSound(soundName) {
        if (systemSound.running) return;
        systemSound.command = ["ii-shim", "system-sound", soundName];
        systemSound.running = true;
    }'''),
])

# Power plans are fetched/apply-result checked through the documented powrprof helper.
edit(model('PowerProfilesToggle'), [
    ('import QtQuick', 'import QtQuick\nimport Quickshell.Io'),
    ('''    name: Translation.tr("Power Profile")''', '''    id: root
    property var state: ({ plans: [], active: "", name: "" })
    property string lastError: ""
    available: !powerProc.running
    name: Translation.tr("Power Profile")'''),
    ('''    toggled: PowerProfiles.profile !== PowerProfile.Balanced''', '''    toggled: state.active !== "balanced" && state.active !== "custom" && state.active !== ""'''),
    ('''    icon: switch(PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return "energy_savings_leaf"
        case PowerProfile.Balanced: return "airwave"
        case PowerProfile.Performance: return "local_fire_department"
    }''', '''    icon: state.active === "power-saver" ? "energy_savings_leaf" : state.active === "performance" ? "local_fire_department" : "airwave"'''),
    ('''    statusText: switch(PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return "Power Saver"
        case PowerProfile.Balanced: return "Balanced"
        case PowerProfile.Performance: return "Performance"
    }''', '''    statusText: lastError || state.name || Translation.tr("Not available")'''),
    ('''    mainAction: () => {
        if (PowerProfiles.hasPerformanceProfile) {
            switch(PowerProfiles.profile) {
                case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                break;
                case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                break;
                case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                break;
            }
        } else {
            PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
        }
    }''', '''    mainAction: () => {
        if (root.state.plans.length < 2) {
            Quickshell.execDetached(["xdg-open", "ms-settings:powersleep"]);
            return;
        }
        powerProc.command = ["ii-shim", "power", "next"];
        powerProc.running = true;
    }'''),
    ('''    tooltipText: Translation.tr("Click to cycle through power profiles")''', '''    tooltipText: Translation.tr("Click to cycle through power profiles") + " · " + (lastError || state.name)
    Process {
        id: powerProc
        running: true
        command: ["ii-shim", "power", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.state = JSON.parse(text);
                    root.lastError = root.state.error ? Translation.tr("Not available") + ` (${root.state.error})` : "";
                } catch (e) { root.lastError = Translation.tr("Not available"); }
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            if (powerProc.running) return;
            powerProc.command = ["ii-shim", "power", "status"];
            powerProc.running = true;
        }
    }'''),
])

# Displays whose driver refuses GDI gamma ramps (ii-host probes at start: available = false):
# the toggle opens Windows' own Night light (it works through the driver) instead of greying out.
edit(model('NightLightToggle'), [
    ('    available: Hyprsunset.available\n    property bool auto',
     '    available: true\n    property bool auto'),
    ('    statusText: (auto ? ',
     '    statusText: !Hyprsunset.available ? Translation.tr("Windows settings") : (auto ? '),
    ('        Hyprsunset.toggleTemperature()\n    }\n    hasMenu',
     '        if (!Hyprsunset.available) Quickshell.execDetached(["xdg-open", "ms-settings:nightlight"]);\n        else Hyprsunset.toggleTemperature();\n    }\n    hasMenu'),
])
