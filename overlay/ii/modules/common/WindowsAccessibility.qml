pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * ii-windows (plan 2026-10-31, F19/F20/H3): Windows' accessibility settings, as ii follows them.
 *   - Contrast theme on → ii in that theme's colors, without transparency (Appearance + MaterialThemeLoader).
 *   - Text size (Accesibilidad > Tamaño del texto) → ii's text grows with it, up to 150 % (larger breaks the bar).
 *   - Animation effects off → ii without animations, like "Reduce animations" but keeping the transparency.
 * Read with `ii-shim a11y` at start and again when ii-host says Windows' settings changed (WM_SETTINGCHANGE).
 * Each one can be turned off in Configuración > Apariencia > Accesibilidad de Windows.
 */
Singleton {
    id: root
    function load() {}
    property bool loaded: false
    property bool windowsHighContrast: false
    property real windowsTextScale: 1
    property bool windowsAnimations: true
    property var colors: ({})

    readonly property var follow: Config.options?.appearance?.followWindows ?? ({})
    readonly property bool highContrast: (root.follow.highContrast ?? true) && root.windowsHighContrast
    readonly property real textScale: (root.follow.textSize ?? true) ? Math.max(1, Math.min(1.5, root.windowsTextScale)) : 1
    readonly property bool reduceMotion: (root.follow.animations ?? true) && !root.windowsAnimations

    function refresh() {
        if (!proc.running) proc.running = true;
    }
    Process {
        id: proc
        running: true
        command: ["ii-shim", "a11y"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.windowsHighContrast = d.highContrast === true;
                    root.windowsTextScale = Number(d.textScale) || 1;
                    root.windowsAnimations = d.animations !== false;
                    root.colors = d.colors ?? {};
                    root.loaded = true;
                } catch (e) {}
            }
        }
    }
    GlobalShortcut {
        name: "windowsAccessibility"
        description: "Windows' settings changed; ii re-reads the accessibility ones (sent by ii-host)"
        onPressed: root.refresh()
    }

    // The theme's colors over Material 3's roles: backgrounds = window, text = window text, accents = highlight.
    function contrastPalette() {
        const c = root.colors;
        const bg = c.window ?? "#000000", fg = c.windowText ?? "#ffffff";
        const hi = c.highlight ?? "#1aebff", onHi = c.highlightText ?? "#000000";
        const gray = c.grayText ?? fg, link = c.hotlight ?? hi;
        const out = {};
        for (const k of ["m3background", "m3surface", "m3surfaceDim", "m3surfaceBright", "m3surfaceContainerLowest",
                "m3surfaceContainerLow", "m3surfaceContainer", "m3surfaceContainerHigh", "m3surfaceContainerHighest",
                "m3surfaceVariant", "m3inverseOnSurface", "m3onTertiary", "m3onTertiaryFixed"]) out[k] = bg;
        for (const k of ["m3onBackground", "m3onSurface", "m3onSurfaceVariant", "m3outline", "m3inverseSurface"]) out[k] = fg;
        for (const k of ["m3primary", "m3secondary", "m3primaryFixed", "m3primaryFixedDim", "m3secondaryFixed",
                "m3secondaryFixedDim", "m3surfaceTint", "m3inversePrimary", "m3primaryContainer", "m3secondaryContainer"]) out[k] = hi;
        for (const k of ["m3onPrimary", "m3onSecondary", "m3onPrimaryFixed", "m3onSecondaryFixed", "m3onPrimaryContainer",
                "m3onSecondaryContainer", "m3onPrimaryFixedVariant", "m3onSecondaryFixedVariant"]) out[k] = onHi;
        for (const k of ["m3tertiary", "m3tertiaryFixed", "m3tertiaryFixedDim", "m3tertiaryContainer"]) out[k] = link;
        for (const k of ["m3onTertiaryContainer", "m3onTertiaryFixedVariant"]) out[k] = bg;
        out.m3outlineVariant = gray;
        return out;
    }
}
