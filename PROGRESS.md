# PROGRESS

Port de la interfaz de [Illogical Impulse](https://github.com/end-4/dots-hyprland) (end-4) a Windows 11.
Documentos: [Viabilidad](docs/FEASIBILITY.md) · [Decisiones](docs/DECISIONS.md)

## Estado: Hito 1 (viabilidad) ✅ — siguiente: Hito 2 (cimientos)

### Hecho
- [x] Clonado `end-4/dots-hyprland` @ `33f31a0` en `upstream/` e inventariados sus módulos.
- [x] Herramientas instaladas, todas oficiales y desinstalables:
  - VS Build Tools 2022 (MSVC + clang-cl + Windows SDK): *Configuración → Aplicaciones*.
  - Qt 6.12.0 en `C:\Users\Calos\dev\Qt` (borrar la carpeta para quitarlo).
  - CMake, Ninja y aqtinstall con `pip --user`.
  - CLI11 en `C:\Users\Calos\dev\deps`.
- [x] Punto de restauración "ii-windows: before dev tools" y Windows Sandbox activado (**falta reiniciar el PC**).
- [x] Prototipo B (web/Electron): funciona, pero se descarta por 308 MB de RAM y la reescritura total.
- [x] Quickshell compilado para Windows: fork en `quickshell/` (rama `windows`, 2 commits sobre upstream).
- [x] Backend `src/win32`: `PanelWindow`, capas, AppBar, clic-a-través y cesión ante apps a pantalla completa.
- [x] Prototipo A (barra estilo ii): reserva de espacio, esquinas redondeadas transparentes con clic-a-través y desenfoque xray. 131 MB, ~2 % de CPU.

### Pendiente (Hito 2: cimientos)
- [ ] Reiniciar el PC para activar Windows Sandbox *(tú)*.
- [ ] `ii-windows-rescue`: script de recuperación independiente + atajo de pánico.
- [ ] Ocultar la barra de tareas (todas las pantallas) con vigilante de reinicio de Explorer, y su camino de vuelta.
- [ ] Ocultar iconos del escritorio y capa de fondo propia (verificar `Progman/WorkerW` en 25H2).
- [ ] Hook de teclado: tecla Windows → launcher, sin tocar Win+L / Ctrl+Alt+Supr.
- [ ] Neutralizar `SW_HIDE` del primer `ShowWindow` dentro del backend.
- [ ] Exportar a `.reg` las claves antes de tocarlas.

### Hitos siguientes
3. ii arrancando (shims Hyprland/Wayland; barra, overview y ajustes rápidos) · 4. Servicios · 5. Dock, overlays y widgets · 6. Temas, fuentes, iconos y cursor · 7. Instalador, multimonitor, sleep · 8. Documentación.

## Cómo probar cada hito

### Hito 1 — prototipo de barra (seguro: no toca nada del sistema)
```powershell
pwsh -File C:\Users\Calos\Desktop\ii-windows\prototypes\qs-bar\check.ps1
```
Durante 25 s aparece una barra arriba. El script imprime el área de trabajo antes, durante y después (`0,40` mientras corre y `0,0` al terminar), a quién llega el clic en la barra y en las esquinas (deben atravesar), la RAM y la CPU. Deja una captura en `prototypes/qs-bar/shot-top.png`.

### Compilar
```powershell
. C:\Users\Calos\Desktop\ii-windows\tools\dev\vsenv.ps1
cmake --build C:\Users\Calos\Desktop\ii-windows\quickshell\build
```

## Problemas conocidos
- La salida de `cmd` llega en CP850 a `Process` (se ve `Versi�n`). Se arreglará al lanzar procesos con UTF-8.
- Si la shell se cierra de golpe, una AppBar podría dejar el área de trabajo reducida hasta reiniciar Explorer. El script de rescate lo cubrirá.
