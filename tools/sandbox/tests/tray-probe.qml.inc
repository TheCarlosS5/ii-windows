    // Test-only inspection, injected into the sandbox copy of Background.qml.
    IpcHandler {
        target: "trayTest"
        function state(): string {
            return JSON.stringify({
                pinned: TrayService.pinnedItems.map(i => i.id + ":" + i.promoted),
                unpinned: TrayService.unpinnedItems.map(i => i.id + ":" + i.promoted),
            });
        }
    }
