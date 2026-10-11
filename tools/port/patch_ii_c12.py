"""C12: live Linux routes in the left sidebar pin, the language list and the cache folders.

  - SidebarLeft.togglePin used to move the Hyprland cursor away (hyprctl cursorpos / dispatch),
    pin, and move it back. On Windows the pin is just the flag: it flips directly, never touches the
    cursor and never starts a process.
  - Translation.qml listed the language files with `find ... -exec basename`: replaced by a
    FolderListModel over the real folder (no process), restricted to locale-named .json files. The
    language that is loaded is resolved against what exists (es_CO -> es_MX when es_CO.json is not
    shipped, otherwise English), and re-resolved when the scan finishes.
  - Directories.qml emptied and recreated its cache folders with `bash -c "rm -rf ...; mkdir -p ..."`;
    ii-shim's bash is deliberately not a shell, so that did nothing. It is now one typed command,
    `ii-shim reset-dir <folder>`, which only touches the user's own folders.
Exact-match edits of the staged tree.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('modules', 'ii', 'sidebarLeft', 'SidebarLeft.qml'), [
    ('''    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }
''', '''    // ii-windows (C12): the pin is only the flag. (Hyprland needed the cursor moved away and back
    // for it to take effect; here nothing moves the cursor or starts a process.)
    function togglePin() {
        root.pin = !root.pin;
    }
'''),
])

edit(path('services', 'Translation.qml'), [
    ('''import qs.modules.common

Singleton {''', '''import qs.modules.common
import Qt.labs.folderlistmodel
import "../modules/common/functions/LanguageResolve.js" as LanguageResolve

Singleton {'''),
    ('''    TranslationScanner {
        id: scanLanguagesProcess''', '''    // ii-windows (C12): what is actually loaded is the requested language resolved against the files
    // that exist (and again when the scan finishes, since it is not known before that).
    property string resolvedLanguageCode: LanguageResolve.resolve(root.languageCode, root.allAvailableLanguages)

    TranslationScanner {
        id: scanLanguagesProcess'''),
    ('''    onLanguageCodeChanged: {
        print("[Translation] Language changed to", root.languageCode);
        translationFileView.languageCode = root.languageCode;
        generatedTranslationFileView.languageCode = root.languageCode;''', '''    onResolvedLanguageCodeChanged: {
        print("[Translation] Language:", root.languageCode, "->", root.resolvedLanguageCode);
        translationFileView.languageCode = root.resolvedLanguageCode;
        generatedTranslationFileView.languageCode = root.resolvedLanguageCode;'''),
    ('''        translationsDir: root.translationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            root.translations = data;''', '''        translationsDir: root.translationsDir
        languageCode: root.resolvedLanguageCode
        onContentLoaded: (data) => {
            root.translations = data;'''),
    ('''        translationsDir: root.generatedTranslationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            root.generatedTranslations = data;''', '''        translationsDir: root.generatedTranslationsDir
        languageCode: root.resolvedLanguageCode
        onContentLoaded: (data) => {
            root.generatedTranslations = data;'''),
    ('''    component TranslationScanner: Process {
        id: translationScanner
        required property string translationsDir
        signal languagesScanned(var languages)

        command: ["find", translationScanner.translationsDir, "-name", "*.json", "-exec", "basename", "{}", ".json", ";"]
        running: true

        stdout: StdioCollector {
            id: languagesCollector
            onStreamFinished: {
                const output = languagesCollector.text;
                const files = output.trim().split('\\n').map(f => f.trim());
                translationScanner.languagesScanned(files);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                translationScanner.languagesScanned(["en_US"]);
            }
        }
    }''', '''    // The language files are listed by Qt, not by `find`/`basename` (Unix programs).
    component TranslationScanner: Item {
        id: translationScanner
        required property string translationsDir
        signal languagesScanned(var languages)

        FolderListModel {
            id: translationFolder
            folder: LanguageResolve.folderUrl(translationScanner.translationsDir)
            nameFilters: ["*.json"]
            showDirs: false
            showDotAndDotDot: false
            onStatusChanged: translationScanner.report()
            onCountChanged: translationScanner.report()
        }

        function report() {
            if (translationFolder.status === FolderListModel.Loading) return;
            const names = [];
            for (let i = 0; i < translationFolder.count; ++i) names.push(translationFolder.get(i, "fileName"));
            const languages = LanguageResolve.parseLanguages(names);
            translationScanner.languagesScanned(languages.length > 0 ? languages : ["en_US"]);
        }
        Component.onCompleted: report()
    }'''),
])

edit(path('modules', 'common', 'Directories.qml'), [
    ('''        Quickshell.execDetached(["bash", "-c", `rm -rf '${coverArt}'; mkdir -p '${coverArt}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${booruPreviews}'; mkdir -p '${booruPreviews}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${latexOutput}'; mkdir -p '${latexOutput}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`])''',
     '''        // ii-windows: one typed step per folder (ii-shim's bash is not a shell and ran none of this).
        Quickshell.execDetached(["ii-shim", "reset-dir", `${coverArt}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${booruPreviews}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${latexOutput}`])
        Quickshell.execDetached(["ii-shim", "reset-dir", `${cliphistDecode}`])'''),
])
