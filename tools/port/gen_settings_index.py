"""Plan 2026-10-31, C3: the index of Configuración's search.

Runs in stage-ii.ps1 after gen_widget_pages.py. Reads every page of modules/settings (the pages listed in settings.qml,
the files they embed, and the widget pages of the gallery), and lists each section (ContentSection), subsection
(ContentSubsection) and control with a label (ConfigSwitch, ConfigSpinBox, ConfigSlider, ...) with:
  p   the page (the settings file name in lower case, like settings.qml's II_SETTINGS_PAGE: "generalconfig")
  sub the part of the page ("clock" for the clock widget's settings in the gallery), or ""
  s   the section title, ss the subsection title, l the label (English source strings: the window shows
      Translation.tr() of them, so the language follows the user's)
  k   the config key it changes ("audio.protection.enable"), when there is one
  i   an icon
  w   extra search words: the Spanish of the strings (from translations/es_MX.json) and synonyms
      (tools/port/settings-synonyms.json), so "oscuro" finds the dark mode whatever the language shown
Writes modules/settings/settings-index.js (.pragma library, `var entries = [...]`).
"""
import json
import os
import re
import sys
import unicodedata

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
SETTINGS = os.path.join(ROOT, 'modules', 'settings')
SYNONYMS = os.path.join(os.path.dirname(__file__), 'settings-synonyms.json')

CONTROLS = {'ConfigSwitch', 'ConfigSpinBox', 'ConfigSlider', 'ConfigSelectionArray', 'MaterialTextArea',
            'MaterialTextField', 'RippleButtonWithIcon'}
SECTIONS = {'ContentSection', 'ContentSubsection'}
TR = re.compile(r'Translation\.tr\("((?:[^"\\]|\\.)*)"\)')
PROP = re.compile(r'^\s*(title|text|icon|buttonIcon|materialIcon|placeholderText|mainText)\s*:\s*(.*)$')
OPEN = re.compile(r'([A-Za-z_][\w.]*)?\s*\{')
KEY = re.compile(r'Config\.options\??\.([A-Za-z_][\w?.]*[A-Za-z0-9_])')


def strip_strings(line):
    """The line without string literals and comments, for counting braces."""
    out, i, quote = [], 0, None
    while i < len(line):
        c = line[i]
        if quote:
            if c == '\\':
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in '"\'`':
            quote = c
        elif line.startswith('//', i):
            break
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def norm(text):
    text = unicodedata.normalize('NFD', text.lower())
    return ''.join(c for c in text if unicodedata.category(c) != 'Mn')


def parse(path):
    """[(kind, element, props, key, ancestors)] for the sections and labelled controls of one QML file."""
    with open(path, encoding='utf-8') as f:
        lines = f.read().replace('\r\n', '\n').split('\n')
    stack = []   # frames: {'name', 'props', 'body'}
    found = []
    for line in lines:
        option = re.match(r'^\s*"?displayName"?\s*:\s*(.*)$', line)
        if option:  # a choice of a ConfigSelectionArray ("Bottom", "Float"): search words of its control
            control = next((f for f in reversed(stack) if f['name'] in CONTROLS), None)
            if control is not None:
                control.setdefault('tips', []).extend(TR.findall(option.group(1)))
        m = PROP.match(line)
        if m and stack and stack[-1]['name'] and stack[-1]['name'][0].isupper():
            name, value = m.groups()
            trs = TR.findall(value)
            if trs:  # `busy ? tr("Be patient...") : tr("Random wallpaper")`: the last one is the usual text
                stack[-1]['props'].setdefault(name, trs[-1])
            elif name in ('icon', 'buttonIcon', 'materialIcon'):
                lit = re.match(r'"([^"]+)"', value.strip())
                if lit:
                    stack[-1]['props'].setdefault('icon', lit.group(1))
        for frame in stack:
            frame['body'].append(line)
        code = strip_strings(line)
        # Opening and closing braces in order along the line.
        pos = 0
        while True:
            o = code.find('{', pos)
            c = code.find('}', pos)
            if o < 0 and c < 0:
                break
            if o >= 0 and (c < 0 or o < c):
                before = code[:o].rstrip()
                ident = re.search(r'([A-Za-z_][\w.]*)$', before)
                name = ident.group(1).split('.')[-1] if ident and not before.endswith(':') else ''
                if name and not name[0].isupper():
                    name = ''
                stack.append({'name': name, 'props': {}, 'body': [line]})
                pos = o + 1
            else:
                if stack:
                    frame = stack.pop()
                    if frame['name'] == 'StyledToolTip' and frame['props'].get('text') and stack:
                        stack[-1].setdefault('tips', []).append(frame['props']['text'])  # search words of its control
                    if frame['name'] in SECTIONS | CONTROLS:
                        label = frame['props'].get('title') or frame['props'].get('text') \
                            or frame['props'].get('mainText') or frame['props'].get('placeholderText')
                        if label:
                            key = KEY.search('\n'.join(frame['body']))
                            ancestors = [(f['name'], f['props'].get('title', '')) for f in stack if f['name'] in SECTIONS]
                            found.append({
                                'element': frame['name'], 'label': label, 'icon': frame['props'].get('icon', ''),
                                'key': key.group(1).replace('?', '') if key and frame['name'] in CONTROLS else '',
                                'ancestors': ancestors, 'tips': frame.get('tips', []),
                            })
                            frame['tips'] = []
                    if frame.get('tips') and stack:  # no label of its own: its words go to what holds it
                        stack[-1].setdefault('tips', []).extend(frame['tips'])
                pos = c + 1
    return found


def main():
    with open(os.path.join(ROOT, 'settings.qml'), encoding='utf-8') as f:
        settings = f.read()
    pages = re.findall(r'component:\s*"modules/settings/([A-Za-z]+)\.qml"', settings)
    page_icons = dict(zip(pages, re.findall(r'icon:\s*"([^"]+)",\s*(?:iconRotation:[^\n]*\n\s*)?component:\s*"modules/settings/', settings)))
    if not pages:
        sys.exit('gen_settings_index.py: no page in settings.qml')
    with open(os.path.join(ROOT, 'translations', 'es_MX.json'), encoding='utf-8') as f:
        spanish = json.load(f)
    synonyms, extras = [], []
    if os.path.exists(SYNONYMS):
        with open(SYNONYMS, encoding='utf-8') as f:
            data = json.load(f)
        synonyms = [[norm(w) for w in group] for group in data['groups']]
        extras = data.get('entries', [])

    # Files to read: the pages, the components they embed from modules/settings, the gallery's widget pages.
    files = []  # (path, page, sub)
    local = {os.path.splitext(n)[0] for n in os.listdir(SETTINGS) if n.endswith('.qml')}
    for page in pages:
        path = os.path.join(SETTINGS, page + '.qml')
        files.append((path, page.lower(), ''))
        with open(path, encoding='utf-8') as f:
            text = f.read()
        for embedded in sorted(local):
            if embedded not in pages and embedded != 'WidgetGallery' and re.search(r'^\s*' + embedded + r'\s*\{', text, re.M):
                files.append((os.path.join(SETTINGS, embedded + '.qml'), page.lower(), ''))
    registry = os.path.join(SETTINGS, 'widgets', 'registry.js')
    if os.path.exists(registry):
        with open(registry, encoding='utf-8') as f:
            widgets = json.loads(re.search(r'var widgets = (\[.*\]);', f.read(), re.S).group(1))
        for w in widgets:
            files.append((os.path.join(SETTINGS, w['file']), 'backgroundconfig', w['key']))

    entries, seen = [], set()
    for path, page, sub in files:
        for item in parse(path):
            sections = [t for n, t in item['ancestors'] if n == 'ContentSection' and t]
            subsections = [t for n, t in item['ancestors'] if n == 'ContentSubsection' and t]
            if item['element'] == 'ContentSection':
                s, ss = item['label'], ''
            elif item['element'] == 'ContentSubsection':
                s, ss = (sections[-1] if sections else ''), item['label']
            else:
                s, ss = (sections[-1] if sections else ''), (subsections[-1] if subsections else '')
            ident = (page, sub, s, ss, item['label'])
            if ident in seen:
                continue
            seen.add(ident)
            own = [item['label'], s, ss] + item['tips']
            words = ' '.join(norm(spanish.get(t, '')) for t in own if t)
            tips = ' '.join(norm(t) for t in item['tips'])
            # Whole words only ("ia" is not in "transparencia").
            haystack = ' ' + re.sub(r'[^a-z0-9]+', ' ', norm(' '.join([item['label'], s, ss, item['key'], words]))) + ' '
            extra = sorted({w for group in synonyms if any(f' {g} ' in haystack for g in group) for w in group}
                           - set(haystack.split()))
            entries.append({
                'p': page, 'sub': sub, 's': s, 'ss': ss, 'l': item['label'], 'k': item['key'],
                'i': item['icon'] or page_icons.get(next(p for p in pages if p.lower() == page), 'settings'),
                'w': re.sub(r'\s+', ' ', ' '.join([words, tips] + extra)).strip(),
            })

    # Settings the parser cannot see (custom controls), listed by hand next to the synonyms.
    for extra in extras:
        words = ' '.join(norm(spanish.get(t, '')) + ' ' + norm(t) for t in [extra['l']] + extra.get('also', []))
        entries.append({'p': extra['p'], 'sub': extra.get('sub', ''), 's': extra.get('s', ''), 'ss': '',
                        'l': extra['l'], 'k': extra.get('k', ''), 'i': extra.get('i', 'settings'),
                        'w': (words + ' ' + extra.get('words', '')).strip()})

    out = os.path.join(SETTINGS, 'settings-index.js')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('.pragma library\n// Generated by tools/port/gen_settings_index.py (plan 2026-10-31, C3): do not edit.\n')
        f.write('var entries = ' + json.dumps(entries, ensure_ascii=False, separators=(',', ':')) + ';\n')
    print(f'settings index: {len(entries)} entries from {len(files)} files')


main()
