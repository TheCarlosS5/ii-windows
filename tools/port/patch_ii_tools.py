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
# Emojis (":" in the launcher, Win+.): ii reads them from the Hyprland config's fuzzel script
# (its data section). Ship that same file inside ii's folder and read it from there.
import shutil  # noqa: E402
UPSTREAM = os.path.join(os.path.dirname(__file__), '..', '..', 'upstream', 'dots', '.config', 'hypr', 'hyprland', 'scripts', 'fuzzel-emoji.sh')
os.makedirs(path('assets', 'emoji'), exist_ok=True)
# LF line endings: ii looks for the exact "### DATA ###" line (a checkout may have CRLF).
with open(UPSTREAM, 'rb') as src, open(path('assets', 'emoji', 'fuzzel-emoji.sh'), 'wb') as dst:
    dst.write(src.read().replace(b'\r\n', b'\n'))
edit(path('services', 'Emojis.qml'), [
    # A plain path for FileView: Qt.resolvedUrl("C:/...") reads "C:" as a URL scheme.
    ('    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`',
     '    property string emojiScriptPath: Quickshell.shellPath("assets/emoji/fuzzel-emoji.sh") // ii-windows'),
    ('        path: Qt.resolvedUrl(root.emojiScriptPath)', '        path: root.emojiScriptPath // ii-windows'),
])

# Welcome window: only ii's title bar and buttons (as the settings app), dragged by its title.
edit(path('welcome.qml'), [
    ('    title: Translation.tr("illogical-impulse Welcome")\n',
     '    title: Translation.tr("illogical-impulse Welcome")\n'
     "    // ii-windows: Quickshell's win32 backend hides the Windows caption, keeping the frame.\n"
     '    property bool customTitleBar: true\n'),
    ('''            // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(welcomeText.implicitHeight, windowControlsRow.implicitHeight)
''',
     '''            // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(welcomeText.implicitHeight, windowControlsRow.implicitHeight)
            DragHandler {
                target: null
                onActiveChanged: if (active) root.startSystemMove()
            }
'''),
])
# Illustration download (left sidebar gallery): ii-shim fetch instead of mkdir + curl, and the
# "Download complete" notice only once the file is there.
edit(path('modules', 'ii', 'sidebarLeft', 'anime', 'BooruImage.qml'), [
    ('''                                Quickshell.execDetached(["bash", "-c", 
                                    `mkdir -p '${targetPath}' && curl '${StringUtils.shellSingleQuoteEscape(root.imageData.file_url)}'${userAgentHeader} -o '${targetPath}/${root.fileName}' && notify-send '${Translation.tr("Download complete")}' '${root.downloadPath}/${root.fileName}' -a 'Shell'`
                                ])''',
     '''                                // ii-windows: ii-shim fetch, then the notice (no bash/curl/mkdir).
                                const file = `${targetPath}/${root.fileName}`;
                                downloadProc.file = file;
                                downloadProc.exec(["ii-shim", "fetch", root.imageData.file_url, "--out", file, "--max", "209715200",
                                    ...(userAgent ? ["--agent", userAgent] : [])]);'''),
    ('''                        MenuButton {
                            id: downloadButton''',
     '''                        Process {
                            id: downloadProc
                            property string file
                            onExited: (exitCode, exitStatus) => {
                                if (exitCode === 0) Quickshell.execDetached(["notify-send", Translation.tr("Download complete"), downloadProc.file, "-a", "Shell"]);
                                else Quickshell.execDetached(["notify-send", Translation.tr("Download failed"), root.imageData.file_url, "-a", "Shell"]);
                            }
                        }
                        MenuButton {
                            id: downloadButton'''),
])

# /konachanwallpaper: ii-shim's randomwall (the .sh needs bash, curl and jq).
edit(path('services', 'LauncherSearch.qml'), [
    ('                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);',
     '                Quickshell.execDetached(["ii-shim", "randomwall", "konachan"]); // ii-windows'),
])

# Battery at the suspend threshold and not charging: Windows' sleep (systemctl doesn't exist).
edit(path('services', 'Battery.qml'), [
    ('            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);',
     '            Quickshell.execDetached(["ii-shim", "suspend"]); // ii-windows'),
])

# Welcome screen on the first run: start it directly (not through bash), and write/remove the
# "already greeted" marker without echo/rm.
edit(path('services', 'FirstRunExperience.qml'), [
    ('''        Quickshell.execDetached(["rm", "-f", root.firstRunFilePath])''',
     '''        Quickshell.execDetached(["cmd", "/c", "del", "/f", "/q", root.firstRunFilePath.replace(/^\\/(?=[A-Za-z]:)/, "").replace(/\\//g, "\\\\")]) // ii-windows'''),
    ('''        Quickshell.execDetached(["bash", "-c", `echo '${root.firstRunFileContent}' > '${root.firstRunFilePath}'`])''',
     '''        firstRunFileView.setText(root.firstRunFileContent) // ii-windows'''),
    ('''        Quickshell.execDetached(["bash", "-c", `qs -p '${root.welcomeQmlPath}'`])''',
     '''        Quickshell.execDetached(["qs", "-p", root.welcomeQmlPath]) // ii-windows'''),
])
print('patched tools')
