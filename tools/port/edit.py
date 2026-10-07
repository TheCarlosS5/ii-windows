"""Tiny exact-match patch helper: edit(path, [(old, new, count)]). Fails if a pattern is missing."""
import sys
def edit(path, pairs):
    s = open(path, encoding='utf-8', newline='').read()
    for item in pairs:
        old, new = item[0], item[1]
        n = item[2] if len(item) > 2 else 1
        c = s.count(old)
        if c == 0 or (n != 0 and c != n):
            sys.exit(f"{path}: expected {n} match(es), found {c} for:\n{old}")
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='').write(s)
    print('patched', path)
