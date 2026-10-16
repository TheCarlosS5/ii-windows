# Atajos de teclado de ii-windows

Generado con `python tools/dev/gen-actions.py` desde `shared/actions.json` (única fuente: la tabla que traga `ii-host`, la chuleta de la shell y este documento salen de ahí). **No editar a mano.**

Estados: **available** = ii does it.; **partial** = ii does part of it, or something close; 'reason' says what is missing.; **external** = Windows keeps handling the combination; ii does not touch it, and 'reason' says why.; **unsupported** = Nothing happens beyond Windows' own behaviour; kept here so that it is visible, not hidden.

Los atajos de ii se resuelven dentro de ii también con una aplicación maximizada. Ceden el paso (y Windows recupera la tecla) solo cuando una aplicación está en pantalla completa exclusiva o a modo de juego; la regla se puede cambiar en `%LOCALAPPDATA%\ii-windows\shortcuts.ini` (ver `docs/DECISIONS.md`). Ctrl+Alt+Mayús+R (pánico) es una tecla de sistema de `ii-host` y funciona incluso con los atajos cedidos.

Las **teclas de volumen** (subir, bajar, silenciar) también las toma ii-host mientras ii está activo: cambia él mismo el volumen (pasos de 2 %) y solo sale el indicador de ii, no el de Windows. Con un juego en pantalla completa, o sin ii, las recupera Windows. Para que las maneje siempre Windows: en `shortcuts.ini` añade `[audio]` y `volumekeys = windows`.

| Atajo | Acción | Estado | Destino | Nota |
| --- | --- | --- | --- | --- |
| Win+SUPER_L | Search apps, files and math (tap the key) | available | `searchToggleRelease` |  |
| Win+S | Search | available | `searchToggle` |  |
| Win+Tab | Overview of open windows | available | `overviewWorkspacesToggle` |  |
| Win+T | Navigate open windows (the overview) | partial | `overviewWorkspacesToggle` | Win+T opens the same overview as Win+Tab; moving through the dock with the keyboard needs the dock navigation of C10. |
| Win+Q | Close the window in front (like Alt+F4) | available | `@closeWindow` |  |
| Win+1-0 | Go to desktop 1-10 (creates one if it doesn't exist) | available | `digits` |  |
| Shift+Win+1-0 | Move the window in front to desktop 1-10 | available | `digits-move` |  |
| Ctrl+Win+Left/Right (lo atiende Windows) | Previous / next desktop (Windows) | external | `windows` | Windows' own combination; it works with ii's desktops. |
| Ctrl+Win+D (lo atiende Windows) | New desktop (Windows) | external | `windows` | Windows' own combination. |
| Ctrl+Win+F4 (lo atiende Windows) | Close this desktop (Windows) | external | `windows` | Windows' own combination. |
| Win+W | Left sidebar | available | `sidebarLeftToggle` |  |
| Win+A | Left sidebar | available | `sidebarLeftToggle` |  |
| Win+O | Left sidebar | available | `sidebarLeftToggle` |  |
| Win+B | Left sidebar | partial | `sidebarLeftToggle` | Win+B is the left sidebar until the tray can be reached from the keyboard (U06). |
| Alt+Win+A | Left sidebar, detached | available | `sidebarLeftToggleDetach` |  |
| Alt+Win+D | Right sidebar (calendar) | available | `sidebarRightToggle` |  |
| Win+N | Right sidebar (quick settings, notifications) | available | `sidebarRightToggle` |  |
| Win+V | Clipboard history | available | `overviewClipboardToggle` |  |
| Win+Period | Emoji picker | available | `overviewEmojiToggle` |  |
| Win+M | Media controls | available | `mediaControlsToggle` |  |
| Win+J | Show or hide the bar | available | `barToggle` |  |
| Win+K | On-screen keyboard | available | `oskToggle` |  |
| Win+Slash | This cheatsheet | available | `cheatsheetToggle` |  |
| Win+D | Show desktop (again to restore) | available | `@showDesktop` |  |
| Ctrl+Win+R | Restart ii | available | `@restartShell` |  |
| Shift+Win+C | Color picker (copies #RRGGBB) | available | `@colorPicker` |  |
| Ctrl+Win+T | Wallpaper selector | available | `wallpaperSelectorToggle` |  |
| Ctrl+Alt+Win+T | Random wallpaper | available | `wallpaperSelectorRandom` |  |
| Ctrl+Shift+Win+D | Toggle light/dark | available | `toggleLightDark` |  |
| Win+I | ii settings | available | `settingsOpen` |  |
| Win+R | Run: programs and links (opens ii's search) | partial | `searchToggle` | Typed shell commands are not run (C05 gives commands an explicit interpreter); programs, links and apps open. |
| Win+X | Session menu (power, sign out, lock) | partial | `sessionToggle` | Win+X opens ii's session menu; the system tools menu of Windows (Task Manager, Device Manager...) has no ii counterpart yet. |
| Shift+Win+S | Region screenshot | available | `regionScreenshot` |  |
| Print | Region screenshot (Print Screen) | available | `regionScreenshot` |  |
| Shift+Win+T | Translate a region | available | `screenTranslate` |  |
| Shift+Win+R | Record a region | partial | `regionRecord` | The region is chosen; there is no video encoder behind it yet (C03). |
| Alt+Win+R | Record a region | partial | `regionRecord` | The region is chosen; there is no video encoder behind it yet (C03). |
| Ctrl+Alt+End | Session menu (power, sign out, lock) | available | `sessionToggle` |  |
| Alt+F4 | Session menu, on the desktop | available | `sessionToggle` |  |
| Win+L (lo atiende Windows) | Lock (Windows) | external | `windows` | Windows' lock screen is the only secure one (R03/U08). |
| Ctrl+Alt+Delete (lo atiende Windows) | Security options (Windows) | external | `windows` | Ctrl+Alt+Del never reaches a program. |
| Ctrl+Shift+Escape (lo atiende Windows) | Task Manager (Windows) | external | `windows` | No process center in ii yet (X03). |
| Win+E (lo atiende Windows) | File Explorer | external | `windows` | No file center in ii yet (X02). |
| Win+P (lo atiende Windows) | Display modes (Windows) | external | `windows` | ii's display selector with rollback comes with U05. |
| Alt+Tab (lo atiende Windows) | Switch windows | external | `windows` | ii's own switcher is U03. |
| Win+Up (lo atiende Windows) | Maximize / snap | external | `windows` | Windows' own combination. |
| Ctrl+Alt+Shift+R | Panic: restore Windows' taskbar and desktop, stop ii | available | `@panic` | A system hotkey of ii-host itself: it works with shortcuts suspended and over games. |
