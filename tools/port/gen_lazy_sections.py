"""Plan 2026-10-31, C4.1: the long settings pages create each section's controls only when it comes into view.

Runs in stage-ii.ps1 after gen_settings_index.py (the index reads the pages as they were). In each page of PAGES, every
top-level `ContentSection {` becomes `LazySection {` (overlay/ii/modules/common/widgets/LazySection.qml): its own
one-line properties (icon, title, visible...) stay, its children move into `content: Component { ColumnLayout { ... } }`.
A section is left as it was when it is the first of the page (on screen at once anyway), when it has an id, or when an
id declared inside it is used outside it (a Component has its own id scope).
"""
import os
import re
import sys

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
SETTINGS = os.path.join(ROOT, 'modules', 'settings')
PAGES = ['InterfaceConfig', 'AppearanceConfig', 'BarConfig', 'GeneralConfig', 'ServicesConfig']
HEADER = re.compile(r'^ {8}(icon|title|visible|enabled|Layout\.\w+|tooltip)\s*:\s*[^{]*$')


def braces(line):
    code = re.sub(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|`[^`]*`', '""', line.split('//')[0] if '"' not in line else line)
    code = re.sub(r'//.*$', '', code)
    return code.count('{') - code.count('}')


def transform(path):
    with open(path, encoding='utf-8', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    lines = text.replace('\r\n', '\n').split('\n')

    blocks, i = [], 0
    while i < len(lines):
        if lines[i] == '    ContentSection {':
            depth, j = 0, i
            while True:
                depth += braces(lines[j])
                if depth == 0 and j > i:
                    break
                j += 1
            blocks.append((i, j))
            i = j + 1
        else:
            i += 1

    out, last, changed, kept = [], 0, 0, 0
    for n, (start, end) in enumerate(blocks):
        body = lines[start + 1:end]
        inside = '\n'.join(body)
        outside = '\n'.join(lines[:start] + lines[end + 1:])
        ids = re.findall(r'^\s*id:\s*(\w+)', inside, re.M)
        own_id = any(re.match(r'^ {8}id:', l) for l in body)
        leaks = [x for x in ids if re.search(r'\b' + x + r'\b', outside)]
        if n == 0 or own_id or leaks:
            kept += 1
            continue
        header = [l for l in body if HEADER.match(l)]
        children = [l for l in body if not HEADER.match(l)]
        while children and not children[0].strip():
            children.pop(0)
        estimate = max(80, min(1500, 5 * sum(1 for l in children if l.strip())))
        out += lines[last:start]
        out.append('    LazySection { // ii-windows (plan 2026-10-31, C4.1): its controls are made when it comes into view')
        out += header
        out.append(f'        estimatedHeight: {estimate}')
        out.append('        content: Component {')
        out.append('            ColumnLayout {')
        out.append('                spacing: 4')
        out += [('        ' + l) if l.strip() else l for l in children]
        out.append('            }')
        out.append('        }')
        out.append('    }')
        last = end + 1
        changed += 1
    out += lines[last:]
    result = '\n'.join(out)
    if crlf:
        result = result.replace('\n', '\r\n')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(result)
    return changed, kept


total = 0
for page in PAGES:
    path = os.path.join(SETTINGS, page + '.qml')
    if not os.path.exists(path):
        sys.exit(f'gen_lazy_sections.py: no {page}.qml')
    changed, kept = transform(path)
    total += changed
    print(f'{page}: {changed} lazy, {kept} as they were')
if total == 0:
    sys.exit('gen_lazy_sections.py: no section changed (did the pages move?)')
