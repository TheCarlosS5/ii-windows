"""UX round of 2026-10-15, part 3: tray overflow, overview modes, launch counter, external wallpapers.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
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


# --- Tray overflow: the popup stays open while the pointer is on it ----------------------------------------
# StyledPopup (patched in patch_ii_p0.py) shows its window only while the hover target is hovered. The tray
# overflow opens by click, so it must stay visible while trayOverflowOpen is true (otherwise moving the
# pointer down onto the icons hid it, and no icon could be right-clicked or pinned).
edit(path('modules', 'ii', 'bar', 'SysTray.qml'), [
    ('    property var activeMenu: null\n',
     '    property var activeMenu: null\n'
     '    property real overflowClearedAt: 0 // ii-windows: the click that closed the grab must not reopen the popup\n'),
    ('''        onCleared: {
            root.trayOverflowOpen = false;
''',
     '''        onCleared: {
            if (root.trayOverflowOpen) root.overflowClearedAt = Date.now();
            root.trayOverflowOpen = false;
'''),
    ('        windows: [trayOverflowLayout.QsWindow?.window, root.activeMenu]\n',
     '        windows: [trayOverflowLayout.QsWindow?.window, trayOverflowButton.QsWindow?.window, root.activeMenu]\n'),
    ('            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen\n',
     '''            downAction: () => {
                if (Date.now() - root.overflowClearedAt < 350) return;
                root.trayOverflowOpen = !root.trayOverflowOpen;
            }
'''),
    ('                active: root.trayOverflowOpen && root.unpinnedItems.length > 0\n',
     '                active: root.trayOverflowOpen && root.unpinnedItems.length > 0\n'
     '                shown: root.trayOverflowOpen && root.unpinnedItems.length > 0 // ii-windows: by click, not by hover\n'),
])
