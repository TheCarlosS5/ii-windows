"""Inventory of the Linux commands the staged QML still starts (B00 / C12), by who answers them on Windows.

    python scan-linux-routes.py <staged ii dir> [--json out.json] [--markdown out.md]

A command is started from QML as the first element of a command array (Process {command: [...]},
Quickshell.execDetached([...]), Quickshell.exec...). Each distinct command is classified:
  shim      ii-shim answers to this name (tools/dev/deploy.ps1 copies it under these names)
  windows   a Windows program or a program that exists on Windows when installed (explorer.exe, ...)
  optional  a third-party Linux/Windows tool that only matters if installed (warp-cli, ...)
  unbacked  nothing on a stock Windows answers to it: the feature behind it does nothing here
It is a static inventory: it finds the call sites, it does not prove they work.
"""
import json
import os
import re
import sys

SHIM = {
    'ii-shim', 'qalc', 'xdg-open', 'notify-send', 'playerctl', 'wpctl', 'pidof', 'killall', 'pkill', 'loginctl',
    'bash', 'qs', 'switchwall', 'test', 'magick', 'ddcutil', 'brightnessctl', 'cava', 'ydotool', 'secret-tool',
    'cliphist', 'hyprpicker', 'trans', 'ls', 'mkdir', 'rm', 'which',
}
WINDOWS = {'shutdown.exe', 'explorer.exe', 'taskmgr.exe', 'cmd', 'cmd.exe', 'powershell.exe', 'whoami', 'clip', 'where'}
OPTIONAL = {'warp-cli', 'mako', 'openwith'}

# command: [ "name"   |   execDetached(["name"   |   exec(["name"
CALL = re.compile(r'(?:command\s*:\s*\[|exec(?:Detached)?\(\s*\[)\s*(?:\[\s*)?"([A-Za-z0-9_.+-]+)"')


def classify(name):
    if name in SHIM:
        return 'shim'
    if name in WINDOWS:
        return 'windows'
    if name in OPTIONAL:
        return 'optional'
    return 'unbacked'


def scan(root):
    sites = {}
    for base, _dirs, files in os.walk(root):
        for f in files:
            if not f.endswith('.qml'):
                continue
            p = os.path.join(base, f)
            text = open(p, encoding='utf-8', errors='replace').read()
            for m in CALL.finditer(text):
                name = m.group(1)
                line = text.count('\n', 0, m.start()) + 1
                sites.setdefault(name, []).append(f"{os.path.relpath(p, root).replace(os.sep, '/')}:{line}")
    return {name: {'class': classify(name), 'count': len(s), 'sites': sorted(s)} for name, s in sorted(sites.items())}


def markdown(result):
    out = ['| Comando | Clase | Llamadas | Ejemplo |', '| --- | --- | ---: | --- |']
    order = {'unbacked': 0, 'optional': 1, 'windows': 2, 'shim': 3}
    for name, info in sorted(result.items(), key=lambda kv: (order[kv[1]['class']], kv[0])):
        out.append(f"| `{name}` | {info['class']} | {info['count']} | `{info['sites'][0]}` |")
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    result = scan(sys.argv[1])
    args = sys.argv[2:]
    if '--json' in args:
        json.dump(result, open(args[args.index('--json') + 1], 'w', encoding='utf-8'), indent=1, sort_keys=True)
    if '--markdown' in args:
        open(args[args.index('--markdown') + 1], 'w', encoding='utf-8').write(markdown(result))
    classes = {}
    for name, info in result.items():
        classes.setdefault(info['class'], []).append(f"{name}({info['count']})")
    for cls in ('unbacked', 'optional', 'windows', 'shim'):
        print(f"{cls}: {' '.join(classes.get(cls, []))}")
