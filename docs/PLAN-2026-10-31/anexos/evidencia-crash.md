# Anexo · Evidencia técnica del crash `quickshell.exe+0x19ed74`

Todo lo de este anexo se puede repetir con lo que hay en esta carpeta y en la PC. Nada de esto modificó el sistema.

## 1. Eventos de Windows (Aplicación, id 1000) de programas de ii en esta PC

```
2026-10-08 16:30  quickshell.exe ts=0x6ac7d7fb  code=0xc0000005 offset=0x1d7cbb   (build de desarrollo, sin binario)
2026-10-11 16:08  quickshell.exe ts=0x6ac965ad  code=0xc0000005 offset=0x1db66b   (= v0.1.3)
2026-10-11 18:52  quickshell.exe ts=0x6acc1af1  code=0xc0000005 offset=0x19ba7c   (= build de la v0.2.0)
2026-10-25 21:19  quickshell.exe ts=0x6ade8ef9  code=0xc0000005 offset=0x19ed74   (= v0.6.0)
2026-10-25 21:30  quickshell.exe ts=0x6ade8ef9  code=0xc0000005 offset=0x19ed74
2026-10-25 21:38  quickshell.exe ts=0x6ade8ef9  code=0xc0000005 offset=0x19ed74
```

Consulta usada (PowerShell):
```powershell
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} |
  Where-Object { $_.Message -match 'quickshell|ii-host|ii-shim|ii-launcher' }
```
No hay informes en `WER\ReportArchive`/`ReportQueue` ni volcados en `%LOCALAPPDATA%\CrashDumps` (por eso A3).

## 2. Cómo se obtuvo cada binario exacto

- v0.6.0: asset `ii-windows-0.6.0-20261025-6d92550.zip` de la release, `app/quickshell/quickshell.exe`
  (marca de tiempo del PE `0x6ADE8EF9` = 2026-10-25 23:21:29 UTC; sin *debug directory*, es decir, sin PDB).
- v0.1.3 y v0.2.0: solo el `quickshell.exe` de cada zip, leído con peticiones HTTP por rango (sin bajar los 100 MB).
  Marcas `0x6ac965ad` y `0x6acc1af1`: coinciden con los eventos.

## 3. Ubicar la función sin símbolos

`python -I crash-locate.py quickshell.exe 19ed74` ([crash-locate.py](crash-locate.py)):

```
pdata: begin 0x19e0c0 end 0x19f9da  (crash at +0xcb4)
```

Llamadas a Qt que hace esa función (anotadas con la tabla de importaciones), que la identifican como
`Backend::pushState` con `saveArt` en línea:

```
QDir::tempPath, QDir::filePath, QDir::mkpath          → carpeta %TEMP%\ii-windows\mpris
QCryptographicHash::hash, QByteArray::toHex           → nombre <sha1>.img de la carátula
QFile::exists, QFile::open, QIODevice::write          → guardar la carátula
QUrl::fromLocalFile, QUrl::toString                   → artUrl
QDateTime::currentDateTimeUtc                         → state.positionUpdated
QLoggingCategory::isDebugEnabled, QMessageLogger::debug → qCDebug(logMpris) << "Session" … "title" …
QMetaObject::invokeMethodImpl                         → enviar el estado al hilo GUI
cadena: "…\Windows Kits\10\Include\10.0.26100.0\cppwinrt\winrt/…"   → source_location de C++/WinRT (check_hresult)
```

Fragmento alrededor del fallo (AT&T, tal como lo da `llvm-objdump`):

```
0019ecf6: movq   $0x0, 0x270(%rbp)
0019ed01: movq   0x1d0(%rbp), %rcx          ; session
0019ed08: movl   $0x58, 0x258(%rbp)         ; línea (source_location)
0019ed2b: movq   (%rcx), %rax               ; vtable de la sesión
0019ed2e: leaq   0x270(%rbp), %rdx          ; &out
0019ed35: callq  *0x48(%rax)                ; GetPlaybackInfo(&out)
0019ed38: testl  %eax, %eax
0019ed3a: js     <throw hresult_error>      ; HRESULT de error: excepción C++ (esa sí la atrapa el catch)
0019ed40: movq   0x270(%rbp), %rcx          ; out → rcx  (S_OK pero NULL)
0019ed47: movq   %rcx, 0x1d8(%rbp)          ; info
0019ed58: movl   $0x440, 0x258(%rbp)        ; línea 1088
0019ed74: movq   (%rcx), %rax      <<<<<<<< ; 0xC0000005: lee la vtable de NULL
0019ed7e: callq  *0x38(%rax)                ; get_PlaybackStatus
0019ed89: movl   0x270(%rbp), %eax
0019ed8f: cmpl   $0x5, %eax                 ; Paused
0019ed97: cmpl   $0x4, %eax                 ; Playing
0019edd9: movq   (%rcx), %rax               ; info
0019ede3: callq  *0x30(%rax)                ; get_Controls
0019ee29: callq  *0x30(%rax)                ; controls.IsPlayEnabled
```

Lectura: si la llamada falla con un HRESULT de error, C++/WinRT lanza `hresult_error` y el `catch (...)` de
`mpris.cpp:210` la atrapa (no hay crash). Si "funciona" pero devuelve nulo, no hay excepción C++ y la siguiente
instrucción lee la dirección 0: **eso** es el crash.

## 4. Los crashes viejos

```
v0.1.3  0x1db630  (función de 0x77 bytes = consume_…PlaybackInfo::PlaybackStatus, no inlined)
001db64b: movq  (%rcx), %rcx        ; this->m_ptr  (NULL)
001db64e: movl  $0x440, 0x20(%rsp)  ; línea 1088, la misma
001db66b: movq  (%rcx), %rax  <<<<  ; crash
001db673: callq *0x38(%rax)         ; get_PlaybackStatus

v0.2.0  dentro de 0x19a7f0-0x19c10a (pushState)
0019ba3c: callq *0x40(%rax)         ; session.GetTimelineProperties(&out)
0019ba47: movq  0x238(%rbp), %rcx   ; out (NULL)
0019ba7c: movq  (%rcx), %rax  <<<<  ; crash
0019ba86: callq *0x30(%rax)         ; timeline.StartTime / EndTime
```

## 5. Logs de la shell antes de cada crash (extracto)

`%TEMP%\quickshell\by-pid\3304\log.log` (crash de las 21:19), `388` (21:30) y `7444` (21:38): en los últimos minutos,
carátulas nuevas cada pocos segundos (`coverart/a757d…`, `e9634…`, `e4bf2…`, `ed0a1…`, `b82f9…`, `2fa27…`, `7336a…`,
`49b8f…`, `5ba25…`) y, en cada cambio:

```
WARN scene: …/mediaControls/PlayerControl.qml[299:37]: Unable to assign [undefined] to bool
WARN scene: …/mediaControls/PlayerControl.qml[85:9]: Unable to assign [undefined] to QString
WARN quickshell.colorquantizer: Failed to load image from "file:///…/cache/media/coverart/<md5>"
WARN scene: …/mediaControls/PlayerControl.qml[147:13]: Unable to assign [undefined] to bool
WARN scene: QML Loader … MediaWidget.qml[73:5]: Cannot open: file:///…/cache/media/coverart/5e543256…
```

Es el patrón del feed de X en Brave: un video nuevo (sesión nueva) cada pocos segundos.

## 6. Detalle menor encontrado de paso

El `quickshell.exe` publicado lleva 21 rutas de la máquina que compiló (`C:\Users\Admin\dev\ii-windows\quickshell\src\…`
por `__FILE__` en los mensajes de Qt y `…\cppwinrt\winrt/…` por el `source_location` de C++/WinRT). No es un dato
personal (el usuario de esa máquina es "Admin"), pero conviene quitarlas: `/clang:-ffile-prefix-map=<raíz>=.` en el fork
y `WINRT_NO_SOURCE_LOCATION` (además reduce el tamaño). `ii-host.exe` no lleva ninguna. Va con A3.2.
