pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// ii-windows: time and date written in kanji (十六時 二十五分 / 十月八日 木曜日), vertical like
// traditional Japanese text (columns read right to left) or horizontal. Options in
// background.widgets.japaneseClock: vertical, showDate, showSeconds, card.
AbstractBackgroundWidget {
    id: root

    configEntryName: "japaneseClock"
    readonly property bool vertical: configEntry.vertical ?? true
    readonly property bool showDate: configEntry.showDate ?? true
    readonly property bool showSeconds: configEntry.showSeconds ?? false
    readonly property bool card: configEntry.card ?? false
    property date now: new Date()

    implicitWidth: content.implicitWidth + (card ? 48 : 16)
    implicitHeight: content.implicitHeight + (card ? 48 : 16)

    Timer {
        interval: root.showSeconds ? 1000 : 10000
        running: root.visible
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

    // Vertical: big time column on the right, date column to its left (read right to left).
    Row {
        id: content
        anchors.centerIn: parent
        visible: root.vertical
        layoutDirection: Qt.RightToLeft
        spacing: 14

        VerticalText {
            text: root.timeText
            pixelSize: 64
            weight: Font.Bold
        }
        VerticalText {
            visible: root.showDate
            text: root.dateText + "　" + root.weekdayText
            pixelSize: 30
            weight: Font.Normal
            opacity: 0.8
        }
    }

    Column {
        anchors.centerIn: parent
        visible: !root.vertical
        spacing: 4
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            color: root.textColor
            font.family: "Yu Gothic UI"
            font.pixelSize: 64
            font.weight: Font.Bold
            style: root.card ? Text.Normal : Text.Raised
            styleColor: Qt.alpha("black", 0.3)
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            text: root.dateText + "　" + root.weekdayText
            color: root.textColor
            opacity: 0.8
            font.family: "Yu Gothic UI"
            font.pixelSize: 30
            style: root.card ? Text.Normal : Text.Raised
            styleColor: Qt.alpha("black", 0.3)
        }
    }

    // One character per line, as tategaki.
    component VerticalText: Column {
        id: column
        property string text
        property int pixelSize
        property int weight
        readonly property real charWidth: pixelSize * 1.1
        width: charWidth
        spacing: -pixelSize * 0.12
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
                style: root.card ? Text.Normal : Text.Raised
                styleColor: Qt.alpha("black", 0.3)
            }
        }
    }
}
