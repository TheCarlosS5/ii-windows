"""Virtual desktops like Hyprland's workspaces (audit 2026-10-09, P2): windows dragged in the
overview onto a desktop of the strip move there, empty desktops left at the end are dropped,
and the bar keeps ii's 10 slots (patch_ii.py). Exact-match edits of the staged tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('GlobalStates.qml'), [
    ('    property bool overviewOpen: false\n',
     '    property bool overviewOpen: false\n'
     '    property int overviewDropDesktop: -1 // ii-windows: strip desktop under a dragged window\n'),
])

edit(path('modules', 'common', 'Config.qml'), [
    ('                    property int shown: 10\n',
     '                    property int shown: 10\n'
     '                    property bool removeEmptyDesktops: true // ii-windows: services/DesktopCleanup.qml\n'),
])

edit(path('shell.qml'), [
    ('        UiSounds.load() // ii-windows: interface sounds\n',
     '        UiSounds.load() // ii-windows: interface sounds\n'
     '        DesktopCleanup.load() // ii-windows: empty desktops don\'t pile up\n'),
])

# The overview shows only the current desktop: a window dropped on another desktop of the strip
# moves there; dropped anywhere else it goes back to its place (Windows places windows).
edit(path('modules', 'ii', 'overview', 'OverviewWidget.qml'), [
    ('''                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace''',
     '''                        onReleased: {
                            const targetWorkspace = GlobalStates.overviewDropDesktop > 0 ? GlobalStates.overviewDropDesktop : root.draggingTargetWorkspace // ii-windows
                            GlobalStates.overviewDropDesktop = -1'''),
    ('''                                Hyprland.dispatch(`hl.dsp.window.move({ x = "${percentageX * root.screen.width}", y = "${percentageY * root.screen.height}", window = "address:${window.windowData?.address}" })`)''',
     '''                                updateWindowPosition.restart() // ii-windows: Windows keeps the window where it is'''),
])
