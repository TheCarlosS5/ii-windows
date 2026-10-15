"""UX round of 2026-10-15, part 2: AI models, features that do not work, welcome, about, settings.
Exact-match edits of the staged tree; every edit fails loudly if upstream moved the code."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- Gemini: the models this key can use today, from Google itself -----------------------------------------
# The built-in list (2.5 Flash, 3 Flash preview) ages: with a free key Google offers newer models and the
# old ones stop answering. The list comes from ListModels with the user's key (through ii-shim ai-request
# {"method":"GET"}); the built-in ones stay as the fallback (offline, no key, older ii-shim).
edit(path('services', 'Ai.qml'), [
    ('''    property var modelList: Object.keys(root.models)
''',
     '''    // --- ii-windows: Gemini models from Google's ListModels ---------------------------------------
    property bool geminiListed: false
    function geminiModelRank(id) {
        // Newer version first, then flash > flash-lite > pro for a free key.
        const v = /gemini-(\\d+(?:\\.\\d+)?)/.exec(id);
        const version = v ? parseFloat(v[1]) : 0;
        const tier = id.includes("flash-lite") ? 1 : id.includes("flash") ? 2 : id.includes("pro") ? 0 : -1;
        return version * 10 + tier;
    }
    function applyGeminiList(text) {
        let parsed;
        try { parsed = JSON.parse(text); } catch (e) { return; }
        const list = (parsed.models ?? []).filter(m => {
            const id = (m.name ?? "").replace("models/", "");
            return id.startsWith("gemini-") && (m.supportedGenerationMethods ?? []).includes("generateContent")
                && !/embedding|tts|image|audio|live|robotics|computer-use|aqa|imagen|exp-|-001$|-002$|-latest$|\\d{2}-\\d{2}$|\\d{4}$|customtools/.test(id);
        }).map(m => ({ id: m.name.replace("models/", ""), name: m.displayName || m.name, description: m.description || "" }));
        if (list.length === 0) return;
        list.sort((a, b) => root.geminiModelRank(b.id) - root.geminiModelRank(a.id));
        const keep = {};
        for (const key of Object.keys(root.models))
            if (root.models[key].api_format !== "gemini") keep[key] = root.models[key];
        const next = {};
        for (const m of list.slice(0, 8)) {
            next[root.safeModelName(m.id)] = aiModelComponent.createObject(root, {
                "name": m.name,
                "icon": "google-gemini-symbolic",
                "description": Translation.tr("Online | Google's model | Available with your key") + "\\n" + m.description,
                "homepage": "https://aistudio.google.com",
                "endpoint": `https://generativelanguage.googleapis.com/v1beta/models/${m.id}:streamGenerateContent`,
                "model": m.id,
                "requires_key": true,
                "key_id": "gemini",
                "key_get_link": "https://aistudio.google.com/app/apikey",
                "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\\n\\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
                "api_format": "gemini",
            });
        }
        root.models = Object.assign({}, next, keep);
        root.modelList = Object.keys(root.models);
        root.geminiListed = true;
        if (!root.models[root.currentModelId]) {
            // The model that was chosen is gone: the newest flash this key offers.
            const preferred = list.find(m => m.id.includes("flash") && !m.id.includes("lite")) ?? list[0];
            root.setModel(root.safeModelName(preferred.id), false, false);
        }
    }
    function refreshGeminiModels() {
        const key = root.apiKeys["gemini"] ?? "";
        if (!key || key.length === 0 || geminiListProc.running) return;
        const requestPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath).replace(/\\.sh$/, "") + ".models." + Quickshell.instanceId + ".json";
        const content = JSON.stringify({ "method": "GET", "url": "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=${API_KEY}", "headers": {} });
        geminiListFile.path = Qt.resolvedUrl(requestPath);
        geminiListFile.setText(content);
        geminiListFile.reload();
        geminiListProc.environment["API_KEY"] = key;
        geminiListProc.command = ["ii-shim", "ai-request", requestPath];
        geminiListProc.running = true;
    }
    FileView {
        id: geminiListFile
        blockWrites: true
        blockAllReads: true
    }
    Process {
        id: geminiListProc
        stdout: StdioCollector {
            onStreamFinished: root.applyGeminiList(text)
        }
    }
    Connections {
        target: KeyringStorage
        function onLoadedChanged() { if (KeyringStorage.loaded) root.refreshGeminiModels(); }
        function onDataChanged() { root.refreshGeminiModels(); }
    }

    property var modelList: Object.keys(root.models)
'''),
])
