"""Packs third_party/icons (Breeze / Breeze Plus themes) into one binary Qt resource, icons.rcc.

The themes are ~40k small files (mostly duplicates left by resolving symlinks); as one compressed
resource they install and load as a single file. Quickshell registers it at startup and serves
the themes from :/icons.

usage: python pack_icons.py <third_party/icons> <out/icons.rcc>   (rcc from Qt must be on PATH)
"""
import os
import subprocess
import sys
from xml.sax.saxutils import escape

src, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
qrc = out + '.qrc'

entries = 0
with open(qrc, 'w', encoding='utf-8') as f:
    f.write('<!DOCTYPE RCC><RCC version="1.0">\n<qresource prefix="/icons">\n')
    for dirpath, _, files in os.walk(src):
        for name in files:
            if name.lower().endswith(('.svg', '.png', '.theme')):
                path = os.path.join(dirpath, name)
                alias = os.path.relpath(path, src).replace(os.sep, '/')
                f.write(f'  <file alias="{escape(alias)}">{escape(path)}</file>\n')
                entries += 1
    f.write('</qresource>\n</RCC>\n')

subprocess.run(['rcc', '--binary', '--compress', '9', '--threshold', '0', '-o', out, qrc], check=True)
os.remove(qrc)
print(f'{entries} icons -> {out} ({os.path.getsize(out) / 1e6:.1f} MB)')
