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
     '                    property bool removeEmptyDesktops: false // ii-windows: services/DesktopCleanup.qml (opt-in; was on by default)\n'
     '                    property bool removeEmptyDesktopsNoticeShown: false // ii-windows: the opt-in change was announced once\n'),
])

# The option has a switch (it had none), disabled with the reason when this Windows can't do it.
edit(path('modules', 'settings', 'BarConfig.qml'), [
    ('''        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
''',
     '''        ConfigSwitch {
            buttonIcon: "delete_sweep"
            text: Translation.tr("Close the last desktop when I leave it empty")
            enabled: DesktopCleanup.canRemove
            checked: Config.options.bar.workspaces.removeEmptyDesktops
            onCheckedChanged: {
                Config.options.bar.workspaces.removeEmptyDesktops = checked;
            }
            StyledToolTip {
                text: DesktopCleanup.canRemove
                    ? Translation.tr("Only a desktop with no windows that you did not name, and only if nothing changed meanwhile. Desktop 1 stays.")
                    : DesktopCleanup.limitation
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: DesktopCleanup.probed && !DesktopCleanup.canRemove
            text: DesktopCleanup.limitation
        }

        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
'''),
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
