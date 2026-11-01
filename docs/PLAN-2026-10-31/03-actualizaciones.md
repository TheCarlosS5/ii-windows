# 03 · Bloque B — Actualizaciones: "Hay una versión nueva de ii"

> **En simple:** ii mira de vez en cuando en GitHub si salió una versión nueva. Si la hay, te avisa con una notificación
> y un puntito en la barra; tú decides: **Actualizar**, **Ver novedades** o **Más tarde**. La descarga se comprueba
> (firma y huella) antes de tocar nada, se instala al lado de la actual sin borrarla, y si la nueva no arranca ii vuelve
> sola a la anterior. Nunca se actualiza sin permiso, nunca durante un juego y nunca con datos móviles.
>
> La parte difícil (instalar al lado y volver atrás) **ya existe y está probada**: `versions\<id>`, `current.txt`,
> `ii-launcher`, `Install-IiRuntime`, `Invoke-IiRollback`. Falta: buscar, avisar, bajar, verificar y la interfaz.

Diseño previo: `docs/AUTOACTUALIZADOR.md` (se mantiene y se amplía aquí). Todo va en la **0.7.0** (B12 explica el paso
desde la 0.6.x).

---

## B0 · Lo que ya hay (y se reutiliza)

| Pieza | Dónde | Estado |
|---|---|---|
| Versiones lado a lado, puntero atómico, *pending → verified*, vuelta atrás | `tools/package/ii-runtime.ps1`, `host/src/rollout.*`, `host/src/launcher.cpp` | ✅ probado (`test-runtime`, `test-install-flow`) |
| Manifiesto SHA-256 de cada archivo del paquete | `payload.manifest` (lo exige el instalador) | ✅ |
| Datos de la versión | `app\build-info.json`, `app\VERSION` | ✅ |
| Cliente HTTPS (WinHTTP, redirecciones validadas, proxy automático) | `host/src/http.cpp` | ⚠️ solo en memoria con tope de 40 MB, sin `Range`, sin cabeceras propias, sin progreso |
| JSON | `host/src/jsonlite.*` | ✅ |
| Saber si hay un juego al frente | `gameInFront()` en `main.cpp` | ✅ |
| Avisar a la shell | `tellUserThroughShell()` (sumidero de notificaciones) | ⚠️ sin botones de acción |
| Página "Acerca de" con versión | `modules/settings/About.qml` (lee `build-info.json`) | ✅ base para la tarjeta |

---

## B1 · Cambios en cómo se publica una versión

Cada release de GitHub llevará, además del `.zip` y el Setup:

1. **`release.json`** (pequeño, lo primero que baja ii):
   ```json
   {
     "schema": 1,
     "version": "0.7.0",
     "id": "0.7.0-20261108-abc1234",
     "channel": "stable",
     "publishedAt": "2026-11-08T22:00:00Z",
     "minFrom": "0.6.0",
     "critical": false,
     "package": { "name": "ii-windows-0.7.0-20261108-abc1234.zip", "size": 93842699, "sha256": "…" },
     "setup":   { "name": "ii-windows-Setup-0.7.0-20261108-abc1234.exe", "size": 57888548, "sha256": "…" },
     "deltas":  [ { "from": "0.6.1-20261102-def5678", "name": "ii-windows-delta-…zip", "size": 2400000, "sha256": "…" } ],
     "needsInstaller": false,
     "notes": { "es": "## Novedades\n- …", "en": "## What's new\n- …" },
     "notesUrl": "https://github.com/TheCarlosS5/ii-windows/releases/tag/v0.7.0"
   }
   ```
   - `critical: true` = arreglo de un crash o de seguridad: el aviso dice "Recomendada" y se repite cada día.
   - `needsInstaller: true` = la versión cambia cosas que solo hace el instalador completo (accesos del menú Inicio,
     tarea de inicio, fuentes, cursor): el actualizador corre el instalador del paquete en modo silencioso (B5).
2. **`release.json.sig`**: firma **ECDSA P-256** (64 bytes r‖s, en base64) de los bytes exactos de `release.json`.
   - La clave privada **nunca** va al repo: `%USERPROFILE%\.ii-release-key\private.pkcs8` con copia en un USB.
   - `tools/package/sign-release.ps1` (PowerShell 7 / .NET: `[System.Security.Cryptography.ECDsa]::Create()`,
     `ImportPkcs8PrivateKey`, `SignData($bytes, 'SHA256')` → formato IEEE P1363, que es justo el r‖s que espera BCrypt).
   - `ii-host` lleva **dos** claves públicas embebidas (actual + respaldo) para poder rotar.
   - Es gratis y no depende de comprar un certificado de firma de código (1.4 sigue pendiente; esto protege las
     actualizaciones mientras tanto, incluso si alguien roba el token de GitHub).
3. **`tools/package/publish-release.ps1`** (nuevo): crea la release por la API (el token de `git credential fill`, como
   hasta ahora), sube zip, Setup, `release.json`, `.sig`, el zip de símbolos (A3) y `release-check.md`; `-Beta` la marca
   como *prerelease*. Comprueba antes que el `sha256` de `release.json` coincide con los archivos que sube.
4. `make-package.ps1` escribe `release.json` (sin firmar) con tamaños y hashes; `release-check.ps1 -Strict` falla si
   falta o no coincide.

---

## B2 · Buscar actualizaciones (en `ii-host`)

**Archivos nuevos:** `host/src/updater.cpp`, `host/src/updater.h` (y pruebas `host/src/updater_test.cpp`).
**Por qué en el host y no en la shell:** no abre consolas, ya sabe de juegos, sesión bloqueada y energía, sigue vivo si
la shell se cae, y la shell solo muestra.

- **Cuándo:** 2 min después de que la shell esté lista; luego cada 6 h ± 30 min al azar; y a pedido (botón "Buscar
  ahora" o IPC). **Nunca** con: juego al frente (`gameInFront()`), sesión bloqueada, conexión medida
  (`Windows.Networking.Connectivity.NetworkInformation::GetInternetConnectionProfile().GetConnectionCost()`, tipo
  `Fixed`/`Variable` o `Roaming`), ahorro de energía activo, o la opción apagada.
- **Cómo:** `GET https://api.github.com/repos/TheCarlosS5/ii-windows/releases?per_page=10` con
  `Accept: application/vnd.github+json`, `User-Agent: ii-windows/<versión>` e `If-None-Match: <etag guardado>`.
  - `304` = nada nuevo (no gasta el límite de 60 consultas/hora sin token).
  - `403/429` = esperar lo que diga `Retry-After` / `X-RateLimit-Reset`.
  - Elegir la release más nueva del canal (estable: `prerelease == false`; beta: cualquiera) que tenga `release.json`.
  - Bajar `release.json` + `.sig` (≤ 64 KB), **verificar la firma** (BCrypt: `BCRYPT_ECDSA_P256_ALGORITHM`,
    `BCryptImportKeyPair(BCRYPT_ECCPUBLIC_BLOB)`, SHA-256, `BCryptVerifySignature`). Sin firma válida: se ignora y se
    registra `update: release.json de vX sin firma válida`.
  - Comparar versiones: semver de `version` contra la base de `build-info.json` (`0.6.0` de `0.6.0-20261025-6d92550`);
    nunca ofrecer una más vieja (protección contra *downgrade*), ni una que el usuario marcó "Omitir esta versión", ni
    una con `minFrom` mayor que la actual (entonces: "Descarga el instalador desde GitHub").
- **Estado** en `%LOCALAPPDATA%\ii-windows\update\state.json` (escritura atómica: temporal + `MoveFileEx`):
  ```json
  {"schema":1,"status":"available","current":"0.6.1-20261102-def5678","channel":"stable",
   "latest":{"version":"0.7.0","id":"0.7.0-20261108-abc1234","size":93842699,"critical":false,
             "notes":"## Novedades…","publishedAt":"2026-11-08T22:00:00Z"},
   "progress":{"bytes":0,"total":0},"lastCheck":"2026-11-09T14:02:11Z","error":null,"skipped":[]}
  ```
  `status`: `idle | checking | available | downloading | paused | verifying | ready | installing | installed | error`.
- **Ampliar `http.cpp`:** `Client::request(url, headers, out*)` que devuelve estado, cabeceras (`ETag`, `Retry-After`) y
  cuerpo; y `Client::download(url, path, expectedSize, sha256, progress, cancel)` (B4). Mantener las reglas actuales
  (solo HTTPS, redirecciones validadas). Lista de hosts permitidos para el actualizador: `api.github.com`, `github.com`,
  `objects.githubusercontent.com`, `release-assets.githubusercontent.com` (donde GitHub redirige los assets).

---

## B3 · Avisar al usuario (la parte que pidió Carlos)

### Canal host → shell
Nuevo mensaje por el sumidero que ya existe (`IiShellNotificationSink`, `WM_COPYDATA`): `dwData = 0x49490030`,
"update-state", con el JSON de `state.json`. En el fork, un *singleton* `IiHost` (C++, en `src/win32/services/`) que
emite `message(type, json)`; en QML, `services/Updates.qml` (Singleton) con propiedades `status`, `latest`, `progress`,
`canInstall`, y funciones `check()`, `download()`, `installNow()`, `installLater()`, `skip()`, `rollback()` que llaman al
host (`ii-shim update <acción>` → `WM_COPYDATA` al host; sin consola).

### Lo que se ve

1. **Notificación de ii** (con botones; las notificaciones propias de la shell sí pueden tener acciones):
   ```
   ┌──────────────────────────────────────────────────────────┐
   │ ⬆  Hay una versión nueva de ii: 0.7.0                     │
   │    Actualizaciones automáticas, Configuración más rápida │
   │    y arreglos. Pesa 89 MB.                                │
   │    [ Actualizar ]   [ Novedades ]   [ Más tarde ]         │
   └──────────────────────────────────────────────────────────┘
   ```
   "Más tarde" la pospone 24 h. Una versión `critical` dice "Recomendada: arregla cierres inesperados".
2. **Puntito** en el botón del panel derecho de la barra (y en "Junto al dock") mientras haya una versión disponible o
   lista para instalar. Tooltip: "Actualización lista: 0.7.0".
3. **Tarjeta en el panel derecho** (arriba, plegable): estado y botón principal ("Actualizar" / barra de progreso
   "Descargando 45 %" / "Reiniciar ii para terminar").
4. **Configuración > Actualizaciones** (página nueva, ver [C1](04-configuracion.md#c1)):
   ```
   Versión instalada   0.6.1 (2 nov 2026)                  [ Buscar ahora ]
   ┌ Hay una versión nueva ─────────────────────────────────────────────┐
   │ 0.7.0 · 8 nov 2026 · 89 MB                                         │
   │ ## Novedades (Markdown de release.json)                            │
   │ [ Descargar e instalar ]  [ Omitir esta versión ]  [ Ver en GitHub ]│
   └────────────────────────────────────────────────────────────────────┘
   ☑ Buscar actualizaciones automáticamente
   ☑ Descargar solo con Wi-Fi o cable (nunca con datos medidos)
   ○ Avisarme con una notificación   ○ Solo el puntito en la barra
   Canal:  (•) Estable   ( ) Beta (versiones de prueba, para testers)
   Al terminar de descargar:  (•) Instalar al reiniciar ii   ( ) Preguntarme
   Historial: 0.6.1 instalada 02/11 · 0.6.0 instalada 25/10      [ Volver a la 0.6.0 ]
   ```
5. **"Acerca de"**: debajo de la versión, una línea con el estado ("Estás al día" / "Hay una versión nueva") que lleva a
   la página de Actualizaciones.
6. **Novedades después de actualizar:** al primer arranque de la versión nueva, una ventana "Novedades de ii 0.7.0" con
   el Markdown de las notas (`Text.MarkdownText`), imágenes opcionales y "Ver todo en GitHub". Se puede reabrir desde
   Acerca de.

---

## B4 · Descargar

- `http::Client::download()` escribe a `update\<id>\<archivo>.part` en bloques de 256 KB, con `Range: bytes=<n>-` e
  `If-Range: <etag>` para **reanudar** si se corta (o si se apaga el PC); al terminar renombra a `<archivo>`.
- Hilo propio con prioridad de E/S baja (`THREAD_MODE_BACKGROUND_BEGIN`); se **pausa** solo si aparece un juego o la
  conexión pasa a medida, y sigue después.
- Espacio: `GetDiskFreeSpaceExW` ≥ 3 × tamaño del paquete; si no, estado `error` con "Libera X GB".
- Progreso en `state.json` cada 1 s (no más) → la tarjeta lo muestra.
- Si la API trae `digest` (SHA-256) en el asset, se compara también; la referencia es `release.json` firmado.

## B5 · Verificar e instalar

1. SHA-256 del zip (BCrypt) = `release.json`. Si no: borrar y `error` ("La descarga llegó dañada; se reintentará").
2. Extraer con `C:\Windows\System32\tar.exe -xf <zip> -C update\<id>\pkg` (incluido en Windows 10 1803+/11;
   `CREATE_NO_WINDOW`). Alternativa robusta si `tar` diera problemas: enlazar *minizip-ng* (licencia zlib) en el host.
3. `app\build-info.json` debe decir el mismo `id` que `release.json`; `app\payload.manifest` debe cuadrar archivo por
   archivo (misma lógica que `Test-IiPayload`, portada a C++ en `host/src/runtime.cpp`).
4. **Instalar sin PowerShell** cuando `needsInstaller` es `false` (lo normal): portar a C++ los 4 pasos de
   `Install-IiRuntime` (copiar a `versions\<id>.staging-<txn>`, verificar, `MoveFileEx` atómico, `current.txt` con
   `pending`), con el mismo `journal.txt` para recuperarse de un corte. Motivo: hay PCs (empresas, colegios) donde
   PowerShell está bloqueado, y así no se abre ninguna consola.
5. Con `needsInstaller: true`: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <pkg>\install.ps1 -Yes
   -NoAutostart -Update` oculto, con `PSModulePath` vacío en el entorno (lección de `setup.iss`), y su salida a
   `update\<id>\install.log`. `-Update` (nuevo) salta copia del registro, cursor, fuentes y punto de restauración si no
   cambiaron.
6. Estado `ready` → "Reiniciar ii para terminar".

## B6 · Aplicar

- **Por defecto: al reiniciar.** Como queda `pending` en `current.txt`, el próximo arranque (inicio de sesión o
  "Reiniciar ii") ya usa la nueva, y `ii-launcher` vuelve sola a la anterior si no llega a `ready` (A7). Cero
  interrupciones.
- **"Instalar ahora":** el host pide a la shell guardar estado (posiciones del escritorio, notas), muestra la portada
  "Actualizando ii a 0.7.0…" (etapas de `splash.cpp`), lanza `ii-launcher.exe --after-update` desacoplado y sale con
  código 20. El *launcher* arranca la versión nueva. Nada se sobrescribe en uso: cada versión vive en su carpeta.
- Después de `verified` (A7): borrar descargas de `update\` y versiones viejas (conservar 2), en nativo.

## B7 · Volver atrás desde la interfaz
Botón "Volver a la 0.6.x" (Configuración > Actualizaciones, y la oferta automática de A7): `ii-host --rollback` →
`rollout` (active↔previous, `rolled-back`) → relanzar. La versión de la que se volvió queda marcada "omitida".

## B8 · Canales
Estable y Beta (para testers). Beta = releases `prerelease`. Cambiar de beta a estable no baja de versión: espera a que
la estable alcance a la beta (sin *downgrade*), o se ofrece "Volver a la estable 0.x" explícitamente.

## B9 · Actualizaciones pequeñas (fase 2, 0.9/1.0)
- `make-package.ps1 -DeltaFrom <ids>` compara `payload.manifest` y arma `ii-windows-delta-<from>-<to>.zip` con solo los
  archivos cambiados + `delta.json` (`removed[]`, `files[]`) + el `payload.manifest` completo de la nueva.
- Aplicar: en `versions\<to>.staging`, **enlaces duros** (`CreateHardLinkW`, mismo volumen) a los archivos iguales de
  `versions\<from>` + los cambiados del delta; verificar el manifiesto completo; renombrar. Si algo no cuadra, bajar el
  paquete completo.
- Una versión que solo toca QML pasaría de ~90 MB a 1–3 MB.

## B10 · Pruebas
`tools/sandbox/tests/test-updater.ps1` con el modo de prueba que ya tiene `http.cpp` (*fixtures* JSON) ampliado:

| Caso | Esperado |
|---|---|
| Sin versión nueva / `304` | `idle`, sin aviso |
| Versión nueva bien firmada | `available` + notificación + puntito |
| Firma inválida / `release.json` alterado | ignorada, log, sin aviso |
| Zip con hash distinto | borrado, `error`, reintento |
| Descarga cortada al 40 % | reanuda desde el 40 % (`Range`) |
| `403` con `Retry-After` | espera, no insiste |
| Juego al frente / conexión medida | no descarga; sigue después |
| Versión nueva que no arranca (shell sale con 1) | `ii-launcher` vuelve a la anterior; aviso "La 0.7.0 no arrancó; sigues en la 0.6.1" |
| Versión nueva que crashea 3 veces en `ready` | oferta de volver (A7) |
| Más vieja que la actual | nunca se ofrece |
| `needsInstaller: true` | corre `install.ps1 -Update` oculto, sin consola visible |
| Disco lleno | `error` con mensaje claro; la versión actual intacta |

## B11 · Seguridad y privacidad (va al README)
- Lo único que sale de la PC: una consulta a la API pública de GitHub (tu IP y "ii-windows/<versión>"). Sin cuentas, sin
  telemetría.
- Nada se ejecuta sin firma válida y hashes correctos. Solo HTTPS y solo los hosts de la lista. Sin administrador.
- Nunca baja de versión sola. Si algo falla, te quedas en la que tienes.

## B12 · Cómo llegan los usuarios actuales
La 0.6.0 no tiene actualizador: la **0.6.1** (con el arreglo del crash) y la **0.7.0** se instalan a mano con el Setup.
A partir de la 0.7.0, ii se actualiza solo. Decirlo en las notas de ambas versiones y en el README.
