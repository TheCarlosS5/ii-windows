"""Hide settings without a Windows implementation using exact-match staged-tree edits.
Run after stage-ii.ps1, with II_STAGE_DIR pointing at that staged tree.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

# Require an explicit stage; do not accidentally patch the running build/ii tree.
ROOT = os.environ['II_STAGE_DIR']


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- About: Linux distribution and dotfiles metadata.
edit(path('modules', 'settings', 'About.qml'), [
    ('''    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")
''',
     '''    ContentSection {
        visible: false // ii-windows: Linux distribution metadata is not used on Windows
        icon: "box"
        title: Translation.tr("Distro")
'''),
    ('''    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Dotfiles")
''',
     '''    ContentSection {
        visible: false // ii-windows: Linux dotfiles management is not available on Windows
        icon: "folder_managed"
        title: Translation.tr("Dotfiles")
'''),
])

# --- Gemini has no Windows transport yet.
edit(path('modules', 'settings', 'GeneralConfig.qml'), [
    ('''        ContentSubsection {
            title: Translation.tr("Generate translation with Gemini")
''',
     '''        ContentSubsection {
            visible: false // ii-windows: Gemini translation has no Windows transport
            title: Translation.tr("Generate translation with Gemini")
'''),
])

# --- Background widgets: keep manual placement and the inexpensive clock options.
placement_options = '''                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]'''

background_edits = [
    ('''            ConfigSwitch {
                buttonIcon: "wand_stars"
                text: Translation.tr("Auto styling with Gemini")
''',
     '''            ConfigSwitch {
                visible: false // ii-windows: Gemini styling has no Windows transport
                buttonIcon: "wand_stars"
                text: Translation.tr("Auto styling with Gemini")
'''),
    ('''            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
''',
     '''            ConfigSwitch {
                visible: false // ii-windows: continuous cookie rotation wastes GPU time
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
'''),
]
for widget in ('clock', 'weather'):
    # Include the widget's config key so each identical option list matches exactly once.
    selector = f'''                currentValue: Config.options.background.widgets.{widget}.placementStrategy
                onSelected: newValue => {{
                    Config.options.background.widgets.{widget}.placementStrategy = newValue;
                }}
''' + placement_options
    background_edits.append((
        selector + '\n',
        selector + '.filter(option => option.value === "free") // ii-windows: automatic placement needs Python\n',
    ))
edit(path('modules', 'settings', 'BackgroundConfig.qml'), background_edits)

# --- Bar: no screen recorder (the workspace count works: ii's 10 slots, patch_ii_desktops.py).
# Hide the whole singleton Record row so it does not leave an empty layout row.
edit(path('modules', 'settings', 'BarConfig.qml'), [
    ('''        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
''',
     '''        ConfigRow {
            visible: false // ii-windows: no screen recorder is available
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
'''),
])

# --- Interface: Linux authentication and circular region selection.
edit(path('modules', 'settings', 'InterfaceConfig.qml'), [
    ('''        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
''',
     '''        ConfigSwitch {
            visible: false // ii-windows: Hyprlock and its fingerprint unlock are Linux-only
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
'''),
    ('''            ConfigSwitch {
                buttonIcon: "key_vertical"
                text: Translation.tr('Also unlock keyring')
''',
     '''            ConfigSwitch {
                visible: false // ii-windows: Linux keyring unlock does not apply to Windows
                buttonIcon: "key_vertical"
                text: Translation.tr('Also unlock keyring')
'''),
    ('''                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ]
''',
     '''                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ].filter(option => option.value !== "circle") // ii-windows: circular selection is not implemented
'''),
    ('''        ContentSubsection {
            title: Translation.tr("Circle selection")
''',
     '''        ContentSubsection {
            visible: false // ii-windows: circular selection is not implemented
            title: Translation.tr("Circle selection")
'''),
])

# --- Services: SongRec and screen recording have no Windows implementation.
# The Arch update section (enable checks and interval included) is already commented out.
# No panel-family/Waffle selector or region-selector recording settings exist in this tree.
edit(path('modules', 'settings', 'ServicesConfig.qml'), [
    ('''    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music Recognition")
''',
     '''    ContentSection {
        visible: false // ii-windows: SongRec music recognition is not available
        icon: "music_cast"
        title: Translation.tr("Music Recognition")
'''),
    ('''        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
''',
     '''        MaterialTextArea {
            visible: false // ii-windows: no screen recorder is available
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
'''),
])
