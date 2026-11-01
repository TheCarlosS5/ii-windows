import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "settings-index.js" as Index
import "widgets/registry.js" as Registry

// ii-windows (plan 2026-10-31, C3): what the settings search finds. The index (settings-index.js) is made from the pages
// when the QML is prepared (tools/port/gen_settings_index.py): every section, subsection and labelled control, its
// Spanish and synonyms. Matching ignores case and accents; every word typed has to appear.
Item {
    id: root

    required property var pages   // settings.qml's pages
    property string query: ""
    property alias currentIndex: list.currentIndex
    readonly property var results: root.search(root.query)
    signal chosen(var entry)

    function norm(text) {
        return (text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    function pageOf(entry) {
        return root.pages.find(p => p.component.split("/").pop().toLowerCase().replace(".qml", "") === entry.p) ?? null;
    }
    function widgetTitle(key) {
        const widget = Registry.widgets.find(w => w.key === key);
        return widget ? Translation.tr(widget.title).replace(/^Widget:\s*/, "") : key;
    }
    function trail(entry) { // Escritorio › Reloj › Estilo de esfera
        const parts = [];
        const page = root.pageOf(entry);
        if (page) parts.push(page.name);
        if (entry.sub) parts.push(root.widgetTitle(entry.sub));
        for (const t of [entry.s, entry.ss])
            if (t && t !== entry.l && !(entry.sub && t.startsWith("Widget:"))) parts.push(Translation.tr(t));
        return parts.join("  ›  ");
    }

    // Haystacks are built on the first search, again when the translations change.
    // (A plain object, changed in place: the results binding must not depend on it.)
    readonly property var cache: ({ haystacks: [] })
    Connections {
        target: Translation
        function onTranslationsChanged() { root.cache.haystacks = []; }
    }
    function haystack(i) {
        if (root.cache.haystacks.length !== Index.entries.length) {
            root.cache.haystacks = Index.entries.map(e => {
                const page = root.pageOf(e);
                return " " + root.norm([Translation.tr(e.l), Translation.tr(e.s), Translation.tr(e.ss), e.l, e.s, e.ss,
                    page ? page.name : "", e.sub ? root.widgetTitle(e.sub) : "", e.k.replace(/\./g, " "), e.w].join(" "));
            });
        }
        return root.cache.haystacks[i];
    }
    function stem(word) { // plurals find the singular: "notas" → "nota", "colores" → "color"
        if (word.length > 4 && word.endsWith("es")) return word.slice(0, -2);
        if (word.length > 3 && word.endsWith("s")) return word.slice(0, -1);
        return word;
    }
    function search(query) {
        const words = root.norm(query).split(/\s+/).filter(w => w.length > 0).map(w => root.stem(w));
        if (words.length === 0) return [];
        const found = [];
        for (let i = 0; i < Index.entries.length; ++i) {
            const hay = root.haystack(i);
            if (!words.every(w => hay.includes(w))) continue;
            const entry = Index.entries[i];
            const label = root.norm(Translation.tr(entry.l));
            let score = 0;
            for (const w of words) {
                if (label.startsWith(w)) score += 6;
                else if (label.includes(" " + w)) score += 4;
                else if (label.includes(w)) score += 3;
                else if (hay.includes(" " + w)) score += 1;
            }
            if (entry.l !== entry.s && entry.l !== entry.ss) score += 0.5; // a control before the section that holds it
            found.push({ entry: entry, score: score, index: i });
        }
        found.sort((a, b) => b.score - a.score || a.index - b.index);
        return found.slice(0, 60).map(f => f.entry);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(600, root.width - 40)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: root.results.length === 0 ? Translation.tr("Nothing found for \"%1\"").arg(root.query)
                : Translation.tr("%1 results").arg(root.results.length)
        }

        ListView {
            id: list
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(600, root.width - 40)
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.results
            currentIndex: 0
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            delegate: RippleButton {
                id: result
                required property var modelData
                required property int index
                width: ListView.view.width
                implicitHeight: row.implicitHeight + 16
                buttonRadius: Appearance.rounding.normal
                colBackground: ListView.isCurrentItem ? Appearance.colors.colLayer2 : "transparent"
                onClicked: root.chosen(result.modelData)
                contentItem: RowLayout {
                    id: row
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    MaterialSymbol {
                        text: result.modelData.i || "settings"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr(result.modelData.l)
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.trail(result.modelData)
                            elide: Text.ElideRight
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    MaterialSymbol {
                        text: "arrow_forward"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
