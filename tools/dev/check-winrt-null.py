"""Plan 2026-10-31, A6: finds the bug class of the 0.6.0 crash in C++/WinRT code.

A WinRT getter can return S_OK with a null object (GetPlaybackInfo() of a browser's closing media session did), and a
call through it reads address 0: no C++ catch stops that. This flags, in files that include <winrt/...>:

    auto x = something.Getter(...);     // a projected object
    x.Method();                         // used within the next 3 lines, with no `if (x` / `if (!x` / `x ?` before

It is a heuristic for review, not a proof: getters that cannot return null (value types, hstrings) show up too and
can be marked with `// winrt-nonnull` on the assignment line.

    python check-winrt-null.py [paths...]   (default: quickshell/src/win32 and host/src)   exit 1 if anything is flagged
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
DEFAULT = [os.path.join(ROOT, 'quickshell', 'src', 'win32'), os.path.join(ROOT, 'host', 'src')]
ASSIGN = re.compile(r'^\s*auto\s+(\w+)\s*=\s*[\w:.>()\-\[\]]+\.([A-Z]\w*)\([^;]*\);')
# Getters whose result is a value (numbers, strings, enums, IReference that is checked differently...).
VALUE_GETTERS = re.compile(r'^(Title|Artist|AlbumTitle|AlbumArtist|SourceAppUserModelId|Id|Name|DisplayName|AppUserModelId|'
                           r'PlaybackStatus|Status|Size|Text|Message|Position|StartTime|EndTime|LastUpdatedTime|'
                           r'IsShuffleActive|AutoRepeatMode|PlaybackRate|ConnectionStatus|BluetoothDeviceId|GetResults|'
                           r'try_as|as|Value|wait_for|GetAccessStatus|CanMaintainConnection|ChargeRateInMilliwatts|'
                           r'RemainingCapacityInMilliwattHours|FullChargeCapacityInMilliwattHours|DesignCapacityInMilliwattHours|'
                           r'NetworkCostType|Roaming|OverDataLimit|LoadAsync|ReadBytes|Kind|State|IsPlayEnabled|'
                           # Windows.Data.Json getters throw on a missing key instead of returning null
                           r'GetNamedObject|GetNamedArray|GetNamedString|GetNamedNumber|GetArray|GetObject|GetString|'
                           r'GetDisplayProperties|HasKey)$')


def check(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        lines = f.read().splitlines()
    if not any('#include <winrt/' in l for l in lines):
        return []
    found = []
    for i, line in enumerate(lines):
        m = ASSIGN.match(line)
        if not m or 'winrt-nonnull' in line:
            continue
        var, getter = m.group(1), m.group(2)
        if VALUE_GETTERS.match(getter) or getter.endswith('Async'):
            continue
        guarded = False
        for j in range(i + 1, min(i + 4, len(lines))):
            nxt = lines[j]
            if re.search(r'(if\s*\(\s*!?\s*%s\b)|(\b%s\s*\?)|(!%s\b)|(\b%s\s*&&)' % (var, var, var, var), nxt):
                guarded = True
                break
            if re.search(r'\b%s\.\w+\(' % var, nxt) and not guarded:
                found.append((i + 1, line.strip(), j + 1, nxt.strip()))
                break
    return found


def main():
    roots = sys.argv[1:] or DEFAULT
    total = 0
    for root in roots:
        for dirpath, _, names in os.walk(root):
            for name in names:
                if not name.endswith(('.cpp', '.hpp', '.h')):
                    continue
                path = os.path.join(dirpath, name)
                for line, text, used, usage in check(path):
                    total += 1
                    print(f'{os.path.relpath(path, ROOT)}:{line}: {text}\n    used at {used}: {usage}')
    print(f'{total} unchecked WinRT object(s)')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
