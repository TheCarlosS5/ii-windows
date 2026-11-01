import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E2): Configuración > Modos. What each mode changes and when it starts by itself. The
// modes live in Config.options.modes.list (a list of objects): every change writes a new copy of the list.
ContentPage {
    id: page
    forceWidth: true

    function modes() {
        return JSON.parse(JSON.stringify(Config.options.modes.list ?? []));
    }
    // set(index, "apply.dnd", true)
    function set(index, key, value) {
        const list = page.modes();
        if (!list[index]) return;
        let target = list[index];
        const parts = key.split(".");
        for (let i = 0; i < parts.length - 1; ++i) {
            if (typeof target[parts[i]] !== "object" || target[parts[i]] === null) target[parts[i]] = {};
            target = target[parts[i]];
        }
        target[parts[parts.length - 1]] = value;
        Config.options.modes.list = list;
    }

    ContentSection {
        icon: "auto_mode"
        title: Translation.tr("Modes")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("A mode changes several things at once and puts them back as they were when it ends. Turn one on in the right panel or from the search (\"modo juego\"), or let it start by itself at its hours or while one of its apps is open.")
        }
        ConfigSwitch {
            buttonIcon: "auto_mode"
            text: Translation.tr("Use modes")
            checked: Config.options.modes.enable
            onCheckedChanged: Config.options.modes.enable = checked
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Tell me when a mode starts or ends by itself")
            checked: Config.options.modes.notify
            onCheckedChanged: Config.options.modes.notify = checked
        }
        StyledText {
            Layout.fillWidth: true
            visible: Modes.active !== null
            wrapMode: Text.Wrap
            color: Appearance.colors.colPrimary
            text: Modes.active ? Translation.tr("Now: %1").arg(Modes.nameOf(Modes.active)) : ""
        }
    }

    Repeater {
        model: Config.options.modes.list
        delegate: ContentSection {
            id: section
            required property var modelData
            required property int index
            readonly property var mode: modelData
            icon: mode.icon || "auto_mode"
            title: Modes.nameOf(mode)

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Name (empty: %1)").arg(Translation.tr(Modes.defaultNames[section.mode.id] ?? ""))
                text: section.mode.name ?? ""
                onEditingFinished: if (text !== (section.mode.name ?? "")) page.set(section.index, "name", text)
            }

            ContentSubsection {
                title: Translation.tr("What it changes")
                ConfigSwitch {
                    buttonIcon: "do_not_disturb_on"
                    text: Translation.tr("Do not disturb")
                    checked: section.mode.apply?.dnd ?? false
                    onCheckedChanged: if (checked !== (section.mode.apply?.dnd ?? false)) page.set(section.index, "apply.dnd", checked)
                }
                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Light mode (fewer animations and effects)")
                    checked: section.mode.apply?.light ?? false
                    onCheckedChanged: if (checked !== (section.mode.apply?.light ?? false)) page.set(section.index, "apply.light", checked)
                }
                ConfigSwitch {
                    buttonIcon: "nightlight"
                    text: Translation.tr("Night light")
                    checked: section.mode.apply?.nightLight ?? false
                    onCheckedChanged: if (checked !== (section.mode.apply?.nightLight ?? false)) page.set(section.index, "apply.nightLight", checked)
                }
                ConfigSwitch {
                    buttonIcon: "coffee"
                    text: Translation.tr("Keep the screen on")
                    checked: section.mode.apply?.keepAwake ?? false
                    onCheckedChanged: if (checked !== (section.mode.apply?.keepAwake ?? false)) page.set(section.index, "apply.keepAwake", checked)
                }
                ConfigSelectionArray {
                    currentValue: section.mode.apply?.theme ?? "keep"
                    onSelected: newValue => page.set(section.index, "apply.theme", newValue)
                    options: [
                        { displayName: Translation.tr("Theme as it is"), icon: "contrast", value: "keep" },
                        { displayName: Translation.tr("Dark"), icon: "dark_mode", value: "dark" },
                        { displayName: Translation.tr("Light"), icon: "light_mode", value: "light" }
                    ]
                }
                ConfigSwitch {
                    id: volumeSwitch
                    buttonIcon: "volume_up"
                    text: Translation.tr("Set the volume")
                    checked: (section.mode.apply?.volume ?? -1) >= 0
                    onCheckedChanged: {
                        const on = (section.mode.apply?.volume ?? -1) >= 0;
                        if (checked !== on) page.set(section.index, "apply.volume", checked ? 50 : -1);
                    }
                }
                ConfigSlider {
                    visible: volumeSwitch.checked
                    text: Translation.tr("Volume")
                    buttonIcon: "volume_down"
                    from: 0
                    to: 100
                    usePercentTooltip: false
                    value: Math.max(0, section.mode.apply?.volume ?? 50)
                    onValueChanged: if (Math.round(value) !== (section.mode.apply?.volume ?? -1) && volumeSwitch.checked) page.set(section.index, "apply.volume", Math.round(value))
                }
            }

            ContentSubsection {
                title: Translation.tr("At its hours")
                ConfigSwitch {
                    id: scheduleSwitch
                    buttonIcon: "schedule"
                    text: Translation.tr("Start by itself at these hours")
                    checked: section.mode.schedule?.enable ?? false
                    onCheckedChanged: if (checked !== (section.mode.schedule?.enable ?? false)) page.set(section.index, "schedule.enable", checked)
                }
                Flow {
                    Layout.fillWidth: true
                    visible: scheduleSwitch.checked
                    spacing: 4
                    Repeater {
                        // Monday first; the stored numbers are JavaScript's (Sunday = 0).
                        model: [{ d: 1, n: "Mon" }, { d: 2, n: "Tue" }, { d: 3, n: "Wed" }, { d: 4, n: "Thu" }, { d: 5, n: "Fri" }, { d: 6, n: "Sat" }, { d: 0, n: "Sun" }]
                        delegate: SelectionGroupButton {
                            required property var modelData
                            readonly property var days: section.mode.schedule?.days ?? [0, 1, 2, 3, 4, 5, 6]
                            buttonText: Translation.tr(modelData.n)
                            toggled: days.includes(modelData.d)
                            leftmost: true
                            rightmost: true
                            onClicked: {
                                const next = toggled ? days.filter(x => x !== modelData.d) : days.concat([modelData.d]);
                                page.set(section.index, "schedule.days", next.sort());
                            }
                        }
                    }
                }
                RowLayout {
                    visible: scheduleSwitch.checked
                    spacing: 10
                    StyledText { text: Translation.tr("From") }
                    MaterialTextField {
                        implicitWidth: 90
                        placeholderText: "18:00"
                        text: section.mode.schedule?.from ?? ""
                        validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
                        onEditingFinished: if (acceptableInput && text !== section.mode.schedule?.from) page.set(section.index, "schedule.from", text)
                    }
                    StyledText { text: Translation.tr("to") }
                    MaterialTextField {
                        implicitWidth: 90
                        placeholderText: "22:00"
                        text: section.mode.schedule?.to ?? ""
                        validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
                        onEditingFinished: if (acceptableInput && text !== section.mode.schedule?.to) page.set(section.index, "schedule.to", text)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr("(it may end the next day: 22:00 to 06:00)")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("While these apps are open")
                tooltip: Translation.tr("The program's file name, as Task Manager shows it in Details (osu!.exe). One per line.")
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("For example: osu!.exe")
                    wrapMode: TextEdit.Wrap
                    text: (section.mode.apps ?? []).join("\n")
                    onActiveFocusChanged: {
                        if (activeFocus) return;
                        const apps = text.split(/[\n,;]+/).map(a => a.trim()).filter(a => a.length > 0);
                        if (apps.join("\n") !== (section.mode.apps ?? []).join("\n")) page.set(section.index, "apps", apps);
                    }
                }
                ConfigSwitch { // F24
                    readonly property bool follows: section.mode.presenting ?? (section.mode.id === "presentacion")
                    buttonIcon: "co_present"
                    text: Translation.tr("Also while Windows is presenting (PowerPoint's slide show)")
                    checked: follows
                    onCheckedChanged: if (checked !== follows) page.set(section.index, "presenting", checked)
                }
                ConfigSwitch {
                    visible: section.mode.id === "juego"
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Also with any app in full screen (not browsers)")
                    checked: section.mode.fullscreen ?? false
                    onCheckedChanged: if (checked !== (section.mode.fullscreen ?? false)) page.set(section.index, "fullscreen", checked)
                }
            }
        }
    }
}
