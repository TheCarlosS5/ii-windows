// Frozen virtual-desktop color picker. No console allocation or helper process.
//   hyprpicker [-a] [-f hex|rgb]
//   hyprpicker --selftest   off-screen bitmap only; never captures the desktop
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace {

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

std::string formatColor(COLORREF color, bool rgb) {
	char text[32];
	if (rgb) std::snprintf(text, sizeof(text), "%u, %u, %u", GetRValue(color), GetGValue(color), GetBValue(color));
	else std::snprintf(text, sizeof(text), "#%02X%02X%02X", GetRValue(color), GetGValue(color), GetBValue(color));
	return text;
}

struct Surface {
	HDC dc = nullptr;
	HBITMAP bitmap = nullptr;
	HGDIOBJ previous = nullptr;
	uint32_t* pixels = nullptr;
	int x = 0, y = 0, width = 0, height = 0;

	Surface() = default;
	Surface(const Surface&) = delete;
	Surface& operator=(const Surface&) = delete;
	~Surface() {
		if (previous) SelectObject(dc, previous);
		if (bitmap) DeleteObject(bitmap);
		if (dc) DeleteDC(dc);
	}
	void create(int left, int top, int w, int h) {
		require(w > 0 && h > 0 && uint64_t(w) * uint64_t(h) <= 128 * 1024 * 1024,
		        "invalid or excessively large desktop bitmap");
		x = left; y = top; width = w; height = h;
		dc = CreateCompatibleDC(nullptr);
		require(dc != nullptr, "cannot create bitmap DC");
		BITMAPINFO info {};
		info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
		info.bmiHeader.biWidth = w;
		info.bmiHeader.biHeight = -h; // top-down, DWORD-aligned BGRA pixels
		info.bmiHeader.biPlanes = 1;
		info.bmiHeader.biBitCount = 32;
		info.bmiHeader.biCompression = BI_RGB;
		void* data = nullptr;
		bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &data, nullptr, 0);
		require(bitmap && data, "cannot allocate bitmap");
		pixels = static_cast<uint32_t*>(data);
		previous = SelectObject(dc, bitmap);
		require(previous && previous != HGDI_ERROR, "cannot select bitmap");
	}
	COLORREF pixel(int screenX, int screenY) const {
		const auto px = int64_t(screenX) - x, py = int64_t(screenY) - y;
		require(px >= 0 && py >= 0 && px < width && py < height, "pixel outside captured desktop");
		auto value = pixels[size_t(py) * size_t(width) + size_t(px)];
		return RGB((value >> 16) & 255, (value >> 8) & 255, value & 255);
	}
};

struct DpiScope {
	DPI_AWARENESS_CONTEXT previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
	DpiScope() { require(previous != nullptr, "cannot enable per-monitor-v2 DPI awareness"); }
	~DpiScope() { SetThreadDpiAwarenessContext(previous); }
};

struct Picker {
	Surface capture, frame;
	POINT cursor {};
	RECT preview {};
	HFONT font = nullptr;
	HPEN grid = nullptr, dark = nullptr, light = nullptr;
	bool done = false, chosen = false, armed = false;
	COLORREF selected = 0;
	ULONGLONG started = GetTickCount64();

	~Picker() {
		if (font) DeleteObject(font);
		if (grid) DeleteObject(grid);
		if (dark) DeleteObject(dark);
		if (light) DeleteObject(light);
	}
	void initialize() {
		auto x = GetSystemMetrics(SM_XVIRTUALSCREEN), y = GetSystemMetrics(SM_YVIRTUALSCREEN);
		auto w = GetSystemMetrics(SM_CXVIRTUALSCREEN), h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
		capture.create(x, y, w, h);
		auto screen = GetDC(nullptr);
		require(screen != nullptr, "cannot access desktop DC");
		auto copied = BitBlt(capture.dc, 0, 0, w, h, screen, x, y, SRCCOPY | CAPTUREBLT);
		ReleaseDC(nullptr, screen);
		require(copied != 0 && GdiFlush() != 0, "cannot capture desktop");
		frame.create(x, y, w, h);
		require(BitBlt(frame.dc, 0, 0, w, h, capture.dc, 0, 0, SRCCOPY) != 0, "cannot prepare picker frame");
		font = CreateFontW(-18, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
		                   OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, FIXED_PITCH, L"Consolas");
		grid = CreatePen(PS_SOLID, 1, RGB(96, 96, 96));
		dark = CreatePen(PS_SOLID, 3, RGB(0, 0, 0));
		light = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
		require(font && grid && dark && light, "cannot create picker drawing objects");
		move(nullptr); // complete first frame before exposing the window
	}
	void restore(const RECT& rect) {
		BitBlt(frame.dc, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
		       capture.dc, rect.left, rect.top, SRCCOPY);
	}
	void move(HWND window) {
		POINT next {};
		if (!GetCursorPos(&next)) { finish(window, false); return; }
		if (window && next.x == cursor.x && next.y == cursor.y) return;
		auto old = preview;
		restore(old);
		cursor = next;
		cursor.x = std::clamp(cursor.x, LONG(capture.x), LONG(capture.x + capture.width - 1));
		cursor.y = std::clamp(cursor.y, LONG(capture.y), LONG(capture.y + capture.height - 1));
		MONITORINFO monitor {};
		monitor.cbSize = sizeof(MONITORINFO);
		RECT bounds {0, 0, capture.width, capture.height};
		if (GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &monitor)) {
			bounds = monitor.rcMonitor;
			OffsetRect(&bounds, -capture.x, -capture.y);
		}
		constexpr int zoom = 8, cells = 17, diameter = zoom * cells, labelHeight = 30;
		int cx = cursor.x - capture.x, cy = cursor.y - capture.y;
		int left = cx + 24, top = cy + 24;
		if (left + diameter + 4 > bounds.right) left = cx - diameter - 28;
		if (top + diameter + labelHeight + 4 > bounds.bottom) top = cy - diameter - labelHeight - 28;
		left = std::clamp(left, int(bounds.left) + 2, std::max(int(bounds.left) + 2, int(bounds.right) - diameter - 2));
		top = std::clamp(top, int(bounds.top) + 2, std::max(int(bounds.top) + 2, int(bounds.bottom) - diameter - labelHeight - 2));
		preview = {left - 2, top - 2, left + diameter + 2, top + diameter + labelHeight + 2};
		auto saved = SaveDC(frame.dc);
		auto circle = CreateEllipticRgn(left, top, left + diameter, top + diameter);
		if (circle) {
			SelectClipRgn(frame.dc, circle);
			DeleteObject(circle);
		}
		// Individual cells also clamp the source at desktop edges: the selected
		// pixel stays exactly in the middle, even at negative virtual coordinates.
		for (int row = 0; row < cells; ++row) for (int col = 0; col < cells; ++col) {
			auto px = std::clamp(int(cursor.x) + col - cells / 2, capture.x, capture.x + capture.width - 1);
			auto py = std::clamp(int(cursor.y) + row - cells / 2, capture.y, capture.y + capture.height - 1);
			SetDCBrushColor(frame.dc, capture.pixel(px, py));
			RECT cell {left + col * zoom, top + row * zoom, left + (col + 1) * zoom, top + (row + 1) * zoom};
			FillRect(frame.dc, &cell, static_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
		}
		SelectObject(frame.dc, grid);
		for (int i = 1; i < cells; ++i) {
			MoveToEx(frame.dc, left + i * zoom, top, nullptr); LineTo(frame.dc, left + i * zoom, top + diameter);
			MoveToEx(frame.dc, left, top + i * zoom, nullptr); LineTo(frame.dc, left + diameter, top + i * zoom);
		}
		SelectObject(frame.dc, GetStockObject(NULL_BRUSH));
		int centerX = left + (cells / 2) * zoom, centerY = top + (cells / 2) * zoom;
		SelectObject(frame.dc, dark);
		Rectangle(frame.dc, centerX, centerY, centerX + zoom, centerY + zoom);
		SelectObject(frame.dc, light);
		Rectangle(frame.dc, centerX, centerY, centerX + zoom, centerY + zoom);
		SelectClipRgn(frame.dc, nullptr);
		SelectObject(frame.dc, dark); Ellipse(frame.dc, left, top, left + diameter, top + diameter);
		SelectObject(frame.dc, light); Ellipse(frame.dc, left, top, left + diameter, top + diameter);
		RECT label {left, top + diameter + 2, left + diameter, top + diameter + labelHeight};
		FillRect(frame.dc, &label, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
		SelectObject(frame.dc, font);
		SetTextColor(frame.dc, RGB(255, 255, 255)); SetBkMode(frame.dc, TRANSPARENT);
		auto hex = formatColor(capture.pixel(cursor.x, cursor.y), false);
		std::wstring text(hex.begin(), hex.end());
		DrawTextW(frame.dc, text.c_str(), -1, &label, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
		RestoreDC(frame.dc, saved);
		if (window) {
			InvalidateRect(window, &old, FALSE);
			InvalidateRect(window, &preview, FALSE);
		}
	}
	void finish(HWND window, bool choose) {
		if (done) return;
		if (choose) {
			POINT point {};
			if (!GetCursorPos(&point) || point.x < capture.x || point.y < capture.y
			    || point.x >= capture.x + capture.width || point.y >= capture.y + capture.height) choose = false;
			else selected = capture.pixel(point.x, point.y);
		}
		chosen = choose; done = true;
		if (window) ShowWindow(window, SW_HIDE);
	}
};

LRESULT CALLBACK pickerProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
	if (message == WM_NCCREATE) {
		auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
		SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
	}
	auto picker = reinterpret_cast<Picker*>(GetWindowLongPtrW(window, GWLP_USERDATA));
	if (!picker) return DefWindowProcW(window, message, wparam, lparam);
	switch (message) {
	case WM_ERASEBKGND: return 1;
	case WM_SETCURSOR: SetCursor(LoadCursorW(nullptr, IDC_CROSS)); return TRUE;
	case WM_MOUSEMOVE: picker->move(window); return 0;
	case WM_LBUTTONDOWN: picker->finish(window, true); return 0;
	case WM_RBUTTONDOWN: case WM_CLOSE: picker->finish(window, false); return 0;
	case WM_KEYDOWN: case WM_SYSKEYDOWN:
		if (wparam == VK_ESCAPE) picker->finish(window, false);
		return 0;
	case WM_KILLFOCUS:
		if (picker->armed) picker->finish(window, false);
		return 0;
	case WM_ACTIVATE:
		if (picker->armed && LOWORD(wparam) == WA_INACTIVE) picker->finish(window, false);
		return 0;
	case WM_TIMER:
		if (GetTickCount64() - picker->started >= 60000 || GetForegroundWindow() != window)
			picker->finish(window, false);
		return 0;
	case WM_DISPLAYCHANGE: case WM_ENDSESSION: picker->finish(window, false); return 0;
	case WM_DPICHANGED:
		// A single PMv2 window covers the physical virtual desktop, not the
		// suggested one-monitor rectangle. Never scale the frozen bitmap.
		return 0;
	case WM_PAINT: {
		PAINTSTRUCT paint {};
		auto dc = BeginPaint(window, &paint);
		auto r = paint.rcPaint;
		BitBlt(dc, r.left, r.top, r.right - r.left, r.bottom - r.top, picker->frame.dc, r.left, r.top, SRCCOPY);
		EndPaint(window, &paint);
		return 0;
	}
	}
	return DefWindowProcW(window, message, wparam, lparam);
}

struct Window {
	HWND handle = nullptr;
	~Window() { if (handle) DestroyWindow(handle); }
};

void copyColor(HWND owner, const std::string& text) {
	auto bytes = (text.size() + 1) * sizeof(wchar_t);
	auto memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
	require(memory != nullptr, "cannot allocate clipboard text");
	auto destination = static_cast<wchar_t*>(GlobalLock(memory));
	if (!destination) { GlobalFree(memory); throw std::runtime_error("cannot lock clipboard text"); }
	for (size_t i = 0; i < text.size(); ++i) destination[i] = static_cast<wchar_t>(text[i]);
	destination[text.size()] = L'\0';
	GlobalUnlock(memory);
	bool opened = false;
	for (int attempt = 0; attempt < 20; ++attempt) {
		if (OpenClipboard(owner)) { opened = true; break; }
		Sleep(10); // bounded retry for another application's brief clipboard lock
	}
	if (!opened) { GlobalFree(memory); throw std::runtime_error("cannot open clipboard"); }
	auto copied = EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, memory) != nullptr;
	CloseClipboard();
	if (!copied) { GlobalFree(memory); throw std::runtime_error("cannot copy clipboard text"); }
	// Windows owns the allocation after SetClipboardData succeeds.
}

int selftest() {
	Surface bitmap;
	bitmap.create(-1920, -200, 3, 2);
	SetPixelV(bitmap.dc, 0, 0, RGB(0x12, 0xAB, 0xEF));
	SetPixelV(bitmap.dc, 2, 1, RGB(1, 2, 3));
	SetPixelV(bitmap.dc, 1, 0, RGB(255, 128, 0));
	GdiFlush();
	require(bitmap.pixel(-1920, -200) == RGB(0x12, 0xAB, 0xEF), "selftest: BGRA/negative-origin pixel");
	require(bitmap.pixel(-1918, -199) == RGB(1, 2, 3), "selftest: bottom-right pixel/stride");
	require(formatColor(bitmap.pixel(-1920, -200), false) == "#12ABEF", "selftest: uppercase hex");
	require(formatColor(bitmap.pixel(-1918, -199), false) == "#010203", "selftest: leading zeroes");
	require(formatColor(bitmap.pixel(-1919, -200), true) == "255, 128, 0", "selftest: RGB format");
	bool rejected = false;
	try { bitmap.pixel(-1921, -200); } catch (const std::runtime_error&) { rejected = true; }
	require(rejected, "selftest: out-of-bounds pixel");
	std::fputs("hyprpicker selftest: PASS (bitmap, virtual coordinates, hex, rgb, bounds)\n", stdout);
	return 0;
}

} // namespace

int hyprpicker(const std::vector<std::wstring>& args) {
	try {
		if (args.size() == 1 && args[0] == L"--selftest") return selftest();
		bool autocopy = false, rgb = false;
		for (size_t i = 0; i < args.size(); ++i) {
			if (args[i] == L"-a" || args[i] == L"--autocopy") autocopy = true;
			else if ((args[i] == L"-f" || args[i] == L"--format") && i + 1 < args.size()) {
				auto value = args[++i];
				require(value == L"hex" || value == L"rgb", "format must be hex or rgb");
				rgb = value == L"rgb";
			} else throw std::runtime_error("usage: hyprpicker [-a] [-f hex|rgb]");
		}
		DpiScope dpi;
		Picker picker;
		picker.initialize();
		auto instance = GetModuleHandleW(nullptr);
		WNDCLASSEXW wc {};
		wc.cbSize = sizeof(WNDCLASSEXW);
		wc.lpfnWndProc = pickerProc; wc.hInstance = instance;
		wc.hCursor = LoadCursorW(nullptr, IDC_CROSS); wc.lpszClassName = L"IiShimHyprpicker";
		require(RegisterClassExW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS, "cannot register picker window");
		Window window;
		window.handle = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, wc.lpszClassName, L"ii color picker", WS_POPUP,
		                               picker.capture.x, picker.capture.y, picker.capture.width, picker.capture.height,
		                               nullptr, nullptr, instance, &picker);
		require(window.handle != nullptr, "cannot create picker window");
		require(SetTimer(window.handle, 1, 100, nullptr) != 0, "cannot start cancellation timer");
		ShowWindow(window.handle, SW_SHOW);
		UpdateWindow(window.handle);
		SetForegroundWindow(window.handle);
		SetFocus(window.handle);
		picker.armed = true;
		if (GetForegroundWindow() != window.handle) picker.finish(window.handle, false);
		MSG message {};
		while (!picker.done) {
			auto result = GetMessageW(&message, nullptr, 0, 0);
			if (result <= 0) { picker.finish(window.handle, false); break; }
			TranslateMessage(&message); DispatchMessageW(&message);
		}
		KillTimer(window.handle, 1);
		if (!picker.chosen) return 1;
		auto text = formatColor(picker.selected, rgb);
		if (autocopy) copyColor(window.handle, text);
		require(std::fprintf(stdout, "%s\n", text.c_str()) > 0 && std::fflush(stdout) == 0, "cannot write stdout");
		return 0;
	} catch (const std::exception& error) {
		std::fprintf(stderr, "hyprpicker: %s\n", error.what());
		return 1;
	}
}
