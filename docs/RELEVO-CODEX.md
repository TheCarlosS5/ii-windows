# Relevo de Claude Code a Codex

Fecha: 2026-10-07. Proyecto: `C:\Users\Calos\Desktop\ii-windows`.

## Punto de partida, antes de modificar código

Este documento y el commit que lo incorpora guardan el estado recibido de Claude.
La sesión importada se llama **Port Illogical Impulse a Windows 11**.

- Último commit del proyecto antes del relevo: `29a2a35` (overlay sin MangoHud y prueba de pantalla completa).
- Último commit de Quickshell antes del relevo: `44e50be` (notificaciones y esquinas durante pantalla completa).
- Claude dejó sin commit `quickshell/src/core/winapps.cpp`: soporte `winfile:` para iconos y miniaturas de archivos, con rutas codificadas en base64.
- Claude creó, sin conectar todavía al fondo ni a la configuración, `overlay/ii/modules/ii/background/widgets/desktop/DesktopIcons.qml`.
- Ese componente lee el Escritorio personal y público, ofrece selección, doble clic y un menú de abrir, mostrar en carpeta y copiar ruta. **Aún no está validado como parte de la shell.**
- Los dos cambios anteriores son trabajo heredado; el checkpoint los conserva tal como se recibieron.

Quickshell tiene su propio repositorio, ignorado por el repositorio principal. Su checkpoint es
`891e2880bc195fdf1931e15d42aace19727b3d86`. Ambos repositorios llevan la etiqueta
`checkpoint/claude-before-codex-2026-10-07`.

## Qué he comprobado en el checkpoint

- Leí el pedido original, los mensajes finales, `PROGRESS.md` y `docs/DECISIONS.md`.
- Revisé el diff heredado y la separación de los dos repositorios.
- `cmake --build quickshell\build` termina con código 0 (`ninja: no work to do`). Esto verifica el estado de la compilación local, **no** el comportamiento del nuevo widget.
- Los resultados anteriores de Sandbox descritos en `PROGRESS.md` corresponden a Claude; Codex todavía no los ha repetido.

## Desde dónde empiezo a modificar

Primer bloque: terminar la integración del escritorio que Claude inició, manteniendo el QML original y el overlay de Windows.

1. Añadir una prueba reproducible en Sandbox que arranque la shell y compruebe la presencia de archivos y carpetas de los Escritorios personal y público. Debe detectar que el widget todavía no está conectado.
2. Añadir las opciones `background.widgets.desktopIcons` y conectar el componente al fondo mediante los parches exactos de `tools/port/patch_ii.py`; no editar `upstream/` ni depender de cambios manuales en `build/ii`.
3. Corregir solo los problemas del widget que esas pruebas reproduzcan: carga QML, nombres Unicode, iconos, selección, apertura, menú y actualización de carpetas.
4. Comprobar visualmente la convivencia con el reloj, el dock y Win+D; repetir las pruebas de recuperación del host antes de declarar este bloque terminado.
5. Actualizar `PROGRESS.md` con resultados y límites concretos y guardar el avance en otro commit local, separado del checkpoint.

Luego seguir las prioridades ya elegidas: dock, overlays y widgets; tematización e instalador después. Un commit de avance no significa que el port completo esté terminado.

## Reglas que se mantienen

- Quickshell real + Qt + QML de ii; Windows mantiene el manejo de sus ventanas.
- Sin tiling, inyección en Explorer, reemplazo de `Winlogon\Shell` ni modificaciones de archivos del sistema.
- Pruebas de ocultación del escritorio y barra solo en Windows Sandbox.
- Mantener guardián, atajo de pánico y rescate; no instalar la shell en la sesión personal durante este bloque.
- No tocar arranque, BIOS, bootloader, políticas de seguridad ni HKLM sin autorización expresa.
- Conservar atribución y licencias; cambios locales, sin publicar ni enviar a ningún remoto.

## Cómo localizar y recuperar la versión guardada

Desde el proyecto:

```powershell
git show checkpoint/claude-before-codex-2026-10-07 --stat
git -C quickshell show checkpoint/claude-before-codex-2026-10-07 --stat
```

Para volver al checkpoint, guardar primero cualquier trabajo posterior y cambiar **ambos** repositorios a esa etiqueta con `git switch --detach checkpoint/claude-before-codex-2026-10-07` (en Quickshell: `git -C quickshell switch --detach ...`). Git bloqueará el cambio si sobrescribiría archivos modificados. Después recompilar, ejecutar `tools/dev/deploy.ps1` y `tools/dev/stage-ii.ps1`.

Los directorios generados (`build/`, `dist/`) y dependencias descargadas no se incluyen en Git. Las etiquetas conservan las fuentes, no una imagen del Sandbox ni un instalador terminado.
