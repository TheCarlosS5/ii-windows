"""The files .gitattributes keeps byte for byte (-text: CRLF or mixed in the repository) still have CRLF line endings
in the working tree. A tool that rewrites one with LF would otherwise commit the whole file as changed and rewrite its
history (git blame). Exit code 1 and the list of such files if any; 0 otherwise.

    python check-eol.py [--fix]      --fix turns a file that lost them back to CRLF
"""
import os
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))


def kept_files():
    with open(os.path.join(REPO, '.gitattributes'), encoding='utf-8') as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and parts[1] == '-text' and not parts[0].startswith('*'):
                yield parts[0].replace('[[:space:]]', ' ')


def main():
    fix = '--fix' in sys.argv
    bad = []
    for name in kept_files():
        path = os.path.join(REPO, name)
        if not os.path.isfile(path):
            continue
        data = open(path, 'rb').read()
        if b'\n' in data and b'\r\n' not in data:
            bad.append(name)
            if fix:
                open(path, 'wb').write(data.replace(b'\n', b'\r\n'))
    for name in bad:
        print(f'{"fixed" if fix else "lost its CRLF line endings"}: {name}')
    return 1 if bad and not fix else 0


if __name__ == '__main__':
    sys.exit(main())
