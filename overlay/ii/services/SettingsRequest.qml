pragma Singleton
import QtQuick
import Quickshell

// ii-windows (plan 2026-10-31, C2/C5): what Configuración was asked to show, "page" or "page/sub" (II_SETTINGS_PAGE at
// start, then what a second Win+I / a widget's gear hands the open window through SingleInstance). A page's own part
// (the widget gallery: "backgroundconfig/clock") reads the "sub" from here, also when the window was already open.
Singleton {
    id: root

    property string argument: Quickshell.env("II_SETTINGS_PAGE") || ""
    property int serial: 0 // changes on every request, even the same one again

    function request(argument) {
        root.argument = argument || "";
        root.serial += 1;
    }

    // The "sub" part when the request is for `page` (a settings file name, with or without "config"), else "".
    function subFor(page) {
        const parts = root.argument.toLowerCase().split("/");
        if (parts.length < 2) return "";
        const wanted = page.toLowerCase();
        return parts[0] === wanted || parts[0] + "config" === wanted ? parts[1] : "";
    }

    // subFor(), and the request is done: coming back to the page later shows it as usual.
    function take(page) {
        const sub = root.subFor(page);
        if (sub !== "") root.argument = "";
        return sub;
    }
}
