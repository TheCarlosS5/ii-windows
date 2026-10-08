#include "common.h"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include <objbase.h>
#include <shlobj.h>
#include <wincodec.h>

// Startup cover: at logon Explorer paints its own wallpaper (and its taskbar flashes) while ii is
// still loading. ii-host --boot shows ii's wallpaper at once, one window per screen, just above
// Explorer's desktop and under any app that opens, and fades it out when the shell's own
// wallpaper window is up (or after a timeout). Nothing is changed in Windows: it is only a window.

namespace ii::splash {

namespace {

constexpr UINT_PTR TIMER_WATCH = 1;
constexpr UINT_PTR TIMER_FADE = 2;
constexpr ULONGLONG TIMEOUT_MS = 30000;

struct Cover {
	HWND hwnd = nullptr;
	HBITMAP bitmap = nullptr;
	RECT rect {};
};

std::vector<Cover> covers;
DWORD shellPid = 0;
ULONGLONG shownAt = 0;
ULONGLONG readySince = 0;
int alpha = 255;

std::wstring widen(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

// background.wallpaperPath from ii's config.json (a plain scan: ii-host has no JSON parser).
std::wstring wallpaperPath() {
	wchar_t* base = nullptr;
	if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) return {};
	std::wstring path = std::wstring(base) + L"\\quickshell\\illogical-impulse\\config.json";
	CoTaskMemFree(base);
	std::ifstream file(path, std::ios::binary);
	if (!file) return {};
	std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	auto key = text.find("\"wallpaperPath\"");
	if (key == std::string::npos) return {};
	auto quote = text.find('"', text.find(':', key) + 1);
	if (quote == std::string::npos) return {};
	std::string value;
	for (auto i = quote + 1; i < text.size() && text[i] != '"'; ++i) {
		if (text[i] == '\\' && i + 1 < text.size()) ++i; // \\ and \/ (enough for paths)
		value += text[i];
	}
	auto result = widen(value);
	if (result.rfind(L"file:///", 0) == 0) result = result.substr(8);
	std::replace(result.begin(), result.end(), L'/', L'\\');
	return result;
}

// The image scaled to cover width x height (cropped to the centre), as a 32-bit DIB; or null.
HBITMAP loadCover(const std::wstring& path, int width, int height) {
	if (path.empty() || width <= 0 || height <= 0) return nullptr;
	IWICImagingFactory* factory = nullptr;
	if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) return nullptr;
	HBITMAP result = nullptr;
	IWICBitmapDecoder* decoder = nullptr;
	IWICBitmapFrameDecode* frame = nullptr;
	IWICBitmapScaler* scaler = nullptr;
	IWICFormatConverter* converter = nullptr;
	UINT iw = 0;
	UINT ih = 0;
	if (SUCCEEDED(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	    && SUCCEEDED(decoder->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&iw, &ih)) && iw > 0 && ih > 0)
	{
		auto scale = std::max(static_cast<double>(width) / iw, static_cast<double>(height) / ih);
		auto sw = std::max<UINT>(static_cast<UINT>(width), static_cast<UINT>(iw * scale + 0.5));
		auto sh = std::max<UINT>(static_cast<UINT>(height), static_cast<UINT>(ih * scale + 0.5));
		if (SUCCEEDED(factory->CreateBitmapScaler(&scaler)) && SUCCEEDED(scaler->Initialize(frame, sw, sh, WICBitmapInterpolationModeFant))
		    && SUCCEEDED(factory->CreateFormatConverter(&converter))
		    && SUCCEEDED(converter->Initialize(scaler, GUID_WICPixelFormat32bppBGR, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)))
		{
			BITMAPINFO info {};
			info.bmiHeader.biSize = sizeof(info.bmiHeader);
			info.bmiHeader.biWidth = width;
			info.bmiHeader.biHeight = -height;
			info.bmiHeader.biPlanes = 1;
			info.bmiHeader.biBitCount = 32;
			void* bits = nullptr;
			result = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
			if (result) {
				WICRect crop {static_cast<INT>((sw - width) / 2), static_cast<INT>((sh - height) / 2), width, height};
				if (FAILED(converter->CopyPixels(&crop, static_cast<UINT>(width) * 4, static_cast<UINT>(width) * height * 4, static_cast<BYTE*>(bits)))) {
					DeleteObject(result);
					result = nullptr;
				}
			}
		}
	}
	if (converter) converter->Release();
	if (scaler) scaler->Release();
	if (frame) frame->Release();
	if (decoder) decoder->Release();
	factory->Release();
	return result;
}

LRESULT CALLBACK coverProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	switch (msg) {
	case WM_PAINT: {
		PAINTSTRUCT ps;
		auto* dc = BeginPaint(hwnd, &ps);
		RECT client;
		GetClientRect(hwnd, &client);
		auto it = std::find_if(covers.begin(), covers.end(), [&](const Cover& c) { return c.hwnd == hwnd; });
		if (it != covers.end() && it->bitmap) {
			auto* mem = CreateCompatibleDC(dc);
			auto* old = SelectObject(mem, it->bitmap);
			BitBlt(dc, 0, 0, client.right, client.bottom, mem, 0, 0, SRCCOPY);
			SelectObject(mem, old);
			DeleteDC(mem);
		} else {
			auto* brush = CreateSolidBrush(RGB(0x14, 0x12, 0x18)); // ii's dark surface
			FillRect(dc, &client, brush);
			DeleteObject(brush);
		}
		EndPaint(hwnd, &ps);
		return 0;
	}
	case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
	case WM_TIMER:
		if (wParam == TIMER_WATCH) watch();
		else if (wParam == TIMER_FADE) {
			alpha -= 32;
			if (alpha <= 0) close();
			else for (auto& c: covers) SetLayeredWindowAttributes(c.hwnd, 0, static_cast<BYTE>(alpha), LWA_ALPHA);
		}
		return 0;
	default: return DefWindowProcW(hwnd, msg, wParam, lParam);
	}
}

BOOL CALLBACK addMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM) {
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (GetMonitorInfoW(monitor, &info)) covers.push_back({nullptr, nullptr, info.rcMonitor});
	return TRUE;
}

// The shell's wallpaper is a visible window of its process covering a whole screen.
BOOL CALLBACK findShellWallpaper(HWND hwnd, LPARAM found) {
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid != shellPid || !IsWindowVisible(hwnd)) return TRUE;
	RECT r;
	GetWindowRect(hwnd, &r);
	for (const auto& c: covers) {
		if (r.left <= c.rect.left && r.top <= c.rect.top && r.right >= c.rect.right && r.bottom >= c.rect.bottom) {
			*reinterpret_cast<bool*>(found) = true; // NOLINT
			return FALSE;
		}
	}
	return TRUE;
}

} // namespace

void show() {
	if (!covers.empty()) return;
	auto initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED));
	auto image = wallpaperPath();
	EnumDisplayMonitors(nullptr, nullptr, addMonitor, 0);

	WNDCLASSW wc {};
	wc.lpfnWndProc = coverProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"IiSplash";
	wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
	RegisterClassW(&wc);
	for (auto& c: covers) {
		auto w = c.rect.right - c.rect.left;
		auto h = c.rect.bottom - c.rect.top;
		c.bitmap = loadCover(image, w, h);
		c.hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, wc.lpszClassName, L"ii-windows", WS_POPUP,
		                         c.rect.left, c.rect.top, w, h, nullptr, nullptr, wc.hInstance, nullptr);
		SetLayeredWindowAttributes(c.hwnd, 0, 255, LWA_ALPHA);
		ShowWindow(c.hwnd, SW_SHOWNOACTIVATE);
	}
	if (initialized) CoUninitialize();
	shownAt = GetTickCount64();
	alpha = 255;
	if (!covers.empty()) SetTimer(covers.front().hwnd, TIMER_WATCH, 150, nullptr);
	log(L"splash: shown on %d screen(s), wallpaper %s", static_cast<int>(covers.size()), image.empty() ? L"(none)" : image.c_str());
}

void setShellPid(DWORD pid) { shellPid = pid; }

void watch() {
	if (covers.empty()) return;
	auto now = GetTickCount64();
	auto found = false;
	if (shellPid) EnumWindows(findShellWallpaper, reinterpret_cast<LPARAM>(&found)); // NOLINT
	if (found && readySince == 0) readySince = now;
	// Give the shell's wallpaper a moment to paint, then fade.
	if ((readySince && now - readySince > 700) || now - shownAt > TIMEOUT_MS) {
		KillTimer(covers.front().hwnd, TIMER_WATCH);
		SetTimer(covers.front().hwnd, TIMER_FADE, 30, nullptr);
		log(L"splash: %s after %llu ms", readySince ? L"shell ready" : L"timeout", now - shownAt);
	}
}

void close() {
	for (auto& c: covers) {
		if (c.hwnd) DestroyWindow(c.hwnd);
		if (c.bitmap) DeleteObject(c.bitmap);
	}
	covers.clear();
	readySince = 0;
}

} // namespace ii::splash
