// ii-shim vdesk: Windows' virtual desktops beyond what is documented.
//
//   ii-shim vdesk probe                 exit 0 when this Windows supports the commands below
//   ii-shim vdesk count                 number of desktops, and the current one (1-based)
//   ii-shim vdesk switch <n>            go to desktop n directly (no stop at the ones between)
//   ii-shim vdesk remove <n>            close desktop n without visiting it (its windows move
//                                       to the neighbour, as in Task View)
//   ii-shim vdesk move <hwnd> <n>       move another app's window to desktop n
//   ii-shim vdesk move-active <n>       the same for the window in front
//
// Windows only documents "which desktop is this window on" (IVirtualDesktopManager). The rest
// is Explorer's internal interface, the one Task View uses; tools like MScholtes/VirtualDesktop
// and VirtualDesktopAccessor rely on it. Its interface ids change between Windows versions:
// asking Explorer for an id it doesn't know fails cleanly (E_NOINTERFACE), so on an unknown
// version nothing is called and the shell keeps using Windows' own shortcuts. Each call runs in
// this short-lived process: a problem here can't take the shell or ii-host down.
// Interface layouts: Windows 11 24H2/25H2 (builds 26100+).

#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <objectarray.h>
#include <shobjidl_core.h>
#include <servprov.h>

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

struct Api {
	Ptr<IServiceProvider> shell;
	Ptr<IVirtualDesktopManagerInternal> manager;
	Ptr<IApplicationViewCollection> views;

	bool open() {
		OSVERSIONINFOEXW version {};
		version.dwOSVersionInfoSize = sizeof(version);
		using RtlGetVersion = LONG(WINAPI*)(OSVERSIONINFOEXW*);
		auto get = reinterpret_cast<RtlGetVersion>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion")); // NOLINT
		if (!get || get(&version) != 0 || version.dwBuildNumber < 26100) return false;
		if (FAILED(CoCreateInstance(CLSID_ImmersiveShell, nullptr, CLSCTX_LOCAL_SERVER, IID_IServiceProvider, reinterpret_cast<void**>(shell.out())))) return false; // NOLINT
		if (FAILED(shell->QueryService(CLSID_VirtualDesktopManagerInternal, IID_IVirtualDesktopManagerInternal, reinterpret_cast<void**>(manager.out())))) return false; // NOLINT
		if (FAILED(shell->QueryService(IID_IApplicationViewCollection, IID_IApplicationViewCollection, reinterpret_cast<void**>(views.out())))) return false; // NOLINT
		int count = 0;
		return SUCCEEDED(manager->GetCount(&count)) && count >= 1;
	}

	// 1-based, in Windows' order (the same as Task View and the bar's dots).
	bool desktop(int n, IVirtualDesktop** out) {
		Ptr<IObjectArray> list;
		if (FAILED(manager->GetDesktops(list.out()))) return false;
		UINT count = 0;
		list->GetCount(&count);
		if (n < 1 || static_cast<UINT>(n) > count) return false;
		return SUCCEEDED(list->GetAt(n - 1, IID_IVirtualDesktop, reinterpret_cast<void**>(out))); // NOLINT
	}

	int currentIndex() {
		Ptr<IVirtualDesktop> current;
		Ptr<IObjectArray> list;
		if (FAILED(manager->GetCurrentDesktop(current.out())) || FAILED(manager->GetDesktops(list.out()))) return 0;
		GUID currentId {};
		current->GetId(&currentId);
		UINT count = 0;
		list->GetCount(&count);
		for (UINT i = 0; i < count; ++i) {
			Ptr<IVirtualDesktop> d;
			if (FAILED(list->GetAt(i, IID_IVirtualDesktop, reinterpret_cast<void**>(d.out())))) continue; // NOLINT
			GUID id {};
			if (SUCCEEDED(d->GetId(&id)) && IsEqualGUID(id, currentId)) return static_cast<int>(i) + 1;
		}
		return 0;
	}
};

int toInt(const std::wstring& s) { return static_cast<int>(wcstol(s.c_str(), nullptr, 0)); }

} // namespace

int vdesk(const std::vector<std::wstring>& args) {
	if (args.empty()) {
		fwprintf(stderr, L"usage: ii-shim vdesk probe|count|switch <n>|remove <n>|move <hwnd> <n>|move-active <n>\n");
		return 2;
	}
	if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 3;
	int code = 1;
	{
		Api api;
		const auto& cmd = args[0];
		if (!api.open()) {
			code = 4; // unsupported Windows version or Explorer not ready
		} else if (cmd == L"probe") {
			code = 0;
		} else if (cmd == L"count") {
			int count = 0;
			api.manager->GetCount(&count);
			wprintf(L"%d %d\n", count, api.currentIndex());
			code = 0;
		} else if (cmd == L"switch" && args.size() >= 2) {
			Ptr<IVirtualDesktop> d;
			if (api.desktop(toInt(args[1]), d.out())) {
				code = SUCCEEDED(api.manager->SwitchDesktopWithAnimation(d.p)) || SUCCEEDED(api.manager->SwitchDesktop(d.p)) ? 0 : 1;
			}
		} else if (cmd == L"remove" && args.size() >= 2) {
			auto n = toInt(args[1]);
			int count = 0;
			api.manager->GetCount(&count);
			Ptr<IVirtualDesktop> d, fallback;
			if (count > 1 && api.desktop(n, d.out()) && api.desktop(n > 1 ? n - 1 : 2, fallback.out())) {
				code = SUCCEEDED(api.manager->RemoveDesktop(d.p, fallback.p)) ? 0 : 1;
			}
		} else if ((cmd == L"move" && args.size() >= 3) || (cmd == L"move-active" && args.size() >= 2)) {
			auto hwnd = cmd == L"move" ? reinterpret_cast<HWND>(static_cast<ULONG_PTR>(wcstoull(args[1].c_str(), nullptr, 0))) // NOLINT
			                           : GetForegroundWindow();
			auto n = toInt(args[cmd == L"move" ? 2 : 1]);
			Ptr<IApplicationView> view;
			Ptr<IVirtualDesktop> d;
			if (hwnd && IsWindow(hwnd) && api.desktop(n, d.out()) && SUCCEEDED(api.views->GetViewForHwnd(hwnd, view.out()))) {
				code = SUCCEEDED(api.manager->MoveViewToDesktop(view.p, d.p)) ? 0 : 1;
			}
		}
	}
	CoUninitialize();
	return code;
}
