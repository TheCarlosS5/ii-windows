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
