"""Every directory or file a staged ii imports must exist and not be empty.

    python check-qml-imports.py <staged ii dir>

Why: ii imports `qs.modules.common.widgets.shapes` (a git submodule of the upstream repository). In a
clone where the submodule was never initialised that folder is EMPTY, staging copies the empty
folder, the package builds, and the shell dies on start with `module "...shapes" is not installed`.
Quickshell only reports it at run time; this reports it before anything is packaged.

Checked: `import qs.a.b` (the folder a/b under the staged root), `import "rel/dir"` and
`import "file.js" as X` (relative to the importing file).
"""
import os
import re
import sys


def main():
    root = os.path.abspath(sys.argv[1])
    bad = []
    checked = 0
    for folder, _, files in os.walk(root):
        for name in files:
            if not name.endswith('.qml'):
                continue
            path = os.path.join(folder, name)
            for line in open(path, encoding='utf-8', errors='replace'):
                m = re.match(r'\s*import\s+qs\.([\w.]+)', line)
                if m:
                    target = os.path.join(root, *m.group(1).split('.'))
                    checked += 1
                    if not os.path.isdir(target) or not os.listdir(target):
                        bad.append((os.path.relpath(path, root), f'qs.{m.group(1)}', 'missing or empty folder'))
                    continue
                m = re.match(r'\s*import\s+"([^"]+)"', line)
                if m and not m.group(1).startswith(('http:', 'https:', 'qrc:')):
                    target = os.path.normpath(os.path.join(folder, m.group(1)))
                    checked += 1
                    if os.path.isdir(target):
                        if not os.listdir(target):
                            bad.append((os.path.relpath(path, root), m.group(1), 'empty folder'))
                    elif not os.path.isfile(target):
                        bad.append((os.path.relpath(path, root), m.group(1), 'missing'))
    for source, what, why in bad:
        print(f'{source}: import {what}: {why}')
    print(f'{checked} imports checked, {len(bad)} unresolvable')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
