"""Small exact-match edits applied to the staged ii (build/ii) by tools/dev/stage-ii.ps1.

For changes too small to justify replacing a whole file in overlay/ii: Windows defaults in
Config.qml. Every pattern must match exactly once, so an upstream change that moves the code
fails the staging loudly instead of silently dropping a Windows default.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

# II_STAGE_DIR: stage somewhere else (a second, private staging while another one is in use).
ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.normpath(os.path.join(ROOT, *parts))


# Windows defaults. Commands run through ii-shim's restricted `bash -c`, which only opens a
# single URI (ms-settings:...) or a single program, so they must be exactly that.
edit(path('modules', 'common', 'Config.qml'), [
    ('property string bluetooth: "kcmshell6 kcm_bluetooth"',
     'property string bluetooth: "ms-settings:bluetooth"'),
    ('''property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"''',
     'property string changePassword: "ms-settings:signinoptions"'),
    ('property string network: "kcmshell6 kcm_networkmanagement"',
     'property string network: "ms-settings:network-wifi"'),
    ('property string manageUser: "kcmshell6 kcm_users"',
     'property string manageUser: "ms-settings:yourinfo"'),
    ('property string networkEthernet: "kcmshell6 kcm_networkmanagement"',
     'property string networkEthernet: "ms-settings:network-ethernet"'),
    ('property string taskManager: "plasma-systemmonitor --page-name Processes"',
     'property string taskManager: "taskmgr"'),
    ('property string terminal: "kitty -1" // This is only for shell actions',
     'property string terminal: "wt" // This is only for shell actions'),
    ('''property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"''',
     'property string update: "ms-settings:windowsupdate"'),
    ('''property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`''',
     'property string volumeMixer: "ms-settings:apps-volume"'),
    # The dock stands in for the hidden Windows taskbar.
    ('''            property JsonObject dock: JsonObject {
                property bool enable: false''',
     '''            property JsonObject dock: JsonObject {
                property bool enable: true'''),
    ('''                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]''',
     '''                property list<string> pinnedApps: [ // IDs of pinned entries
                    "Microsoft.Windows.Explorer", "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App",]'''),
    ('''                property list<string> pinnedApps: [ "org.kde.dolphin", "kitty", "cmake-gui"]''',
     '''                property list<string> pinnedApps: [ "Microsoft.Windows.Explorer", "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"]'''),
])

# /tmp would be C:\tmp on Windows (a new folder at the drive root): use the user's temp folder.
WIN_TMP = 'FileUtils.trimFileProtocol(StandardPaths.writableLocation(StandardPaths.TempLocation))'
edit(path('modules', 'common', 'Directories.qml'), [
    ('property string tempImages: "/tmp/quickshell/media/images"',
     'property string tempImages: `${' + WIN_TMP + '}/quickshell/media/images`'),
    ('property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)',
     'property string cliphistDecode: `${' + WIN_TMP + '}/quickshell/media/cliphist`'),
    ('property string screenshotTemp: "/tmp/quickshell/media/screenshot"',
     'property string screenshotTemp: `${' + WIN_TMP + '}/quickshell/media/screenshot`'),
])

# Recorder widget: a full screenshot straight to the clipboard (was grim - | wl-copy), after the
# overlay's closing animation.
edit(path('modules', 'ii', 'overlay', 'recorder', 'Recorder.qml'), [
    ('Quickshell.execDetached(["bash", "-c", "grim - | wl-copy"]);',
     'Quickshell.execDetached(["ii-shim", "screenshot", "--copy", "--delay", "400"]);'),
])

# Overlay: the FPS limiter drives MangoHud (Linux only); on Windows it would claim success and do
# nothing, so it isn't offered.
edit(path('modules', 'ii', 'overlay', 'OverlayContext.qml'), [
    ('        { identifier: "fpsLimiter", materialSymbol: "animation" },\n', ''),
])

# Windows desktop entries use the real personal and shared Desktop folders. Keep the
# original background/clock intact and place the icons outside the parallax canvas.
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject background: JsonObject {
                property JsonObject widgets: JsonObject {''',
     '''            property JsonObject background: JsonObject {
                property JsonObject widgets: JsonObject {
                    property JsonObject desktopIcons: JsonObject {
                        property bool enable: true
                        property int iconSize: 48
                    }'''),
])
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('import qs.modules.ii.background.widgets.clock',
     'import qs.modules.ii.background.widgets.desktop\nimport qs.modules.ii.background.widgets.clock'),
    ('''            WidgetCanvas {
                id: widgetCanvas''',
     '''            MouseArea {
                id: desktopMenuArea
                // Right click on the desktop or on a widget: ii's desktop menu (icons keep theirs).
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                enabled: !GlobalStates.screenLocked
                onPressed: event => {
                    // A widget under the pointer can add its own entries (photo: change, resize...).
                    // Widgets sit in loaders at the canvas origin: test each widget itself, top first.
                    let hit = null;
                    const loaders = widgetCanvas.children;
                    for (let i = loaders.length - 1; i >= 0 && !hit; i--) {
                        const widget = loaders[i].item;
                        if (widget?.visible && widget.contains(widget.mapFromItem(desktopMenuArea, event.x, event.y)))
                            hit = widget;
                    }
                    desktopMenu.popup(event.x, event.y, hit);
                }
            }

            Loader {
                id: desktopIconsLoader
                anchors.fill: parent
                active: Config.options.background.widgets.desktopIcons.enable && !GlobalStates.screenLocked
                // A name being edited must receive clicks above clock/weather.
                z: item?.raised ? 1 : 0
                sourceComponent: DesktopIcons {
                    menu: desktopMenu
                }
            }

            WidgetCanvas {
                id: widgetCanvas'''),
    ('''                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }
''',
     '''                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }

            DesktopMenu {
                id: desktopMenu
                anchors.fill: parent
                z: 2
                screen: bgRoot.screen
                desktopEntries: desktopIconsLoader.item?.desktopEntries ?? []
            }
'''),
    # The desktop takes the keyboard when clicked (arrows, F2, Delete...). It is never activated
    # just by appearing, and stays under the apps when activated (Quickshell's win32 backend).
    ('''        WlrLayershell.namespace: "quickshell:background"''',
     '''        WlrLayershell.namespace: "quickshell:background"
        focusable: Config.options.background.widgets.desktopIcons.enable'''),
])

# The upstream canvas is an otherwise empty full-screen MouseArea. It must not eat
# clicks intended for desktop icons beneath it; clock/weather keep their own handlers.
edit(path('modules', 'common', 'widgets', 'widgetCanvas', 'WidgetCanvas.qml'), [
    ('    id: root', '    id: root\n    acceptedButtons: Qt.NoButton'),
])

# Background widgets: a negative x/y counts from the right/bottom edge, so defaults can sit in
# a corner on any screen size. Dragging still saves ordinary positive coordinates.
edit(path('modules', 'ii', 'background', 'widgets', 'AbstractBackgroundWidget.qml'), [
    ('    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))',
     '    property real targetX: Math.max(0, Math.min(configEntry.x < 0 ? scaledScreenWidth - width + configEntry.x : configEntry.x, scaledScreenWidth - width))'),
    ('    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))',
     '    property real targetY: Math.max(0, Math.min(configEntry.y < 0 ? scaledScreenHeight - height + configEntry.y : configEntry.y, scaledScreenHeight - height))'),
])

# Desktop layout: icons down the left like Windows, so the clock defaults to the top right
# ("leastBusy" placement needs ii's Python image script, which Windows doesn't have), and a
# folder widget (Downloads unless configured) sits in the bottom right.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property string style: "cookie"''',
     '''                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: -48
                        property real y: 72
                        property string style: "cookie"'''),
    ('''                    property JsonObject desktopIcons: JsonObject {
                        property bool enable: true
                        property int iconSize: 48
                    }''',
     '''                    property JsonObject desktopIcons: JsonObject {
                        property bool enable: true
                        property int iconSize: 48
                    }
                    property JsonObject folder: JsonObject {
                        property bool enable: true
                        property string path: "" // empty: Downloads
                        property int maxItems: 7
                        property string placementStrategy: "free"
                        property real x: -48
                        property real y: -48
                    }'''),
])

edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('''                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable''',
     '''                FadeLoader {
                    shown: Config.options.background.widgets.folder.enable
                    sourceComponent: FolderWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable'''),
])

# Two more desktop widgets (ii-windows additions in ii's style): the music player card under the
# clock, and a photo (a local image or an https URL, gifs play) anywhere on the desktop. The
# desktop's right-click menu turns any widget on or off; a widget turned on from there appears
# where the menu was opened.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                    property JsonObject folder: JsonObject {''',
     '''                    property JsonObject media: JsonObject {
                        property bool enable: true
                        property string placementStrategy: "free"
                        property real x: -48
                        property real y: 330
                    }
                    property JsonObject photo: JsonObject {
                        property bool enable: false
                        property string source: "" // local image path or https URL
                        property real scale: 1
                        property string placementStrategy: "free"
                        property real x: 560
                        property real y: 140
                    }
                    property JsonObject folder: JsonObject {'''),
])
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    # Loaded by URL, not as types: if one of these fails to load (a missing Qt module, say),
    # only that widget is missing instead of the whole desktop.
    ('''                FadeLoader {
                    shown: Config.options.background.widgets.folder.enable''',
     '''                FadeLoader {
                    shown: Config.options.background.widgets.media.enable
                    Component.onCompleted: setSource(Qt.resolvedUrl("widgets/media/MediaWidget.qml"), {
                        screenWidth: bgRoot.screen.width,
                        screenHeight: bgRoot.screen.height,
                        scaledScreenWidth: bgRoot.screen.width,
                        scaledScreenHeight: bgRoot.screen.height,
                        wallpaperScale: 1,
                    })
                }

                FadeLoader {
                    shown: Config.options.background.widgets.photo.enable
                    Component.onCompleted: setSource(Qt.resolvedUrl("widgets/photo/PhotoWidget.qml"), {
                        screenWidth: bgRoot.screen.width,
                        screenHeight: bgRoot.screen.height,
                        scaledScreenWidth: bgRoot.screen.width,
                        scaledScreenHeight: bgRoot.screen.height,
                        wallpaperScale: 1,
                    })
                }

                FadeLoader {
                    shown: Config.options.background.widgets.folder.enable'''),
])

# Overview: Windows has one set of windows (no Hyprland workspaces to move them to) and its
# windows overlap or are maximized, so drawing each at its real position hides most of them.
# One large workspace, windows laid out in a grid (most recently used first), no dragging;
# click focuses, middle click closes, as in ii.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5''',
     '''                property real scale: 0.55 // Relative to screen size
                property real rows: 1
                property real columns: 1'''),
])
edit(path('modules', 'ii', 'overview', 'OverviewWidget.qml'), [
    ('''    property real scale: Config.options.overview.scale''',
     '''    property real scale: Config.options.overview.scale

    // ii-windows: grid positions for this monitor's windows, in monitor pixels, with the shape
    // of hyprctl's window objects so OverviewWindow scales them like real positions.
    readonly property var gridLayout: {
        const mon = root.monitorData;
        if (!mon) return ({});
        const wins = root.windows.filter(w => w.monitor === mon.id && w.size[0] > 0 && w.size[1] > 0
            && w.workspace.id === root.effectiveActiveWorkspaceId);
        const n = wins.length;
        if (n === 0) return ({});
        const areaX = mon.x + mon.reserved[0];
        const areaY = mon.y + mon.reserved[1];
        const areaW = mon.width / mon.scale - mon.reserved[0] - mon.reserved[2];
        const areaH = mon.height / mon.scale - mon.reserved[1] - mon.reserved[3];
        // Windows are roughly screen-shaped: a square-ish grid of screen-shaped cells.
        const cols = Math.ceil(Math.sqrt(n));
        const rows = Math.ceil(n / cols);
        const cellW = areaW / cols;
        const cellH = areaH / rows;
        const gap = Math.min(cellW, cellH) * 0.06;
        const result = {};
        wins.forEach((w, i) => {
            const row = Math.floor(i / cols);
            const inRow = row === rows - 1 ? n - row * cols : cols;
            const col = i % cols;
            // Minimized windows have no live image (DWM keeps none): a screen-shaped card with
            // the app's icon (OverviewWindow shows it when there is no preview).
            const size = w.hidden ? [areaW * 0.6, areaH * 0.6] : w.size;
            const s = Math.min((cellW - gap * 2) / size[0], (cellH - gap * 2) / size[1], 1);
            const width = size[0] * s;
            const height = size[1] * s;
            // Center a shorter last row.
            const rowOffset = (cols - inRow) * cellW / 2;
            result[w.address] = Object.assign({}, w, {
                at: [areaX + rowOffset + col * cellW + (cellW - width) / 2, areaY + row * cellH + (cellH - height) / 2],
                size: [width, height],
            });
        });
        return result;
    }'''),
    ('''                    windowData: windowByAddress[address]''',
     '''                    windowData: root.gridLayout[address] ?? windowByAddress[address]'''),
])
# Overview.qml, SearchWidget.qml and AppGrid.qml are overlay files now (GNOME-style overview, desktop strip on top).
edit(path('modules', 'ii', 'overview', 'OverviewWindow.qml'), [
    ('        captureSource: GlobalStates.overviewOpen ? root.toplevel : null',
     '        captureSource: GlobalStates.overviewOpen && !root.windowData?.hidden ? root.toplevel : null'),
])
# Dock: now a full overlay (overlay/ii/modules/ii/dock): magnifying icons, right-click menu, minimize on click.

# Bar: the active window's line is overlay/ii/modules/ii/bar/ActiveWindow.qml (friendly app names).

# Weather: on Windows "GPS" is the Location service, which pops a system permission prompt the
# moment the weather turns on. Off by default: wttr.in then locates by IP (or uses `city`).
edit(path('modules', 'common', 'Config.qml'), [
    ('property bool enableGPS: true // gps based location',
     'property bool enableGPS: false // gps based location (Windows asks for location permission)'),
])
# Qt's Windows positioning backend asks for that permission as soon as a PositionSource exists,
# started or not: create it only while GPS is on.
edit(path('services', 'Weather.qml'), [
    ('        positionSource.start();', '        positionLoader.item?.start();'),
    ('''    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval
''',
     '''    Loader {
        id: positionLoader
        active: Config.options.bar.weather.enableGPS
        onLoaded: item.start()
        sourceComponent: PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval
'''),
    ('''                console.error("[WeatherService] Could not aquire a valid backend plugin.");
            }
        }
    }
''',
     '''                console.error("[WeatherService] Could not aquire a valid backend plugin.");
            }
        }
    }
    }
'''),
])

# Windows reports regional variants (es_CO, pt_PT, de_AT...): with "auto", use the shipped
# translation of the same language when there is no exact one, instead of falling back to English.
edit(path('services', 'Translation.qml'), [
    ('''        if (configLang !== "auto")
            return configLang;

        return Qt.locale().name;''',
     '''        if (configLang !== "auto")
            return configLang;

        const name = Qt.locale().name;
        const shipped = ["de_DE", "en_US", "es_MX", "fr_FR", "he_HE", "id_ID", "it_IT", "ja_JP", "pt_BR", "ru_RU", "tr_TR", "uk_UA", "vi_VN", "zh_CN"];
        if (shipped.includes(name))
            return name;
        return shipped.find(code => code.split("_")[0] === name.split("_")[0]) ?? name;'''),
])

# Workspaces are Windows' virtual desktops: the bar keeps ii's fixed slots (10 by default, as on
# Hyprland), and a dot is "occupied" when that desktop has windows (an empty or missing desktop
# looks empty).
edit(path('modules', 'common', 'models', 'WorkspaceModel.qml'), [
    ('            return Hyprland.workspaces.values.some(ws => ws.id === thisWorkspaceId);',
     '            return HyprlandData.windowList.some(w => w.workspace.id === thisWorkspaceId);'),
    ('''    onGroupChanged: {
        updateWorkspaceOccupied();
    }''',
     '''    onGroupChanged: {
        updateWorkspaceOccupied();
    }
    onShownCountChanged: updateWorkspaceOccupied()'''),
    ('''    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }''',
     '''    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.updateWorkspaceOccupied();
        }
    }'''),
])

# The number of dots follows the desktops: for a moment a new dot has no "occupied" entry yet.
edit(path('modules', 'ii', 'bar', 'Workspaces.qml'), [
    ('property bool currentOccupied: wsModel.occupied[index] && wsId != wsModel.fakeWorkspace',
     'property bool currentOccupied: !!wsModel.occupied[index] && wsId != wsModel.fakeWorkspace'),
    ('property bool previousOccupied: index > 0 && wsModel.occupied[index - 1] && (wsId - 1) != wsModel.fakeWorkspace',
     'property bool previousOccupied: index > 0 && !!wsModel.occupied[index - 1] && (wsId - 1) != wsModel.fakeWorkspace'),
    ('property bool nextOccupied: index < wsModel.shownCount - 1 && wsModel.occupied[index + 1] && (wsId + 1) != wsModel.fakeWorkspace',
     'property bool nextOccupied: index < wsModel.shownCount - 1 && !!wsModel.occupied[index + 1] && (wsId + 1) != wsModel.fakeWorkspace'),
])

# Tray: the icons Windows keeps behind the arrow (not "promoted" in Settings > Taskbar) go to
# ii's overflow menu as well, so many background apps don't crowd the bar.
edit(path('services', 'TrayService.qml'), [
    ('''    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList''',
     '''    // ii-windows: Windows decides by default (Settings > Taskbar > Other system tray icons);
    // a middle click on an icon moves it between the bar and the overflow menu (shownItems /
    // hiddenItems), as ii's pins do on Linux through the icon's own menu, which Windows apps lack.
    readonly property list<var> trayItems: SystemTray.items.values.filter(i => !smartTray || i.status !== Status.Passive)
    function inBar(item) {
        if ((Config.options.tray.hiddenItems ?? []).includes(item.id)) return false;
        if ((Config.options.tray.shownItems ?? []).includes(item.id)) return true;
        return item.promoted !== false;
    }
    function toggleInBar(item) {
        const tray = Config.options.tray;
        const show = !root.inBar(item);
        tray.hiddenItems = (tray.hiddenItems ?? []).filter(id => id !== item.id).concat(show ? [] : [item.id]);
        tray.shownItems = (tray.shownItems ?? []).filter(id => id !== item.id).concat(show ? [item.id] : []);
    }
    property list<var> pinnedItems: trayItems.filter(i => root.inBar(i))
    property list<var> unpinnedItems: trayItems.filter(i => !root.inBar(i))'''),
    (r'''        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";''',
     r'''        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        result += "\n" + (root.inBar(item) ? Translation.tr("Middle click: hide behind the arrow")
                                           : Translation.tr("Middle click: show on the bar"));'''),
])
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property list<var> pinnedItems: [ "Fcitx" ]''',
     '''                property list<var> pinnedItems: [ "Fcitx" ]
                property list<var> shownItems: [] // ii-windows: forced onto the bar
                property list<var> hiddenItems: [] // ii-windows: forced behind the arrow'''),
])

# ii's settings app is a plain Qt window: Windows would add its own caption and buttons next to
# ii's title bar and close button. Keep only ii's: no Windows caption (frame, shadow and resizable
# edges stay), ii's title bar moves the window and a double click maximizes, as Windows' does.
edit(path('settings.qml'), [
    ('    title: "illogical-impulse Settings"\n',
     '    title: "illogical-impulse Settings"\n'
     "    // Quickshell's win32 backend hides the Windows caption of such windows, keeping the frame.\n"
     '    property bool customTitleBar: true\n'),
    ('''        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
''',
     '''        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            DragHandler {
                target: null
                onActiveChanged: if (active) root.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
'''),
])

# Spanish for the strings this port adds (desktop menu, desktop icons, folder and photo widgets).
# Only missing keys are added; ii's own translations win.
PORT_STRINGS_ES = {
    "Change wallpaper": "Cambiar fondo",
    "Random wallpaper": "Fondo aleatorio",
    "Clock": "Reloj",
    "Music": "Música",
    "Photo": "Foto",
    "Recent files": "Archivos recientes",
    "Desktop icons": "Iconos del escritorio",
    "Overlay widgets": "Widgets superpuestos",
    "Display settings": "Configuración de pantalla",
    "Show in folder": "Mostrar en la carpeta",
    "Nothing here yet": "Aún no hay nada aquí",
    "Just now": "Ahora mismo",
    "%1 min ago": "hace %1 min",
    "%1 h ago": "hace %1 h",
    "%1 d ago": "hace %1 d",
    "Open folder": "Abrir carpeta",
    "Choose a photo": "Elige una foto",
    "Couldn't load the photo": "No se pudo cargar la foto",
    "Choose…": "Elegir…",
    "Change photo…": "Cambiar foto…",
    "Reset size": "Restablecer tamaño",
    "Open image": "Abrir imagen",
    "Remove from desktop": "Quitar del escritorio",
    "New window": "Nueva ventana",
    "Pin to dock": "Anclar al dock",
    "Unpin from dock": "Desanclar del dock",
    "Close window": "Cerrar ventana",
    "Close all windows": "Cerrar todas las ventanas",
    "Desktop %1": "Escritorio %1",
    "New desktop": "Nuevo escritorio",
    "Close desktop": "Cerrar escritorio",
    "Middle click: hide behind the arrow": "Clic con la rueda: ocultar detrás de la flecha",
    "Middle click: show on the bar": "Clic con la rueda: mostrar en la barra",
    "From": "Desde",
    "To": "Hasta",
    "Gamma": "Gamma",
    "No networks found": "No se encontraron redes",
    "Not available": "No disponible",
    "Reload Quickshell": "Recargar Quickshell",
    "Windows settings": "Ajustes de Windows",
    "Open": "Abrir",
    "Open with…": "Abrir con…",
    "Cut": "Cortar",
    "Copy": "Copiar",
    "Copy path": "Copiar ruta",
    "Rename": "Cambiar nombre",
    "Delete": "Eliminar",
    "Properties": "Propiedades",
    "More options": "Más opciones",
    "New folder": "Nueva carpeta",
    "Paste": "Pegar",
    "Sort by": "Ordenar por",
    "Name": "Nombre",
    "Date": "Fecha",
    "Type": "Tipo",
    "%1 more": "%1 más",
    "Recent": "Recientes",
    "Icons": "Iconos",
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


add_translations('es_MX', PORT_STRINGS_ES)

# Wallpaper and colors: switchwall.sh (bash + matugen + Python) becomes ii-shim's native
# `switchwall` (in <dist>\bin, found on PATH; ii also runs it as `bash -c "switchwall ..."`).
edit(path('modules', 'common', 'Directories.qml'), [
    ('property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/switchwall.sh`)',
     'property string wallpaperSwitchScriptPath: "switchwall"'),
])

# Thumbnails: ii-shim makes them with WIC instead of `bash -c "[ -f ... ] || magick ..."`, with
# the same exit codes (0 already there, 1 generated now so the image reloads).
edit(path('modules', 'common', 'widgets', 'ThumbnailImage.qml'), [
    ('''            return ["bash", "-c", 
                `[ -f '${FileUtils.trimFileProtocol(root.thumbnailPath)}' ] && exit 0 || { magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} '${FileUtils.trimFileProtocol(root.thumbnailPath)}' && exit 1; }`
            ]''',
     '''            return ["ii-shim", "thumbnail", FileUtils.trimFileProtocol(root.sourcePath), `${maxSize}`, FileUtils.trimFileProtocol(root.thumbnailPath)]'''),
])

# Wallpaper selector: ii makes the thumbnails in one batch with a bash/Python script; on Windows
# each ThumbnailImage makes its own (same file name, computed by ThumbnailImage itself).
edit(path('modules', 'ii', 'wallpaperSelector', 'WallpaperDirectoryItem.qml'), [
    ('                        generateThumbnail: false\n', '                        generateThumbnail: true\n'),
])
