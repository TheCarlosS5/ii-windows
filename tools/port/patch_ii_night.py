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
print('patch_ii_night: ok')
