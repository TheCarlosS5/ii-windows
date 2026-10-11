"""D01: config.json carries the version of its format.

`configVersion` is declared in the JsonAdapter, so ii writes it with the rest of the options and a
build that does not know a newer format can recognise it (ii-shim config guard leaves such a file
alone). Exact-match edit of the staged tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')

edit(os.path.join(ROOT, 'modules', 'common', 'Config.qml'), [
    ('            property string panelFamily: "ii" // "ii", "waffle"\n',
     '            property string panelFamily: "ii" // "ii", "waffle"\n'
     '            property int configVersion: 1 // ii-windows (D01): the format of this file; see host/src/configtool.h\n'),
])
