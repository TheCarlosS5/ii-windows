"""R11: the Gelbooru account key moves out of config.json into the per-user secret store.

ii already keeps API keys for AI chat in KeyringStorage (a JSON blob in one secret, encrypted with
DPAPI by ii-shim secret-tool). The Gelbooru key was a plain string in config.json, which is also what
backups, exports and bug reports get near. After this patch:
  - the key is read from the secret store (booru.gelbooru.apiKey / userId);
  - a key found in config.json by an older version is copied to the store, then read back from
    the store (a fresh read of the encrypted file), and only if it matches is the plain copy erased;
    if anything fails the plain copy stays and the migration is retried next time;
  - `/gelbooru <userId> <apiKey>` in the booru panel stores a key, and the 401 message says so.
Exact-match edits of the staged tree; runs after patch_ii_p0.py (which added the config fields).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('services', 'Booru.qml'), [
    # Where the credentials come from: the store first, config.json only as the legacy fallback.
    ('''        if (currentProvider === "gelbooru") {
            const key = Config.options?.sidebar?.booru?.gelbooru?.apiKey ?? "";
            const user = Config.options?.sidebar?.booru?.gelbooru?.userId ?? "";
            if (key.length > 0 && user.length > 0)
                params.push("api_key=" + encodeURIComponent(key), "user_id=" + encodeURIComponent(user));
        }''',
     '''        if (currentProvider === "gelbooru") {
            const credentials = root.gelbooruCredentials();
            if (credentials.apiKey.length > 0 && credentials.userId.length > 0)
                params.push("api_key=" + encodeURIComponent(credentials.apiKey), "user_id=" + encodeURIComponent(credentials.userId));
        }'''),
    ('''            return Translation.tr("Gelbooru needs an API key. Create one at gelbooru.com > My Account > Options, then set sidebar.booru.gelbooru.apiKey and userId in ii's config.json");''',
     '''            return Translation.tr("Gelbooru needs an API key. Create one at gelbooru.com > My Account > Options, then type /gelbooru <user id> <api key> here. It is stored encrypted for your Windows user, not in config.json");'''),
    ('''    // ii-windows: say why instead of the generic tips.
    function statusMessage(status) {''',
     '''    // ii-windows (R11): the Gelbooru key lives in the secret store, not in config.json.
    function gelbooruCredentials() {
        const stored = KeyringStorage.keyringData?.booru?.gelbooru;
        if (stored && (stored.apiKey ?? "").length > 0) return { apiKey: stored.apiKey, userId: stored.userId ?? "" };
        // Legacy: the plain copy an older version left in config.json, until it has been moved.
        return {
            apiKey: Config.options?.sidebar?.booru?.gelbooru?.apiKey ?? "",
            userId: Config.options?.sidebar?.booru?.gelbooru?.userId ?? "",
        };
    }

    function saveGelbooruCredentials(userId, apiKey) {
        KeyringStorage.setNestedField(["booru", "gelbooru"], { "apiKey": apiKey.trim(), "userId": userId.trim() });
    }

    // Migration of a key found in config.json. Phases: 0 nothing to do / not started, 1 copied to the
    // store (waiting for the write), 2 re-read from the encrypted file (waiting to compare).
    // The plain copy is erased only when the fresh read matches it.
    property int gelbooruMigrationPhase: 0
    readonly property bool canMigrateGelbooru: Config.ready && KeyringStorage.loaded
    onCanMigrateGelbooruChanged: if (canMigrateGelbooru) root.advanceGelbooruMigration()

    function advanceGelbooruMigration() {
        const legacyKey = Config.options?.sidebar?.booru?.gelbooru?.apiKey ?? "";
        const legacyUser = Config.options?.sidebar?.booru?.gelbooru?.userId ?? "";
        if (!root.canMigrateGelbooru || (legacyKey === "" && legacyUser === "")) { root.gelbooruMigrationPhase = 0; return; }
        const stored = KeyringStorage.keyringData?.booru?.gelbooru;
        const inStore = stored && stored.apiKey === legacyKey && (stored.userId ?? "") === legacyUser;
        if (root.gelbooruMigrationPhase === 0) {
            if (!inStore) root.saveGelbooruCredentials(legacyUser, legacyKey);
            root.gelbooruMigrationPhase = 1;
            gelbooruMigrationTimer.restart();
        } else if (root.gelbooruMigrationPhase === 1) {
            KeyringStorage.fetchKeyringData(); // a fresh read of the encrypted file
            root.gelbooruMigrationPhase = 2;
            gelbooruMigrationTimer.restart();
        } else if (inStore) {
            Config.options.sidebar.booru.gelbooru.apiKey = "";
            Config.options.sidebar.booru.gelbooru.userId = "";
            root.gelbooruMigrationPhase = 0;
            console.log("[Booru] Gelbooru key moved to the secret store; the plain copy in config.json was erased");
        } else {
            console.warn("[Booru] Could not read the Gelbooru key back from the secret store; the copy in config.json is kept");
            root.gelbooruMigrationPhase = 0;
        }
    }

    Timer {
        id: gelbooruMigrationTimer
        interval: 1500
        onTriggered: root.advanceGelbooruMigration()
    }

    // ii-windows: say why instead of the generic tips.
    function statusMessage(status) {'''),
])

edit(path('modules', 'ii', 'sidebarLeft', 'Anime.qml'), [
    ('''    property var allCommands: [
        {
            name: "mode",''',
     '''    property var allCommands: [
        {
            // ii-windows (R11): the account key is kept encrypted for this Windows user.
            name: "gelbooru",
            description: Translation.tr("Save your Gelbooru user id and API key (stored encrypted, not in config.json)"),
            execute: (args) => {
                if (args.length < 2 || args[0].length === 0 || args[1].length === 0) {
                    Booru.addSystemMessage(Translation.tr("Usage: /gelbooru <user id> <api key>"));
                    return;
                }
                Booru.saveGelbooruCredentials(args[0], args[1]);
                Booru.addSystemMessage(Translation.tr("Gelbooru key saved (encrypted for your Windows user)."));
            }
        },
        {
            name: "mode",'''),
])
