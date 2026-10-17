// ii-shim lockscreen-image: prints the path of the picture Windows shows behind its sign-in screen
// ("Bienvenido"), so ii-host's welcome cover can use the very same one and the switch from Windows'
// screen to ii's is not seen. Windows Spotlight first (its newest picture), then the user's own lock
// screen picture, then Windows' default. Exit 1 when nothing readable was found.

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <shlobj.h>
#include <wincodec.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.System.UserProfile.h>

namespace {

struct Candidate {
	std::wstring path;
	ULONGLONG written = 0;
};

std::wstring localAppData() {
	wchar_t* base = nullptr;
	std::wstring out;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) out = base;
	CoTaskMemFree(base);
	return out;
}

void collect(const std::wstring& dir, bool recurse, std::vector<Candidate>& out, int depth = 0) {
	if (depth > 4) return;
	WIN32_FIND_DATAW data {};
	auto* find = FindFirstFileW((dir + L"\\*").c_str(), &data);
	if (find == INVALID_HANDLE_VALUE) return;
	do {
		std::wstring name = data.cFileName;
		if (name == L"." || name == L"..") continue;
		auto full = dir + L"\\" + name;
		if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
			if (recurse) collect(full, true, out, depth + 1);
			continue;
		}
		auto size = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
		if (size < 150 * 1024) continue; // icons and thumbnails
		Candidate c;
		c.path = full;
		c.written = (static_cast<ULONGLONG>(data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
		out.push_back(c);
	} while (FindNextFileW(find, &data));
	FindClose(find);
}

// A landscape picture WIC can read (Spotlight keeps portrait versions next to the landscape ones).
bool landscape(IWICImagingFactory* factory, const std::wstring& path) {
	IWICBitmapDecoder* decoder = nullptr;
	IWICBitmapFrameDecode* frame = nullptr;
	UINT w = 0;
	UINT h = 0;
	bool ok = SUCCEEDED(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	          && SUCCEEDED(decoder->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&w, &h)) && w >= 1024 && w > h;
	if (frame) frame->Release();
	if (decoder) decoder->Release();
	return ok;
}

bool spotlightOn() {
	DWORD value = 0;
	DWORD size = sizeof(value);
	return RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
	                    L"RotatingLockScreenEnabled", RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS && value == 1;
}

std::wstring newestLandscape(IWICImagingFactory* factory, std::vector<Candidate> found) {
	std::sort(found.begin(), found.end(), [](const Candidate& a, const Candidate& b) { return a.written > b.written; });
	for (const auto& c: found) if (landscape(factory, c.path)) return c.path;
	return {};
}

} // namespace

int lockscreenImage(const std::vector<std::wstring>&) {
	winrt::init_apartment(winrt::apartment_type::multi_threaded);
	IWICImagingFactory* factory = nullptr;
	if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) return 1;
	std::wstring result;
	auto local = localAppData();
	if (spotlightOn() && !local.empty()) {
		// Windows 11 24H2 and later keep Spotlight's pictures here...
		std::vector<Candidate> found;
		collect(local + L"\\Packages\\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\\LocalCache\\Microsoft\\IrisService", true, found);
		result = newestLandscape(factory, found);
		// ...earlier builds here.
		if (result.empty()) {
			found.clear();
			collect(local + L"\\Packages\\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\\LocalState\\Assets", false, found);
			result = newestLandscape(factory, found);
		}
	}
	if (result.empty()) {
		try {
			auto uri = winrt::Windows::System::UserProfile::LockScreen::OriginalImageFile();
			if (uri && uri.SchemeName() == L"file") {
				std::wstring path(winrt::Windows::Foundation::Uri::UnescapeComponent(uri.AbsoluteUri()));
				path = path.substr(8); // file:///
				std::replace(path.begin(), path.end(), L'/', L'\\');
				if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES && landscape(factory, path)) result = path;
			}
		} catch (...) {
		}
	}
	if (result.empty()) {
		wchar_t windir[MAX_PATH] {};
		GetWindowsDirectoryW(windir, MAX_PATH);
		std::wstring fallback = std::wstring(windir) + L"\\Web\\Screen\\img100.jpg";
		if (GetFileAttributesW(fallback.c_str()) != INVALID_FILE_ATTRIBUTES) result = fallback;
	}
	factory->Release();
	if (result.empty()) return 1;
	// UTF-8 on stdout (ii-host reads it).
	auto bytes = WideCharToMultiByte(CP_UTF8, 0, result.c_str(), -1, nullptr, 0, nullptr, nullptr);
	std::string utf8(static_cast<size_t>(bytes), '\0');
	WideCharToMultiByte(CP_UTF8, 0, result.c_str(), -1, utf8.data(), bytes, nullptr, nullptr);
	std::fputs(utf8.c_str(), stdout);
	std::fputc('\n', stdout);
	return 0;
}
