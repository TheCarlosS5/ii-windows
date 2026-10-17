"""Fonts the shell loads, trimmed to what its QML uses (run on dist\\fonts by deploy.ps1).

Qt registers every *named instance* of a variable font as its own DirectWrite face and keeps it, and each one costs
about the whole file in memory: Google Sans Flex (4 MB, 18 instances) took 73 MB and Material Symbols (15 MB,
7 instances) ~105 MB of the shell's RAM, for weights no QML asks for (Thin, ExtraLight, ExtraBold, nine italics...).
Only the list of named instances (fvar) shrinks: every axis stays, so variableAxes (ROND, wdth, opsz, FILL, wght)
work as before. JetBrains Mono's italic and semibold files go (Qt makes italic itself; DemiBold takes Bold/Medium).

Licences: Google Sans Flex and JetBrains Mono are OFL 1.1 without a Reserved Font Name, Material Symbols Apache 2.0:
modified versions may keep their names; the change is described here and in the licences folder of the package.

    python -I trim_fonts.py <fonts dir>
"""
import os
import sys

from fontTools.ttLib import TTFont

KEEP = {
    'GoogleSansFlex': {'Regular', 'Medium', 'SemiBold', 'Bold', 'Black'},
    'MaterialSymbolsRounded': {'Regular', 'Medium', 'SemiBold'},
}
DROP_FILES = ('JetBrainsMonoNerdFont-Italic.ttf', 'JetBrainsMonoNerdFont-SemiBold.ttf')


def trim(path, keep):
    font = TTFont(path)
    fvar = font['fvar']
    names = font['name']
    before = len(fvar.instances)
    kept = [i for i in fvar.instances if names.getDebugName(i.subfamilyNameID) in keep]
    if len(kept) == before:
        return f'{os.path.basename(path)}: already {before} instances'
    if len(kept) != len(keep):
        # A font update renamed its instances: never ship a font without the weights the QML asks for.
        sys.exit(f'{os.path.basename(path)}: expected the instances {sorted(keep)}, found {len(kept)} of them')
    fvar.instances = kept
    font.save(path + '.tmp')
    font.close()
    os.replace(path + '.tmp', path)
    return f'{os.path.basename(path)}: {before} -> {len(kept)} named instances'


def main(folder):
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if name in DROP_FILES:
            os.remove(path)
            print(f'{name}: removed')
            continue
        for prefix, keep in KEEP.items():
            if name.startswith(prefix) and name.endswith('.ttf'):
                print(trim(path, keep))


if __name__ == '__main__':
    main(sys.argv[1])
