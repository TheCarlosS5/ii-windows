"""UX round of 2026-10-15 (feedback from 3 testers + the owner): the macOS-like dock options,
bar changes, battery warnings, transparency defaults ... Exact-match edits of the staged tree;
every edit fails loudly if upstream moved the code."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- Dock: options of the macOS-like dock (overlay/ii/modules/ii/dock) ---------------------------
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
''',
     '''                property bool monochromeIcons: false // ii-windows: colour icons, like macOS
                property real height: 60 // legacy: the dock sizes itself from iconSize
                property real hoverRegionHeight: 2
                property string position: "bottom" // bottom | left | right
                property real iconSize: 44
                property real magnification: 1.7 // 1 = no magnification
                property real magnificationRange: 2.6 // in icons
                property bool showLabels: true
'''),
])

edit(path('GlobalStates.qml'), [
    ('    property bool overviewOpen: false\n',
     '    property bool overviewOpen: false\n'
     '    property real dockInsetBottom: 0 // ii-windows: space the dock takes, for the desktop icons\n'
     '    property real dockInsetLeft: 0\n'
     '    property real dockInsetRight: 0\n'),
])

edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr("Tint app icons")
            checked: Config.options.dock.monochromeIcons
            onCheckedChanged: {
                Config.options.dock.monochromeIcons = checked;
            }
        }
''',
     '''        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr("Tint app icons")
            checked: Config.options.dock.monochromeIcons
            onCheckedChanged: {
                Config.options.dock.monochromeIcons = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "label"
            text: Translation.tr("Show the app name above the icon")
            checked: Config.options.dock.showLabels
            onCheckedChanged: {
                Config.options.dock.showLabels = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Position")
            ConfigSelectionArray {
                currentValue: Config.options.dock.position
                onSelected: newValue => {
                    Config.options.dock.position = newValue;
                }
                options: [
                    { displayName: Translation.tr("Bottom"), icon: "south", value: "bottom" },
                    { displayName: Translation.tr("Left"), icon: "west", value: "left" },
                    { displayName: Translation.tr("Right"), icon: "east", value: "right" }
                ]
            }
        }
        ConfigSlider {
            text: Translation.tr("Icon size")
            buttonIcon: "photo_size_select_small"
            value: Config.options.dock.iconSize
            usePercentTooltip: false
            from: 28
            to: 72
            stopIndicatorValues: [44]
            onValueChanged: {
                Config.options.dock.iconSize = Math.round(value);
            }
        }
        ConfigSlider {
            text: Translation.tr("Magnification")
            buttonIcon: "zoom_in"
            value: Config.options.dock.magnification
            usePercentTooltip: false
            from: 1
            to: 2.5
            stopIndicatorValues: [1, 1.7]
            onValueChanged: {
                Config.options.dock.magnification = Math.round(value * 20) / 20;
            }
        }
        ConfigSlider {
            text: Translation.tr("Magnification reach")
            buttonIcon: "width"
            value: Config.options.dock.magnificationRange
            usePercentTooltip: false
            from: 1.5
            to: 4.5
            stopIndicatorValues: [2.6]
            onValueChanged: {
                Config.options.dock.magnificationRange = Math.round(value * 10) / 10;
            }
        }
'''),
])

# Desktop icons keep clear of the dock wherever it is (the desktop menu does it in its own overlay file).
edit(path('modules', 'ii', 'background', 'widgets', 'desktop', 'DesktopIcons.qml'), [
    ('(Config.options.dock.enable ? Config.options.dock.height : 0)',
     '(Config.options.dock.enable ? GlobalStates.dockInsetBottom : 0)'),
])

# --- Battery: no false "critically low" at start-up ----------------------------------------------------
# Reports from laptops: a "Critically low battery" / "Low battery" notice at every start with the battery
# above 80 %. A fresh battery object can read 0 for a moment (before the first real report), and the
# thresholds were also evaluated on AC power. Now: nothing before the first complete reading plus a
# short grace period, only while really running on battery, and the value is taken as a fraction
# whether the backend gives 0-1 or 0-100.
edit(path('services', 'Battery.qml'), [
    ('''    property bool available: UPower.displayDevice.isLaptopBattery
''',
     '''    property bool available: UPower.displayDevice.isLaptopBattery
    // ii-windows: warnings wait for the first complete reading and a grace period after start.
    property bool settled: false
    Timer {
        running: true
        interval: 20000
        onTriggered: root.settled = true
    }
    readonly property bool readingValid: settled && (UPower.displayDevice.ready ?? true) && UPower.onBattery
'''),
    ('''    property real percentage: UPower.displayDevice?.percentage ?? 1
''',
     '''    readonly property real rawPercentage: UPower.displayDevice?.percentage ?? 1
    property real percentage: rawPercentage > 1.0 ? Math.min(1, rawPercentage / 100) : rawPercentage
'''),
    ('''    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
''',
     '''    property bool isLow: available && readingValid && percentage > 0 && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && readingValid && percentage > 0 && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && readingValid && percentage > 0 && (percentage <= Config.options.battery.suspend / 100)
'''),
])

# --- Bar: no Swap, only the desktops that exist ------------------------------------------------------------
edit(path('modules', 'ii', 'bar', 'Resources.qml'), [
    ('''        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: (Config.options.bar.resources.alwaysShowSwap && percentage > 0) || 
                (MprisController.activePlayer?.trackTitle == null) ||
                root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

''', ''),
])
edit(path('modules', 'ii', 'bar', 'ResourcesPopup.qml'), [
    ('            visible: ResourceUsage.swapTotal > 0\n',
     '            visible: false // ii-windows: the page file is not shown (it only looked like an alarm)\n'),
])

edit(path('modules', 'common', 'Config.qml'), [
    ('                    property int shown: 10\n',
     '                    property int shown: 10\n'
     '                    property bool onlyOpen: true // ii-windows: show only the desktops that exist, not 10 fixed dots\n'),
])
edit(path('modules', 'common', 'models', 'WorkspaceModel.qml'), [
    ('''    readonly property int shownCount: C.Config.options.bar.workspaces.shown
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
''',
     '''    // ii-windows: the dots are the desktops that exist (windows or not) and the active one.
    readonly property bool onlyOpen: C.Config.options.bar.workspaces.onlyOpen ?? true
    readonly property int highestKnown: {
        let highest = Math.max(1, activeWorkspace);
        for (const w of Hyprland.workspaces.values)
            if (w.id > 0 && w.id > highest) highest = w.id;
        for (const w of HyprlandData.windowList)
            if (w.workspace && w.workspace.id > highest) highest = w.workspace.id;
        return highest;
    }
    readonly property int shownCount: onlyOpen ? Math.max(1, Math.min(highestKnown, 20)) : C.Config.options.bar.workspaces.shown
    readonly property int group: onlyOpen ? 0 : Math.floor((activeWorkspace - 1) / shownCount)
'''),
])

# --- Transparency on by default ---------------------------------------------------------------------------
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property JsonObject transparency: JsonObject {
                    property bool enable: false
''',
     '''                property JsonObject transparency: JsonObject {
                    property bool enable: true // ii-windows: on by default (it is what makes ii look like ii)
'''),
])

# --- Desktop widgets only move in the edit mode (they took the click otherwise) ---------------------------------
edit(path('modules', 'ii', 'background', 'widgets', 'AbstractBackgroundWidget.qml'), [
    ('    draggable: placementStrategy === "free"\n',
     '    draggable: placementStrategy === "free" && GlobalStates.desktopEditMode // ii-windows: move them only while editing\n'),
])


# --- Spanish for the new texts -------------------------------------------------------------------------------------
ES_UX = {
    "Let the dock hide": "Dejar que el dock se oculte",
    "Keep the dock visible": "Mantener el dock visible",
    "Dock at the bottom": "Dock abajo",
    "Dock on the left": "Dock a la izquierda",
    "Dock on the right": "Dock a la derecha",
    "Dock settings": "Ajustes del dock",
    "Show the app name above the icon": "Mostrar el nombre de la app sobre el icono",
    "Position": "Posición",
    "Bottom": "Abajo",
    "Left": "Izquierda",
    "Right": "Derecha",
    "Icon size": "Tamaño de los iconos",
    "Magnification": "Ampliación",
    "Magnification reach": "Alcance de la ampliación",
    "Overview": "Vista general",
    "Personalize": "Personalizar",
    "Open in Terminal": "Abrir en Terminal",
}


def add_translations(code, strings):
    import json
    file = path('translations', code + '.json')
    with open(file, encoding='utf-8') as f:
        data = json.load(f)
    for key, value in strings.items():
        data.setdefault(key, value)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


add_translations('es_MX', ES_UX)
