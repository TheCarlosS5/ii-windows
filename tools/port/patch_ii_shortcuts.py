"""U02: the shell side of the shortcuts that shared/actions.json adds. Loads
overlay/ii/modules/ii/shortcuts/ExtraShortcuts.qml (Win+I -> ii's settings) from shell.qml.
Exact-match edit of the staged tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')

edit(os.path.join(ROOT, 'shell.qml'), [
    ('''import "panelFamilies"
''', '''import "panelFamilies"
import "modules/ii/shortcuts"
'''),
    ('''    // Stuff for every panel family
    ReloadPopup {}
''', '''    // Stuff for every panel family
    ReloadPopup {}
    ExtraShortcuts {} // ii-windows (U02)
'''),
])
