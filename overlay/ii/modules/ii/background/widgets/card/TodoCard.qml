import QtQuick

// ii's to-do list (sidebar) on the desktop: same tasks as the sidebar's.
CardWidget {
    configEntryName: "todo"
    cardWidth: 360
    cardHeight: 380
    source: Qt.resolvedUrl("../../../sidebarRight/todo/TodoWidget.qml")
}
