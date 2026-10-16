import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * ii-windows: the translator of the left sidebar (the `trans` command, which ii-shim answers with Google's
 * public endpoint). Same behaviour as upstream's, laid out again: the two languages side by side with a swap
 * button on top, then the text you type and the translation as two cards that share the height.
 */
Item {
    id: root

    property real padding: 10

    // Widget variables
    property string translatedText: ""
    property bool translating: false
    property list<string> languages: []

    // Options
    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    property var inputField: inputArea
    readonly property bool canSwap: sourceLanguage !== "auto" && targetLanguage !== "auto"

    function labelFor(code, isSource) {
        if (code === "auto")
            return isSource ? Translation.tr("Detect language") : Translation.tr("System language");
        return code;
    }
    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true;
    }
    function setLanguage(isTarget, code) {
        if (isTarget) {
            root.targetLanguage = code;
            Config.options.language.translator.targetLanguage = code; // Save to config
        } else {
            root.sourceLanguage = code;
            Config.options.language.translator.sourceLanguage = code;
        }
    }
    function swapLanguages() {
        if (!root.canSwap)
            return;
        const source = root.sourceLanguage;
        root.setLanguage(false, root.targetLanguage);
        root.setLanguage(true, source);
        // The translation becomes the text to translate back.
        if (root.translatedText.trim().length > 0)
            inputArea.text = root.translatedText;
        translateTimer.restart();
    }

    onFocusChanged: focus => {
        if (focus)
            inputArea.forceActiveFocus();
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (inputArea.text.trim().length > 0) {
                translateProc.running = false;
                translateProc.buffer = ""; // Clear the buffer
                root.translating = true;
                translateProc.running = true; // Restart the process
            } else {
                root.translatedText = "";
                root.translating = false;
            }
        }
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `trans -brief -no-bidi` + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'` + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'` + ` '${StringUtils.shellSingleQuoteEscape(inputArea.text.trim())}'`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            // With -brief mode, we get output with no metadata
            root.translatedText = translateProc.buffer.trim();
            root.translating = false;
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ensure "auto" is always the first language
            let langs = getLanguagesProc.bufferList.filter(lang => lang.trim().length > 0 && lang !== "auto").sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = []; // Clear the buffer
        }
    }

    // A language, as a pill: the name and an arrow.
    component LanguageButton: RippleButton {
        id: languageButton
        property string displayText: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 44
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 2
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: languageButton.width - 44
                text: languageButton.displayText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.hugeass
                text: "arrow_drop_down"
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    // A small round button for the cards.
    component CardButton: RippleButton {
        id: cardButton
        property string symbol: ""
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger
            text: cardButton.symbol
            color: cardButton.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 10

        // The languages
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            LanguageButton {
                displayText: root.labelFor(root.sourceLanguage, true)
                onClicked: root.showLanguageSelectorDialog(false)
            }
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: root.canSwap
                colBackground: Appearance.colors.colLayer2
                onClicked: root.swapLanguages()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.hugeass
                    text: "swap_horiz"
                    color: parent.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: root.canSwap ? Translation.tr("Swap languages") : Translation.tr("Pick the two languages to swap them")
                }
            }
            LanguageButton {
                displayText: root.labelFor(root.targetLanguage, false)
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        // What you type
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 100
            Layout.minimumHeight: 110
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                StyledFlickable {
                    id: inputFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: Math.max(inputArea.implicitHeight, height)
                    clip: true

                    StyledTextArea {
                        id: inputArea
                        width: inputFlick.width
                        height: Math.max(implicitHeight, inputFlick.height)
                        placeholderText: Translation.tr("Enter text to translate...")
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                        padding: 14
                        background: null
                        onTextChanged: translateTimer.restart()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 6
                    Layout.bottomMargin: 6
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 characters").arg(inputArea.text.length)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    CardButton {
                        symbol: "content_paste"
                        onClicked: inputArea.text = Quickshell.clipboardText
                        StyledToolTip {
                            text: Translation.tr("Paste")
                        }
                    }
                    CardButton {
                        symbol: "close"
                        enabled: inputArea.text.length > 0
                        onClicked: inputArea.text = ""
                        StyledToolTip {
                            text: Translation.tr("Clear")
                        }
                    }
                }
            }
        }

        // The translation
        Rectangle {
            id: outputCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 100
            Layout.minimumHeight: 110
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer

            readonly property bool hasTranslation: root.translatedText.trim().length > 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                StyledFlickable {
                    id: outputFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: outputText.implicitHeight + 28
                    clip: true

                    StyledText {
                        id: outputText
                        x: 14
                        y: 14
                        width: outputFlick.width - 28
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: outputCard.hasTranslation ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        text: outputCard.hasTranslation ? root.translatedText : Translation.tr("Translation goes here...")
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 6
                    Layout.bottomMargin: 6
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.translating ? Translation.tr("Translating...") : ""
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    CardButton {
                        symbol: "content_copy"
                        enabled: root.translatedText.trim().length > 0
                        onClicked: Quickshell.clipboardText = root.translatedText
                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    CardButton {
                        symbol: "travel_explore"
                        enabled: root.translatedText.trim().length > 0
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + root.translatedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                        StyledToolTip {
                            text: Translation.tr("Search the web")
                        }
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: result => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0)
                    return; // No selection made
                root.setLanguage(root.languageSelectorTarget, result);
                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
