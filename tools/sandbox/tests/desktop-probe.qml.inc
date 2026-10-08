    // Test-only inspection, injected into the sandbox copy of Background.qml.
    QtObject {
        id: desktopInspection
        function walk(object, visit, seen) {
            if (!object || seen.indexOf(object) >= 0) return;
            seen.push(object);
            visit(object);
            if (object.contentItem) walk(object.contentItem, visit, seen);
            if (object.active === true && object.item) walk(object.item, visit, seen);
            // resources: windows declared inside items (the desktop menu's own window).
            for (const list of [object.children, object.instances, object.resources]) {
                if (!list || list.length === undefined) continue;
                for (let i = 0; i < list.length; ++i) walk(list[i], visit, seen);
            }
        }

        function menu() {
            let found = null;
            walk(bgRoot.contentItem, object => {
                if (object.toString().indexOf("DesktopMenu_QMLTYPE") === 0) found = object;
            }, []);
            return found;
        }

        function desktop() {
            let found = null;
            walk(bgRoot.contentItem, object => {
                if (object.toString().indexOf("DesktopIcons_QMLTYPE") === 0) found = object;
            }, []);
            return found;
        }

    }

    IpcHandler {
        target: "desktopTest"
        function snapshot(): string {
            const widget = desktopInspection.desktop();
            const result = { present: !!widget, files: [], menu: null };
            if (!widget) return JSON.stringify(result);
            result.selectedPath = widget.selectedPaths()[0] ?? "";
            result.iconSize = widget.iconSize;
            result.userDesktop = widget.userDesktop;
            result.publicDesktop = widget.publicDesktop;
            result.widget = { width: widget.width, height: widget.height, visible: widget.visible,
                opacity: widget.opacity, loaderActive: widget.parent.active, screenLocked: GlobalStates.screenLocked };
            desktopInspection.walk(widget, object => {
                if (typeof object.filePath === "string" && typeof object.fileName === "string") {
                    const point = object.mapToItem(null, object.width / 2, 20);
                    const entry = { path: object.filePath, name: object.fileName, x: point.x, y: point.y,
                        selected: object.selected, iconStatus: -1, label: "" };
                    for (const child of object.children) {
                        if (child.fillMode !== undefined && child.status !== undefined) entry.iconStatus = child.status;
                        if (typeof child.text === "string") entry.label = child.text;
                    }
                    result.files.push(entry);
                }
            }, []);
            const menu = desktopInspection.menu();
            if (menu) {
                result.menu = { visible: menu.menuOpen, target: result.selectedPath, entries: [], backgroundAlpha: 0 };
                desktopInspection.walk(menu, object => {
                    if (object.modelData?.text !== undefined && object.isWidget !== undefined) {
                        const point = object.mapToItem(null, 60, object.height / 2);
                        result.menu.entries.push({ text: object.modelData.text, x: point.x, y: point.y });
                    }
                    if (object.radius !== undefined && object.color !== undefined && object.shown !== undefined)
                        result.menu.backgroundAlpha = object.color.a;
                }, []);
            }
            return JSON.stringify(result);
        }

        function enabled(value: bool): void {
            Config.options.background.widgets.desktopIcons.enable = value;
        }

        function captureIcon(name: string, path: string): void {
            desktopInspection.walk(desktopInspection.desktop(), object => {
                if (object.fileName !== name) return;
                for (const child of object.children) {
                    if (child.fillMode !== undefined && child.status !== undefined)
                        child.grabToImage(result => result.saveToFile(path));
                }
            }, []);
        }
    }
