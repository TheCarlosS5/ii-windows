"""Icon themes illogical-impulse uses: breeze-plus(-dark) on top of breeze(-dark).

- breeze / breeze-dark: Arch Linux's official breeze-icons package (KDE, LGPL-3.0). The
  archive's SHA256 is checked against the repository database before extraction.
- breeze-plus / breeze-plus-dark: https://github.com/mjkim0727/breeze-plus (LGPL-2.1).

Symlinks (thousands of icon aliases) become plain copies so the themes work on Windows.

usage: python fetch_icons.py <work-dir> <out-dir>
"""
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

import zstandard

MIRROR = 'https://geo.mirror.pkgbuild.com/extra/os/x86_64'
work, out = sys.argv[1], sys.argv[2]
os.makedirs(work, exist_ok=True)
os.makedirs(out, exist_ok=True)


def get(url):
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read()


# --- breeze-icons from Arch, verified ---------------------------------------------------
db = tarfile.open(fileobj=io.BytesIO(get(f'{MIRROR}/extra.db')))
desc = None
for member in db.getmembers():
    if member.name.startswith('breeze-icons-') and member.name.endswith('/desc'):
        desc = db.extractfile(member).read().decode()
        break
if desc is None:
    sys.exit('breeze-icons not found in extra.db')

fields = {}
key = None
for line in desc.splitlines():
    if line.startswith('%') and line.endswith('%'):
        key = line.strip('%')
        fields[key] = []
    elif line and key:
        fields[key].append(line)
filename, sha256 = fields['FILENAME'][0], fields['SHA256SUM'][0]

pkg_path = os.path.join(work, filename)
if not os.path.exists(pkg_path) or hashlib.sha256(open(pkg_path, 'rb').read()).hexdigest() != sha256:
    print('download', filename)
    open(pkg_path, 'wb').write(get(f'{MIRROR}/{filename}'))
actual = hashlib.sha256(open(pkg_path, 'rb').read()).hexdigest()
if actual != sha256:
    sys.exit(f'SHA256 MISMATCH for {filename}: {actual} != {sha256}')
print('verified', filename, sha256)


def extract_theme_tar(tar, prefix, dest_root):
    """Extract members under prefix (e.g. usr/share/icons/), resolving symlinks to copies."""
    members = {m.name: m for m in tar.getmembers()}

    def resolve(name, depth=0):
        m = members.get(name)
        if m is None or depth > 40:
            return None
        if m.issym():
            target = os.path.normpath(os.path.join(os.path.dirname(name), m.linkname)).replace('\\', '/')
            return resolve(target, depth + 1)
        return m

    count = 0
    for name, m in members.items():
        if not name.startswith(prefix) or m.isdir():
            continue
        real = resolve(name)
        if real is None or not real.isfile():
            continue
        dest = os.path.join(dest_root, name[len(prefix):])
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with tar.extractfile(real) as src, open(dest, 'wb') as dst:
            shutil.copyfileobj(src, dst)
        count += 1
    return count


raw = zstandard.ZstdDecompressor().stream_reader(open(pkg_path, 'rb'))
tar = tarfile.open(fileobj=io.BytesIO(raw.read()))
n = extract_theme_tar(tar, 'usr/share/icons/', out)
print(f'breeze themes: {n} files')
lic = [m for m in tar.getmembers() if m.name.startswith('usr/share/licenses/') and m.isfile()]
for m in lic:
    dest = os.path.join(out, 'LICENSES', 'breeze-icons-' + os.path.basename(m.name))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, 'wb').write(tar.extractfile(m).read())

# --- breeze-plus from git -----------------------------------------------------------------
src = os.path.join(work, 'breeze-plus')
if not os.path.isdir(src):
    # symlinks=true would need privileges; plain checkout writes links as small text files
    subprocess.run(['git', 'clone', '-q', '--depth', '1', '-c', 'core.symlinks=false',
                    'https://github.com/mjkim0727/breeze-plus.git', src], check=True)
ls = subprocess.run(['git', '-C', src, 'ls-files', '-s'], capture_output=True, text=True, check=True).stdout
links = {line.split('\t', 1)[1] for line in ls.splitlines() if line.startswith('120000')}

count = 0
for theme in ('breeze-plus', 'breeze-plus-dark'):
    base = os.path.join(src, 'src', theme)
    for root, _, files in os.walk(base):
        for f in files:
            path = os.path.join(root, f)
            rel_repo = os.path.relpath(path, src).replace('\\', '/')
            target = path
            hops = 0
            while rel_repo in links and hops < 40:  # follow text-file "links"
                link_to = open(target, encoding='utf-8', errors='replace').read().strip()
                target = os.path.normpath(os.path.join(os.path.dirname(target), link_to))
                rel_repo = os.path.relpath(target, src).replace('\\', '/')
                hops += 1
            if not os.path.isfile(target):
                continue
            dest = os.path.join(out, theme, os.path.relpath(path, base))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copyfile(target, dest)
            count += 1
os.makedirs(os.path.join(out, 'LICENSES'), exist_ok=True)
shutil.copyfile(os.path.join(src, 'LICENSE'), os.path.join(out, 'LICENSES', 'breeze-plus-LGPL-2.1.txt'))
print(f'breeze-plus themes: {count} files')
