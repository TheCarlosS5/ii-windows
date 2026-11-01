# 07 · Bloque F — Integraciones nuevas con Windows (catálogo)

> **En simple:** cosas de Windows que ii puede mostrar o controlar desde su barra, sus paneles o la búsqueda. Todas por
> usuario, sin administrador salvo donde se indica, sin inyectar nada en Explorer y reversibles (las reglas de siempre,
> `docs/LO-QUE-QUEDA-DE-WINDOWS.md`).

Leyenda de riesgo: **bajo** = API documentada · **medio** = API documentada pero delicada o que depende del hardware ·
**alto** = interfaz no documentada (aislar en `ii-shim`, comprobar la build, apagar si falla).

| # | Integración | Dónde se ve | API / mecanismo | Permisos | Riesgo | Esfuerzo | Prioridad · versión |
|---|---|---|---|---|---|---|---|
| F1 | **Indicadores de micrófono, cámara y ubicación en uso** | Píldora en la barra | `CapabilityAccessManager\ConsentStore` + `RegNotifyChangeKeyValue` ([E10](06-plus.md#e10)) | Usuario | Bajo | S | **P1 · 0.7.0** |
| F2 | "Windows necesita reiniciar" (actualizaciones de Windows) | Píldora suave + menú de sesión | COM `Microsoft.Update.SystemInfo` → `RebootRequired` | Usuario | Bajo | S | P2 · 0.8.0 |
| F3 | **Apps con actualizaciones (winget)** + "Actualizar todo" | Tienda de ii, insignia en su icono | `winget upgrade` (la tienda ya usa winget); `--scope user` cuando se pueda; avisar que las de toda la máquina piden UAC | Usuario/UAC | Medio | M | P2 · 0.8.0 |
| F4 | Ahorro de energía de Windows 11 (estado y botón) | Ajustes rápidos | `ms-settings:batterysaver` siempre; estado con `PowerGetEffectiveOverlayScheme`; cambiarlo con `PowerSetActiveOverlayScheme` (comprobar en 25H2) | Usuario | Medio | S | P2 · 0.8.0 |
| F5 | No molestar de Windows sincronizado con el de ii | Ajustes rápidos | Hoy ii apaga banners por app (D12). Investigar si hay forma documentada de leer/poner el DND de Windows 11; si no, solo enlace a `ms-settings:notifications` | Usuario | Alto | M | P3 |
| F6 | HDR encendido/apagado (gamers) | Ajustes rápidos | `DisplayConfigSetDeviceInfo` con `DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE` | Usuario | Medio | S | P3 · 0.9.0 |
| F7 | Frecuencia de la pantalla (144 ↔ 60 Hz en portátiles con batería) | Ajustes rápidos / modos (E2) | `EnumDisplaySettingsEx` + `ChangeDisplaySettingsEx` | Usuario | Medio | S | P3 · 0.9.0 |
| F8 | Escala y resolución rápidas | Menú de la pantalla | `ms-settings:display` + DisplayConfig | Usuario | Medio | S | P3 |
| F9 | **Batería de dispositivos Bluetooth** | Menú Bluetooth, aviso < 20 % | Propiedad de batería del nodo del dispositivo ([E5](06-plus.md#e5)) | Usuario | Medio | S | P2 · 0.9.0 |
| F10 | **Salida de audio en 1 clic** y micrófono global | Barra | `IMMDeviceEnumerator`, `IAudioEndpointVolume`; predeterminado con `IPolicyConfig` (no documentada) | Usuario | Alto (solo el cambio de predeterminado) | M | P2 · 0.9.0 |
| F11 | Zona Wi-Fi (hotspot) | Ajustes rápidos | `NetworkOperatorTetheringManager` (comprobar si funciona sin identidad de paquete); si no, `ms-settings:network-mobilehotspot` | Usuario | Medio | S | P3 |
| F12 | Compartir Wi-Fi por QR | Menú Wi-Fi | `WlanGetProfile` con `WLAN_PROFILE_GET_PLAINTEXT_KEY` (comprobar si basta usuario normal; si pide admin, no) + generar QR | Usuario | Medio | S | P3 |
| F13 | VPN integradas de Windows | Ajustes rápidos | `RasEnumEntries` / `rasdial`; WireGuard/Tailscale si están instalados (su CLI) | Usuario | Medio | M | P3 |
| F14 | Poco espacio en disco | Aviso + "Liberar espacio" | `GetDiskFreeSpaceExW` cada hora; `ms-settings:storagesense` | Usuario | Bajo | S | P3 · 0.8.0 |
| F15 | **Búsqueda de archivos del índice de Windows** | "Buscar todo" ([E1](06-plus.md#e1)) | OLE DB `Search.CollatorDSO` / Everything IPC | Usuario | Bajo | M | P2 · 1.0 |
| F16 | Listas de salto (recientes por app) | Clic derecho en el dock | `IApplicationDocumentLists` | Usuario | Bajo | S | P2 · 0.9.0 |
| F17 | Apps que piden atención | Dock | `RegisterShellHookWindow` → `HSHELL_FLASH` ([E6](06-plus.md#e6)) | Usuario | Bajo | S | **P2 · 0.8.0** |
| F18 | Papelera en el dock | Dock | `SHQueryRecycleBinW`, `SHEmptyRecycleBinW` | Usuario | Bajo | S | P2 · 0.9.0 |
| F19 | Alto contraste de Windows | Toda la interfaz | `SystemParametersInfo(SPI_GETHIGHCONTRAST)` + `WM_SETTINGCHANGE` → paleta de alto contraste de ii | Usuario | Bajo | M | P2 · 0.9.0 (ver H3) |
| F20 | Tamaño de texto de Windows (Accesibilidad > Tamaño del texto) | Toda la interfaz | `HKCU\Software\Microsoft\Accessibility\TextScaleFactor` → escala de fuentes de ii | Usuario | Bajo | S | P2 · 0.9.0 |
| F21 | Grabación de pantalla | Botón en utilidades / búsqueda | Recortes de Windows (atajo o `ms-screenclip:`) ([E7](06-plus.md#e7)) | Usuario | Bajo | S | P2 · 0.9.0 |
| F22 | Fondo por escritorio virtual | Selector de fondos | `IVirtualDesktopManagerInternal::SetWallpaper` ([E13](06-plus.md#e13)) | Usuario | Alto | S | P3 · 1.0 |
| F23 | Multi-monitor y DPI por monitor | Barra, dock, widgets | Ya hay ventanas por monitor; falta la prueba sistemática (G7) y opciones por monitor (barra en todos / solo principal; dock en el principal) | Usuario | Medio | M | **P1 · 0.8.0** |
| F24 | Modo presentación / compartir pantalla | No molestar automático (E2/E12) | `SHQueryUserNotificationState` = `QUNS_PRESENTATION_MODE`, y apps de reunión al frente | Usuario | Bajo | S | P2 · 0.9.0 |

### Notas para quien implemente
- Cada integración con API no documentada (F10 predeterminado, F22, y las de escritorios virtuales que ya existen) vive
  en `ii-shim` o en un módulo aislado, **comprueba la build de Windows** antes de usar los IID y, si algo no cuadra,
  se apaga sola y lo dice en el log (nunca crashea la shell: ver A6).
- Todo lo que cambie un ajuste de Windows guarda el valor original y lo restaura al salir de ii, como ya hace
  `ii-ownership.ps1`/`state.ini` (D22: "cada cambio externo guarda original/aplicado/dueño").
- Lo que no se puede hacer por usuario y sin inyectar nada (por ejemplo, el aviso de brillo del portátil) sigue en
  `docs/LO-QUE-QUEDA-DE-WINDOWS.md`, que se actualiza con cada integración nueva (F1 añade una fila: "Indicadores de
  privacidad: ✅ propios").
