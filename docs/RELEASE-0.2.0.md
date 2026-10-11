# ii-windows 0.2.0 (estable) — notas

Paquete: `out\ii-windows-0.2.0-<fecha>-<commit>.zip` (`tools\package\make-package.ps1`). **No publicado** en ningún sitio: es un archivo local.

## Qué está comprobado y dónde

Probado en **un PC de escritorio** (Windows 11 build 28000, 1 monitor 1920x1080 al 125 %, GPU integrada/única, sin batería): instalado sobre la instalación real del usuario (desde la 0.1.3 «plana», con vuelta atrás a ella), arrancó y quedó **verificada** por el lanzador en el primer arranque real; la shell en marcha con barra, widgets, bandeja, notificaciones de Windows (`health: notifications available`), escritorios virtuales y el panel izquierdo (IA, Anime, traductor).

**No probado:** portátiles (batería, brillo, tapa, Modern Standby, GPU híbrida, pantalla táctil/touchpad), varios monitores, otros builds de Windows 11, RDP, usuario estándar sin permisos para la tarea de inicio. El código para esos casos existe (ver `docs/HARDWARE-SERVICES.md`) pero **no está verificado en hardware**: tratar un portátil como «instalable y reversible, sin garantías de hardware» hasta que alguien lo pruebe.

## Cambios desde 0.1.3

- Todo lo de `TASKS_ii_windows.md` marcado en la sección 15 (B00–B02, R01–R09, R11, P04, P11, P12, P15, C12, U01/U02, D01, F01…) con su estado y límites reales en `docs/seguimiento/`.
- **Runtime versionado con vuelta atrás:** el lanzador (`ii-launcher.exe`) elige la versión activa, la marca *verificada* al primer arranque bueno y vuelve a la anterior (o a la 0.1.3 plana) si no arranca. Esto funcionó de verdad: un primer paquete salió sin una carpeta del QML de upstream (el submódulo `shapes` sin inicializar), el lanzador lo detectó (3 intentos) y devolvió al usuario a su versión anterior sin intervención.
- **Panel izquierdo (IA/Anime) que se cerraba con cualquier clic:** la región de entrada de un panel con máscara se calculaba solo con la geometría propia del elemento; los paneles se deslizan con una `Translate` (parche de animación), así que la región quedó fuera de la ventana y todo el panel era transparente a los clics: el clic caía a la ventana de abajo y el «focus grab» cerraba el panel. Ahora la región se compara en cada fotograma de animación (`PendingRegion`, fork). Prueba de regresión: `test-input-region` (falla con el binario anterior, pasa con el nuevo).
- **Cuelgue intermitente al arrancar la shell** (≈1 de cada 7 arranques en frío, también en la 0.1.3): un volcado de pila mostró un auto-bloqueo en `WindowTracker::instance()` (la inicialización estática esperándose a sí misma mientras el constructor llama a Explorer por COM y recibe un evento). Corregido; 0 cuelgues en 24 arranques en frío tras el cambio.
- `stage-ii.ps1` **se niega a preparar** un ii cuyos imports no resuelven (`check-qml-imports.py`) y `smoke-shell.ps1` carga la shell real con el QML real; `deploy.ps1` ya no depende de la ruta de Visual Studio.
- Limpieza automática de escritorios vacíos: ahora es opt-in, con interruptor en Ajustes y con comprobaciones antes de borrar (R09).
- `config.json`: copia de seguridad antes de reparar, última copia buena, exportar/importar sin credenciales (`docs/CONFIGURACION.md`).

## Cómo volver atrás

- Menú Inicio > ii-windows > **Rescate de ii**, o Ctrl+Alt+Shift+R con ii en marcha.
- Versiones anteriores: `%LOCALAPPDATA%\Programs\ii-windows\versions\` y `current.txt` (`previous=`); la 0.1.3 plana sigue en la carpeta de instalación mientras sea `previous=legacy`.
- Copia completa previa de esta actualización en el PC probado: `C:\Users\Admin\ii-live-backup-20261011\` (instalación, datos y configuración).

## Conocido / pendiente

- El **inicio con Windows** sigue siendo el de la 0.1.3 (tarea `ii-windows` con la ruta plana); migrarlo a la tarea por usuario del lanzador pide permiso de administrador una vez (`install.ps1` sin `-NoAutostart`). Hasta entonces, tras reiniciar sesión arrancaría la 0.1.3 plana.
- La **IA** necesita su clave (`/key` en el panel); Gelbooru también. Sin clave el panel lo dice. No se probó una conversación real con un proveedor (no hay claves en esta máquina).
- El primer arranque de una versión nueva tarda ~20 s (se compila la caché de QML y Windows analiza los archivos nuevos); los siguientes ~3–10 s.
- Lo marcado `IMPLEMENTADA_SIN_VALIDAR_WINDOWS` en el seguimiento sigue sin validación de extremo a extremo (p. ej. Win+L real, RDP, segundo usuario).
