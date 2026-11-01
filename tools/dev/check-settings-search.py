"""Plan 2026-10-31, C8: does Configuración's search find what people type?

Runs the same matching as overlay/ii/modules/settings/SettingsSearchResults.qml (every word typed in the entry's text,
ignoring case and accents; ranked by where the words are in the label) over the staged index
(build/ii/modules/settings/settings-index.js, Spanish from translations/es_MX.json), for the terms in
tests/settings-search/terms.json. A term passes when a label containing its expected text is among the first 5.
Exit 1 under 95 %.   python -I tools/dev/check-settings-search.py [-v]
"""
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
STAGED = os.environ.get('II_STAGE_DIR') or os.path.join(ROOT, 'build', 'ii')


def norm(text):
    text = unicodedata.normalize('NFD', (text or '').lower())
    return ''.join(c for c in text if unicodedata.category(c) != 'Mn')


def main():
    verbose = '-v' in sys.argv
    with open(os.path.join(STAGED, 'modules', 'settings', 'settings-index.js'), encoding='utf-8') as f:
        entries = json.loads(re.search(r'var entries = (\[.*\]);', f.read(), re.S).group(1))
    with open(os.path.join(STAGED, 'translations', 'es_MX.json'), encoding='utf-8') as f:
        es = json.load(f)
    with open(os.path.join(STAGED, 'settings.qml'), encoding='utf-8') as f:
        settings = f.read()
    pages = {c.lower(): es.get(n, n) for n, c in re.findall(
        r'name:\s*Translation\.tr\("([^"]+)"\)[^\n]*\n(?:[^\n]*\n){0,2}?\s*component:\s*"modules/settings/([A-Za-z]+)\.qml"', settings)}
    with open(os.path.join(STAGED, 'modules', 'settings', 'widgets', 'registry.js'), encoding='utf-8') as f:
        widgets = {w['key']: re.sub(r'^Widget:\s*', '', es.get(w['title'], w['title']))
                   for w in json.loads(re.search(r'var widgets = (\[.*\]);', f.read(), re.S).group(1))}
    with open(os.path.join(ROOT, 'tests', 'settings-search', 'terms.json'), encoding='utf-8') as f:
        terms = json.load(f)['terms']

    tr = lambda s: es.get(s, s) if s else ''
    hays = [' ' + norm(' '.join([tr(e['l']), tr(e['s']), tr(e['ss']), e['l'], e['s'], e['ss'], pages.get(e['p'], ''),
                                 widgets.get(e['sub'], '') if e['sub'] else '', e['k'].replace('.', ' '), e['w']]))
            for e in entries]

    def stem(w):  # as SettingsSearchResults.qml's stem()
        if len(w) > 4 and w.endswith('es'):
            return w[:-2]
        if len(w) > 3 and w.endswith('s'):
            return w[:-1]
        return w

    def search(query):
        words = [stem(w) for w in norm(query).split() if w]
        found = []
        for i, e in enumerate(entries):
            if not all(w in hays[i] for w in words):
                continue
            label = norm(tr(e['l']))
            score = 0
            for w in words:
                if label.startswith(w): score += 6
                elif ' ' + w in label: score += 4
                elif w in label: score += 3
                elif ' ' + w in hays[i]: score += 1
            if e['l'] != e['s'] and e['l'] != e['ss']: score += 0.5
            found.append((-score, i))
        found.sort()
        return [entries[i] for _, i in found[:60]]

    passed = 0
    for query, expected in terms:
        results = search(query)
        top = [norm(tr(e['l'])) for e in results[:5]]
        ok = any(norm(expected) in label for label in top)
        passed += ok
        if verbose or not ok:
            print(f"{'ok  ' if ok else 'FAIL'} {query!r:28} -> {top[:3]} ({len(results)} results)")
    rate = 100 * passed / len(terms)
    print(f'settings search: {passed}/{len(terms)} terms found ({rate:.0f} %), {len(entries)} entries')
    sys.exit(0 if rate >= 95 else 1)


main()
