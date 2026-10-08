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

        function find(prefix) {
            let found = null;
            walk(bgRoot.contentItem, object => {
                if (object.toString().indexOf(prefix) === 0) found = object;
            }, []);
            return found;
        }
    }

    IpcHandler {
        target: "desktopTest"
        function snapshot(): string {
            const widget = desktopInspection.find("DesktopIcons_QMLTYPE");
            const menu = desktopInspection.find("DesktopMenu_QMLTYPE");
            const result = { present: !!widget, files: [], menu: null };
            if (!widget) return JSON.stringify(result);
            result.iconSize = widget.iconSize;
            result.rows = widget.rows;
            result.columns = widget.columns;
            result.userDesktop = widget.userDesktop;
            result.selectionCount = widget.selectionCount;
            result.currentPath = widget.currentPath;
            result.renamingPath = widget.renamingPath;
            result.overflowCount = widget.overflowCount;
            result.sortMode = widget.sortMode;
            result.activeFocus = widget.activeFocus;
            result.windowActive = bgRoot.active ?? null;
            desktopInspection.walk(widget, object => {
                if (typeof object.filePath === "string" && typeof object.fileName === "string" && object.cell !== undefined) {
                    const point = object.mapToItem(null, object.width / 2, 24);
                    result.files.push({ path: object.filePath, name: object.fileName, x: point.x, y: point.y,
                        cell: object.cell, selected: object.selected, renaming: object.renaming, visible: object.visible });
                }
            }, []);
            if (menu) {
                result.menu = { shown: menu.menuOpen, entries: [], choices: [] };
                desktopInspection.walk(menu, object => {
                    if (object.modelData?.checked !== undefined && object.isWidget === undefined && object.mapToItem) {
                        const point = object.mapToItem(null, object.width / 2, object.height / 2);
                        result.menu.choices.push({ text: object.modelData.text, x: point.x, y: point.y, checked: object.modelData.checked });
                    }
                    if (object.modelData !== undefined && object.modelData?.text !== undefined && object.isWidget !== undefined) {
                        const point = object.mapToItem(null, 60, object.height / 2);
                        result.menu.entries.push({ text: object.modelData.text, x: point.x, y: point.y, visible: object.visible });
                    }
                }, []);
            }
            return JSON.stringify(result);
        }
    }
