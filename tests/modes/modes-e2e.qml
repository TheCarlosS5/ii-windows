//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules.common
import qs.services

// E2 end to end, with only harmless effects: a test mode that turns on No molestar (this process' memory) while a
// powershell.exe window is open. The caller backs up config.json and puts it back.
ShellRoot {
    id: root
    property int step: 0
    Component.onCompleted: Modes.load()
    Timer {
        interval: 1000
        running: Config.ready
        repeat: true
        onTriggered: {
            root.step += 1;
            if (root.step === 1) {
                Config.options.modes.notify = false;
                Config.options.modes.list = [{ id: "prueba", name: "Prueba", icon: "science",
                    apply: { dnd: true, theme: "keep", light: false, nightLight: false, keepAwake: false, volume: -1 },
                    schedule: { enable: false }, apps: ["powershell.exe"], fullscreen: false }];
                console.log("E2E start silent=" + Notifications.silent + " active='" + Modes.activeId + "'");
            }
            // The caller opens a powershell.exe window at ~4 s and closes it at ~12 s.
            if (root.step === 9) console.log("E2E open silent=" + Notifications.silent + " active='" + Modes.activeId + "' reason=" + Modes.reason + " detail=" + Modes.reasonDetail);
            if (root.step === 10) { Modes.turnOff(); }
            if (root.step === 11) console.log("E2E dismissed silent=" + Notifications.silent + " active='" + Modes.activeId + "'");
            if (root.step === 12) { Modes.turnOn("prueba"); }
            if (root.step === 13) console.log("E2E manual silent=" + Notifications.silent + " active='" + Modes.activeId + "' reason=" + Modes.reason);
            if (root.step === 14) { Modes.toggle("prueba"); }
            if (root.step === 15) console.log("E2E manualoff silent=" + Notifications.silent + " active='" + Modes.activeId + "'");
            if (root.step === 20) console.log("E2E closed silent=" + Notifications.silent + " active='" + Modes.activeId + "' dismissed=" + JSON.stringify(Modes.dismissed));
            // F24: ii-host's "windowsPresentation" (pressed/released) sets Modes.presenting.
            if (root.step === 21) {
                const m = JSON.parse(JSON.stringify(Config.options.modes.list[0]));
                m.apps = []; m.presenting = true;
                Config.options.modes.list = [m];
                Modes.dismissed = ({}); // the earlier steps turned it off by hand
                Modes.presenting = true;
            }
            if (root.step === 23) console.log("E2E presenting silent=" + Notifications.silent + " active='" + Modes.activeId + "' reason=" + Modes.reason);
            if (root.step === 24) Modes.presenting = false;
            if (root.step === 26) { console.log("E2E presentingend silent=" + Notifications.silent + " active='" + Modes.activeId + "'"); Qt.quit(); }
        }
    }
}
