// ii-shim vdesk: Windows' virtual desktops beyond what is documented.
//
//   ii-shim vdesk probe                 what this Windows lets us do, one capability per line (below)
//   ii-shim vdesk list                  each desktop: position, id, how many app windows it holds
//   ii-shim vdesk count                 number of desktops, and the current one (1-based)
//   ii-shim vdesk switch <d>            go to desktop d directly (no stop at the ones between)
//   ii-shim vdesk remove <d>            close desktop d without visiting it (its windows move to the
//                                       neighbour, as in Task View)
//   ii-shim vdesk remove-empty <id> <ids>
//                                       close desktop <id> only if it is still what the caller saw:
//                                       <ids> is the ordered, comma-separated list of desktops the
//                                       decision was taken on; any difference, the desktop being the
//                                       current or the first one, or any window on it (or not being
//                                       able to tell) cancels with exit 6/7 and removes nothing
//   ii-shim vdesk move <hwnd> <d>       move another app's window to desktop d
//   ii-shim vdesk move-active <d>       the same for the window in front
//   <d> is a position (1-based) or a desktop id "{GUID}"; the id is what callers should use, a
//   position can be stale by the time the command runs.
//
// Windows only documents "which desktop is this window on" (IVirtualDesktopManager). The rest
// is Explorer's internal interface, the one Task View uses; tools like MScholtes/VirtualDesktop
// and VirtualDesktopAccessor rely on it. Its layout changes between Windows versions and there is no
// version number that guarantees it, so nothing is assumed from the build: every run checks, with
// calls that change nothing and sit at (or after) the vtable slot of each operation, that the
// interface answers coherently, and an operation whose check fails is reported "no" and refused
// (exit 5) instead of calling a method that might be a different one. Each call runs in this
// short-lived process with a deadline, so a problem here (or a stuck Explorer) can't take the shell
// or ii-host down.
//
// Output: the last line is "ok" or "fail <reason>". Exit codes: 0 ok; 1 Windows refused (HRESULT in
// the reason); 2 usage; 3 COM; 4 interface unavailable; 5 operation not verified on this Windows;
// 6 cancelled because what was seen changed (nothing done); 7 cancelled because the desktop is
// occupied or that could not be told (nothing done); 8 deadline.
// Interface layouts: the Windows 11 24H2/25H2 family (builds 26100+).

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <objectarray.h>
#include <shobjidl_core.h>
#include <servprov.h>

#include "vdesk_policy.h"

namespace {

const CLSID CLSID_ImmersiveShell = {0xC2F03A33, 0x21F5, 0x47FA, {0xB4, 0xBB, 0x15, 0x63, 0x62, 0xA2, 0xF2, 0x39}};
const CLSID CLSID_VirtualDesktopManagerInternal = {0xC5E0CDCA, 0x7B6E, 0x41B2, {0x9F, 0xC4, 0xD9, 0x39, 0x75, 0xCC, 0x46, 0x7B}};
const IID IID_IVirtualDesktopManagerInternal = {0x53F5CA0B, 0x158F, 0x4124, {0x90, 0x0C, 0x05, 0x71, 0x58, 0x06, 0x0B, 0x27}};
const IID IID_IVirtualDesktop = {0x3F07F4BE, 0xB107, 0x441A, {0xAF, 0x0F, 0x39, 0xD8, 0x25, 0x29, 0x07, 0x2C}};
const IID IID_IApplicationViewCollection = {0x1841C6D7, 0x4F9D, 0x42C0, {0xAF, 0x41, 0x87, 0x47, 0x53, 0x8F, 0x10, 0xE5}};

// Only used as an opaque pointer handed back to Explorer.
struct IApplicationView: IUnknown {};

struct IVirtualDesktop: IUnknown {
	virtual HRESULT STDMETHODCALLTYPE IsViewVisible(IApplicationView* view, BOOL* visible) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetId(GUID* id) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetName(void** name) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetWallpaperPath(void** path) = 0;
	virtual HRESULT STDMETHODCALLTYPE IsRemote(BOOL* remote) = 0;
};

struct IVirtualDesktopManagerInternal: IUnknown {
	virtual HRESULT STDMETHODCALLTYPE GetCount(int* count) = 0;
	virtual HRESULT STDMETHODCALLTYPE MoveViewToDesktop(IApplicationView* view, IVirtualDesktop* desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE CanViewMoveDesktops(IApplicationView* view, BOOL* can) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetCurrentDesktop(IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetDesktops(IObjectArray** desktops) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetAdjacentDesktop(IVirtualDesktop* from, int direction, IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE SwitchDesktop(IVirtualDesktop* desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE SwitchDesktopAndMoveForegroundView(IVirtualDesktop* desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE CreateDesktop(IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE MoveDesktop(IVirtualDesktop* desktop, int index) = 0;
	virtual HRESULT STDMETHODCALLTYPE RemoveDesktop(IVirtualDesktop* desktop, IVirtualDesktop* fallback) = 0;
	virtual HRESULT STDMETHODCALLTYPE FindDesktop(const GUID* id, IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetDesktopSwitchIncludeExcludeViews(IVirtualDesktop* desktop, IObjectArray** a, IObjectArray** b) = 0;
	virtual HRESULT STDMETHODCALLTYPE SetDesktopName(IVirtualDesktop* desktop, void* name) = 0;
	virtual HRESULT STDMETHODCALLTYPE SetDesktopWallpaper(IVirtualDesktop* desktop, void* path) = 0;
	virtual HRESULT STDMETHODCALLTYPE UpdateWallpaperPathForAllDesktops(void* path) = 0;
	virtual HRESULT STDMETHODCALLTYPE CopyDesktopState(IApplicationView* a, IApplicationView* b) = 0;
	virtual HRESULT STDMETHODCALLTYPE CreateRemoteDesktop(void* path, IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE SwitchRemoteDesktop(IVirtualDesktop* desktop, void* type) = 0;
	virtual HRESULT STDMETHODCALLTYPE SwitchDesktopWithAnimation(IVirtualDesktop* desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetLastActiveDesktop(IVirtualDesktop** desktop) = 0;
	virtual HRESULT STDMETHODCALLTYPE WaitForAnimationToComplete() = 0;
};

struct IApplicationViewCollection: IUnknown {
	virtual HRESULT STDMETHODCALLTYPE GetViews(IObjectArray** views) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetViewsByZOrder(IObjectArray** views) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetViewsByAppUserModelId(LPCWSTR id, IObjectArray** views) = 0;
	virtual HRESULT STDMETHODCALLTYPE GetViewForHwnd(HWND hwnd, IApplicationView** view) = 0;
};

template <typename T> struct Ptr {
	T* p = nullptr;
	Ptr() = default;
	Ptr(const Ptr&) = delete;
	Ptr& operator=(const Ptr&) = delete;
	~Ptr() { if (p) p->Release(); }
	T** out() { return &p; }
	T* operator->() const { return p; }
	explicit operator bool() const { return p != nullptr; }
};

constexpr DWORD DEADLINE_MS = 8000;
constexpr int EXIT_FAILED = 1, EXIT_USAGE = 2, EXIT_COM = 3, EXIT_UNAVAILABLE = 4, EXIT_UNVERIFIED = 5, EXIT_CANCELLED = 6, EXIT_OCCUPIED = 7, EXIT_DEADLINE = 8;

// A stuck Explorer would leave a COM call hanging forever: this process gives up on its own.
DWORD WINAPI deadline(void*) {
	Sleep(DEADLINE_MS);
	wprintf(L"fail deadline (Explorer did not answer in %lu ms)\n", DEADLINE_MS);
	fflush(stdout);
	ExitProcess(EXIT_DEADLINE);
}

std::wstring guidText(const GUID& id) {
	wchar_t buffer[64] {};
	StringFromGUID2(id, buffer, 64);
	return vdeskpolicy::normalize(buffer);
}

struct Caps {
	std::wstring read = L"no: interface not reached";
	std::wstring switching = L"no: interface not reached";
	std::wstring remove = L"no: interface not reached";
	std::wstring move = L"no: interface not reached";
	static bool yes(const std::wstring& c) { return c == L"yes"; }
};

struct Api {
	Ptr<IServiceProvider> shell;
	Ptr<IVirtualDesktopManagerInternal> manager;
	Ptr<IApplicationViewCollection> views;
	Caps caps;
	DWORD build = 0;

	// Reaches Explorer's interface. Nothing here is called on a Windows older than 11 24H2; on newer
	// ones, whether it is usable is decided by verify(), not by the build number.
	bool open() {
		OSVERSIONINFOEXW version {};
		version.dwOSVersionInfoSize = sizeof(version);
		using RtlGetVersion = LONG(WINAPI*)(OSVERSIONINFOEXW*);
		auto get = reinterpret_cast<RtlGetVersion>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion")); // NOLINT
		if (!get || get(&version) != 0) return false;
		build = version.dwBuildNumber;
		if (build < 26100) return false;
		if (FAILED(CoCreateInstance(CLSID_ImmersiveShell, nullptr, CLSCTX_LOCAL_SERVER, IID_IServiceProvider, reinterpret_cast<void**>(shell.out())))) return false; // NOLINT
		if (FAILED(shell->QueryService(CLSID_VirtualDesktopManagerInternal, IID_IVirtualDesktopManagerInternal, reinterpret_cast<void**>(manager.out())))) return false; // NOLINT
		if (FAILED(shell->QueryService(IID_IApplicationViewCollection, IID_IApplicationViewCollection, reinterpret_cast<void**>(views.out())))) return false; // NOLINT
		return true;
	}

	std::vector<std::wstring> ids() {
		std::vector<std::wstring> out;
		Ptr<IObjectArray> list;
		if (FAILED(manager->GetDesktops(list.out()))) return out;
		UINT count = 0;
		list->GetCount(&count);
		for (UINT i = 0; i < count; ++i) {
			Ptr<IVirtualDesktop> d;
			GUID id {};
			if (FAILED(list->GetAt(i, IID_IVirtualDesktop, reinterpret_cast<void**>(d.out()))) || FAILED(d->GetId(&id))) { // NOLINT
				out.clear(); // a partial list would pass for the real one
				return out;
			}
			out.push_back(guidText(id));
		}
		return out;
	}

	// 0-based position of the current desktop in `list`, -1 if it can't be told.
	int currentIndex(const std::vector<std::wstring>& list) {
		Ptr<IVirtualDesktop> current;
		GUID id {};
		if (FAILED(manager->GetCurrentDesktop(current.out())) || FAILED(current->GetId(&id))) return -1;
		auto text = guidText(id);
		for (size_t i = 0; i < list.size(); ++i) {
			if (list[i] == text) return static_cast<int>(i);
		}
		return -1;
	}

	// Checks the parts of the interface the operations depend on with calls that change nothing, at
	// or after the slot of the operation: if the layout moved, these return nonsense (or fail)
	// instead of doing something.
	void verify() {
		int count = 0;
		auto list = ids();
		if (FAILED(manager->GetCount(&count)) || count < 1 || static_cast<int>(list.size()) != count) {
			caps.read = L"no: the list of desktops is not coherent";
			return;
		}
		auto current = currentIndex(list);
		if (current < 0) {
			caps.read = L"no: the current desktop is not in the list";
			return;
		}
		caps.read = L"yes";

		// FindDesktop sits right after RemoveDesktop in the interface: finding the current desktop
		// by its id and getting the same one back shows the slots up to it are the ones we think.
		Ptr<IVirtualDesktop> found;
		GUID wanted {};
		CLSIDFromString(list[static_cast<size_t>(current)].c_str(), &wanted);
		GUID gotId {};
		auto layout = SUCCEEDED(manager->FindDesktop(&wanted, found.out())) && found && SUCCEEDED(found->GetId(&gotId)) && IsEqualGUID(gotId, wanted);
		caps.switching = layout ? L"yes" : L"no: FindDesktop does not answer as expected";
		caps.remove = layout ? L"yes" : L"no: FindDesktop does not answer as expected";

		// CanViewMoveDesktops (slot 5) with a real window, through the view collection.
		HWND probe = nullptr;
		EnumWindows([](HWND h, LPARAM l) -> BOOL {
			if (!IsWindowVisible(h) || (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) || GetWindowTextLengthW(h) == 0) return TRUE;
			*reinterpret_cast<HWND*>(l) = h; // NOLINT
			return FALSE;
		}, reinterpret_cast<LPARAM>(&probe)); // NOLINT
		if (!layout) {
			caps.move = L"no: FindDesktop does not answer as expected";
		} else if (!probe) {
			caps.move = L"no: no window to check it with";
		} else {
			Ptr<IApplicationView> view;
			BOOL can = FALSE;
			caps.move = SUCCEEDED(views->GetViewForHwnd(probe, view.out())) && view && SUCCEEDED(manager->CanViewMoveDesktops(view.p, &can))
			                ? L"yes"
			                : L"no: the view of a window can not be asked about";
		}
	}

	bool desktopById(const std::wstring& id, IVirtualDesktop** out) {
		GUID guid {};
		if (FAILED(CLSIDFromString(id.c_str(), &guid))) return false;
		return SUCCEEDED(manager->FindDesktop(&guid, out)) && *out;
	}

	// A position (1-based, Windows' order) or a "{GUID}".
	bool desktop(const std::wstring& arg, IVirtualDesktop** out) {
		if (!arg.empty() && arg[0] == L'{') return desktopById(arg, out);
		auto n = static_cast<int>(wcstol(arg.c_str(), nullptr, 0));
		Ptr<IObjectArray> list;
		if (FAILED(manager->GetDesktops(list.out()))) return false;
		UINT count = 0;
		list->GetCount(&count);
		if (n < 1 || static_cast<UINT>(n) > count) return false;
		return SUCCEEDED(list->GetAt(n - 1, IID_IVirtualDesktop, reinterpret_cast<void**>(out))); // NOLINT
	}
};

// A window Task View would show: visible, and not a tool window or an owned popup (unless it asks
// to be listed). Those are the ones that move when a desktop is closed, and the ones a person would
// miss. Hidden helper windows, ii's own layer windows and the shell's are not.
bool isAppWindow(HWND h) {
	if (!IsWindowVisible(h)) return false;
	auto ex = GetWindowLongW(h, GWL_EXSTYLE);
	auto listed = (ex & WS_EX_APPWINDOW) != 0;
	if ((ex & WS_EX_TOOLWINDOW) && !listed) return false;
	if (GetWindow(h, GW_OWNER) && !listed) return false;
	return true;
}

// How many app windows say they live on `target`; -1 if one could not be asked (we would be
// guessing, and a guess is never grounds to delete). With `perDesktop`, also counts the windows of
// each desktop listed; `unknown` receives how many app windows could not be placed.
int occupantsOf(const std::wstring& target, std::vector<std::pair<std::wstring, int>>* perDesktop = nullptr, int* unknownWindows = nullptr) {
	constexpr CLSID clsid {0xaa509086, 0x5ca9, 0x4c25, {0x8f, 0x95, 0x58, 0x9d, 0x3c, 0x07, 0xb4, 0x8a}};
	Ptr<IVirtualDesktopManager> manager;
	if (FAILED(CoCreateInstance(clsid, nullptr, CLSCTX_ALL, IID_PPV_ARGS(manager.out())))) return -1;
	struct State {
		IVirtualDesktopManager* manager;
		std::wstring target;
		int found = 0;
		int unknown = 0;
		std::vector<std::wstring> all;
	} state {manager.p, target, 0, 0, {}};
	EnumWindows([](HWND h, LPARAM l) -> BOOL {
		auto& s = *reinterpret_cast<State*>(l); // NOLINT
		if (!isAppWindow(h)) return TRUE;
		GUID id {};
		auto hr = s.manager->GetWindowDesktopId(h, &id);
		// Not a window virtual desktops manage at all (Windows' own surfaces such as the "Windows Input Experience"
		// of TextInputHost): no desktop can hold it, so it is not an app window left out.
		if (hr == TYPE_E_ELEMENTNOTFOUND) return TRUE;
		if (FAILED(hr) || IsEqualGUID(id, GUID_NULL)) {
			++s.unknown;
			return TRUE;
		}
		auto text = guidText(id);
		if (text == s.target) ++s.found;
		s.all.push_back(text);
		return TRUE;
	}, reinterpret_cast<LPARAM>(&state)); // NOLINT
	if (unknownWindows) *unknownWindows = state.unknown;
	if (perDesktop) {
		for (auto& entry: *perDesktop) {
			entry.second = static_cast<int>(std::count(state.all.begin(), state.all.end(), entry.first));
		}
	}
	return state.found > 0 ? state.found : (state.unknown > 0 ? -1 : 0);
}

int refuse(int code, const std::wstring& reason) {
	wprintf(L"fail %ls\n", reason.c_str());
	return code;
}

int windowsRefused(HRESULT hr) {
	return refuse(EXIT_FAILED, L"Windows refused (hr " + std::to_wstring(static_cast<long>(hr)) + L")");
}

} // namespace

int vdesk(const std::vector<std::wstring>& args) {
	if (args.empty()) {
		fwprintf(stderr, L"usage: ii-shim vdesk probe|list|count|switch <d>|remove <d>|remove-empty <id> <ids>|move <hwnd> <d>|move-active <d>\n");
		return EXIT_USAGE;
	}
	if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return refuse(EXIT_COM, L"COM did not start");
	CreateThread(nullptr, 0, deadline, nullptr, 0, nullptr);
	int code = EXIT_FAILED;
	{
		Api api;
		const auto& cmd = args[0];
		bool known = cmd == L"probe" || cmd == L"list" || cmd == L"count" || cmd == L"switch" || cmd == L"remove" || cmd == L"remove-empty" || cmd == L"move" || cmd == L"move-active";
		if (!known) {
			code = refuse(EXIT_USAGE, L"unknown command");
		} else if (!api.open()) {
			if (cmd == L"probe") wprintf(L"build %lu\nread no: Explorer's interface is not available (Windows older than 11 24H2, or Explorer not ready)\nswitch no\nremove no\nmove no\n", api.build);
			code = refuse(EXIT_UNAVAILABLE, L"Explorer's desktop interface is not available");
		} else {
			api.verify();
			if (cmd == L"probe") {
				wprintf(L"build %lu\nread %ls\nswitch %ls\nremove %ls\nmove %ls\n", api.build, api.caps.read.c_str(), api.caps.switching.c_str(), api.caps.remove.c_str(), api.caps.move.c_str());
				code = Caps::yes(api.caps.read) ? 0 : EXIT_UNAVAILABLE;
				wprintf(code == 0 ? L"ok\n" : L"fail reading the desktops is not verified\n");
			} else if (!Caps::yes(api.caps.read)) {
				code = refuse(EXIT_UNVERIFIED, L"reading the desktops is not verified on this Windows: " + api.caps.read);
			} else if (cmd == L"list") {
				auto list = api.ids();
				std::vector<std::pair<std::wstring, int>> per;
				for (auto& id: list) per.emplace_back(id, 0);
				int unknown = 0;
				occupantsOf(L"", &per, &unknown);
				auto current = api.currentIndex(list);
				for (size_t i = 0; i < list.size(); ++i) {
					wprintf(L"desktop %zu %ls windows=%d%ls\n", i + 1, list[i].c_str(), per[i].second, static_cast<int>(i) == current ? L" current" : L"");
				}
				wprintf(L"unknown-app-windows %d\nok\n", unknown);
				code = 0;
			} else if (cmd == L"count") {
				auto list = api.ids();
				wprintf(L"%zu %d\nok\n", list.size(), api.currentIndex(list) + 1);
				code = 0;
			} else if (cmd == L"switch" && args.size() >= 2) {
				Ptr<IVirtualDesktop> d;
				if (!Caps::yes(api.caps.switching)) {
					code = refuse(EXIT_UNVERIFIED, L"switching is not verified on this Windows: " + api.caps.switching);
				} else if (!api.desktop(args[1], d.out())) {
					code = refuse(EXIT_CANCELLED, L"no such desktop");
				} else {
					auto hr = api.manager->SwitchDesktopWithAnimation(d.p);
					if (FAILED(hr)) hr = api.manager->SwitchDesktop(d.p);
					code = SUCCEEDED(hr) ? 0 : windowsRefused(hr);
					if (code == 0) wprintf(L"ok\n");
				}
			} else if (cmd == L"remove" && args.size() >= 2) {
				auto list = api.ids();
				Ptr<IVirtualDesktop> d, fallback;
				GUID id {};
				if (!Caps::yes(api.caps.remove)) {
					code = refuse(EXIT_UNVERIFIED, L"removing is not verified on this Windows: " + api.caps.remove);
				} else if (list.size() < 2 || !api.desktop(args[1], d.out()) || FAILED(d->GetId(&id))) {
					code = refuse(EXIT_CANCELLED, L"no such desktop, or it is the only one");
				} else {
					auto position = std::find(list.begin(), list.end(), guidText(id)) - list.begin();
					auto neighbour = position > 0 ? position - 1 : 1;
					if (!api.desktop(list[static_cast<size_t>(neighbour)], fallback.out())) {
						code = refuse(EXIT_CANCELLED, L"the neighbour desktop is gone");
					} else {
						auto hr = api.manager->RemoveDesktop(d.p, fallback.p);
						code = SUCCEEDED(hr) ? 0 : windowsRefused(hr);
						if (code == 0) wprintf(L"ok\n");
					}
				}
			} else if (cmd == L"remove-empty" && args.size() >= 3) {
				auto expected = vdeskpolicy::splitIds(args[2]);
				auto target = vdeskpolicy::normalize(args[1]);
				if (!Caps::yes(api.caps.remove)) {
					code = refuse(EXIT_UNVERIFIED, L"removing is not verified on this Windows: " + api.caps.remove);
				} else {
					auto list = api.ids();
					auto verdict = vdeskpolicy::judgeRemoveEmpty(expected, list, api.currentIndex(list), target, 0);
					if (verdict == vdeskpolicy::Verdict::Ok) {
						// Windows are asked last, and the inventory and current desktop are read again
						// after: the closer to the call, the less can change in between.
						auto occupants = occupantsOf(target);
						list = api.ids();
						verdict = vdeskpolicy::judgeRemoveEmpty(expected, list, api.currentIndex(list), target, occupants);
					}
					if (verdict != vdeskpolicy::Verdict::Ok) {
						code = refuse(verdict == vdeskpolicy::Verdict::Occupied ? EXIT_OCCUPIED : EXIT_CANCELLED, std::wstring(L"not removed: ") + vdeskpolicy::name(verdict));
					} else {
						Ptr<IVirtualDesktop> d, fallback;
						auto position = std::find(list.begin(), list.end(), target) - list.begin();
						if (!api.desktopById(target, d.out()) || !api.desktopById(list[static_cast<size_t>(position - 1)], fallback.out())) {
							code = refuse(EXIT_CANCELLED, L"not removed: the desktop or its neighbour is gone");
						} else {
							auto hr = api.manager->RemoveDesktop(d.p, fallback.p);
							code = SUCCEEDED(hr) ? 0 : windowsRefused(hr);
							if (code == 0) wprintf(L"ok\n");
						}
					}
				}
			} else if ((cmd == L"move" && args.size() >= 3) || (cmd == L"move-active" && args.size() >= 2)) {
				auto hwnd = cmd == L"move" ? reinterpret_cast<HWND>(static_cast<ULONG_PTR>(wcstoull(args[1].c_str(), nullptr, 0))) // NOLINT
				                           : GetForegroundWindow();
				Ptr<IApplicationView> view;
				Ptr<IVirtualDesktop> d;
				if (!Caps::yes(api.caps.move)) {
					code = refuse(EXIT_UNVERIFIED, L"moving windows is not verified on this Windows: " + api.caps.move);
				} else if (!hwnd || !IsWindow(hwnd) || !api.desktop(args[cmd == L"move" ? 2 : 1], d.out()) || FAILED(api.views->GetViewForHwnd(hwnd, view.out()))) {
					code = refuse(EXIT_CANCELLED, L"no such window or desktop");
				} else {
					auto hr = api.manager->MoveViewToDesktop(view.p, d.p);
					code = SUCCEEDED(hr) ? 0 : windowsRefused(hr);
					if (code == 0) wprintf(L"ok\n");
				}
			} else {
				code = refuse(EXIT_USAGE, L"missing arguments");
			}
		}
	}
	fflush(stdout);
	CoUninitialize();
	return code;
}
