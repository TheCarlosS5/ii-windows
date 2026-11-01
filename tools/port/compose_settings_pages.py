"""Plan 2026-10-31, C1/C7: Configuración's sections where people look for them.

Runs in stage-ii.ps1 after the patches and gen_widget_pages.py, before gen_settings_index.py (the index follows the
pages as they end up). Moves whole top-level sections between the pages of modules/settings, or some parts of one
section into a new section, and makes the new pages. The pages list of settings.qml is patched in
patch_ii_plan31.py (C1/C7). Every move fails loudly if its section is not found or uses an id declared elsewhere in
its old page (it would not exist in the new one).

  Paneles › Notificaciones: also the bar's notification option, one place for notices.
  Rendimiento (new): Apariencia's Performance / Reduce animations / Drawing, and "Windows of other programs".
  Apariencia: gets Paneles' "Window animations" and Avanzado's "Live wallpapers".
"""
import os
import re
import sys

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
SETTINGS = os.path.join(ROOT, 'modules', 'settings')

NEW_PAGES = ['PerformanceConfig']
# (from page, section title, to page, section there): the section's controls join the other section
MERGES = [
    ('BarConfig', 'Notifications', 'InterfaceConfig', 'Notifications'),
]
# (from page, section title, to page, changes: new 'title' / 'icon' of the moved section)
MOVES = [
    ('InterfaceConfig', 'Window animations', 'AppearanceConfig', {}),
    ('AdvancedConfig', 'Live wallpapers', 'AppearanceConfig', {}),
]
# (from page, section title, the parts to take (subsection titles / control texts), to page, the new section)
SPLITS = [
    ('AppearanceConfig', 'Transparency and motion', ['Performance', 'Reduce animations', 'Drawing'],
     'PerformanceConfig', {'title': 'Performance', 'icon': 'speed', 'rename': {'Performance': 'Effects'}}),
]
# Then, sections moved whole (after the split, so the rest of Apariencia keeps its order).
MOVES_AFTER = [
    ('AppearanceConfig', 'Windows of other programs', 'PerformanceConfig', {}),
]


def braces(line):
    code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    code = re.sub(r'//.*$', '', code)
    return code.count('{') - code.count('}')


class Page:
    def __init__(self, name, new=False):
        self.name = name
        self.path = os.path.join(SETTINGS, name + '.qml')
        if new:
            self.crlf = True
            self.lines = []
            self.imports = []
            self.new = True
            return
        self.new = False
        with open(self.path, encoding='utf-8', newline='') as f:
            text = f.read()
        self.crlf = '\r\n' in text
        self.lines = text.replace('\r\n', '\n').split('\n')
        self.imports = [l for l in self.lines if l.startswith('import ')]

    def sections(self):
        """[(start, end, title)] of the top-level sections (`    ContentSection {` at indentation 4)."""
        out, i = [], 0
        while i < len(self.lines):
            if self.lines[i] == '    ContentSection {':
                depth, j = 0, i
                while True:
                    depth += braces(self.lines[j])
                    if depth == 0 and j > i:
                        break
                    j += 1
                title = re.search(r'^ {8}title:\s*Translation\.tr\("([^"]+)"\)', '\n'.join(self.lines[i:j]), re.M)
                out.append((i, j, title.group(1) if title else ''))
                i = j + 1
            else:
                i += 1
        return out

    def find(self, title):
        found = [s for s in self.sections() if s[2] == title]
        if len(found) != 1:
            sys.exit(f'compose_settings_pages.py: {self.name} has {len(found)} sections "{title}"')
        return found[0]

    def check_ids(self, start, end, what):
        inside = '\n'.join(self.lines[start:end + 1])
        outside = self.lines[:start] + self.lines[end + 1:]
        declared = re.findall(r'^\s*id:\s*(\w+)', '\n'.join(outside), re.M)
        used = [x for x in declared if re.search(r'\b' + x + r'\b', inside)]
        if used:
            sys.exit(f'compose_settings_pages.py: {what} in {self.name} uses {used}, declared outside it')

    def take(self, title):
        start, end, _ = self.find(title)
        self.check_ids(start, end, f'section "{title}"')
        block = self.lines[start:end + 1]
        del self.lines[start:end + 1]
        if start < len(self.lines) and not self.lines[start].strip() and start > 0 and not self.lines[start - 1].strip():
            del self.lines[start]
        return block

    def add(self, block, imports):
        for imp in imports:
            if imp not in self.imports:
                self.imports.append(imp)
        if self.new:
            if self.lines:
                self.lines.append('')
            self.lines += block
            return
        # Before the page's closing brace.
        close = max(i for i, l in enumerate(self.lines) if l.strip() == '}' and not l.startswith(' '))
        insert = ([''] if self.lines[close - 1].strip() else []) + block
        self.lines[close:close] = insert
        missing = [imp for imp in imports if imp not in [l for l in self.lines if l.startswith('import ')]]
        if missing:
            last = max(i for i, l in enumerate(self.lines) if l.startswith('import '))
            self.lines[last + 1:last + 1] = missing

    def save(self):
        if self.new:
            text = '\n'.join(self.imports) + '\n\n' + \
                '// Generated by tools/port/compose_settings_pages.py (plan 2026-10-31, C1/C7) from sections of other pages.\n' + \
                'ContentPage {\n    forceWidth: true\n\n' + '\n'.join(self.lines) + '\n}\n'
        else:
            text = '\n'.join(self.lines)
        if self.crlf:
            text = text.replace('\r\n', '\n').replace('\n', '\r\n')
        with open(self.path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)


def retitle(block, changes):
    if 'title' in changes:
        block = [re.sub(r'^( {8}title:\s*Translation\.tr\(")[^"]+("\))', r'\g<1>' + changes['title'] + r'\2', l, count=1)
                 if re.match(r'^ {8}title:', l) else l for l in block]
    if 'icon' in changes:
        block = [re.sub(r'^( {8}icon:\s*")[^"]+(")', r'\g<1>' + changes['icon'] + r'\2', l) if re.match(r'^ {8}icon:', l)
                 else l for l in block]
    return block


def split(page, title, parts, changes):
    """Take the top-level parts of a section (`        Element {` blocks whose title/text is in parts) out of it."""
    start, end, _ = page.find(title)
    taken, keep, labels, i = [], [], set(), start + 1
    while i < end:
        line = page.lines[i]
        j, depth = i, braces(line)
        while depth > 0:
            j += 1
            depth += braces(page.lines[j])
        block = page.lines[i:j + 1]
        label = re.search(r'^ {12}(?:title|text):\s*Translation\.tr\("([^"]+)"\)', '\n'.join(block), re.M)
        if re.match(r'^ {8}[A-Z][\w.]*\s*\{', line) and label and label.group(1) in parts:
            taken.append(block)
            labels.add(label.group(1))
        else:
            keep.append(block)
        i = j + 1
    if set(parts) - labels:
        sys.exit(f'compose_settings_pages.py: "{title}" of {page.name} has no {sorted(set(parts) - labels)}')
    inside = '\n'.join(l for b in taken for l in b)
    outside = page.lines[:start] + [l for b in keep for l in b] + page.lines[end:]
    declared = re.findall(r'^\s*id:\s*(\w+)', '\n'.join(outside), re.M)
    used = [x for x in declared if re.search(r'\b' + x + r'\b', inside)]
    if used:
        sys.exit(f'compose_settings_pages.py: parts {parts} of "{title}" use {used}, declared outside them')
    page.lines[start + 1:end] = [l for b in keep for l in b]
    section = ['    ContentSection {',
               f'        icon: "{changes["icon"]}"',
               f'        title: Translation.tr("{changes["title"]}")',
               '']
    for old, new in changes.get('rename', {}).items():  # a part titled like its new section
        taken = [[l.replace(f'title: Translation.tr("{old}")', f'title: Translation.tr("{new}")', 1)
                  if re.match(r'^ {12}title:', l) else l for l in b] for b in taken]
    section += [l for b in taken for l in b]
    section.append('    }')
    return section


pages = {}


def page(name):
    if name not in pages:
        pages[name] = Page(name, new=name in NEW_PAGES)
    return pages[name]


for source, title, target, into in MERGES:
    block = page(source).take(title)
    children = [l for l in block[1:-1] if not re.match(r'^ {8}(icon|title)\s*:', l)]
    to = page(target)
    for imp in page(source).imports:
        if imp not in to.imports:
            sys.exit(f'compose_settings_pages.py: {target} lacks "{imp}" for the controls of "{title}"')
    _, end, _ = to.find(into)
    to.lines[end:end] = children
for source, title, target, changes in MOVES:
    block = retitle(page(source).take(title), changes)
    page(target).add(block, page(source).imports)
for source, title, parts, target, changes in SPLITS:
    block = split(page(source), title, parts, changes)
    page(target).add(block, page(source).imports)
for source, title, target, changes in MOVES_AFTER:
    block = retitle(page(source).take(title), changes)
    page(target).add(block, page(source).imports)
for p in pages.values():
    p.save()
print('settings pages: ' + ', '.join(f'{p.name} {len(p.sections())} sections' for p in pages.values()))
