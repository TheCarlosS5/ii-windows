// ii-shim files ...: the file actions of ii's desktop, done by Windows' own shell so they
// behave exactly as in Explorer (Recycle Bin, conflict and progress dialogs, undo-safe names,
// property sheets, "Open with", the full Explorer context menu with its shell extensions).
//
//   ii-shim files recycle <path>...          to the Recycle Bin
//   ii-shim files delete <path>...           permanently, after Windows' own confirmation
//   ii-shim files rename <path> <new name>   prints the new full path
//   ii-shim files newfolder <dir> <name>     unique name ("name (2)"...), prints the new path
//   ii-shim files copy|move <dir> <path>...  into a folder
//   ii-shim files clip copy|cut <path>...    put files on the clipboard (as Explorer does)
//   ii-shim files paste <dir>                paste files from the clipboard into a folder
//   ii-shim files canpaste                   exit 0 if the clipboard holds files
//   ii-shim files properties <path>...       Windows' property sheet
//   ii-shim files openwith <path>            Windows' "Open with" dialog
//   ii-shim files menu [--at x,y] <path>...  Explorer's context menu for the items
//   ii-shim files menu [--at x,y] --background <dir>   ...for the empty folder (New, Paste...)
//
// Only documented shell APIs (IFileOperation, IContextMenu, SHMultiFileProperties...).

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

namespace {

using Args = std::vector<std::wstring>;

template <class T>
struct Com {
	T* p = nullptr;
	Com() = default;
	Com(const Com&) = delete;
	Com& operator=(const Com&) = delete;
	~Com() {
		if (p) p->Release();
	}
	T** put() { return &p; }
	T* operator->() const { return p; }
	explicit operator bool() const { return p != nullptr; }
};

struct ComScope {
	bool ok;
	ComScope(): ok(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE))) {}
	~ComScope() {
		if (ok) CoUninitialize();
	}
};

std::wstring fullPath(const std::wstring& path) {
	wchar_t buffer[MAX_PATH * 4];
	auto n = GetFullPathNameW(path.c_str(), static_cast<DWORD>(std::size(buffer)), buffer, nullptr);
	if (n == 0 || n >= std::size(buffer)) return path;
	return buffer;
}

std::wstring parentOf(const std::wstring& path) {
	auto slash = path.find_last_of(L"\\/");
	return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

bool exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

void printPath(const std::wstring& path) {
	// UTF-8 on stdout, whatever the console code page: the shell reads it with a Process.
	auto size = WideCharToMultiByte(CP_UTF8, 0, path.c_str(), -1, nullptr, 0, nullptr, nullptr);
	std::string utf8(size > 0 ? size - 1 : 0, '\0');
	if (size > 1) WideCharToMultiByte(CP_UTF8, 0, path.c_str(), -1, utf8.data(), size, nullptr, nullptr);
	std::fwrite(utf8.data(), 1, utf8.size(), stdout);
	std::fputc('\n', stdout);
	std::fflush(stdout);
}

bool shellItem(const std::wstring& path, IShellItem** item) {
	return SUCCEEDED(SHCreateItemFromParsingName(fullPath(path).c_str(), nullptr, IID_PPV_ARGS(item)));
}

// Absolute PIDLs for the paths that exist; freed by the destructor.
struct Pidls {
	std::vector<PIDLIST_ABSOLUTE> list;
	Pidls() = default;
	Pidls(const Pidls&) = delete;
	Pidls& operator=(const Pidls&) = delete;
	~Pidls() {
		for (auto* p: list) CoTaskMemFree(p);
	}
	explicit Pidls(const Args& paths) {
		for (const auto& path: paths) {
			PIDLIST_ABSOLUTE pidl = nullptr;
			if (SUCCEEDED(SHParseDisplayName(fullPath(path).c_str(), nullptr, &pidl, 0, nullptr))) list.push_back(pidl);
		}
	}
};

// Items of one parent folder (context menus and multi-file property sheets need that).
bool itemArray(const Args& paths, IShellItemArray** array) {
	Args sameParent;
	auto parent = parentOf(fullPath(paths.front()));
	for (const auto& path: paths) {
		if (_wcsicmp(parentOf(fullPath(path)).c_str(), parent.c_str()) == 0) sameParent.push_back(path);
	}
	Pidls pidls(sameParent);
	if (pidls.list.empty()) return false;
	return SUCCEEDED(SHCreateShellItemArrayFromIDLists(
	    static_cast<UINT>(pidls.list.size()),
	    const_cast<PCIDLIST_ABSOLUTE_ARRAY>(pidls.list.data()), // NOLINT
	    array
	));
}

bool newOperation(IFileOperation** op, DWORD flags) {
	if (FAILED(CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL, IID_PPV_ARGS(op)))) return false;
	return SUCCEEDED((*op)->SetOperationFlags(flags));
}

// Runs the operation; false if it failed or the user cancelled.
bool perform(IFileOperation* op) {
	if (FAILED(op->PerformOperations())) return false;
	BOOL aborted = FALSE;
	op->GetAnyOperationsAborted(&aborted);
	return !aborted;
}

constexpr DWORD kUiFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMMKDIR | FOFX_ADDUNDORECORD;

int removeItems(const Args& paths, bool recycle) {
	if (paths.empty()) return 2;
	Com<IFileOperation> op;
	if (!newOperation(op.put(), recycle ? kUiFlags | FOFX_RECYCLEONDELETE : FOF_NOCONFIRMMKDIR)) return 1;
	auto queued = 0;
	for (const auto& path: paths) {
		Com<IShellItem> item;
		if (shellItem(path, item.put()) && SUCCEEDED(op->DeleteItem(item.p, nullptr))) ++queued;
	}
	if (queued == 0) return 1;
	return perform(op.p) ? 0 : 1;
}

int rename(const Args& args) {
	if (args.size() != 2 || args[1].empty()) return 2;
	if (args[1].find_first_of(L"\\/:*?\"<>|") != std::wstring::npos) return 3;
	Com<IFileOperation> op;
	Com<IShellItem> item;
	if (!newOperation(op.put(), kUiFlags) || !shellItem(args[0], item.put())) return 1;
	if (FAILED(op->RenameItem(item.p, args[1].c_str(), nullptr)) || !perform(op.p)) return 1;
	auto renamed = parentOf(fullPath(args[0])) + L"\\" + args[1];
	if (!exists(renamed)) return 1;
	printPath(renamed);
	return 0;
}

int newFolder(const Args& args) {
	if (args.size() != 2 || args[1].empty()) return 2;
	auto dir = fullPath(args[0]);
	std::wstring path = dir + L"\\" + args[1];
	for (int i = 2; exists(path) && i < 1000; ++i) path = dir + L"\\" + args[1] + L" (" + std::to_wstring(i) + L")";
	if (!CreateDirectoryW(path.c_str(), nullptr)) return 1;
	SHChangeNotify(SHCNE_MKDIR, SHCNF_PATHW | SHCNF_FLUSH, path.c_str(), nullptr);
	printPath(path);
	return 0;
}

int transfer(const std::wstring& dir, const Args& paths, bool move) {
	if (paths.empty()) return 2;
	auto destination = fullPath(dir);
	// Pasting into the folder an item is already in makes "name - Copy", as in Explorer.
	auto flags = kUiFlags;
	for (const auto& path: paths) {
		if (_wcsicmp(parentOf(fullPath(path)).c_str(), destination.c_str()) == 0) {
			if (move) return 0; // moving onto itself: nothing to do
			flags |= FOF_RENAMEONCOLLISION;
		}
	}
	Com<IFileOperation> op;
	Com<IShellItem> folder;
	if (!newOperation(op.put(), flags) || !shellItem(destination, folder.put())) return 1;
	auto queued = 0;
	for (const auto& path: paths) {
		Com<IShellItem> item;
		if (!shellItem(path, item.put())) continue;
		auto hr = move ? op->MoveItem(item.p, folder.p, nullptr, nullptr) : op->CopyItem(item.p, folder.p, nullptr, nullptr);
		if (SUCCEEDED(hr)) ++queued;
	}
	if (queued == 0) return 1;
	return perform(op.p) ? 0 : 1;
}

UINT dropEffectFormat() {
	static auto format = RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT);
	return format;
}

bool openClipboard() {
	// Another app may hold it for a moment.
	for (int i = 0; i < 20; ++i) {
		if (OpenClipboard(nullptr)) return true;
		Sleep(25);
	}
	return false;
}

int clipSet(const Args& args) {
	if (args.size() < 2 || (args[0] != L"copy" && args[0] != L"cut")) return 2;
	// CF_HDROP: DROPFILES header, then NUL-separated paths, then an extra NUL.
	std::wstring list;
	for (size_t i = 1; i < args.size(); ++i) {
		auto path = fullPath(args[i]);
		if (exists(path)) list += path + L'\0';
	}
	if (list.empty()) return 1;
	list += L'\0';

	auto bytes = sizeof(DROPFILES) + list.size() * sizeof(wchar_t);
	auto* drop = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
	auto* effect = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
	if (!drop || !effect) return 1;
	auto* header = static_cast<DROPFILES*>(GlobalLock(drop));
	header->pFiles = sizeof(DROPFILES);
	header->fWide = TRUE;
	memcpy(reinterpret_cast<BYTE*>(header) + sizeof(DROPFILES), list.data(), list.size() * sizeof(wchar_t)); // NOLINT
	GlobalUnlock(drop);
	*static_cast<DWORD*>(GlobalLock(effect)) = args[0] == L"cut" ? DROPEFFECT_MOVE : DROPEFFECT_COPY;
	GlobalUnlock(effect);

	if (!openClipboard()) {
		GlobalFree(drop);
		GlobalFree(effect);
		return 1;
	}
	EmptyClipboard();
	auto ok = SetClipboardData(CF_HDROP, drop) != nullptr;
	if (!ok) GlobalFree(drop);
	if (!SetClipboardData(dropEffectFormat(), effect)) GlobalFree(effect);
	CloseClipboard();
	return ok ? 0 : 1;
}

// Files on the clipboard and whether they were cut.
bool clipFiles(Args& files, bool& cut) {
	if (!IsClipboardFormatAvailable(CF_HDROP) || !openClipboard()) return false;
	if (auto* drop = static_cast<HDROP>(GetClipboardData(CF_HDROP))) {
		auto count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
		for (UINT i = 0; i < count; ++i) {
			auto length = DragQueryFileW(drop, i, nullptr, 0);
			std::wstring path(length, L'\0');
			DragQueryFileW(drop, i, path.data(), length + 1);
			files.push_back(path);
		}
	}
	cut = false;
	if (auto* effect = GetClipboardData(dropEffectFormat())) {
		if (auto* value = static_cast<DWORD*>(GlobalLock(effect))) {
			cut = (*value & DROPEFFECT_MOVE) != 0;
			GlobalUnlock(effect);
		}
	}
	CloseClipboard();
	return !files.empty();
}

int paste(const Args& args) {
	if (args.size() != 1) return 2;
	Args files;
	bool cut = false;
	if (!clipFiles(files, cut)) return 1;
	auto result = transfer(args[0], files, cut);
	// Cut files can only be pasted once, as in Explorer.
	if (result == 0 && cut && openClipboard()) {
		EmptyClipboard();
		CloseClipboard();
	}
	return result;
}

// Shell extensions run in this process (property sheets, "Send to", zip...). The documented way
// for a host to know when they are done: they hold a reference on the object registered with
// SHSetInstanceExplorer. Also wait for any window of ours.
class ProcessReference: public IUnknown {
public:
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override {
		if (riid == IID_IUnknown) {
			*out = static_cast<IUnknown*>(this);
			AddRef();
			return S_OK;
		}
		*out = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override { return --refs; }
	std::atomic<ULONG> refs = 1;
};

ProcessReference processReference; // NOLINT

bool hasOwnWindows(HWND except) {
	struct Search {
		DWORD pid;
		HWND except;
		bool found = false;
	} search {GetCurrentProcessId(), except};
	EnumWindows(
	    [](HWND hwnd, LPARAM data) -> BOOL {
		    auto* s = reinterpret_cast<Search*>(data); // NOLINT
		    DWORD pid = 0;
		    GetWindowThreadProcessId(hwnd, &pid);
		    if (pid == s->pid && hwnd != s->except && IsWindowVisible(hwnd)) {
			    s->found = true;
			    return FALSE;
		    }
		    return TRUE;
	    },
	    reinterpret_cast<LPARAM>(&search) // NOLINT
	);
	return search.found;
}

// Pumps messages until in-process shell work is over (windows closed, references released).
void waitForShellWork(HWND except) {
	auto start = GetTickCount64();
	auto idleSince = start;
	while (true) {
		MSG msg;
		while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		auto now = GetTickCount64();
		if (hasOwnWindows(except) || processReference.refs > 1) idleSince = now;
		// Give a verb a moment to open its window before deciding it is finished.
		if (now - idleSince > 1500 && now - start > 2500) break;
		MsgWaitForMultipleObjects(0, nullptr, FALSE, 100, QS_ALLINPUT);
	}
}

int properties(const Args& paths) {
	if (paths.empty()) return 2;
	if (paths.size() == 1) {
		auto path = fullPath(paths[0]);
		if (!SHObjectProperties(nullptr, SHOP_FILEPATH, path.c_str(), nullptr)) return 1;
	} else {
		Com<IShellItemArray> array;
		Com<IDataObject> data;
		if (!itemArray(paths, array.put())) return 1;
		if (FAILED(array->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(data.put())))) return 1;
		if (FAILED(SHMultiFileProperties(data.p, 0))) return 1;
	}
	waitForShellWork(nullptr);
	return 0;
}

int openWith(const Args& args) {
	if (args.size() != 1) return 2;
	auto path = fullPath(args[0]);
	OPENASINFO info {};
	info.pcszFile = path.c_str();
	info.oaifInFlags = OAIF_ALLOW_REGISTRATION | OAIF_REGISTER_EXT | OAIF_EXEC;
	return SUCCEEDED(SHOpenWithDialog(nullptr, &info)) ? 0 : 1;
}

// Owner window of the context menu: submenus drawn by shell extensions ("Open with", "Send to",
// "New") need these messages forwarded.
IContextMenu2* menu2 = nullptr; // NOLINT
IContextMenu3* menu3 = nullptr; // NOLINT

LRESULT CALLBACK menuProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
	if (menu3) {
		LRESULT result = 0;
		if (SUCCEEDED(menu3->HandleMenuMsg2(msg, wp, lp, &result))) {
			if (msg == WM_INITMENUPOPUP || msg == WM_DRAWITEM || msg == WM_MEASUREITEM || msg == WM_MENUCHAR) return result;
		}
	} else if (menu2 && (msg == WM_INITMENUPOPUP || msg == WM_DRAWITEM || msg == WM_MEASUREITEM)) {
		if (SUCCEEDED(menu2->HandleMenuMsg(msg, wp, lp))) return 0;
	}
	return DefWindowProcW(hwnd, msg, wp, lp);
}

int contextMenu(Args args) {
	POINT at {};
	GetCursorPos(&at);
	if (args.size() >= 2 && args[0] == L"--at") {
		swscanf_s(args[1].c_str(), L"%ld,%ld", &at.x, &at.y);
		args.erase(args.begin(), args.begin() + 2);
	}
	auto background = !args.empty() && args[0] == L"--background";
	if (background) args.erase(args.begin());
	if (args.empty()) return 2;

	Com<IContextMenu> menu;
	if (background) {
		// The empty folder's menu (New, Paste, ...), as when right-clicking its background.
		Com<IShellItem> folderItem;
		Com<IShellFolder> folder;
		if (!shellItem(args[0], folderItem.put())) return 1;
		if (FAILED(folderItem->BindToHandler(nullptr, BHID_SFObject, IID_PPV_ARGS(folder.put())))) return 1;
		if (FAILED(folder->CreateViewObject(nullptr, IID_PPV_ARGS(menu.put())))) return 1;
	} else {
		Com<IShellItemArray> array;
		if (!itemArray(args, array.put())) return 1;
		if (FAILED(array->BindToHandler(nullptr, BHID_SFUIObject, IID_PPV_ARGS(menu.put())))) return 1;
	}
	menu->QueryInterface(IID_PPV_ARGS(&menu2));
	menu->QueryInterface(IID_PPV_ARGS(&menu3));

	WNDCLASSW wc {};
	wc.lpfnWndProc = menuProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"ii-shim-menu";
	RegisterClassW(&wc);
	// A real (invisible, zero-size) top-level window: TrackPopupMenu needs a foreground owner.
	auto* owner = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"", WS_POPUP, at.x, at.y, 0, 0, nullptr, nullptr, wc.hInstance, nullptr);
	if (!owner) return 1;
	ShowWindow(owner, SW_SHOWNOACTIVATE);
	SetForegroundWindow(owner);

	auto* popup = CreatePopupMenu();
	constexpr UINT kFirst = 1;
	constexpr UINT kLast = 0x7FFF;
	auto flags = CMF_NORMAL | CMF_CANRENAME;
	if (GetKeyState(VK_SHIFT) < 0) flags |= CMF_EXTENDEDVERBS;
	auto result = 1;
	if (SUCCEEDED(menu->QueryContextMenu(popup, 0, kFirst, kLast, flags))) {
		auto command = TrackPopupMenuEx(popup, TPM_RETURNCMD | TPM_RIGHTBUTTON, at.x, at.y, owner, nullptr);
		PostMessageW(owner, WM_NULL, 0, 0);
		if (command >= static_cast<int>(kFirst)) {
			wchar_t verb[64] {};
			menu->GetCommandString(command - kFirst, GCS_VERBW, nullptr, reinterpret_cast<LPSTR>(verb), 63); // NOLINT
			// "rename" needs a view to edit the name in place: hand it to the shell, which does it.
			if (_wcsicmp(verb, L"rename") == 0) {
				std::fputs("rename\n", stdout);
				result = 0;
			} else {
				CMINVOKECOMMANDINFOEX info {};
				info.cbSize = sizeof(info);
				info.fMask = CMIC_MASK_UNICODE | CMIC_MASK_PTINVOKE | CMIC_MASK_ASYNCOK;
				if (GetKeyState(VK_CONTROL) < 0) info.fMask |= CMIC_MASK_CONTROL_DOWN;
				if (GetKeyState(VK_SHIFT) < 0) info.fMask |= CMIC_MASK_SHIFT_DOWN;
				info.hwnd = owner;
				info.lpVerb = MAKEINTRESOURCEA(command - kFirst);
				info.lpVerbW = MAKEINTRESOURCEW(command - kFirst);
				info.nShow = SW_SHOWNORMAL;
				info.ptInvoke = at;
				// A folder's own path lets "New" and "Paste" land in the right place.
				std::wstring directory = background ? fullPath(args[0]) : parentOf(fullPath(args[0]));
				info.lpDirectoryW = directory.c_str();
				result = SUCCEEDED(menu->InvokeCommand(reinterpret_cast<CMINVOKECOMMANDINFO*>(&info))) ? 0 : 1; // NOLINT
				waitForShellWork(owner);
			}
		} else {
			result = 0; // dismissed
		}
	}
	DestroyMenu(popup);
	if (menu3) menu3->Release();
	if (menu2) menu2->Release();
	menu2 = nullptr;
	menu3 = nullptr;
	DestroyWindow(owner);
	return result;
}

} // namespace

int filesCommand(const std::vector<std::wstring>& all) {
	if (all.empty()) return 2;
	auto command = all[0];
	Args args(all.begin() + 1, all.end());
	ComScope com;
	if (!com.ok) return 1;
	SHSetInstanceExplorer(&processReference);

	if (command == L"recycle") return removeItems(args, true);
	if (command == L"delete") return removeItems(args, false);
	if (command == L"rename") return rename(args);
	if (command == L"newfolder") return newFolder(args);
	if (command == L"copy" || command == L"move") {
		if (args.size() < 2) return 2;
		return transfer(args[0], Args(args.begin() + 1, args.end()), command == L"move");
	}
	if (command == L"clip") return clipSet(args);
	if (command == L"paste") return paste(args);
	if (command == L"canpaste") return IsClipboardFormatAvailable(CF_HDROP) ? 0 : 1;
	if (command == L"properties") return properties(args);
	if (command == L"openwith") return openWith(args);
	if (command == L"menu") return contextMenu(args);
	return 2;
}
