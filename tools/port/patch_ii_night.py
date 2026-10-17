"""Night round of 2026-10-17, features: what is slowing the PC down, in the bar's resources popup.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


def add_translations(code, strings):
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    for key, value in strings.items():
        data.setdefault(key, value)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


# --- Resources popup: the programs using the most processor and memory (ii-shim top) ----------------------------------
# On a slow PC the first question is "what is eating it?". While the popup is shown, `ii-shim top` (one system snapshot,
# another 0.6 s later; processes of one program added up) is asked every 3 s. A click on the indicator opens Task
# Manager, where a program can be ended.
edit(path('modules', 'ii', 'bar', 'ResourcesPopup.qml'), [
    ('import QtQuick\nimport QtQuick.Layouts\n', 'import QtQuick\nimport QtQuick.Layouts\nimport Quickshell.Io\n'),
    ('''    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }
''', '''    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // ii-windows: the programs using the most, while the popup is shown
    property var topPrograms: []
    function formatMB(mb) {
        return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB";
    }
    function programName(entry) {
        const exe = entry.exe.toLowerCase();
        if (exe === "svchost.exe")
            return Translation.tr("Windows services");
        if (exe === "quickshell.exe")
            return "ii";
        return entry.name;
    }
    property Timer topTimer: Timer {
        running: root.shown
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!topProc.running) topProc.running = true
    }
    property Process topProc: Process {
        id: topProc
        command: ["ii-shim", "top", "4"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    // The busiest by processor (only if they really use it), then the biggest by memory.
                    const list = data.cpu.filter(p => p.cpu >= 1).slice(0, 3);
                    for (const p of data.memory) {
                        if (list.length >= 5)
                            break;
                        if (!list.some(q => q.exe === p.exe))
                            list.push(p);
                    }
                    root.topPrograms = list;
                } catch (e) {
                    root.topPrograms = [];
                }
            }
        }
    }
'''),
    ('''            StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
            }
        }
''', '''            StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8
            visible: root.topPrograms.length > 0

            StyledPopupHeaderRow {
                icon: "monitoring"
                label: Translation.tr("Using the most")
            }
            Column {
                spacing: 4
                Repeater {
                    model: root.topPrograms
                    delegate: StyledPopupValueRow {
                        required property var modelData
                        icon: modelData.cpu >= 1 ? "bolt" : "memory"
                        label: root.programName(modelData)
                        value: (modelData.cpu >= 1 ? `${Math.round(modelData.cpu)}% · ` : "") + root.formatMB(modelData.memMB)
                        width: 260
                    }
                }
            }
            StyledText {
                text: Translation.tr("Click: Task Manager")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
'''),
])
edit(path('modules', 'ii', 'bar', 'Resources.qml'), [
    ('import QtQuick\nimport QtQuick.Layouts\n', 'import QtQuick\nimport QtQuick.Layouts\nimport Quickshell\n'),
    ('''    hoverEnabled: !Config.options.bar.tooltips.clickToShow
''', '''    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    // ii-windows: where a program that eats the PC can be ended
    onClicked: if (!Config.options.bar.tooltips.clickToShow) Quickshell.execDetached(["taskmgr.exe"])
'''),
])
add_translations('es_MX', {
    "Using the most": "Lo que más gasta",
    "Windows services": "Servicios de Windows",
    "Click: Task Manager": "Clic: Administrador de tareas",
})


# --- The music spectrum (cava: audio capture + a redraw ~60 times a second) is a decorative animation: "Reduce
# animations" (and so the light mode) stops it, on the desktop widget and in the media panel.
edit(path('modules', 'ii', 'background', 'widgets', 'media', 'MediaWidget.qml'), [
    ('&& !root.desktopCovered && !GlobalStates.mediaControlsOpen\n',
     '&& !root.desktopCovered && !GlobalStates.mediaControlsOpen\n            && !Config.options.appearance.reduceMotion // ii-windows\n'),
])
edit(path('modules', 'ii', 'mediaControls', 'MediaControls.qml'), [
    ('        running: mediaControlsLoader.active\n',
     '        running: mediaControlsLoader.active && !Config.options.appearance.reduceMotion // ii-windows: decorative\n'),
])

# --- Light mode offered once to people who already did the tour (installed before the light mode existed) ---------
edit(path('modules', 'common', 'Persistent.qml'), [
    ('''            property JsonObject tour: JsonObject {
                property bool done: false // ii-windows: the guided tour was shown (or skipped)
            }
''', '''            property JsonObject tour: JsonObject {
                property bool done: false // ii-windows: the guided tour was shown (or skipped)
            }
            property JsonObject performance: JsonObject {
                property bool lightOffered: false // ii-windows: the light mode was offered on this modest PC
            }
'''),
])
add_translations('es_MX', {
    "A lighter ii for this PC": "Un ii más ligero para este PC",
    "Settings > Appearance > Performance > Lightweight: no animations or transparencies, more room for your programs.":
        "Configuración > Apariencia > Rendimiento > Ligero: sin animaciones ni transparencias, más recursos para tus programas.",
})


# --- Names and icons looked up before the Start menu list is loaded (it fills in the background now) are looked up
# again once it is there: a cheap counter that bindings calling these functions depend on.
edit(path('services', 'AppSearch.qml'), [
    ('''    readonly property var preppedNames: list.map''',
     '''    readonly property int appsVersion: list.length // ii-windows: read by lookups so their bindings rerun when the list loads

    readonly property var preppedNames: list.map'''),
    ('''    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";
''', '''    function guessIcon(str) {
        if (root.appsVersion < 0) return "image-missing"; // ii-windows: dependency only (see appsVersion)
        if (!str || str.length == 0) return "image-missing";
'''),
    ('''    function iconForWindow(appId, exe) {
''', '''    function iconForWindow(appId, exe) {
        if (root.appsVersion < 0) return ""; // ii-windows: dependency only (see appsVersion)
'''),
])
edit(path('modules', 'ii', 'bar', 'ActiveWindow.qml'), [
    ('''    function friendlyName(id) {
        if (!id || id.length === 0) return "";''', '''    function friendlyName(id) {
        if (AppSearch.appsVersion < 0) return ""; // ii-windows: dependency only, reruns once the app list is loaded
        if (!id || id.length === 0) return "";'''),
])

# --- Do not disturb for a while: the notifications tile's body goes Show -> silent 1 hour -> silent until tomorrow
# 8:00 -> Show; its icon still silences until turned back on. The silence ends by itself at that time.
edit(path('services', 'Notifications.qml'), [
    ('''    property bool silent: false
''', '''    property bool silent: false
    // ii-windows: when a timed silence ends (ms since epoch, 0 = until turned off) and which one it is
    property real silentUntil: 0
    property string silentPreset: ""
    onSilentChanged: if (!silent) { silentUntil = 0; silentPreset = ""; }
    function silenceFor(preset) {
        const now = new Date();
        if (preset === "hour") {
            silentUntil = now.getTime() + 3600000;
        } else if (preset === "tomorrow") {
            const morning = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (now.getHours() < 8 ? 0 : 1), 8, 0, 0);
            silentUntil = morning.getTime();
        }
        silentPreset = preset;
        silent = true;
    }
    property Timer silenceEnd: Timer {
        running: root.silentUntil > 0
        interval: 20000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (Date.now() >= root.silentUntil) root.silent = false
    }
'''),
])
edit(path('modules', 'common', 'models', 'quickToggles', 'NotificationToggle.qml'), [
    ('''    statusText: toggled ? Translation.tr("Show") : Translation.tr("Silent")''',
     '''    statusText: toggled ? Translation.tr("Show")
        : Notifications.silentUntil > 0 ? Translation.tr("Silent until %1").arg(Qt.locale().toString(new Date(Notifications.silentUntil), "HH:mm"))
        : Translation.tr("Silent")'''),
    ('''    mainAction: () => {
        Notifications.silent = !Notifications.silent;
    }

    tooltipText: Translation.tr("Show notifications")''',
     '''    mainAction: () => {
        Notifications.silent = !Notifications.silent;
    }
    // ii-windows: the tile's body silences for a while: 1 hour, until tomorrow 8:00, then shows again
    altAction: () => {
        if (!Notifications.silent || Notifications.silentPreset === "")
            Notifications.silenceFor("hour");
        else if (Notifications.silentPreset === "hour")
            Notifications.silenceFor("tomorrow");
        else
            Notifications.silent = false;
    }

    tooltipText: Translation.tr("Icon: silence notifications. Rest of the button: 1 hour, until tomorrow 8:00, back on")'''),
])
add_translations('es_MX', {
    "Silent until %1": "Hasta las %1",
    "Icon: silence notifications. Rest of the button: 1 hour, until tomorrow 8:00, back on":
        "Icono: silenciar avisos. Resto del botón: 1 hora, hasta mañana a las 8:00, volver a mostrar",
})
print('patch_ii_night: ok')
