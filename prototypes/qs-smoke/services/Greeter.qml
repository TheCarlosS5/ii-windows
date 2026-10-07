pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property string message: "hello from qs.services (" + Quickshell.env("USERNAME") + ")"
}
