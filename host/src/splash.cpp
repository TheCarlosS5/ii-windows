#include "common.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include <objbase.h>
#include <shlobj.h>
#include <wincodec.h>
// GDI+ needs min/max as macros or its own; it only draws the loading indicator.
#include <algorithm>
namespace Gdiplus { using std::max; using std::min; }
#include <gdiplus.h>

// Startup cover: at logon Explorer paints its own wallpaper (and its taskbar flashes) while ii is
// still loading. ii-host --boot shows ii's wallpaper at once, one window per screen, just above
// Explorer's desktop and under any app that opens, and fades it out when the shell's own
// wallpaper window is up (or after a timeout). Nothing is changed in Windows: it is only a window.

namespace ii::splash {

namespace {

constexpr UINT_PTR TIMER_WATCH = 1;
constexpr UINT_PTR TIMER_FADE = 2;
constexpr UINT_PTR TIMER_SPIN = 3;
// As long as the watchdog waits for a stuck shell: the cover only sits above Explorer's desktop
// (apps open above it), so it can stay until ii is really there.
constexpr ULONGLONG TIMEOUT_MS = 90000;
constexpr ULONGLONG SLOW_MS = 15000;
// Once one screen is covered by the shell, the others get this long; after that their covers go
// too (the shell is not going to draw there), instead of sitting on a screen until the timeout.
constexpr ULONGLONG PARTIAL_MS = 10000;

// One cover per screen, and each leaves when the shell's own wallpaper is up on that screen.
struct Cover {
	HWND hwnd = nullptr;
	HBITMAP bitmap = nullptr;
	RECT rect {};
	RECT indicator {}; // where the loading pill has been drawn (grows only): the only part that repaints
	ULONGLONG readySince = 0;
	int alpha = 255;
	bool fading = false;
};

std::vector<Cover> covers;
HWND controller = nullptr; // message-only window owning the timers, so they outlive any one cover
DWORD shellPid = 0;
ULONGLONG shownAt = 0;
ULONGLONG firstReadyAt = 0;
ULONG_PTR gdiplusToken = 0;
bool firstRun = false;
bool spanish = false;

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

// A pill near the bottom: a turning arc (Material's loading indicator, roughly) and what is
// happening. Only GDI+ for the antialiasing.
void paintIndicator(HDC dc, const RECT& client, int originX, int originY, RECT* drawn) {
	if (!gdiplusToken) return;
	using namespace Gdiplus;
	Graphics g(dc);
	// The DC holds only the dirty rectangle starting at (originX, originY) of the window.
	g.TranslateTransform(static_cast<REAL>(-originX), static_cast<REAL>(-originY));
	g.SetSmoothingMode(SmoothingModeAntiAlias);
	g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
	auto dpi = static_cast<REAL>(GetDeviceCaps(dc, LOGPIXELSY)) / 96.0F;
	auto now = GetTickCount64();
	const wchar_t* text = firstRun ? (spanish ? L"Preparando ii por primera vez\u2026" : L"Getting ii ready for the first time\u2026")
	                               : (spanish ? L"Cargando ii\u2026" : L"Loading ii\u2026");
	if (now - shownAt > SLOW_MS) text = spanish ? L"Esto est\u00e1 tardando m\u00e1s de lo normal\u2026" : L"This is taking longer than usual\u2026";

	FontFamily family(L"Segoe UI");
	Font font(&family, 15.0F * dpi, FontStyleRegular, UnitPixel);
	RectF measured;
	g.MeasureString(text, -1, &font, PointF(0, 0), &measured);
	auto spinner = 22.0F * dpi;
	auto pad = 14.0F * dpi;
	auto width = pad + spinner + pad * 0.8F + measured.Width + pad;
	auto height = spinner + pad * 1.4F;
	auto x = (static_cast<REAL>(client.right) - width) / 2;
	auto y = static_cast<REAL>(client.bottom) * 0.78F;

	if (drawn) {
		// Remember the pill's extent (with a margin for antialiasing) so the spinner repaints
		// just this rectangle instead of the whole screen.
		RECT now {static_cast<LONG>(x) - 4, static_cast<LONG>(y) - 4, static_cast<LONG>(x + width) + 4, static_cast<LONG>(y + height) + 4};
		if (drawn->right <= drawn->left) *drawn = now;
		else UnionRect(drawn, drawn, &now);
	}

	GraphicsPath pill;
	auto r = height / 2;
	pill.AddArc(x, y, height, height, 90, 180);
	pill.AddArc(x + width - height, y, height, height, 270, 180);
	pill.CloseFigure();
	SolidBrush back(Color(200, 0x1d, 0x1b, 0x20));
	g.FillPath(&back, &pill);

	Pen track(Color(60, 0xe6, 0xe0, 0xe9), 3.0F * dpi);
	Pen arc(Color(255, 0xd0, 0xbc, 0xff), 3.0F * dpi);
	arc.SetStartCap(LineCapRound);
	arc.SetEndCap(LineCapRound);
	auto sx = x + pad;
	auto sy = y + (height - spinner) / 2;
	g.DrawEllipse(&track, sx, sy, spinner, spinner);
	auto start = static_cast<REAL>((now / 3) % 360);
	auto sweep = 90.0F + 70.0F * static_cast<REAL>(std::sin(static_cast<double>(now) / 450.0));
	g.DrawArc(&arc, sx, sy, spinner, spinner, start, sweep);

	SolidBrush ink(Color(255, 0xe6, 0xe0, 0xe9));
	g.DrawString(text, -1, &font, PointF(sx + spinner + pad * 0.8F, y + (height - measured.Height) / 2), &ink);
	(void) r;
}

LRESULT CALLBACK coverProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	switch (msg) {
	case WM_PAINT: {
		PAINTSTRUCT ps;
		auto* dc = BeginPaint(hwnd, &ps);
		RECT client;
		GetClientRect(hwnd, &client);
		auto it = std::find_if(covers.begin(), covers.end(), [&](const Cover& c) { return c.hwnd == hwnd; });
		// Only the dirty rectangle is composed: the wallpaper does not change, so a spinner
		// frame costs a pill-sized buffer, not a full-screen one.
		auto x0 = ps.rcPaint.left;
		auto y0 = ps.rcPaint.top;
		auto w = ps.rcPaint.right - ps.rcPaint.left;
		auto h = ps.rcPaint.bottom - ps.rcPaint.top;
		if (w > 0 && h > 0) {
			auto* frame = CreateCompatibleDC(dc);
			auto* frameBitmap = CreateCompatibleBitmap(dc, w, h);
			auto* frameOld = SelectObject(frame, frameBitmap);
			if (it != covers.end() && it->bitmap) {
				auto* mem = CreateCompatibleDC(dc);
				auto* old = SelectObject(mem, it->bitmap);
				BitBlt(frame, 0, 0, w, h, mem, x0, y0, SRCCOPY);
				SelectObject(mem, old);
				DeleteDC(mem);
			} else {
				auto* brush = CreateSolidBrush(RGB(0x14, 0x12, 0x18)); // ii's dark surface
				RECT all {0, 0, w, h};
				FillRect(frame, &all, brush);
				DeleteObject(brush);
			}
			paintIndicator(frame, client, x0, y0, it != covers.end() ? &it->indicator : nullptr);
			BitBlt(dc, x0, y0, w, h, frame, 0, 0, SRCCOPY);
			SelectObject(frame, frameOld);
			DeleteObject(frameBitmap);
			DeleteDC(frame);
		}
		EndPaint(hwnd, &ps);
		return 0;
	}
	case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
	case WM_TIMER:
		if (wParam == TIMER_WATCH) watch();
		else if (wParam == TIMER_SPIN) {
			for (auto& c: covers) {
				if (!c.hwnd || c.fading) continue;
				// Before the first paint the pill's place is unknown: repaint everything once.
				InvalidateRect(c.hwnd, c.indicator.right > c.indicator.left ? &c.indicator : nullptr, FALSE);
			}
		}
		else if (wParam == TIMER_FADE) {
			bool any = false;
			for (auto& c: covers) {
				if (!c.hwnd || !c.fading) continue;
				c.alpha -= 32;
				if (c.alpha <= 0) {
					DestroyWindow(c.hwnd);
					c.hwnd = nullptr;
					if (c.bitmap) DeleteObject(c.bitmap);
					c.bitmap = nullptr;
				} else {
					SetLayeredWindowAttributes(c.hwnd, 0, static_cast<BYTE>(c.alpha), LWA_ALPHA);
					any = true;
				}
			}
			bool remaining = std::any_of(covers.begin(), covers.end(), [](const Cover& c) { return c.hwnd != nullptr; });
			if (!remaining) close();
			else if (!any) KillTimer(controller, TIMER_FADE);
		}
		return 0;
	default: return DefWindowProcW(hwnd, msg, wParam, lParam);
	}
}

BOOL CALLBACK addMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM) {
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (GetMonitorInfoW(monitor, &info)) {
		Cover cover;
		cover.rect = info.rcMonitor;
		covers.push_back(cover);
	}
	return TRUE;
}

// The shell's wallpaper is a visible window of its process covering a whole screen: mark each
// cover whose screen has one.
BOOL CALLBACK markCoveredScreens(HWND hwnd, LPARAM data) {
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid != shellPid || !IsWindowVisible(hwnd)) return TRUE;
	RECT r;
	GetWindowRect(hwnd, &r);
	auto* covered = reinterpret_cast<std::vector<bool>*>(data); // NOLINT
	for (size_t i = 0; i < covers.size(); ++i) {
		const auto& c = covers[i];
		if (r.left <= c.rect.left && r.top <= c.rect.top && r.right >= c.rect.right && r.bottom >= c.rect.bottom) (*covered)[i] = true;
	}
	return TRUE;
}

void startFading(Cover& c) {
	if (c.fading || !c.hwnd) return;
	c.fading = true;
	SetTimer(controller, TIMER_FADE, 30, nullptr);
}

} // namespace

// The cover windows only: plain colour, up in a few milliseconds. The wallpaper image is decoded
// afterwards by loadImages(), once the shell has been launched.
void show() {
	if (!covers.empty()) return;
	Gdiplus::GdiplusStartupInput gdiplusInput;
	if (Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusInput, nullptr) != Gdiplus::Ok) gdiplusToken = 0;
	spanish = PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_SPANISH;
	{
		// No compiled QML yet (quickshell/cache/by-shell): the first start takes longer.
		wchar_t* base = nullptr;
		if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) {
			firstRun = GetFileAttributesW((std::wstring(base) + L"\\quickshell\\cache\\by-shell").c_str()) == INVALID_FILE_ATTRIBUTES;
		}
		CoTaskMemFree(base);
	}
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
		c.hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, wc.lpszClassName, L"ii-windows", WS_POPUP,
		                         c.rect.left, c.rect.top, w, h, nullptr, nullptr, wc.hInstance, nullptr);
		SetLayeredWindowAttributes(c.hwnd, 0, 255, LWA_ALPHA);
		ShowWindow(c.hwnd, SW_SHOWNOACTIVATE);
		UpdateWindow(c.hwnd); // the plain colour right now, not at the next message-loop turn
	}
	shownAt = GetTickCount64();
	firstReadyAt = 0;
	if (!covers.empty()) {
		controller = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
		SetTimer(controller, TIMER_WATCH, 150, nullptr);
		SetTimer(controller, TIMER_SPIN, 50, nullptr);
	}
	log(L"splash: shown on %d screen(s)", static_cast<int>(covers.size()));
}

void loadImages() {
	if (covers.empty()) return;
	auto image = wallpaperPath();
	if (image.empty()) {
		log(L"splash: no wallpaper configured, plain cover");
		return;
	}
	auto initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED));
	ULONGLONG started = GetTickCount64();
	for (auto& c: covers) {
		if (!c.hwnd || c.fading) continue;
		c.bitmap = loadCover(image, c.rect.right - c.rect.left, c.rect.bottom - c.rect.top);
		if (c.bitmap) InvalidateRect(c.hwnd, nullptr, FALSE);
	}
	if (initialized) CoUninitialize();
	log(L"splash: wallpaper %s decoded in %llu ms", image.c_str(), GetTickCount64() - started);
}

void setShellPid(DWORD pid) { shellPid = pid; }

void watch() {
	if (covers.empty()) return;
	auto now = GetTickCount64();
	std::vector<bool> covered(covers.size(), false);
	if (shellPid) EnumWindows(markCoveredScreens, reinterpret_cast<LPARAM>(&covered)); // NOLINT

	size_t ready = 0;
	size_t live = 0;
	for (size_t i = 0; i < covers.size(); ++i) {
		auto& c = covers[i];
		if (!c.hwnd) continue;
		++live;
		if (covered[i] && c.readySince == 0) c.readySince = now;
		if (c.readySince) ++ready;
		// Give the shell's wallpaper a moment to paint on that screen, then fade that cover only.
		if (c.readySince && now - c.readySince > 700) {
			log(L"splash: screen %zu ready after %llu ms", i, now - shownAt);
			bench(L"splash-screen-fading", std::to_wstring(i).c_str());
			startFading(c);
		}
	}
	if (ready > 0 && firstReadyAt == 0) firstReadyAt = now;

	// Some screens never got the shell's wallpaper: do not keep them covered for ever.
	auto partialExpired = firstReadyAt != 0 && now - firstReadyAt > PARTIAL_MS;
	auto timedOut = now - shownAt > TIMEOUT_MS;
	if (partialExpired || timedOut) {
		for (size_t i = 0; i < covers.size(); ++i) {
			auto& c = covers[i];
			if (!c.hwnd || c.fading) continue;
			log(L"splash: screen %zu never got the shell's wallpaper (%s), removing its cover", i, timedOut ? L"timeout" : L"others are ready");
			startFading(c);
		}
	}
	(void) live;
	// Once everything is fading there is nothing left to watch or animate.
	bool waiting = std::any_of(covers.begin(), covers.end(), [](const Cover& c) { return c.hwnd && !c.fading; });
	if (!waiting) {
		KillTimer(controller, TIMER_WATCH);
		KillTimer(controller, TIMER_SPIN);
	}
}

void close() {
	if (!covers.empty()) bench(L"splash-closed");
	if (controller) {
		KillTimer(controller, TIMER_WATCH);
		KillTimer(controller, TIMER_SPIN);
		KillTimer(controller, TIMER_FADE);
		DestroyWindow(controller);
		controller = nullptr;
	}
	for (auto& c: covers) {
		if (c.hwnd) DestroyWindow(c.hwnd);
		if (c.bitmap) DeleteObject(c.bitmap);
	}
	covers.clear();
	firstReadyAt = 0;
	if (gdiplusToken) Gdiplus::GdiplusShutdown(gdiplusToken);
	gdiplusToken = 0;
}

} // namespace ii::splash
