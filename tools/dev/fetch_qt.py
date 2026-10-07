"""Download official Qt binaries from download.qt.io (new 6.12+ repository layout,
which aqtinstall 3.3 does not understand yet). Every archive is checked against the
SHA1 published in the official Updates.xml before extraction.

usage: python -I fetch_qt.py <download-dir> <install-dir>
"""
import hashlib
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

import py7zr

VER = "6120"
ARCH = "win64_msvc2022_64"
BASE = f"https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_{VER}/qt6_{VER}_msvc2022_64"
ADDONS = [
    "qt5compat", "qtimageformats", "qtmultimedia", "qtpositioning", "qtquicktimeline",
    "qtsensors", "qtshadertools", "qtvirtualkeyboard", "qtwebsockets", "qtlanguageserver",
]

dl, dest = Path(sys.argv[1]), Path(sys.argv[2])
dl.mkdir(parents=True, exist_ok=True)
dest.mkdir(parents=True, exist_ok=True)

def get(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()

root = ET.fromstring(get(f"{BASE}/Updates.xml"))
wanted = {f"qt.qt6.{VER}.{ARCH}"} | {f"qt.qt6.{VER}.addons.{a}.{ARCH}" for a in ADDONS}
found = set()
for pkg in root.findall("PackageUpdate"):
    name = pkg.findtext("Name")
    if name not in wanted:
        continue
    found.add(name)
    version = pkg.findtext("Version")
    for archive in [a.strip() for a in (pkg.findtext("DownloadableArchives") or "").split(",") if a.strip()]:
        fname = f"{version}{archive}"
        url = f"{BASE}/{name}/{fname}"
        expected = get(url + ".sha1").decode().split()[0].strip().lower()
        local = dl / archive
        if not (local.exists() and hashlib.sha1(local.read_bytes()).hexdigest() == expected):
            print("download", archive, flush=True)
            local.write_bytes(get(url))
        actual = hashlib.sha1(local.read_bytes()).hexdigest()
        if actual != expected:
            sys.exit(f"SHA1 MISMATCH {archive}: {actual} != {expected}")
        print("ok      ", archive, actual, flush=True)
        with py7zr.SevenZipFile(local) as z:
            z.extractall(dest)

missing = wanted - found
if missing:
    sys.exit(f"packages not found: {sorted(missing)}")

# The archives unpack as <dest>/6.12.0/msvc2022_64/...; make the prefix relocatable.
for qtconf in dest.glob("*/msvc2022_64/bin"):
    (qtconf / "qt.conf").write_text("[Paths]\nPrefix=..\n")
    print("prefix", qtconf.parent)
