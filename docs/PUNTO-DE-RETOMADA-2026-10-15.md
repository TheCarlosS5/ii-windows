# Punto de retomada (2026-10-15, noche)

Rama `ux/feedback-round` (repo ii-windows) y rama `windows` del fork `quickshell`. **Nada subido ni publicado.** Lo hecho: `docs/RONDA-2026-10-15.md` (primera) y `docs/RONDA-2026-10-15-noche.md` (bandeja, dock, vista general, volumen, fondos animados). En el PC de Carlos corre ahora la **shell de desarrollo** (runtime privado) con todo esto; el instalado sigue siendo la 0.3.0 `5b1d7b3`, con la 0.2.0 de vuelta atrás.

## Pendiente

1. **Revisión** del diff completo de esta noche (commits `6717bc5`..`15bf9f0` en la rama, `5e81509` en el fork) antes de empaquetar.
2. **Probar con Wallpaper Engine y Lively de verdad** (Lively es gratis: `winget install rocksdanister.LivelyWallpaper`; **preguntar a Carlos** antes de instalarlo). Ver "No se pudo comprobar" en la ronda de la noche: el formato de sus archivos está escrito de la documentación.
3. Que Carlos pase el dock rápido con varias apps abiertas (tirones) y lo diga si siguen.
4. Escala 1,25, Win+Tab en pantalla, clic derecho/central en la bandeja, portátil real (batería, brillo, GPU híbrida), Gemini con clave real, nombre del entorno.
5. Detalles: icono genérico del cliente de Steam en el dock; selector de proyectos de Wallpaper Engine/Lively dentro de ii (no se hizo, se acordó "convivir + paleta"); fondos distintos por monitor; atajo propio para la tienda; actualizador incremental.
6. Cuando Carlos lo apruebe: empaquetar (`make-package.ps1`, `test-install`), subir la rama y publicar 0.3.0 (**preguntar antes**).

## Cómo trabajar

`pwsh tools/dev/redev.ps1 [-Scale 1.5]` (para ii, prepara el QML con `stage-ii.ps1`, comprueba que carga y arranca en el runtime privado). Host: `. tools\dev\vsenv.ps1; cmake --build host\build` y `make-devrt.ps1`. Fork: `cmake --build quickshell\build` y `make-devrt.ps1 -NewQuickshell`. Esquema de opciones: `python -I tools/dev/gen-config-schema.py --stage build/ii` tras tocar `Config.qml` (y recompilar el host). Parches en `tools/port/patch_ii_*.py` (los de esta noche en `patch_ii_ux3.py`); escribirlos con Write/Edit, no con heredocs. Registro del shell: `%TEMP%\quickshell\by-pid\<pid>\log.log` (buscar `ReferenceError`). Memoria: `ii-windows-ux-round.md`.
