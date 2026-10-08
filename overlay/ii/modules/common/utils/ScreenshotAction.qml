pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

// ii-windows: same actions as ii's, done by `ii-shim crop` with what Windows ships
// (WIC, the clipboard, Paint, Windows OCR) instead of magick / wl-copy / swappy / tesseract.
// Search uploads to a third-party host and recording needs a recorder, so those report that
// they aren't available yet instead.
Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        const region = [Math.round(x), Math.round(y), Math.round(width), Math.round(height)].map(String);
        const crop = (verb, ...extra) => ["ii-shim", "crop", screenshotPath, ...region, verb, ...extra];
        switch (action) {
            case ScreenshotAction.Action.Copy:
                return saveDir === "" ? crop("copy") : crop("save", saveDir);
            case ScreenshotAction.Action.Edit:
                return crop("edit");
            case ScreenshotAction.Action.CharRecognition:
                return crop("ocr");
            case ScreenshotAction.Action.Search:
                return crop("search");
            case ScreenshotAction.Action.Record:
            case ScreenshotAction.Action.RecordWithSound:
                return crop("record");
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
