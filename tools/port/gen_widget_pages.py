"""Plan 2026-10-31, C2: Configuración > Escritorio as a widget gallery instead of one 915-line page.

Runs in stage-ii.ps1 after the patches. Every top-level `ContentSection` of modules/settings/BackgroundConfig.qml whose
title is "Widget: <name>" moves to its own file, modules/settings/widgets/Widget_<key>.qml (a ColumnLayout holding the
section, loaded only when that widget's "Personalizar" is pressed), and modules/settings/widgets/registry.js lists the
widgets (key from Config.options.background.widgets.<key>.enable, title, icon). Where the first widget section was,
the page gets `WidgetGallery {}` (overlay/ii/modules/settings/WidgetGallery.qml). The other sections stay.
Being derived from the staged file, it follows upstream's and the patches' changes to those sections by itself.
"""
import json
import os
import re
import sys

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
PAGE = os.path.join(ROOT, 'modules', 'settings', 'BackgroundConfig.qml')
OUT = os.path.join(ROOT, 'modules', 'settings', 'widgets')

with open(PAGE, encoding='utf-8', newline='') as f:
    text = f.read()
crlf = '\r\n' in text
text = text.replace('\r\n', '\n')
lines = text.split('\n')

# Imports of the page, reused by every widget file.
imports = [l for l in lines if l.startswith('import ')]

# Top-level sections: "    ContentSection {" at indentation 4, closed by the matching brace.
blocks = []
i = 0
while i < len(lines):
    if lines[i] == '    ContentSection {':
        depth = 0
        j = i
        while True:
            depth += lines[j].count('{') - lines[j].count('}')
            if depth == 0 and j > i:
                break
            j += 1
        blocks.append((i, j))
        i = j + 1
    else:
        i += 1

# C2.4: widgets whose settings are long get tabs. Each top-level part of the section goes to the tab that lists its
# subsection title; parts with no listed title go to the first tab, except the first `above` parts (on/off, ...),
# which stay above the tabs. A tab's `note` shows while its `when` holds (options for one clock style only).
TABS = {
    'clock': {
        'above': 2,
        'tabs': [
            {'name': 'Style', 'icon': 'palette', 'titles': []},
            {'name': 'Dial', 'icon': 'clock_loader_40', 'titles': ['Dial style'],
             'note': 'These options are for the Cookie style', 'when': '!settingsClock.cookiePresent'},
            {'name': 'Hands', 'icon': 'schedule', 'titles': ['Hour hand', 'Minute hand', 'Second hand'],
             'note': 'These options are for the Cookie style', 'when': '!settingsClock.cookiePresent'},
            {'name': 'Date', 'icon': 'calendar_today', 'titles': ['Date style'],
             'note': 'These options are for the Cookie style', 'when': '!settingsClock.cookiePresent'},
            {'name': 'Quote', 'icon': 'format_quote', 'titles': ['Quote']},
        ],
    },
}


def braces(line):
    code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    code = re.sub(r'//.*$', '', code)
    return code.count('{') - code.count('}')


def with_tabs(section, spec):
    """The section's lines (`    ContentSection {` ... `    }`) with its parts in tabs."""
    body = section[1:-1]
    parts, i = [], 0  # (kind, lines): kind 'child' for `        Element {` blocks, 'head' for the rest
    while i < len(body):
        line = body[i]
        j, depth = i, braces(line)
        while depth > 0:
            j += 1
            depth += braces(body[j])
        block = body[i:j + 1]
        kind = 'child' if re.match(r'^ {8}[A-Z][\w.]*\s*\{', line) else 'head'
        parts.append((kind, block))
        i = j + 1
    head = [p for k, p in parts if k == 'head']
    children = [p for k, p in parts if k == 'child']
    above, rest = children[:spec['above']], children[spec['above']:]
    groups = [[] for _ in spec['tabs']]
    for child in rest:
        title = re.search(r'^ {12}title:\s*Translation\.tr\("([^"]+)"\)', '\n'.join(child), re.M)
        index = next((n for n, t in enumerate(spec['tabs']) if title and title.group(1) in t['titles']), 0)
        groups[index].append(child)
    out = [section[0]]
    for block in head + above:
        out += block
    out += ['        SecondaryTabBar { // ii-windows (plan 2026-10-31, C2.4): this widget\'s settings in tabs',
            '            id: widgetTabs',
            '            Layout.fillWidth: true']
    for tab in spec['tabs']:
        out.append(f'            SecondaryTabButton {{ buttonIcon: "{tab["icon"]}"; buttonText: Translation.tr("{tab["name"]}") }}')
    out.append('        }')
    for n, (tab, group) in enumerate(zip(spec['tabs'], groups)):
        out += ['        ColumnLayout {',
                f'            readonly property int settingsTab: {n} // the settings search opens the tab it needs',
                '            readonly property var tabBar: widgetTabs',
                f'            visible: widgetTabs.currentIndex === {n}',
                '            Layout.fillWidth: true',
                '            spacing: 6']
        if tab.get('note'):
            out += ['            NoticeBox {',
                    '                Layout.fillWidth: true',
                    f'                visible: {tab["when"]}',
                    f'                text: Translation.tr("{tab["note"]}")',
                    '            }']
        for child in group:
            out += [('    ' + l) if l.strip() else l for l in child]
        out.append('        }')
    out.append(section[-1])
    return out


widgets = []
remove = []
for start, end in blocks:
    body = '\n'.join(lines[start:end + 1])
    title = re.search(r'title:\s*Translation\.tr\("(Widget: [^"]+)"\)', '\n'.join(lines[start:start + 6]))
    key = re.search(r'Config\.options\.background\.widgets\.(\w+)\.enable\b', body)
    if not title or not key:
        continue
    icon = re.search(r'icon:\s*"([^"]+)"', '\n'.join(lines[start:start + 6]))
    k = key.group(1)
    widgets.append({'key': k, 'title': title.group(1), 'icon': icon.group(1) if icon else 'widgets',
                    'file': f'widgets/Widget_{k}.qml'})
    os.makedirs(OUT, exist_ok=True)
    if k in TABS:
        body = '\n'.join(with_tabs(lines[start:end + 1], TABS[k]))
    content = '\n'.join(imports) + '\n\n' + \
        '// Generated by tools/port/gen_widget_pages.py from BackgroundConfig.qml: do not edit, edit the section there.\n' + \
        'ColumnLayout {\n    Layout.fillWidth: true\n    spacing: 20\n\n' + body + '\n}\n'
    with open(os.path.join(OUT, f'Widget_{k}.qml'), 'w', encoding='utf-8', newline='\r\n' if crlf else '\n') as f:
        f.write(content)
    remove.append((start, end))

if not widgets:
    sys.exit('gen_widget_pages.py: no "Widget: ..." section found in BackgroundConfig.qml')

# The page without them, the gallery where the first one was.
out = []
first = remove[0][0]
skip = set()
for start, end in remove:
    skip.update(range(start, end + 1))
for n, line in enumerate(lines):
    if n == first:
        out.append('    WidgetGallery {} // ii-windows (plan 2026-10-31, C2): the widgets, each one\'s settings loaded on demand')
        out.append('')
    if n in skip:
        continue
    out.append(line)
result = '\n'.join(out)
result = re.sub(r'\n{3,}', '\n\n', result)
if crlf:
    result = result.replace('\n', '\r\n')
with open(PAGE, 'w', encoding='utf-8', newline='') as f:
    f.write(result)

with open(os.path.join(OUT, 'registry.js'), 'w', encoding='utf-8', newline='\n') as f:
    f.write('.pragma library\n// Generated by tools/port/gen_widget_pages.py (plan 2026-10-31, C2).\n')
    f.write('var widgets = ' + json.dumps(widgets, indent=2, ensure_ascii=False) + ';\n')
print(f'widget pages: {len(widgets)} ({", ".join(w["key"] for w in widgets)})')
