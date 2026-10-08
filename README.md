# ii-windows

**Illogical Impulse en Windows 11.** Un port de la interfaz de
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (Illogical Impulse) que corre de
verdad en Windows: el mismo QML de ii, sobre un fork de [Quickshell](https://quickshell.org)
compilado para Windows. No es una imitación ni un tema: es la shell de ii, con un backend nativo
para Windows debajo.

> Estado: en desarrollo activo. Funciona en el día a día del autor; lee [PROGRESS.md](PROGRESS.md)
> para ver qué está probado y qué falta.

*English summary at the end.*

## Qué incluye

- **Barra** de ii con bandeja del sistema (iconos reales de tus apps, menús nativos), red, audio,
  multimedia, reloj y recursos. Las ventanas maximizadas respetan el espacio de la barra.
- **Lanzador y vista general** (tecla Windows): búsqueda de apps, calculadora, emojis y todas tus
  ventanas en cuadrícula con vista previa en vivo.
- **Dock** con vista previa de ventanas al pasar el ratón, botón de cerrar y menú de clic derecho.
- **Paneles laterales**: ajustes rápidos, notificaciones de Windows, calendario, tareas, pomodoro,
  mezclador de volumen, Wi-Fi, luz nocturna, planes de energía.
- **Escritorio de ii**: tus iconos reales, reloj, música, foto, clima, archivos recientes y un menú
  de clic derecho para activar widgets y cambiar el fondo.
- **Colores Material 3 desde el fondo** (la biblioteca oficial de Google), selector de fondos,
  fondo aleatorio. Windows sigue los colores de ii: modo oscuro/claro, color de acento y un esquema
  para Windows Terminal.
- **Notificaciones**, overlay (Super+G), recortes de pantalla con OCR, menú de sesión, cheatsheet.
- Fuentes, iconos y el cursor **Bibata** del dotfile.
- Se aparta de los juegos a pantalla completa.

Lo que **no** hace: no gestiona ventanas (sin tiling), no emula Hyprland ni sus workspaces.
Windows sigue siendo Windows.

## Seguridad primero

Todo es por usuario y reversible. No toca el arranque, no inyecta nada en Explorer, no cambia
`Winlogon\Shell`, no escribe en `HKLM` ni modifica archivos del sistema.

- El instalador ofrece crear un **punto de restauración** y exporta a `.reg` cada clave que va a tocar.
- **Atajo de pánico: `Ctrl+Alt+Shift+R`**: cierra ii y devuelve la barra de tareas, los iconos y
  los colores de Windows.
- **Rescate**: menú Inicio > ii-windows > *Rescate de ii*. También funciona aunque ii esté colgado.
- Un proceso guardián restaura Windows si la shell muere.
- **Desinstalar** (menú Inicio o Configuración > Aplicaciones) deja Windows exactamente como estaba.

## Instalar

1. Descarga el `.zip` de la última versión en *Releases* y descomprímelo.
2. Doble clic en `install.cmd`. Pregunta antes de cada paso; no pide administrador salvo para el
   punto de restauración opcional.
3. ii arranca con Windows. Para quitarlo: *Desinstalar ii-windows*.

Requisitos: Windows 11 (probado en 24H2/25H2), x64.

## Compilar desde el código

Necesitas Visual Studio Build Tools 2022 (con clang-cl), Qt 6.12 MSVC y Python 3.

```powershell
git clone <este repo> ii-windows; cd ii-windows
git clone <fork de quickshell, rama windows> quickshell
git clone https://github.com/end-4/dots-hyprland upstream; git -C upstream checkout 33f31a08caddd41422a2d97670adeeb52b4f1e7c
. .\tools\dev\vsenv.ps1                                   # Qt desde $env:QTDIR
cmake -S quickshell -B quickshell\build -G Ninja; cmake --build quickshell\build
cmake -S host -B host\build -G Ninja; cmake --build host\build
.\tools\dev\stage-ii.ps1; .\tools\dev\deploy.ps1 -Full
.\tools\package\make-package.ps1                          # out\ii-windows-<versión>.zip
```

Cómo está hecho: [docs/DECISIONS.md](docs/DECISIONS.md). Pruebas en Windows Sandbox:
`tools\sandbox\sbx.ps1` y `tools\sandbox\tests`.

## Créditos y licencias

- **Illogical Impulse** (diseño, módulos QML, recursos): [end-4](https://github.com/end-4) y
  colaboradores, GPL-3.0. Este port se distribuye bajo **GPL-3.0** (ver [LICENSE](LICENSE)). El QML
  de ii no se edita: se copia tal cual y se le aplican parches pequeños y explícitos
  (`tools/port/`) más archivos propios de Windows (`overlay/`).
- **Quickshell**: [outfoxxed](https://git.outfoxxed.me/quickshell/quickshell) y colaboradores,
  LGPL-3.0. El fork para Windows conserva esa licencia y su código está publicado.
- **material-color-utilities** (Google, Apache-2.0), **Bibata Modern Classic** (GPL-3.0), las
  fuentes e iconos del dotfile: sus licencias van incluidas en el paquete (`licenses/`).
- Hecho por Carlos con Claude Code (Anthropic) y Codex (OpenAI).

## English summary

ii-windows runs end-4's Illogical Impulse shell (Quickshell/QML) natively on Windows 11 through a
Windows port of Quickshell: bar with a real system tray, launcher and window overview, dock with
live previews, sidebars, notifications, desktop widgets, Material 3 colours from the wallpaper that
Windows' own theme follows. It doesn't manage windows. Everything is per-user and reversible
(restore point, `.reg` backups, panic hotkey `Ctrl+Alt+Shift+R`, rescue shortcut, clean uninstall).
GPL-3.0; Quickshell fork LGPL-3.0. Credits above.
