pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// ii-windows: the wallpaper, small and blurred (`ii-shim blurwall`, on the CPU, once per wallpaper), for the
// frosted glass behind ii's panels (modules/common/widgets/WallpaperBlur.qml). The panels only draw this
// picture: no blur shader per panel, so the glass looks the same on any GPU, and on none.
// It is made again whenever the palette is (colors.json changes): random wallpapers keep their file name.
Singleton {
    id: root

    // file:/// URL of the current blurred picture, "" until there is one.
    property string source: ""

    readonly property string wallpaper: {
        const p = Config.options.background.wallpaperPath ?? "";
        const video = /\.(mp4|webm|mkv|avi|mov|gif)$/i.test(p);
        return FileUtils.trimFileProtocol(video ? (Config.options.background.thumbnailPath ?? "") : p);
    }
    readonly property string outDir: FileUtils.trimFileProtocol(`${Directories.cache}/media/blurred`)
    property int flip: 0 // two files in turn: a new name makes every Image load the new picture

    function refresh() {
        if (!Config.ready || root.wallpaper.length === 0 || !(Config.options.appearance.transparency.blurBehind ?? true))
            return;
        debounce.restart();
    }
    onWallpaperChanged: refresh()

    Timer {
        id: debounce
        interval: 300
        onTriggered: {
            if (blurProc.running) {
                restart();
                return;
            }
            root.flip = 1 - root.flip;
            blurProc.target = `${root.outDir}/glass-${root.flip}.png`.replace(/^\/(?=[A-Za-z]:)/, "");
            // blurwall makes the folder itself (no cmd: Quickshell's quoting and cmd's do not mix)
            blurProc.command = ["ii-shim", "blurwall", root.wallpaper.replace(/^\/(?=[A-Za-z]:)/, ""), blurProc.target, "480"];
            blurProc.running = true;
        }
    }
    Process {
        id: blurProc
        property string target: ""
        onExited: (code, status) => {
            if (code === 0)
                root.source = "file:///" + blurProc.target;
        }
    }

    // A new palette = a new (or rewritten) wallpaper.
    FileView {
        path: Qt.resolvedUrl(Directories.generatedMaterialThemePath)
        watchChanges: true
        preload: false
        onFileChanged: root.refresh()
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.refresh();
        }
    }
    Component.onCompleted: refresh()
}
