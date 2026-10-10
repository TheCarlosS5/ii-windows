#include "common.h"
#include "nightlight.h"

#include <shellapi.h>

// Desktop icons live in a SysListView32 ("FolderView") inside SHELLDLL_DefView, which is a
// child of Progman or, after the wallpaper WorkerW split, of a WorkerW. Hiding that list view
// is not persisted anywhere: an Explorer restart brings the icons back by itself.

namespace ii::desktop {

namespace {

HWND findDefView() {
	if (auto* progman = FindWindowW(L"Progman", nullptr)) {
		if (auto* view = FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr)) return view;
	}

	for (auto* worker: findTopLevel(L"WorkerW")) {
		if (auto* view = FindWindowExW(worker, nullptr, L"SHELLDLL_DefView", nullptr)) return view;
	}

	return nullptr;
}

HWND findFolderView() {
	auto* view = findDefView();
	if (!view) return nullptr;
	return FindWindowExW(view, nullptr, L"SysListView32", nullptr);
}

} // namespace

void hideIcons() {
	auto* list = findFolderView();
	if (!list) {
		log(L"desktop: FolderView not found");
		return;
	}
	state::set(L"iconsHidden", 1);
	ShowWindow(list, SW_HIDE);
	log(L"desktop: icons hidden");
}

void reapplyIcons() {
	if (auto* list = findFolderView(); list && IsWindowVisible(list)) ShowWindow(list, SW_HIDE);
}

void restoreIcons(bool force) {
	if (!force && state::get(L"iconsHidden", 0) == 0) return; // not hidden by this ii
	if (auto* list = findFolderView()) ShowWindow(list, SW_SHOWNA);
	state::set(L"iconsHidden", 0);
	log(L"desktop: icons shown");
}

} // namespace ii::desktop

namespace ii {

void restoreAll(bool restartExplorer, bool force) {
	log(L"restoreAll(restartExplorer=%d, force=%d)", restartExplorer ? 1 : 0, force ? 1 : 0);
	nightlight::restore();
	if (noUi()) {
		log(L"restoreAll: II_NO_UI, Explorer's taskbar and icons left alone");
	} else {
		taskbar::restore(force);
		desktop::restoreIcons(force);
	}
	banners::restore();
	theme::restore();

	if (!restartExplorer) return;

	// A clean Explorer restart also drops any appbar space left behind by a crashed shell.
	if (auto* tray = explorerTray()) {
		auto pid = processIdOf(tray);
		if (auto* proc = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid)) {
			TerminateProcess(proc, 1);
			WaitForSingleObject(proc, 5000);
			CloseHandle(proc);
		}
	}

	Sleep(1500);
	if (!explorerTray()) {
		wchar_t windir[MAX_PATH];
		GetWindowsDirectoryW(windir, MAX_PATH);
		auto exe = std::wstring(windir) + L"\\explorer.exe";
		ShellExecuteW(nullptr, L"open", exe.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
		log(L"explorer restarted");
	}
}

} // namespace ii
