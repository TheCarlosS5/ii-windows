"""Exact-match network edits to staged ii; upstream stays untouched.

Windows has no bash/curl/jq/file pipelines. Fetch with ii-shim argument lists,
then leave presentation and image decoding to QML. Every pattern must match once.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.normpath(os.path.join(ROOT, *parts))


# wttr JSON selection moves into the shim; city formatting, GPS and refinement stay in QML.
edit(path('services', 'Weather.qml'), [
    ('''        let command = "curl -s wttr.in";

        if (root.gpsActive && root.location.valid) {
            command += `/${root.location.lat},${root.location.long}`;
        } else {
            command += `/${formatCityName(root.city)}`;
        }

        // format as json
        command += "?format=j1";
        command += " | ";
        // only take the current weather, location, asytronmy data
        command += "jq '{current: .current_condition[0], location: .nearest_area[0], astronomy: .weather[0].astronomy[0]}'";
        fetcher.command[2] = command;''',
     '''        const place = root.gpsActive && root.location.valid
            ? `${root.location.lat},${root.location.long}`
            : formatCityName(root.city);
        fetcher.command = ["ii-shim", "weather", place];'''),
    ('        command: ["bash", "-c", ""]',
     '        command: ["ii-shim", "weather", ""]'),
])

# Fetch creates folders and reuses cache files. Qt replaces `file` for dimensions; a failed
# fetch or image decode still emits no done signal, just as the old pipeline did.
edit(path('modules', 'common', 'utils', 'ImageDownloaderProcess.qml'), [
    ('''        return StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(filePath));''',
     '''        const path = FileUtils.trimFileProtocol(filePath);
        return filePath.startsWith("file:") ? decodeURIComponent(path) : path;'''),
    ('        return StringUtils.shellSingleQuoteEscape(sourceUrl);',
     '        return sourceUrl;'),
    (r'''    function curlUserAgentArg() {
        if (!downloadUserAgent) {
            return "";
        }
        return ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(downloadUserAgent)}'`;
    }

    running: true
    command: ["bash", "-c", 
        `mkdir -p $(dirname '${processFilePath()}'); [ -f '${processFilePath()}' ] || curl -sSL '${processSourceUrl()}'${curlUserAgentArg()} -o '${processFilePath()}' && file '${processFilePath()}'`
    ]
    stdout: StdioCollector {
        id: imageSizeOutputCollector
        onStreamFinished: {
            const output = imageSizeOutputCollector.text.trim();
            const match = output.match(/(\d+)\s*x\s*(\d+)/);

            if (match) {
                const width = Number(match[1]);
                const height = Number(match[2]);
                root.done(root.filePath, width, height);
            }
        }
    }''',
     r'''    function imageFileUrl() {
        if (filePath.startsWith("file:")) return filePath;
        const path = processFilePath().replace(/\\/g, "/");
        let encoded = path.split("/").map(part => encodeURIComponent(part)).join("/");
        if (/^\/?[A-Za-z]:\//.test(path)) {
            encoded = "file:///" + encoded.replace(/^\/?([A-Za-z])%3A\//, "$1:/");
        } else if (path.startsWith("//")) {
            encoded = "file:" + encoded;
        } else if (path.startsWith("/")) {
            encoded = "file://" + encoded;
        }
        return Qt.resolvedUrl(encoded);
    }

    running: true
    command: {
        const args = ["ii-shim", "fetch", processSourceUrl(), "--out", processFilePath(), "--keep"];
        if (downloadUserAgent) args.push("--agent", downloadUserAgent);
        return args;
    }
    onRunningChanged: {
        if (running) imageSizeProbe.source = "";
    }
    onExited: (exitCode, exitStatus) => {
        if (exitCode !== 0) return;
        imageSizeProbe.source = "";
        imageSizeProbe.source = imageFileUrl();
    }
    property Image imageSizeProbe: Image {
        visible: false
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (status === Image.Ready) {
                const width = sourceSize.width;
                const height = sourceSize.height;
                source = ""; // Release the invisible decode after measuring it.
                root.done(root.filePath, width, height);
            }
        }
    }'''),
])

# Windows media already supplies file: cover art. Use it directly and only fetch remote art;
# retain downloaded=true on process exit so ii's existing reload/colour bindings keep working.
edit(path('modules', 'ii', 'mediaControls', 'PlayerControl.qml'), [
    ('    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""',
     '''    property string displayedArtFilePath: String(root.artUrl ?? "").toLowerCase().startsWith("file:")
        ? root.artUrl : (root.downloaded ? Qt.resolvedUrl(artFilePath) : "")'''),
    ('''        if (root.artUrl.length == 0) {''',
     '''        if (!root.artUrl || root.artUrl.length == 0) {'''),
    ('''        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl ''',
     '''        if (String(root.artUrl).toLowerCase().startsWith("file:")) {
            coverArtDownloader.running = false;
            root.downloaded = true;
            return;
        }

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl '''),
    ('''        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'` ]''',
     '''        command: ["ii-shim", "fetch", targetFile, "--out", FileUtils.trimFileProtocol(artFilePath), "--keep"]'''),
])

# Favicon uses the same cached atomic GET, including the configured User-Agent as one argument.
edit(path('modules', 'common', 'widgets', 'Favicon.qml'), [
    ('''        command: ["bash", "-c", `[ -f ${faviconFilePath} ] || curl -s '${root.faviconUrl}' -o '${faviconFilePath}' -L -H 'User-Agent: ${downloadUserAgent}'`]''',
     '''        command: ["ii-shim", "fetch", root.faviconUrl, "--out", FileUtils.trimFileProtocol(faviconFilePath), "--keep", "--agent", downloadUserAgent]'''),
])
