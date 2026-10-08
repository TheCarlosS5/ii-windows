# Sidebar derecho en Windows

Inventario: 2026-10-08. Se leyó el staging antes de implementar. La tabla incluye el fallo inicial y el resultado del port; **implementado** no significa probado visualmente. No se ejecutaron ii-host, Quickshell ni Sandbox, ni se aplicaron rampas/planes en este PC.

| Control | Estado | Qué hace en Windows | Pendiente |
| --- | --- | --- | --- |
| Cabecera: sistema / uptime | Implementado; antes Linux/Unknown | Nombre/edición/build leídos de HKLM; MaterialSymbol desktop_windows (no hay logo Windows suelto en temas); uptime en tooltip | Ver texto largo/DPI |
| Cabecera: editar | Corregido | Añadir/quitar, cambiar tamaño, mover; filtra incompatibles conservando índices del Config original | Clic/rueda en ambos tamaños |
| Cabecera: recargar | Corregido | Sólo Quickshell.reload; se retiró hyprctl reload | Visual |
| Cabecera: ajustes | Existente | qs -p settings.qml mediante shim | Visual |
| Cabecera: sesión | Existente | Menú de sesión portado | Claude; no apagar este PC |
| Internet | Corregido | Native Wifi/NLM; Ethernet o sin adaptador abre ms-settings:network-status (Android y clásico) | Wi-Fi real |
| Bluetooth | No disponible, explícito | Toggle/Detalles abre ajustes Bluetooth; diálogo indica ausencia; no escribe en adaptador null | Backend real opcional; sin hardware aquí |
| Mantener despierto | Existente | IdleInhibitor de Windows | Suspensión/reanudación en Sandbox |
| EasyEffects | Oculto | Antes buscaba easyeffects/flatpak inexistentes | Sin equivalente integrado |
| Luz nocturna | Implementado; antes hyprsunset roto | Gamma por monitor en ii-host, horario de ii, readback y restauración | Driver/SDR y recuperación real |
| Modo oscuro | Existente | switchwall nativo y tema reversible en host | Visual |
| Cloudflare WARP | Oculto | Antes warp-cli por bash restringido | Cliente no garantizado |
| Modo juego | Redirigido | ms-settings:gaming-gamemode; sin cambios Hyprland | Visual |
| Recorte de pantalla | Redirigido | URI actual ms-screenclip://capture/image?rectangle | Recortes instalado/versión en hardware real |
| Selector de color | Oculto | Antes hyprpicker ausente | Captura de color no integrada |
| Teclado virtual | Redirigido | ms-settings:easeofaccess-keyboard para activar teclado de Windows | Visual |
| Micrófono | Protegido | Core Audio mute; desactivado sin entrada | Dispositivo ausente/presente |
| Audio | Protegido | Core Audio mute; desactivado sin salida | Dispositivo ausente/presente |
| Notificaciones | Existente | Silencia popups de ii, no No molestar global de Windows | Visual |
| Perfil de energía | Implementado; antes UPower vacío | powrprof: cicla Economizador/Equilibrado/Alto rendimiento sólo si existen; con <2 planes abre ajustes | Aplicación en Sandbox/Modern Standby |
| Reconocer música | Oculto | Antes songrec inexistente | Sin equivalente integrado |
| Anti-flashbang | Oculto | Antes shader/eventos Hyprland | Sin equivalente público sencillo |
| Diálogo Wi-Fi | Corregido | Escanear, conectar/desconectar, contraseña/portal por backend existente; vacío explícito; Detalles en ajustes | Wi-Fi/WPA reales; empresarial sigue pendiente |
| Diálogo Bluetooth | Corregido | No disponible + Detalles/Done; sin escaneo ni acceso null | Backend Bluetooth real no implementado |
| Diálogo audio / micro | Corregido | Volumen/mute por app Core Audio; selector abre ms-settings:sound | Cambio de dispositivo en ajustes; sin IPolicyConfig en este flujo |
| Diálogo luz nocturna | Implementado | Enable/Auto, horas desde/hasta, kelvin/gamma, valores efectivos y límite verificado; ajustes de pantalla | Intensidad aceptada por driver |
| Sliders rápidos | Corregido | Audio/micro sólo con endpoint; brillo físico oculto | DDC/CI futuro; gamma queda en diálogo |
| Lista de notificaciones | Existente | Listener Windows: cerrar, borrar todas, silenciar, abrir app | Acciones propias del toast siguen indisponibles |
| Calendario | Existente | Mes anterior/siguiente, hoy, navegación QML/JS | Visual/idioma |
| Tareas | Existente | Añadir, completar/reabrir, borrar; JSON/FileView | Persistencia en Sandbox |
| Pomodoro | Corregido | Iniciar/pausar/reset, notificación y MessageBeep de Windows; sin ffplay | Oír alarma en Sandbox |
| Cronómetro | Existente | Iniciar/pausar/reset/vueltas, Persistent | Visual/persistencia |
| Grupo inferior | Existente | Pestañas, Ctrl+PgUp/PgDown, colapsar/expandir | Visual |

## Luz nocturna y recuperación

`ii-shim nightlight <1200..6500> [25..100]`, `off`, `status`; `preview <kelvin> [gamma]` sólo calcula. WM_COPYDATA lleva nuestro protocolo a ii-host; el hilo GDI no bloquea el gancho de teclado. `--no-nightlight` desactiva soporte. Se exige guardián vivo; si termina, el host restaura/desactiva gamma.

Originales por **ID de interfaz del monitor**, antes de la primera escritura: `%LOCALAPPDATA%\ii-windows\gamma.bin`. Archivo temporal + FlushFileBuffers + MoveFileEx WRITE_THROUGH; mutex común a host/guard/rescate. Salida, pánico, muerte de la shell gestionada, guard y `--rescue` pasan por restoreAll. Heartbeat QML cada 5 s: si falta >15 s, restaura (temporizador de 1 s). `ii-rescue.ps1` restaura sin binarios. Backups corruptos bloquean nuevas aplicaciones; fallos de restauración/pantallas desconectadas conservan originales y el worker reintenta cada 5 s, también tras fallos temporales de lectura del backup. Si la recuperación inicial falla, el soporte permanece desactivado hasta reiniciar ii-host, aunque después logre restaurar los originales (comportamiento conservador). Pánico/Off cancelan el sondeo entre monitores/temperaturas para iniciar la restauración sin esperar toda la calibración.

El cálculo mantiene cada canal a ≤30000 unidades de la identidad y ganancias ≥0.55; mínimo matemático **3450 K**, gamma mínima efectiva depende de temperatura. No toca GdiIcmGammaRange ni otra clave HKLM. En la primera aplicación se prueba ese mínimo, aumentando de 100 en 100 K si Windows rechaza, y se lee cada rampa aplicada. `minimumKelvin` + `minimumVerified` informa el menor valor verificado para todas las pantallas presentes; es una búsqueda conservadora con resolución de 100 K, no un mínimo físico exacto. El diálogo muestra `✓` sólo después de readback. Si sólo acepta neutral, informa error en vez de fingir filtro activo.

La [API GDI](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-setdevicegammaramp) puede devolver TRUE sin aplicar; otras apps/calibración pueden sobrescribirla. HDR/advanced color se omite mediante QueryDisplayConfig/DisplayConfigGetDeviceInfo. No se fuerza HDR ni se promete efecto en él. La aceptación real y las rutas de recuperación todavía necesitan hardware/Sandbox de Claude. Errores: 1 host/guard ausente, 2 pantalla/lectura/HDR, 3 backup, 4 rampa rechazada, 5 restauración pendiente.

## Energía, archivos y comprobaciones

[PowerEnumerate/PowerGetActiveScheme/PowerSetActiveScheme](https://learn.microsoft.com/en-us/windows/win32/power/managing-power-schemes) manejan planes, no el overlay «modo de energía». No se usan llamadas privadas, no se crean planes ausentes ni se sustituyen planes personalizados al consultar. Cambiar/ciclar es acción explícita del usuario. `system-info` corrige ProductName Windows 10 a Windows 11 cuando build ≥22000; sólo lectura. Los [enlaces a ajustes](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings) y el [protocolo de Recortes](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-snipping-tool) son públicos.

Archivos: `host/src/nightlight.{h,cpp}`, `nightlight_core.cpp`, `nightlight_test.cpp`, `sidebar.cpp`; hooks mínimos en `main.cpp`/`desktop.cpp`, dispatch en `shim.cpp`, `host/CMakeLists.txt`; `patch_ii_sidebar.py`; overlay `nightLight/NightLightDialog.qml`; `ii-rescue.ps1`; `tools/dev/test-sidebar.ps1`. Staging ya tenía el hook de Claude; no se editó.

```powershell
. tools\dev\vsenv.ps1; cmake --build host\build
pwsh -NoProfile -File tools\dev\stage-ii.ps1
pwsh -NoProfile -File tools\dev\test-sidebar.ps1
```

Resultados: build/stage código 0; pruebas `sidebar failures=0`. 768 valores de identidad, rampas monotónicas/clamp, backup/lectura fallidos + off sin perder originales, guard ausente, cancelación de sondeo, originales calibrados, 2 monitores/hotplug/reconexión, rechazo silencioso y lease; planes listados con plan activo idéntico antes/después; Windows 11 Pro build 26200 leído; horario real JS/override/medianoche e índices de edición; C# de rescate compila sin ejecutarse; 77 archivos QML parseados con qmlformat sin arrancar shell; staging aislado con -Dest probado sin cambiar el staging principal. El aviso previo de vsenv («vswhere.exe» ausente) no impidió compilar. Un primer intento del formatter, antes de añadir DLLs CRT al PATH, abrió un diálogo de error de runtime; se detuvo inmediatamente. Las pruebas finales suprimen esos diálogos y lanzan sólo herramientas de consola.

Claude debe verificar Android/clásico, editar con toggles antiguos ocultos, diálogos y texto/DPI; conexión Wi-Fi, Bluetooth sin adaptador, audio desconectado/cambio de dispositivo; tareas/notificaciones/calendario/timers. En Sandbox/hardware autorizado: gamma en SDR/multimonitor, guardar/restaurar exactamente las rampas originales (incluida calibración), off, salida normal, pánico, matar host, matar guard, matar shell, rescate C++ y PowerShell con guard detenido, desconectar/reconectar, HDR y sleep/resume; planes reales y máquina que sólo tenga Equilibrado. No se acreditan aún estas pruebas visuales ni la temperatura mínima del driver de este PC.
