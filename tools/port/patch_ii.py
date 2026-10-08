"""Small exact-match edits applied to the staged ii (build/ii) by tools/dev/stage-ii.ps1.

For changes too small to justify replacing a whole file in overlay/ii: Windows defaults in
Config.qml. Every pattern must match exactly once, so an upstream change that moves the code
fails the staging loudly instead of silently dropping a Windows default.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


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
                    "Microsoft.Windows.Explorer", "MSEdge", "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App",]'''),
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
     '''            Loader {
                anchors.fill: parent
                active: Config.options.background.widgets.desktopIcons.enable && !GlobalStates.screenLocked
                // Menus must receive clicks above clock/weather; lower icons again on close.
                z: item?.menuOpen ? 1 : 0
                sourceComponent: DesktopIcons {}
            }

            WidgetCanvas {
                id: widgetCanvas'''),
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
