"""Startup work on slow PCs (2026-10-17): what the QML profiler showed the shell doing at every start.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- App list: the de-duplication compared every app with every other one (findIndex inside filter) --------
edit(path('services', 'AppSearch.qml'), [
    ("""    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )""",
     """    // ii-windows: one pass with a Set (findIndex inside filter compared every app with every other one)
    readonly property list<DesktopEntry> list: {
        const seen = new Set();
        return Array.from(DesktopEntries.applications.values).filter(app => {
            if (seen.has(app.id))
                return false;
            seen.add(app.id);
            return true;
        });
    }"""),
])


# --- Start-up stages: the welcome cover waits only for what is on screen ----------------------------------------------
# Before, the cover stayed until phase 2 (right sidebar, overview, notifications, OSD: ~1,500 hidden objects) had been
# created on the UI thread, plus a second. On a slow PC that was 10+ s of a cover in front of a desktop that was ready.
# Now: phase 1 = wallpaper, bar, dock; phase 2 = desktop icons and widgets; then the cover goes (phase 3) and the
# panels that only open later are created in the background, in slices between frames (LazyLoader `loading`), the
# ones of the old phase 2 first and the rest (phase 4) 2.5 s later.
edit(path('panelFamilies', 'PanelLoader.qml'), [
    ('''    property int phase: 1 // ii-windows: 1 = at once, 2 and 3 = a little later (GlobalStates.startupPhase)
    active: Config.ready && extraCondition && GlobalStates.startupPhase >= phase
''',
     '''    property int phase: 1 // ii-windows: 1 = at once; 2 and 3 = in the background once the desktop is on screen
    // (GlobalStates.startupPhase 3 and 4). A panel loaded in the background is never unloaded again.
    readonly property bool wanted: Config.ready && extraCondition && GlobalStates.startupPhase >= (phase === 1 ? 1 : phase + 1)
    active: phase === 1 && wanted
    loading: phase > 1 && wanted
'''),
])
edit(path('panelFamilies', 'IllogicalImpulseFamily.qml'), [
    ('''    Timer {
        running: Config.ready
        interval: 800
        repeat: true
        onTriggered: {
            if (GlobalStates.startupPhase < 3) GlobalStates.startupPhase += 1;
            else running = false;
            interval = 2500;
        }
    }
    Timer {
        running: Config.ready && GlobalStates.startupPhase >= 2
        interval: 1000
        onTriggered: shellReadyFile.setText(`${Date.now()}`)
    }
''',
     '''    Timer {
        running: Config.ready && GlobalStates.startupPhase === 1
        interval: 800
        onTriggered: GlobalStates.startupPhase = 2 // desktop icons and widgets
    }
    // The desktop is on screen (wallpaper, bar, dock, icons, widgets): the welcome cover can go, and the panels that
    // only open later start loading in the background.
    Timer {
        running: Config.ready && GlobalStates.startupPhase === 2
        interval: 400
        onTriggered: {
            shellReadyFile.setText(`${Date.now()}`);
            GlobalStates.startupPhase = 3;
        }
    }
    Timer {
        running: GlobalStates.startupPhase === 3
        interval: 2500
        onTriggered: GlobalStates.startupPhase = 4
    }
'''),
])


# --- Icon lookups: the same names were searched in the icon theme over and over (each miss walks the theme) ---------
edit(path('services', 'AppSearch.qml'), [
    ('import Quickshell\n', 'import QtQuick\nimport Quickshell\n'),
    ('''    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }''',
     '''    // ii-windows: answers are remembered until the list of apps changes (a new app can bring new icons)
    property var iconExistsCache: ({})
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.iconExistsCache = ({});
        }
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        const known = root.iconExistsCache[iconName];
        if (known !== undefined)
            return known;
        const exists = (Quickshell.iconPath(iconName, true).length > 0)
            && !iconName.includes("image-missing");
        root.iconExistsCache[iconName] = exists;
        return exists;
    }'''),
])


# --- The Waffle family (Windows 11 look-alike panels, not used on Windows) was compiled at every start ---------------
edit(path('shell.qml'), [
    ('''        identifier: "waffle"
        component: WaffleFamily {}''',
     '''        identifier: "waffle"
        // ii-windows: by file name, so it is only compiled when it is the chosen family
        source: Config.options.panelFamily === "waffle" ? "panelFamilies/WaffleFamily.qml" : ""'''),
])


# --- Directories: nine processes at every start to create and empty cache folders, now three ------------------------
# (each process start costs tens of ms, much more on a slow PC whose antivirus checks every start)
edit(path('modules', 'common', 'Directories.qml'), [
    ('''        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        // ii-windows: one typed step per folder (ii-shim's bash is not a shell and ran none of this).
        Quickshell.execDetached(["ii-shim", "reset-dir", `${coverArt}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${booruPreviews}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${latexOutput}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${cliphistDecode}`])
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`])
        Quickshell.execDetached(["mkdir", "-p", `${userActions}`])
        Quickshell.execDetached(["rm", "-rf", `${tempImages}`])''',
     '''        // ii-windows: typed steps (ii-shim's bash is not a shell), several folders per process.
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`, `${favicons}`, `${aiChats}`, `${userActions}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${coverArt}`, `${booruPreviews}`, `${latexOutput}`, `${cliphistDecode}`])
        Quickshell.execDetached(["rm", "-rf", `${tempImages}`])'''),
])


# --- Processes: Linux checks that can only fail on Windows, and polls that never stop ----------------------------------
# Every process start costs (more on a slow PC, whose antivirus checks each one). At start ii launched ~27, several of
# them Linux tools that do not exist here; and three ran again every 5-10 s forever, ~30 a minute while idle.

# kded6 / mako / dunst (programs that fight ii for the tray and notifications on Linux) do not exist on Windows; the
# check also ended in a TypeError (the reply had no ';').
edit(path('services', 'ConflictKiller.qml'), [
    ('            if (Config.ready) checkConflictsProc.running = true',
     '            // ii-windows: kded6, mako and dunst do not exist on Windows: nothing to check'),
])
# CPU top speed: lscpu is Linux; Windows keeps it in the registry (one `reg query`).
edit(path('services', 'ResourceUsage.qml'), [
    ('''        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]''',
     '''        command: ["reg", "query", "HKLM\\\\HARDWARE\\\\DESCRIPTION\\\\System\\\\CentralProcessor\\\\0", "/v", "~MHz"] // ii-windows'''),
    ('''                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"''',
     '''                const mhz = parseInt((outputCollector.text.match(/0x[0-9a-fA-F]+/) ?? ["0"])[0]); // ii-windows: REG_DWORD
                if (mhz > 0) root.maxAvailableCpuString = (mhz / 1000).toFixed(1) + " GHz"'''),
])
# Fingerprints through fprintd (Linux); Windows Hello is not reachable this way.
edit(path('modules', 'common', 'panels', 'lock', 'LockContext.qml'), [
    ('''        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]''',
     '''        running: false // ii-windows: fprintd is Linux
        command: ["bash", "-c", "fprintd-list $(whoami)"]'''),
])
# Package updates through Arch's checkupdates: never there.
edit(path('services', 'Updates.qml'), [
    ('''        running: Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]''',
     '''        running: false // ii-windows: checkupdates is Arch Linux (Windows Update is Windows' own business)
        command: ["which", "checkupdates"]'''),
])
# The user name is in the environment: no `whoami` process.
edit(path('services', 'SystemInfo.qml'), [
    ('''    property string username: "user"''',
     '''    property string username: Quickshell.env("USERNAME") || "user" // ii-windows: no whoami process'''),
    ('''    Process {
        running: true
        command: ["whoami"]
        stdout: StdioCollector { onStreamFinished: root.username = text.trim() }
    }
''', ''),
])
# The on-screen keyboard released all 249 keys (a long injected key-up storm) when its panel was created, not only
# after it had been open.
edit(path('modules', 'ii', 'onScreenKeyboard', 'OnScreenKeyboard.qml'), [
    ('''        active: GlobalStates.oskOpen
        onActiveChanged: {
            if (!oskLoader.active) {
                Ydotool.releaseAllKeys();
            }
        }''',
     '''        active: GlobalStates.oskOpen
        property bool wasOpen: false // ii-windows: only release keys the keyboard may have pressed
        onActiveChanged: {
            if (oskLoader.active) {
                oskLoader.wasOpen = true;
            } else if (oskLoader.wasOpen) {
                Ydotool.releaseAllKeys();
            }
        }'''),
])
# Night light: `nightlight off` every 5 s while night light is off. Re-applying is only needed while it tints.
edit(path('services', 'Hyprsunset.qml'), [
    ('''    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.fetchState()
    }''',
     '''    Timer {
        interval: 5000
        running: root.requestedTemperature || root.gamma !== 100 // ii-windows: nothing to keep applied when off
        repeat: true
        onTriggered: root.fetchState()
    }'''),
])
# Live wallpaper programs: looked for every 6 s; every 20 s while none is running.
edit(path('services', 'ExternalWallpaper.qml'), [
    ('''    Timer {
        interval: 6000
        running: root.enabled''',
     '''    Timer {
        interval: root.running ? 6000 : 20000 // ii-windows: less often while no live wallpaper runs
        running: root.enabled'''),
])
# Power plan toggle: asked Windows every 10 s, also with the sidebar closed.
edit(path('modules', 'common', 'models', 'quickToggles', 'PowerProfilesToggle.qml'), [
    ('''    Timer {
        interval: 10000
        running: true
        repeat: true''',
     '''    Timer {
        interval: 10000
        running: GlobalStates.sidebarRightOpen // ii-windows: only while it can be seen
        triggeredOnStart: true
        repeat: true'''),
])
