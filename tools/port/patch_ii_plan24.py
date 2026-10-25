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
