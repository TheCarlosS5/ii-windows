import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'quickshell', 'src', 'win32'))

edit('native.hpp', [
  ('''// Mirrors wlr-layer-shell layers. Windows only has "topmost" and "normal" bands,
// so Top/Overlay are both topmost with Overlay re-raised above Top, and
// Background/Bottom sit at the bottom of the normal band.''',
   '''// Mirrors wlr-layer-shell layers. Windows only has "topmost" and "normal" bands,
// so Top/Overlay are both topmost with Overlay re-raised above Top, and
// Background/Bottom are kept directly above the Windows desktop (Progman): under every
// application window, over the Windows wallpaper. They are never children of Explorer's
// windows, so an Explorer restart cannot take them down.'''),
  ('''	// Temporarily drops Top-layer windows on a monitor below everything (fullscreen apps).
	void setFullscreenAppActive(quintptr monitor, bool active);
	void restack();

private:
	explicit LayerManager(QObject* parent = nullptr): QObject(parent) {}''',
   '''	// Temporarily drops Top-layer windows on a monitor below everything (fullscreen apps).
	void setFullscreenAppActive(quintptr monitor, bool active);
	void restack();
	// Puts desktop-layer windows back right above Progman (z-order drifts as apps activate).
	void restackDesktop();

private:
	explicit LayerManager(QObject* parent = nullptr);'''),
])

edit('native.cpp', [
  ('''LayerManager* LayerManager::instance() {
	static auto* manager = new LayerManager(); // NOLINT
	return manager;
}
''', '''namespace {
void CALLBACK onForegroundChanged(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) {
	QMetaObject::invokeMethod(LayerManager::instance(), &LayerManager::restackDesktop, Qt::QueuedConnection);
}
} // namespace

LayerManager::LayerManager(QObject* parent): QObject(parent) {
	// Out-of-context hook, nothing injected.
	SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, onForegroundChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
}

LayerManager* LayerManager::instance() {
	static auto* manager = new LayerManager(); // NOLINT
	return manager;
}
'''),
  ('''void LayerManager::apply(QWindow* window, Layer layer) {
	auto above = layer == Layer::Top || layer == Layer::Overlay;
	window->setFlag(Qt::WindowStaysOnTopHint, above);
	window->setFlag(Qt::WindowStaysOnBottomHint, !above);
}
''', '''void LayerManager::apply(QWindow* window, Layer layer) {
	auto above = layer == Layer::Top || layer == Layer::Overlay;
	window->setFlag(Qt::WindowStaysOnTopHint, above);
	// Not WindowStaysOnBottomHint: HWND_BOTTOM would put us under the desktop itself.
	window->setFlag(Qt::WindowStaysOnBottomHint, false);
	if (!above) this->restackDesktop();
}

void LayerManager::restackDesktop() {
	auto* progman = FindWindowW(L"Progman", nullptr);
	if (!progman) return;

	for (auto [window, layer]: this->layers.asKeyValueRange()) {
		if (layer != Layer::Background && layer != Layer::Bottom) continue;
		if (!window->isVisible()) continue;
		auto h = toHwnd(hwnd(window));
		if (!h) continue;

		// Insert right after the window above Progman, i.e. directly over the desktop.
		auto* above = GetWindow(progman, GW_HWNDPREV);
		if (above == h) continue; // already in place
		SetWindowPos(
		    h,
		    above ? above : HWND_TOP,
		    0,
		    0,
		    0,
		    0,
		    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING
		);
	}

	// Background below Bottom when both exist.
	for (auto [window, layer]: this->layers.asKeyValueRange()) {
		if (layer != Layer::Background || !window->isVisible()) continue;
		if (auto h = toHwnd(hwnd(window))) {
			auto* above = GetWindow(progman, GW_HWNDPREV);
			if (above && above != h) {
				SetWindowPos(h, above, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
			}
		}
	}
}
'''),
  ('''void LayerManager::restack() {''', '''void LayerManager::restack() {
	this->restackDesktop();
'''),
])
