"""Linux tools ii calls through bash scripts, pointed at ii-shim's Windows versions directly.
Exact-match edits of the staged tree (run after patch_ii.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# Keyring (API keys): secret-tool is ii-shim's (DPAPI, per Windows user). The lookup went through
# a bash script that also asks gnome-keyring whether it is unlocked; there is no lock here, so
# call it directly: exit 1 = no entry yet (ii then creates it).
edit(path('services', 'KeyringStorage.qml'), [
    ('''            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,''',
     '''            "secret-tool", "lookup", ...root.propertiesAsArgs, // ii-windows: ii-shim, DPAPI'''),
])
# Clipboard images: ii decodes an entry with `echo entry | cliphist decode > file` through bash;
# ii-shim's cliphist writes it straight to the file (services/Cliphist.qml is the Windows one).
edit(path('modules', 'common', 'widgets', 'CliphistImage.qml'), [
    ("""        command: ["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(root.entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]""",
     """        command: [Cliphist.cliphistBinary, "decode-to", Cliphist.idOf(root.entry), imageDecodeFilePath] // ii-windows"""),
])
edit(path('modules', 'ii', 'sidebarLeft', 'AiChat.qml'), [
    ("""            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);""",
     """            decodeImageAndAttachProc.exec([Cliphist.cliphistBinary, "decode-to", Cliphist.idOf(entry), imageDecodeFilePath]); // ii-windows"""),
])
print('patched tools')
