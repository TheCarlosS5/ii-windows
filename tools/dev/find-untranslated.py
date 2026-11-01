"""Plan 2026-10-31, H1: the texts of the staged ii QML that have no Spanish (or other) translation.

    python find-untranslated.py [--stage build/ii] [--lang es_MX] [--all]

Lists every Translation.tr("...") string missing from translations/<lang>.json, grouped by file (the modules ii-windows
uses; the Waffle style, out of scope, is skipped unless --all). Exit 1 if any is missing.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
TR = re.compile(r'Translation\.tr\(\s*"((?:[^"\\]|\\.)*)"\s*[,)]')


def unescape(text):
    return text.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', default=os.path.join(ROOT, 'build', 'ii'))
    ap.add_argument('--lang', default='es_MX')
    ap.add_argument('--all', action='store_true')
    args = ap.parse_args()
    with open(os.path.join(args.stage, 'translations', args.lang + '.json'), encoding='utf-8') as f:
        known = json.load(f)
    missing = {}
    for dirpath, _, names in os.walk(args.stage):
        rel = os.path.relpath(dirpath, args.stage).replace('\\', '/')
        if not args.all and ('/waffle' in '/' + rel or rel.startswith('translations')):
            continue
        for name in names:
            if not name.endswith(('.qml', '.js')):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding='utf-8', errors='replace') as f:
                text = f.read()
            for m in TR.finditer(text):
                key = unescape(m.group(1))
                if key and key not in known:
                    missing.setdefault(key, set()).add(os.path.relpath(path, args.stage).replace('\\', '/'))
    for key in sorted(missing):
        print(json.dumps(key, ensure_ascii=False), '  <-', ', '.join(sorted(missing[key])[:3]))
    print(f'{len(missing)} text(s) without {args.lang}')
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
