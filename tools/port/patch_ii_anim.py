"""Panel animations on Windows (audit 2026-10-09, P2). On Hyprland the compositor animates ii's
layer surfaces (layerrule animation slide / popin per namespace); Windows does no such thing and
ii-windows turns DWM's own transitions off, so panels popped in and out. The panels animate
their content inside the window instead, and the window stays visible until it has slid out.
Exact-match edits of the staged tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


SLIDE = '''property real slide: {open} ? 0 : 1 // ii-windows: 0 = in place, 1 = out past the edge
{indent}Behavior on slide {{
{indent}    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
{indent}}}
{indent}visible: {open} || slide < 1'''

edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeft.qml'), [
    ('''            id: panelWindow
            visible: GlobalStates.sidebarLeftOpen
''',
     '''            id: panelWindow
            ''' + SLIDE.format(open='GlobalStates.sidebarLeftOpen', indent='            ') + '\n'),
    ('''            StyledRectangularShadow {
                target: sidebarLeftBackground
''',
     '''            StyledRectangularShadow {
                target: sidebarLeftBackground
                transform: Translate { x: -panelWindow.slide * panelWindow.width }
'''),
    ('''            Rectangle {
                id: sidebarLeftBackground
''',
     '''            Rectangle {
                id: sidebarLeftBackground
                transform: Translate { x: -panelWindow.slide * panelWindow.width }
'''),
])

# The overview pops in (Hyprland's "popin"): a short fade and zoom from 94 %.
edit(path('modules', 'ii', 'overview', 'Overview.qml'), [
    ('''        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
''',
     '''        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            // ii-windows: pops in, as Hyprland animates the layer on Linux.
            opacity: GlobalStates.overviewOpen ? 1 : 0
            scale: GlobalStates.overviewOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
'''),
])

edit(path('modules', 'ii', 'sidebarRight', 'SidebarRight.qml'), [
    ('''        id: panelWindow
        visible: GlobalStates.sidebarRightOpen
''',
     '''        id: panelWindow
        ''' + SLIDE.format(open='GlobalStates.sidebarRightOpen', indent='        ') + '\n'),
    ('''            active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
''',
     '''            active: GlobalStates.sidebarRightOpen || panelWindow.visible || Config?.options.sidebar.keepRightSidebarLoaded
            transform: Translate { x: panelWindow.slide * panelWindow.width }
'''),
])
