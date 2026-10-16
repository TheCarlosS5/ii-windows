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


# --- Window icons: the Start menu entry's, else the program's own icon, else a guess by name -----------------
# A window class only gives a guess ("Valve.Steam.Client" matched nothing and the generic program icon showed);
# `winfile:<exe>` is what Explorer shows for that program (the icon provider of the fork).
edit(path('services', 'AppSearch.qml'), [
    ('    function guessIcon(str) {\n',
     '''    // ii-windows: the icon of a window (appId = its class, exe = the program's path, may be empty).
    function iconForWindow(appId, exe) {
        const entry = appId ? DesktopEntries.heuristicLookup(appId) : null;
        if (entry && entry.icon)
            return entry.icon;
        const path = (exe ?? "").replace(/\\\\/g, "/");
        // Store apps run inside ApplicationFrameHost: its own icon would be wrong for all of them.
        if (path !== "" && !/applicationframehost\\.exe$/i.test(path))
            return "winfile:" + path;
        return root.guessIcon(appId);
    }

    function guessIcon(str) {
'''),
])


# --- Launch counter ("most used" apps above the grid): services/AppUsage.qml keeps it here -----------------
edit(path('modules', 'common', 'Persistent.qml'), [
    ('            property JsonObject tour: JsonObject {\n',
     '''            property JsonObject launcher: JsonObject {
                // ii-windows: {"<entry id, lower case>": {"n": launches, "t": time of the last one, ms}}
                property var counts: ({})
            }
            property JsonObject externalWallpaper: JsonObject {
                // ii-windows: the preview picture the palette was last made from while a live wallpaper ran
                property string palette: ""
            }
            property JsonObject tour: JsonObject {
'''),
])

# --- Wallpaper Engine / Lively: ii's own picture steps aside so the live wallpaper shows through -----------------
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0\n',
     '                // ii-windows: not while Wallpaper Engine / Lively runs (the window is transparent: its animation shows through)\n'
     '                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo && (!ExternalWallpaper.active || GlobalStates.screenLocked)) ? 1 : 0\n'),
])

ES_UX3.update({
    "Live wallpapers": "Fondos animados",
    "Show the live wallpaper of Wallpaper Engine or Lively when it is open": "Mostrar el fondo animado de Wallpaper Engine o Lively cuando esté abierto",
    "ii stops drawing its own wallpaper while one of them runs, so the animation shows behind your icons and widgets. The colors come from the wallpaper's preview picture.": "ii deja de dibujar su propio fondo mientras uno de ellos está abierto, así la animación se ve detrás de tus iconos y widgets. Los colores salen de la imagen de vista previa del fondo.",
    "Detected: %1 — %2": "Detectado: %1 — %2",
    "No live wallpaper program is open": "No hay ningún programa de fondos animados abierto",
    "Make the colors from this wallpaper again": "Volver a calcular los colores con este fondo",
})
add_translations('es_MX', ES_UX3)
edit(path('modules', 'settings', 'AdvancedConfig.qml'), [
    ('''    ContentSection {
        icon: "backup"
''',
     '''    ContentSection {
        icon: "animation"
        title: Translation.tr("Live wallpapers")

        ConfigSwitch {
            buttonIcon: "wallpaper_slideshow"
            text: Translation.tr("Show the live wallpaper of Wallpaper Engine or Lively when it is open")
            checked: Config.options.background.externalProvider !== "off"
            onCheckedChanged: Config.options.background.externalProvider = checked ? "auto" : "off"
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("ii stops drawing its own wallpaper while one of them runs, so the animation shows behind your icons and widgets. The colors come from the wallpaper's preview picture.")
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: ExternalWallpaper.active
                ? Translation.tr("Detected: %1 — %2").arg(ExternalWallpaper.providerName).arg(ExternalWallpaper.title)
                : Translation.tr("No live wallpaper program is open")
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                visible: ExternalWallpaper.active
                materialIcon: "palette"
                mainText: Translation.tr("Make the colors from this wallpaper again")
                onClicked: ExternalWallpaper.recalc()
            }
        }
    }

    ContentSection {
        icon: "backup"
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
    // The pinned dock (Dock.qml): the space it takes from the bottom, and where it ends left and right.
    property real dockExclusiveBottom: 0
    property real dockSpanLeft: 0
    property real dockSpanRight: 0
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


# --- Windows of other programs: light transparency, calmer borders (ii-host does the work: host/src/windowfx.cpp) --
edit(path('modules', 'common', 'Config.qml'), [
    ('                property JsonObject wallpaperTheming: JsonObject {\n                    property bool enableAppsAndShell: true',
     '''                property JsonObject windowEffects: JsonObject {
                    // ii-windows: read by ii-host (windowfx.cpp), not by the shell
                    property bool transparency: true // other programs' windows a little translucent
                    property int opacity: 94 // percent, 60-100
                    property bool accentBorders: false // window borders and title bars in the wallpaper's accent colour
                    property string exclude: "" // programs that keep their windows opaque: "chrome.exe; code.exe"
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true'''),
])
ES_UX3.update({
    "Windows of other programs": "Ventanas de otros programas",
    "Light transparency in windows": "Transparencia ligera en las ventanas",
    "Makes the windows of your programs a little translucent. Games, fullscreen windows and programs that already use transparency are never touched. Turn it off and every window goes back to normal.": "Hace las ventanas de tus programas un poco translúcidas. Nunca toca juegos, ventanas a pantalla completa ni programas que ya usan transparencia. Si la apagas, todas las ventanas vuelven a la normalidad.",
    "Window opacity (%)": "Opacidad de las ventanas (%)",
    "Colored window borders": "Bordes de color en las ventanas",
    "Window borders and title bars take the accent color of the wallpaper. Off: they stay calm.": "Los bordes y barras de título toman el color de énfasis del fondo. Apagado: se quedan tranquilos.",
    "Keep these programs opaque": "Mantener opacos estos programas",
    "Program names separated by ; (for example chrome.exe; code.exe)": "Nombres de programas separados por ; (por ejemplo chrome.exe; code.exe)",
})
add_translations('es_MX', ES_UX3)
edit(path('modules', 'settings', 'AppearanceConfig.qml'), [
    ('''    ContentSection {
        icon: "colors"
        title: Translation.tr("Color generation")
''',
     '''    ContentSection {
        icon: "web_asset"
        title: Translation.tr("Windows of other programs")

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Light transparency in windows")
            checked: Config.options.appearance.windowEffects.transparency
            onCheckedChanged: Config.options.appearance.windowEffects.transparency = checked
            StyledToolTip {
                text: Translation.tr("Makes the windows of your programs a little translucent. Games, fullscreen windows and programs that already use transparency are never touched. Turn it off and every window goes back to normal.")
            }
        }
        ConfigSpinBox {
            enabled: Config.options.appearance.windowEffects.transparency
            icon: "gradient"
            text: Translation.tr("Window opacity (%)")
            value: Config.options.appearance.windowEffects.opacity
            from: 60
            to: 100
            stepSize: 2
            onValueChanged: Config.options.appearance.windowEffects.opacity = value
        }
        ConfigSwitch {
            buttonIcon: "border_color"
            text: Translation.tr("Colored window borders")
            checked: Config.options.appearance.windowEffects.accentBorders
            onCheckedChanged: Config.options.appearance.windowEffects.accentBorders = checked
            StyledToolTip {
                text: Translation.tr("Window borders and title bars take the accent color of the wallpaper. Off: they stay calm.")
            }
        }
        MaterialTextField {
            Layout.fillWidth: true
            enabled: Config.options.appearance.windowEffects.transparency
            placeholderText: Translation.tr("Keep these programs opaque")
            text: Config.options.appearance.windowEffects.exclude
            onEditingFinished: Config.options.appearance.windowEffects.exclude = text
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Program names separated by ; (for example chrome.exe; code.exe)")
        }
    }

    ContentSection {
        icon: "colors"
        title: Translation.tr("Color generation")
'''),
])

# The translator tab of the left sidebar is on by default (it was off, so a new install had no Translator tab).
edit(path('modules', 'common', 'Config.qml'), [
    ('                    property bool enable: false\n                    property int delay: 300',
     '                    property bool enable: true // ii-windows: on by default\n                    property int delay: 300'),
])
ES_UX3.update({
    "Detect language": "Detectar idioma",
    "System language": "Mi idioma",
    "Swap languages": "Intercambiar idiomas",
    "Pick the two languages to swap them": "Elige los dos idiomas para intercambiarlos",
    "Translating...": "Traduciendo...",
    "Paste": "Pegar",
    "Clear": "Borrar",
    "Copy": "Copiar",
    "Search the web": "Buscar en la web",
})
add_translations('es_MX', ES_UX3)


# --- Side panels use the corner next to a pinned dock ------------------------------------------------------------
# A pinned dock reserves space at the bottom, so the panels stop above it even where the dock does not reach (an
# empty corner, and cramped content). Down to the screen edge when the dock's span does not touch the panel.
edit(path('modules', 'ii', 'sidebarRight', 'SidebarRight.qml'), [
    ('        implicitWidth: sidebarWidth\n        WlrLayershell.namespace: "quickshell:sidebarRight"\n',
     '        implicitWidth: sidebarWidth\n'
     '        margins.bottom: (GlobalStates.dockExclusiveBottom > 0 && GlobalStates.dockSpanRight < (screen?.width ?? 0) - sidebarWidth - 16) ? -GlobalStates.dockExclusiveBottom : 0\n'
     '        WlrLayershell.namespace: "quickshell:sidebarRight"\n'),
])
edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeft.qml'), [
    ('            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin\n',
     '            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin\n'
     '            margins.bottom: (GlobalStates.dockExclusiveBottom > 0 && GlobalStates.dockSpanLeft > implicitWidth + 16) ? -GlobalStates.dockExclusiveBottom : 0\n'),
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
    # A left click on an icon of the popup opens its app: the popup closes then, as Windows' hidden icons do.
    ('                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);\n',
     '                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);\n'
     '                            onActivated: {\n'
     '                                root.trayOverflowOpen = false;\n'
     '                                root.closeOverflowMenu();\n'
     '                            }\n'),
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
