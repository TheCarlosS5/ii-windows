"""UX round of 2026-10-15, part 3: tray overflow, overview modes, launch counter, external wallpapers.
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


ES_UX3 = {
    "Show windows": "Mostrar ventanas",
    "Show the app store in the dock": "Mostrar la tienda en el dock",
    "Frequently used": "Usadas con frecuencia",
    "Show the most used apps above the app grid": "Mostrar las apps más usadas sobre la rejilla de aplicaciones",
    "Forget the most used apps": "Olvidar las apps más usadas",
}
add_translations('es_MX', ES_UX3)

# Settings: the store in the dock, and the "most used" row of the overview.
edit(path('modules', 'settings', 'DockConfig.qml'), [
    ('''            checked: Config.options.dock.showLabels
            onCheckedChanged: {
                Config.options.dock.showLabels = checked;
            }
        }
''',
     '''            checked: Config.options.dock.showLabels
            onCheckedChanged: {
                Config.options.dock.showLabels = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "storefront"
            text: Translation.tr("Show the app store in the dock")
            checked: Config.options.dock.showStore
            onCheckedChanged: {
                Config.options.dock.showStore = checked;
            }
        }
'''),
])
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''            checked: Config.options.overview.enable
            onCheckedChanged: {
                Config.options.overview.enable = checked;
            }
        }
''',
     '''            checked: Config.options.overview.enable
            onCheckedChanged: {
                Config.options.overview.enable = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "star"
            text: Translation.tr("Show the most used apps above the app grid")
            checked: Config.options.overview.showFrequent
            onCheckedChanged: {
                Config.options.overview.showFrequent = checked;
            }
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            buttonRadius: Appearance.rounding.small
            materialIcon: "history"
            mainText: Translation.tr("Forget the most used apps")
            onClicked: AppUsage.clear()
        }
'''),
])


# --- Options of this round ---------------------------------------------------------------------------------
# (shared/config-schema.json and host/src/config_schema.inc are generated from this file: run
# tools/dev/gen-config-schema.py --stage build/ii after changing them.)
edit(path('modules', 'common', 'Config.qml'), [
    ('                property bool showLabels: true\n',
     '                property bool showLabels: true\n'
     '                property bool showStore: true // ii-windows: the app store as a tile next to the overview button\n'),
    ('            property JsonObject overview: JsonObject {\n                property bool enable: true\n',
     '            property JsonObject overview: JsonObject {\n                property bool enable: true\n'
     '                property bool showFrequent: true // ii-windows: "most used" apps above the app grid\n'
     '                property int frequentCount: 8\n'),
    ('            property JsonObject background: JsonObject {\n',
     '            property JsonObject background: JsonObject {\n'
     '                property string externalProvider: "auto" // ii-windows: auto = show Wallpaper Engine / Lively when running, off = never\n'),
])


# --- Launch counter ("most used" apps above the grid): services/AppUsage.qml keeps it here -----------------
edit(path('modules', 'common', 'Persistent.qml'), [
    ('            property JsonObject tour: JsonObject {\n',
     '''            property JsonObject launcher: JsonObject {
                // ii-windows: {"<entry id, lower case>": {"n": launches, "t": time of the last one, ms}}
                property var counts: ({})
            }
            property JsonObject tour: JsonObject {
'''),
])


# Search field: Left/Right move through the app tiles (not only after Up/Down) when there is nothing to
# move the text cursor to: an empty field (the app grid), or the cursor at the end of the text.
edit(path('modules', 'ii', 'overview', 'SearchBar.qml'), [
    ('''            } else if (root.navigating && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                root.navigate(event.key === Qt.Key_Left ? "left" : "right");
                event.accepted = true;
            }''',
     '''            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                const atEnd = searchInput.cursorPosition === searchInput.text.length;
                if (root.navigating || searchInput.text.length === 0 || (event.key === Qt.Key_Right && atEnd)) {
                    root.navigating = true;
                    root.navigate(event.key === Qt.Key_Left ? "left" : "right");
                    event.accepted = true;
                }
            }'''),
])

# Every app opened from the search counts as a launch.
edit(path('services', 'LauncherSearch.qml'), [
    ('''                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)''',
     '''                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    AppUsage.record(entry); // ii-windows: counts for the "most used" apps
                    if (!entry.runInTerminal)'''),
])


# --- Overview modes: Win opens the app grid, Win+Tab the windows --------------------------------------------
edit(path('GlobalStates.qml'), [
    ('    property bool overviewOpen: false\n',
     '''    property bool overviewOpen: false
    property string overviewMode: "apps" // ii-windows: "apps" (the grid, Win) or "windows" (Win+Tab)
    property real overviewDismissedAt: 0
    // A press on a dock/bar button first "clicks outside" (which closes the overview), and then the click
    // itself arrives: don't reopen what that same click just closed.
    function toggleOverview(mode) {
        if (!overviewOpen && Date.now() - overviewDismissedAt < 350) return;
        if (overviewOpen && overviewMode === mode) {
            overviewOpen = false;
            return;
        }
        overviewMode = mode;
        overviewOpen = true;
    }
'''),
])


# The bar's own overview buttons (right click on the bar / on the desktop dots) open the grid too, and go
# through the same guard against "dismissed by the press, reopened by the click".
edit(path('modules', 'ii', 'bar', 'BarContent.qml'), [
    ('                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;\n',
     '                            GlobalStates.toggleOverview("apps");\n'),
])
edit(path('modules', 'ii', 'bar', 'Workspaces.qml'), [
    ('            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;\n',
     '            GlobalStates.toggleOverview("apps");\n'),
])
edit(path('modules', 'ii', 'verticalBar', 'VerticalBarContent.qml'), [
    ('                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;\n',
     '                            GlobalStates.toggleOverview("apps");\n'),
])


# --- Tray overflow: the popup stays open while the pointer is on it ----------------------------------------
# StyledPopup (patched in patch_ii_p0.py) shows its window only while the hover target is hovered. The tray
# overflow opens by click, so it must stay visible while trayOverflowOpen is true (otherwise moving the
# pointer down onto the icons hid it, and no icon could be right-clicked or pinned).
edit(path('modules', 'ii', 'bar', 'SysTray.qml'), [
    ('    property var activeMenu: null\n',
     '    property var activeMenu: null\n'
     '    property real overflowClearedAt: 0 // ii-windows: the click that closed the grab must not reopen the popup\n'),
    ('''        onCleared: {
            root.trayOverflowOpen = false;
''',
     '''        onCleared: {
            if (root.trayOverflowOpen) root.overflowClearedAt = Date.now();
            root.trayOverflowOpen = false;
'''),
    ('        windows: [trayOverflowLayout.QsWindow?.window, root.activeMenu]\n',
     '        windows: [trayOverflowLayout.QsWindow?.window, trayOverflowButton.QsWindow?.window, root.activeMenu]\n'),
    ('            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen\n',
     '''            downAction: () => {
                if (Date.now() - root.overflowClearedAt < 350) return;
                root.trayOverflowOpen = !root.trayOverflowOpen;
            }
'''),
    ('                active: root.trayOverflowOpen && root.unpinnedItems.length > 0\n',
     '                active: root.trayOverflowOpen && root.unpinnedItems.length > 0\n'
     '                shown: root.trayOverflowOpen && root.unpinnedItems.length > 0 // ii-windows: by click, not by hover\n'),
])
