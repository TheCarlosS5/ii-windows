"""Plan of 2026-10-24 (reports from the first users). Exact-match edits of the staged tree; every edit fails loudly
if upstream moved the code."""
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


# --- 0.3 Wallpaper: never upstream's brown picture ------------------------------------------------------------------
# overlay/ii/assets/images/default_wallpaper.png is ii-windows' own picture now (tools/dev/make-default-wallpaper.py).
# At every start switchwall also gets it as the fallback: a chosen wallpaper whose file is gone shows it (and Windows
# follows), and the old copy of upstream's picture in Pictures\Wallpapers is replaced by it.
edit(path('shell.qml'), [
    ('''        Quickshell.execDetached(["switchwall", "--adopt-windows"]) // ii-windows: the wallpaper Windows has is ii's too
''', '''        Quickshell.execDetached(["switchwall", "--adopt-windows", "--default", FirstRunExperience.defaultWallpaperPath]) // ii-windows: one wallpaper for ii and Windows; a missing file falls back to ii-windows' own
'''),
])


# --- 0.4 The Windows key shows a launcher that is already there ------------------------------------------------------
# The app grid was a Loader active only while the overview was open: every Win press built every tile and read every
# icon on the GUI thread, and the overview's window was drawn for the very first time then too. On slow PCs that froze
# the whole shell for seconds. Now, a few seconds after start-up, the grid is made once and kept, and the window is
# shown once (nothing visible in it, click-through, no keyboard) so its graphics are set up before the first press.
edit(path('modules', 'ii', 'overview', 'Overview.qml'), [
    ('''    readonly property bool showApps: GlobalStates.overviewMode === "apps"
''', '''    readonly property bool showApps: GlobalStates.overviewMode === "apps"
    // ii-windows: made once after start-up and kept (see above), instead of on every Win press.
    property bool warm: false
    property bool warming: false
    Timer {
        running: (Config?.ready ?? false) && !overviewScope.warm
        interval: 8000
        onTriggered: {
            overviewScope.warm = true;
            if (!GlobalStates.overviewOpen) {
                overviewScope.warming = true;
                warmEnd.restart();
            }
        }
    }
    Timer {
        id: warmEnd
        interval: 1500
        onTriggered: overviewScope.warming = false
    }
'''),
    ('''        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen
''', '''        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen || overviewScope.warming
'''),
    # ii-host knows the search shows by this name on the window (Quickshell for Windows marks each panel window with
    # its namespace): not while it is only warming up, invisible.
    ('''        WlrLayershell.namespace: "quickshell:overview"
''', '''        WlrLayershell.namespace: GlobalStates.overviewOpen ? "quickshell:overview" : "quickshell:overviewHidden"
'''),
    ('''        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
''', '''        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen || overviewScope.warming // ii-windows: drawn once at opacity 0 to warm up
'''),
    # The arrows and Enter go to the grid only while it is shown (kept alive, it must not take them in Win+Tab).
    ('''                gridNavigator: appGridLoader.item
''', '''                gridNavigator: appGridLoader.visible ? appGridLoader.item : null
'''),
    # Kept while searching and in the windows mode too: only hidden (typing, or Win+Tab and back, rebuilt it whole).
    ('''                active: GlobalStates.overviewOpen && overviewScope.showApps && panelWindow.searchingText == ""
                visible: active
''', '''                active: GlobalStates.overviewOpen || overviewScope.warm
                visible: active && overviewScope.showApps && panelWindow.searchingText == ""
'''),
])


# --- 0.7 Wallpaper Engine: touching ii's desktop does not pause it ---------------------------------------------------
# A click on the desktop activated ii's background window (it takes the keyboard like Explorer's desktop, D20), and
# Wallpaper Engine / Lively saw "another application in front" and paused. While one of them runs, the desktop only
# takes the keyboard to rename an icon; the bar, dock and widgets never activate (WS_EX_NOACTIVATE, Quickshell).
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('''        focusable: Config.options.background.widgets.desktopIcons.enable
''', '''        focusable: Config.options.background.widgets.desktopIcons.enable && (!ExternalWallpaper.active || (desktopIconsLoader.item?.renamingPath ?? "") !== "") // ii-windows: no activation over a live wallpaper
'''),
])


# --- 1.5 Charger notice ---------------------------------------------------------------------------------------------
# The Caps/Num/Scroll Lock pill (overlay LockKeysOsd.qml) also says when the charger is plugged in or out, with the
# battery level. Its own switch, next to the lock keys one.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property bool lockKeys: true // ii-windows: "Caps Lock on" and the like
''', '''                property bool lockKeys: true // ii-windows: "Caps Lock on" and the like
                property bool charger: true // ii-windows: "Charging · 45%" when the charger is plugged in or out
'''),
])
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''            checked: Config.options.osd.lockKeys
            onCheckedChanged: Config.options.osd.lockKeys = checked
        }
''', '''            checked: Config.options.osd.lockKeys
            onCheckedChanged: Config.options.osd.lockKeys = checked
        }
        ConfigSwitch {
            buttonIcon: "battery_charging_full"
            text: Translation.tr("Show when the charger is plugged in or out")
            checked: Config.options.osd.charger
            onCheckedChanged: Config.options.osd.charger = checked
        }
'''),
])
add_translations('es_MX', {
    "On battery · %1%": "Con batería · %1 %",
    "Charging · %1%": "Cargando · %1 %",
    "Plugged in · %1%": "Conectado · %1 %",
    "Show when the charger is plugged in or out": "Avisar al conectar o desconectar el cargador",
})


# --- 2.1 The bar beside the dock --------------------------------------------------------------------------------------
# Bar position gets a fifth choice, "Beside the dock" (bar.besideDock): no bar along an edge; its things (tray, clock,
# network, sound, battery, resources) sit in two pills in the bottom corners, level with the dock, a panel of their own
# that never magnifies (overlay modules/ii/dockBar/DockBar.qml). The choice also sets bar.bottom, so the bar's popups
# and tray menus, the notices and the desktop icons treat it as a bar at the bottom. There is no "no bar at all": ii
# takes the tray from Windows (D13), and apps that live only there (Discord, Steam, the antivirus) need it somewhere.
# What kept clear of the bar uses Appearance.sizes.barReserve: the bar's height, or the dock's strip in this mode.
# (The bar's own widgets keep barHeight: the lock screen reuses them.)
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property bool bottom: false // Instead of top
''', '''                property bool besideDock: false // ii-windows: the bar's things in pills beside the dock (Settings > Bar > Bar position)
                property bool bottom: false // Instead of top
'''),
])
edit(path('modules', 'common', 'Appearance.qml'), [
    ('''        property real barCenterSideModuleWidth:''', '''        // ii-windows: the pills beside the dock are as tall as the dock and stand as far from the edge (DockApps.qml).
        property real dockBarPillHeight: Math.max(24, Config.options.dock.iconSize) + 18
        property real dockBarThickness: hyprlandGapsOut + 1 + dockBarPillHeight
        // ii-windows: the room kept clear of the bar by other panels.
        property real barReserve: (Config.options.bar.besideDock ?? false) ? dockBarThickness : barHeight
        property real barCenterSideModuleWidth:'''),
])
# Beside the dock, the dock's strip is the bar's: the desktop icons and menu count it once, not twice.
edit(path('modules', 'ii', 'background', 'widgets', 'desktop', 'DesktopIcons.qml'), [
    ('''    readonly property real gridBottom: height - bottomInset - 12 - (Config.options.dock.enable ? GlobalStates.dockInsetBottom : 0)''',
     '''    readonly property real gridBottom: height - 12 - ((Config.options.bar.besideDock ?? false) ? Math.max(bottomInset, Config.options.dock.enable ? GlobalStates.dockInsetBottom : 0)
        : bottomInset + (Config.options.dock.enable ? GlobalStates.dockInsetBottom : 0))'''),
])
edit(path('modules', 'ii', 'background', 'widgets', 'desktop', 'DesktopMenu.qml'), [
    ('''        - (Config.options.dock.enable ? GlobalStates.dockInsetBottom + 16 : 0)''',
     '''        - (Config.options.dock.enable && !(Config.options.bar.besideDock ?? false) ? GlobalStates.dockInsetBottom + 16 : 0)'''),
])
# The bar's popups (clock, battery, resources) stop above the pills, not above a bar's height.
edit(path('modules', 'ii', 'bar', 'StyledPopup.qml'), [
    ('''            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
''', '''            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barReserve // ii-windows: the pills beside the dock too
'''),
])
for parts in [('modules', 'ii', 'background', 'widgets', 'desktop', 'DesktopIcons.qml'),
              ('modules', 'ii', 'background', 'widgets', 'desktop', 'DesktopMenu.qml'),
              ('modules', 'ii', 'background', 'widgets', 'DesktopEditBar.qml'),
              ('modules', 'ii', 'mediaControls', 'MediaControls.qml'),
              ('modules', 'ii', 'onScreenDisplay', 'LockKeysOsd.qml'),
              ('modules', 'ii', 'onScreenDisplay', 'OnScreenDisplay.qml'),
              ('modules', 'ii', 'tour', 'Tour.qml'),
              ('modules', 'ii', 'wallpaperSelector', 'WallpaperSelector.qml')]:
    edit(path(*parts), [('Appearance.sizes.barHeight', 'Appearance.sizes.barReserve', 0)])
edit(path('panelFamilies', 'IllogicalImpulseFamily.qml'), [
    ('''import qs.modules.ii.dock
''', '''import qs.modules.ii.dock
import qs.modules.ii.dockBar
'''),
    ('''    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }''',
     '''    PanelLoader { extraCondition: !(Config.options.bar.besideDock ?? false) && !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { extraCondition: Config.options.bar.besideDock ?? false; component: DockBar {} } // ii-windows: plan 2.1'''),
    ('''    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }''',
     '''    PanelLoader { extraCondition: !(Config.options.bar.besideDock ?? false) && Config.options.bar.vertical; component: VerticalBar {} }'''),
])
for page in ('BarConfig.qml', 'QuickConfig.qml'):
    edit(path('modules', 'settings', page), [
        ('''                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }''', '''                    currentValue: (Config.options.bar.besideDock ?? false) ? 4 : (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.besideDock = newValue === 4; // ii-windows: a bar at the bottom, beside the dock
                        Config.options.bar.bottom = newValue === 4 || (newValue & 1) !== 0;
                        Config.options.bar.vertical = newValue !== 4 && (newValue & 2) !== 0;
                    }'''),
        ('''                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]''', '''                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        },
                        {
                            displayName: Translation.tr("Beside the dock"),
                            icon: "dock_to_bottom",
                            value: 4 // ii-windows: bar.besideDock
                        }
                    ]'''),
    ])
add_translations('es_MX', {"Beside the dock": "Junto al dock"})


# --- 2.2 Minimize into the dock ---------------------------------------------------------------------------------------
# overlay modules/ii/minimizeAnimation/MinimizeAnimation.qml flies a card of a minimized window into the dock (nothing
# on restore: the real window is back at once); ii-host turns Windows' own animation off in memory meanwhile (minanim.cpp).
edit(path('modules', 'common', 'Config.qml'), [
    ('''            property JsonObject dock: JsonObject {
''', '''            property JsonObject windowAnimations: JsonObject { // ii-windows
                property bool minimizeToDock: true // ii's own minimize/restore animation instead of Windows' one
                property int duration: 320 // ms, 100-600
                property string curve: "expressive" // "expressive" (M3 Expressive spring) or "linear"
            }

            property JsonObject dock: JsonObject {
'''),
])
edit(path('panelFamilies', 'IllogicalImpulseFamily.qml'), [
    ('''import qs.modules.ii.mediaControls
''', '''import qs.modules.ii.mediaControls
import qs.modules.ii.minimizeAnimation
'''),
    ('''    PanelLoader { phase: 2; component: MediaControls {} }
''', '''    PanelLoader { phase: 2; component: MediaControls {} }
    PanelLoader { phase: 2; component: MinimizeAnimation {} } // ii-windows: minimize into the dock
'''),
])
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''    ContentSection {
        icon: "voting_chip"
        title: Translation.tr("On-screen display")
''', '''    ContentSection {
        icon: "animation"
        title: Translation.tr("Window animations")

        ConfigSwitch {
            buttonIcon: "minimize"
            text: Translation.tr("Minimize into the dock (instead of Windows' animation)")
            checked: Config.options.windowAnimations.minimizeToDock
            onCheckedChanged: Config.options.windowAnimations.minimizeToDock = checked
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Duration (ms)")
            enabled: Config.options.windowAnimations.minimizeToDock
            value: Config.options.windowAnimations.duration
            from: 100
            to: 600
            stepSize: 20
            onValueChanged: Config.options.windowAnimations.duration = value
        }
        ConfigSelectionArray {
            enabled: Config.options.windowAnimations.minimizeToDock
            currentValue: Config.options.windowAnimations.curve
            onSelected: newValue => Config.options.windowAnimations.curve = newValue
            options: [
                { displayName: Translation.tr("Springy"), icon: "airwave", value: "expressive" },
                { displayName: Translation.tr("Linear"), icon: "trending_flat", value: "linear" }
            ]
        }
    }

    ContentSection {
        icon: "voting_chip"
        title: Translation.tr("On-screen display")
'''),
])
add_translations('es_MX', {
    "Window animations": "Animaciones de ventanas",
    "Minimize into the dock (instead of Windows' animation)": "Minimizar hacia el dock (en vez de la animación de Windows)",
    "Duration (ms)": "Duración (ms)",
    "Springy": "Con rebote",
    "Linear": "Lineal",
})


# --- 0.2 Night light off by default -------------------------------------------------------------------------------
# Upstream ships the schedule switched on (19:00-06:30): on Windows a fresh install turned the screen yellow in the
# evening without the user touching anything. Off by default, and an install that still has upstream's untouched
# schedule is switched off once (nightLightMigrated). Until that check has run the schedule counts as off, so the
# tint never shows for a moment before the migration.
edit(path('modules', 'common', 'Config.qml'), [
    ('''                property JsonObject night: JsonObject {
                    property bool automatic: true
''', '''                property JsonObject night: JsonObject {
                    property bool automatic: false // ii-windows: never tint the screen on its own
                    property bool nightLightMigrated: false // ii-windows: upstream's automatic default switched off once
'''),
])
edit(path('services', 'Hyprsunset.qml'), [
    ('''    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
''', '''    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true) && (Config.options?.light?.night?.nightLightMigrated ?? false)
'''),
    ('''    // Change temp
    Connections {
        target: Config.options.light.night
''', '''    // ii-windows: an install from before 0.6 has upstream's schedule switched on; if the user never changed it, off.
    function migrateNightLight() {
        if (!(Config?.ready ?? false))
            return;
        const night = Config.options.light.night;
        if (night.nightLightMigrated)
            return;
        if (night.automatic && night.from === "19:00" && night.to === "06:30" && night.colorTemperature === 5000)
            night.automatic = false;
        night.nightLightMigrated = true;
    }
    Component.onCompleted: migrateNightLight()
    Connections {
        target: Config
        function onReadyChanged() {
            root.migrateNightLight();
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
'''),
])
# Windows' own night light is on (host error 6): say so instead of a bare error number.
edit(path('modules', 'ii', 'sidebarRight', 'nightLight', 'NightLightDialog.qml'), [
    ('''            : Hyprsunset.errorCode ? "Windows: "''', '''            : Hyprsunset.errorCode === 6 ? Translation.tr("Windows' night light is on: ii does not tint on top of it (turn it off in Settings > Display to use ii's)")
            : Hyprsunset.errorCode ? "Windows: "'''),
])
add_translations('es_MX', {
    "Windows' night light is on: ii does not tint on top of it (turn it off in Settings > Display to use ii's)":
        "La luz nocturna de Windows está encendida: ii no pone su color encima (apágala en Configuración > Pantalla para usar la de ii)",
})
