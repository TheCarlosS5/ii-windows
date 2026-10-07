// Prototype B: web-UI bar (stand-in for an Electron/Tauri rewrite).
// Transparent + acrylic, reserves screen space with an AppBar, quits itself after 20 s.
const { app, BrowserWindow, screen } = require('electron');
const koffi = require('koffi');
const fs = require('fs');

const user32 = koffi.load('user32.dll');
const shell32 = koffi.load('shell32.dll');
const RECT = koffi.struct('RECT', { left: 'long', top: 'long', right: 'long', bottom: 'long' });
const APPBARDATA = koffi.struct('APPBARDATA', {
  cbSize: 'uint32', hWnd: 'void *', uCallbackMessage: 'uint32', uEdge: 'uint32', rc: RECT, lParam: 'intptr',
});
const SHAppBarMessage = shell32.func('uintptr __stdcall SHAppBarMessage(uint32, _Inout_ APPBARDATA *)');
const SystemParametersInfoW = user32.func('bool __stdcall SystemParametersInfoW(uint32, uint32, _Out_ RECT *, uint32)');
const ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABE_TOP = 1, SPI_GETWORKAREA = 0x30;
const H = 44;
const out = [];
const log = (...a) => { out.push(a.join(' ')); console.log(...a); };
const workArea = () => { const r = {}; SystemParametersInfoW(SPI_GETWORKAREA, 0, r, 0); return r; };

let abd;
app.whenReady().then(() => {
  const t0 = Date.now();
  const { width } = screen.getPrimaryDisplay().bounds;
  const win = new BrowserWindow({
    x: 0, y: 0, width, height: H, frame: false, transparent: false, backgroundMaterial: 'acrylic',
    backgroundColor: '#00000000', resizable: false, skipTaskbar: true, alwaysOnTop: true, show: false,
    webPreferences: { backgroundThrottling: false },
  });
  win.loadFile('bar.html');
  win.once('ready-to-show', () => {
    win.showInactive();
    log('first paint ms', Date.now() - t0);
    const hwnd = koffi.decode(win.getNativeWindowHandle(), 'void *');
    abd = { cbSize: koffi.sizeof(APPBARDATA), hWnd: hwnd, uCallbackMessage: 0x8001, uEdge: ABE_TOP,
            rc: { left: 0, top: 0, right: width, bottom: H }, lParam: 0 };
    log('work area before', JSON.stringify(workArea()));
    log('ABM_NEW', SHAppBarMessage(ABM_NEW, abd));
    SHAppBarMessage(ABM_QUERYPOS, abd);
    abd.rc.bottom = abd.rc.top + H;
    SHAppBarMessage(ABM_SETPOS, abd);
    setTimeout(() => log('work area with bar', JSON.stringify(workArea())), 500);
  });
  setTimeout(async () => {
    const metrics = app.getAppMetrics();
    const mb = metrics.reduce((s, m) => s + m.memory.workingSetSize, 0) / 1024;
    log('processes', metrics.length, 'total working set MB', mb.toFixed(1));
    log('per process', metrics.map(m => `${m.type}:${(m.memory.workingSetSize / 1024).toFixed(0)}`).join(' '));
    const img = await win.webContents.capturePage();
    fs.writeFileSync('shot-web-bar.png', img.toPNG());
  }, 12000);
  setTimeout(() => app.quit(), 20000);
});

app.on('will-quit', () => {
  if (abd) log('ABM_REMOVE', SHAppBarMessage(ABM_REMOVE, abd));
  log('work area after', JSON.stringify(workArea()));
  fs.writeFileSync('result.txt', out.join('\n'));
});
