pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// ii-windows: time and date written in kanji (十六時 二十五分 / 十月八日 木曜日), vertical like
// traditional Japanese text (columns read right to left) or horizontal. Options in
// background.widgets.japaneseClock: vertical, showDate, showSeconds, card.
// Its size multiplies the font sizes (scalesContent) instead of stretching the rendered text,
// so it stays sharp at any size.
AbstractBackgroundWidget {
    id: root

    configEntryName: "japaneseClock"
    scalesContent: true
    readonly property real f: root.widgetScale
    readonly property bool vertical: configEntry.vertical ?? true
    readonly property bool showDate: configEntry.showDate ?? true
    readonly property bool showSeconds: configEntry.showSeconds ?? false
    readonly property bool card: configEntry.card ?? false
    property date now: new Date()

    readonly property Item shown: vertical ? verticalContent : horizontalContent
    implicitWidth: Math.ceil(shown.implicitWidth + (card ? 48 : 16) * f)
    implicitHeight: Math.ceil(shown.implicitHeight + (card ? 48 : 16) * f)

    Timer {
        interval: root.showSeconds ? 1000 : 10000
        // Nobody sees it under a maximized app: no repaints of the whole wallpaper for it.
        running: root.visible && !root.desktopCovered
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var digits: ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    readonly property var weekdays: ["日", "月", "火", "水", "木", "金", "土"]

    // 0..99 in kanji: 十 = 10, 二十五 = 25, 零 for zero hours/minutes.
    function kanji(n) {
        if (n === 0) return "零";
        const tens = Math.floor(n / 10);
        const ones = n % 10;
        return (tens > 1 ? digits[tens] : "") + (tens > 0 ? "十" : "") + (ones > 0 ? digits[ones] : "");
    }

    readonly property string timeText: kanji(now.getHours()) + "時" + kanji(now.getMinutes()) + "分"
        + (showSeconds ? kanji(now.getSeconds()) + "秒" : "")
    readonly property string dateText: kanji(now.getMonth() + 1) + "月" + kanji(now.getDate()) + "日"
    readonly property string weekdayText: weekdays[now.getDay()] + "曜日"
    readonly property color textColor: card ? Appearance.colors.colOnLayer0 : Appearance.colors.colPrimary

    StyledDropShadow {
        visible: root.card
        target: background
    }
    Rectangle {
        id: background
        anchors.fill: parent
        visible: root.card
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
    }

    // Without a card, a soft shadow keeps it readable on any wallpaper (Text.Raised drew a
    // second copy 1 px lower, which looked doubled on thin kanji strokes).
    component Shadowed: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.35
        shadowOpacity: 0.45
        shadowVerticalOffset: 1
        shadowColor: "black"
    }

    // Vertical: big time column on the right, date column to its left (read right to left).
    Row {
        id: verticalContent
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        visible: root.vertical
        layer.enabled: !root.card
        layer.effect: Shadowed {}
        layoutDirection: Qt.RightToLeft
        spacing: Math.round(14 * root.f)

        VerticalText {
            text: root.timeText
            pixelSize: Math.round(64 * root.f)
            weight: Font.Bold
        }
        VerticalText {
            visible: root.showDate
            text: root.dateText + "　" + root.weekdayText
            pixelSize: Math.round(30 * root.f)
            weight: Font.Normal
            opacity: 0.8
        }
    }

    Column {
        id: horizontalContent
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        visible: !root.vertical
        layer.enabled: !root.card
        layer.effect: Shadowed {}
        spacing: Math.round(4 * root.f)
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            color: root.textColor
            font.family: "Yu Gothic UI"
            font.pixelSize: Math.round(64 * root.f)
            font.weight: Font.Bold
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            text: root.dateText + "　" + root.weekdayText
            color: root.textColor
            opacity: 0.8
            font.family: "Yu Gothic UI"
            font.pixelSize: Math.round(30 * root.f)
        }
    }

    // One character per line, as tategaki.
    component VerticalText: Column {
        id: column
        property string text
        property int pixelSize
        property int weight
        readonly property real charWidth: Math.round(pixelSize * 1.1)
        width: charWidth
        spacing: -Math.round(pixelSize * 0.12)
        Repeater {
            model: Array.from(column.text)
            delegate: StyledText {
                required property string modelData
                width: column.charWidth
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: root.textColor
                font.family: "Yu Gothic UI"
                font.pixelSize: column.pixelSize
                font.weight: column.weight
            }
        }
    }
}
