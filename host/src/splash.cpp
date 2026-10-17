#include "common.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include <objbase.h>
#include <sddl.h>
#include <shlobj.h>
#include <wincodec.h>
#define SECURITY_WIN32
#include <security.h>
// GDI+ needs min/max as macros or its own; it only draws the welcome text and the dots.
namespace Gdiplus { using std::max; using std::min; }
#include <gdiplus.h>

#pragma comment(lib, "secur32.lib")

// Startup cover ("Bienvenido"): Windows' own welcome screen ends as soon as Explorer is up, long
// before ii has loaded, and the user then watched the desktop build itself piece by piece. ii-host
// puts up its own welcome screen at once, styled like Windows' (the same sign-in picture blurred and dimmed,
// the user's picture and name, the turning dots, "Bienvenido"), above everything while ii loads,
// and fades it out in one go when the shell says its desktop is complete (the shell writes
// <dataDir>\shell-visual-ready), or after a time limit. Nothing is changed in Windows: it is only
// a window per screen.
//
// Nothing slow runs on the host's thread: the picture is decoded, blurred and scaled on a worker
// thread, from a small blurred copy cached on disk while ii runs (at logon the disk is busy: a
// full-size decode on the main thread once took 14 s, frozen spinner and all).

namespace ii::splash {

namespace {

constexpr UINT_PTR TIMER_WATCH = 1;
constexpr UINT_PTR TIMER_FADE = 2;
constexpr UINT_PTR TIMER_SPIN = 3;
constexpr UINT WM_SPLASH_IMAGE = WM_APP + 41;  // wParam = cover index, lParam = HBITMAP
constexpr UINT WM_SPLASH_AVATAR = WM_APP + 42; // lParam = AvatarImage*

// Above every window while ii loads (Explorer's taskbar, a startup app...), but not for ever: after
// this long the cover drops behind new windows. The first start (no compiled QML yet) is slower.
constexpr ULONGLONG TOPMOST_MS = 40000;
constexpr ULONGLONG TOPMOST_FIRST_RUN_MS = 70000;
// As long as the watchdog waits for a stuck shell.
constexpr ULONGLONG TIMEOUT_MS = 90000;
constexpr ULONGLONG SLOW_MS = 20000;
// A shell that shows its wallpaper but never writes the ready file (an older ii): leave after this.
constexpr ULONGLONG NO_SIGNAL_MS = 15000;
// Once one screen is ready, the others get this long (the shell is not going to draw there).
constexpr ULONGLONG PARTIAL_MS = 10000;
// After the shell's "ready": a moment for its first frames to reach the screen, then the fade.
constexpr ULONGLONG SETTLE_MS = 350;
constexpr ULONGLONG FADE_MS = 450;

// The small blurred copy of the wallpaper (wallpaper aspect, this wide).
constexpr UINT SMALL_WIDTH = 160;
constexpr uint32_t CACHE_MAGIC = 0x56434949; // "IICV"
constexpr uint32_t CACHE_VERSION = 2;

struct Cover {
	HWND hwnd = nullptr;
	HBITMAP bitmap = nullptr;
	RECT rect {};
	RECT content {}; // where the picture, name and dots are drawn: the only part that repaints
	ULONGLONG readySince = 0;
	ULONGLONG fadeStart = 0;
	bool fading = false;
};

struct AvatarImage {
	UINT width = 0;
	UINT height = 0;
	std::vector<BYTE> pixels; // 32bpp BGRA, top-down
};

std::vector<Cover> covers;
HWND controller = nullptr; // message-only window owning the timers, so they outlive any one cover
DWORD shellPid = 0;
ULONGLONG shownAt = 0;
ULONGLONG shellSeenAt = 0;
ULONGLONG firstReadyAt = 0;
ULONG_PTR gdiplusToken = 0;
bool firstRun = false;
bool spanish = false;
bool contentOn = false; // the text and dots come one tick after the first (plain) paint
bool topmost = true;
COLORREF plainColour = RGB(0x1b, 0x1a, 0x22);
std::wstring displayName;
AvatarImage* avatar = nullptr;
std::atomic<int> generation {0};

std::wstring widen(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::wstring readyFile() { return dataDir() + L"\\shell-visual-ready"; }
std::wstring cacheFile() { return dataDir() + L"\\cover-cache.bin"; }

// A string value of ii's config.json (a plain scan: ii-host has no JSON parser here).
std::string configString(const std::string& text, const char* key) {
	auto at = text.find(std::string("\"") + key + "\"");
	if (at == std::string::npos) return {};
	auto quote = text.find('"', text.find(':', at) + 1);
	if (quote == std::string::npos) return {};
	std::string value;
	for (auto i = quote + 1; i < text.size() && text[i] != '"'; ++i) {
		if (text[i] == '\\' && i + 1 < text.size()) ++i;
		value += text[i];
	}
	return value;
}

// The picture ii shows as the wallpaper (for a video wallpaper, its still).
std::wstring wallpaperPath() {
	wchar_t* base = nullptr;
	if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) return {};
	std::wstring path = std::wstring(base) + L"\\quickshell\\illogical-impulse\\config.json";
	CoTaskMemFree(base);
	std::ifstream file(path, std::ios::binary);
	if (!file) return {};
	std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	auto value = configString(text, "wallpaperPath");
	auto lower = value;
	std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	for (const char* ext: {".mp4", ".webm", ".mkv", ".avi", ".mov", ".gif"}) {
		if (lower.size() > 4 && lower.rfind(ext) == lower.size() - std::strlen(ext)) {
			value = configString(text, "thumbnailPath");
			break;
		}
	}
	if (value.rfind("file://", 0) == 0) value = value.substr(7);
	auto wide = widen(value);
	std::replace(wide.begin(), wide.end(), L'/', L'\\');
	return wide;
}

// ---- the small blurred copy -------------------------------------------------------------------------

struct Small {
	UINT width = 0;
	UINT height = 0;
	std::vector<BYTE> pixels; // BGRA
};

struct FileStamp {
	uint64_t size = 0;
	uint64_t written = 0;
};

FileStamp stampOf(const std::wstring& path) {
	WIN32_FILE_ATTRIBUTE_DATA data {};
	FileStamp s;
	if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
		s.size = (static_cast<uint64_t>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
		s.written = (static_cast<uint64_t>(data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
	}
	return s;
}

// The cached copy is good while the picture it was made from is unchanged. `expected` (optional):
// only a copy of that very picture counts.
bool readCache(Small& out, const std::wstring& expected = {}, std::wstring* source = nullptr) {
	std::ifstream f(cacheFile(), std::ios::binary);
	if (!f) return false;
	uint32_t head[4] {};
	f.read(reinterpret_cast<char*>(head), sizeof(head));
	if (!f || head[0] != CACHE_MAGIC || head[1] != CACHE_VERSION || head[2] == 0 || head[3] == 0 || head[2] > 1024 || head[3] > 1024) return false;
	uint32_t pathChars = 0;
	f.read(reinterpret_cast<char*>(&pathChars), sizeof(pathChars));
	if (!f || pathChars > 4096) return false;
	std::wstring path(pathChars, L'\0');
	f.read(reinterpret_cast<char*>(path.data()), static_cast<std::streamsize>(pathChars * sizeof(wchar_t)));
	FileStamp stamp;
	f.read(reinterpret_cast<char*>(&stamp), sizeof(stamp));
	auto now = stampOf(path);
	if (!f || now.size == 0 || stamp.size != now.size || stamp.written != now.written) return false;
	if (!expected.empty() && _wcsicmp(path.c_str(), expected.c_str()) != 0) return false;
	if (source) *source = path;
	out.width = head[2];
	out.height = head[3];
	out.pixels.resize(static_cast<size_t>(out.width) * out.height * 4);
	f.read(reinterpret_cast<char*>(out.pixels.data()), static_cast<std::streamsize>(out.pixels.size()));
	return static_cast<bool>(f);
}

// The picture behind Windows' own sign-in screen (`ii-shim lockscreen-image`, next to ii-host): the
// cover then continues Windows' "Bienvenido" with the same background. Empty when it cannot tell.
std::wstring lockScreenPath() {
	wchar_t self[MAX_PATH] {};
	GetModuleFileNameW(nullptr, self, MAX_PATH);
	std::wstring dir(self);
	dir = dir.substr(0, dir.find_last_of(L"\\/"));
	auto exe = dir + L"\\quickshell\\bin\\ii-shim.exe"; // where the package puts it
	if (GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES) exe = dir + L"\\ii-shim.exe"; // a build folder
	if (GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES) return {};
	SECURITY_ATTRIBUTES sa {sizeof(sa), nullptr, TRUE};
	HANDLE readEnd = nullptr;
	HANDLE writeEnd = nullptr;
	if (!CreatePipe(&readEnd, &writeEnd, &sa, 0)) return {};
	SetHandleInformation(readEnd, HANDLE_FLAG_INHERIT, 0);
	STARTUPINFOW si {};
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdOutput = writeEnd;
	si.hStdError = writeEnd;
	PROCESS_INFORMATION pi {};
	auto cmd = L"\"" + exe + L"\" lockscreen-image";
	std::string output;
	if (CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr, dir.c_str(), &si, &pi)) {
		CloseHandle(writeEnd);
		writeEnd = nullptr;
		char buffer[1024];
		DWORD n = 0;
		while (ReadFile(readEnd, buffer, sizeof(buffer), &n, nullptr) && n > 0 && output.size() < 8192) output.append(buffer, n);
		WaitForSingleObject(pi.hProcess, 5000);
		DWORD code = 1;
		GetExitCodeProcess(pi.hProcess, &code);
		CloseHandle(pi.hProcess);
		CloseHandle(pi.hThread);
		if (code != 0) output.clear();
	}
	if (writeEnd) CloseHandle(writeEnd);
	CloseHandle(readEnd);
	while (!output.empty() && (output.back() == '\n' || output.back() == '\r')) output.pop_back();
	auto path = widen(output);
	return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES ? path : std::wstring();
}

void writeCache(const std::wstring& image, const Small& s) {
	auto tmp = cacheFile() + L".tmp";
	{
		std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
		if (!f) return;
		uint32_t head[4] {CACHE_MAGIC, CACHE_VERSION, s.width, s.height};
		f.write(reinterpret_cast<const char*>(head), sizeof(head));
		auto chars = static_cast<uint32_t>(image.size());
		f.write(reinterpret_cast<const char*>(&chars), sizeof(chars));
		f.write(reinterpret_cast<const char*>(image.data()), static_cast<std::streamsize>(chars * sizeof(wchar_t)));
		auto stamp = stampOf(image);
		f.write(reinterpret_cast<const char*>(&stamp), sizeof(stamp));
		f.write(reinterpret_cast<const char*>(s.pixels.data()), static_cast<std::streamsize>(s.pixels.size()));
		if (!f) return;
	}
	MoveFileExW(tmp.c_str(), cacheFile().c_str(), MOVEFILE_REPLACE_EXISTING);
}

// Three box passes per direction: close to a Gaussian, on a picture this small it costs nothing.
void blur(Small& s, int radius) {
	auto w = static_cast<int>(s.width);
	auto h = static_cast<int>(s.height);
	std::vector<BYTE> tmp(s.pixels.size());
	auto pass = [&](const BYTE* src, BYTE* dst, bool horizontal) {
		int outer = horizontal ? h : w;
		int inner = horizontal ? w : h;
		for (int o = 0; o < outer; ++o) {
			for (int i = 0; i < inner; ++i) {
				int sum[4] {};
				int n = 0;
				for (int k = -radius; k <= radius; ++k) {
					int j = std::clamp(i + k, 0, inner - 1);
					auto idx = static_cast<size_t>(horizontal ? (o * w + j) : (j * w + o)) * 4;
					for (int c = 0; c < 4; ++c) sum[c] += src[idx + c];
					++n;
				}
				auto idx = static_cast<size_t>(horizontal ? (o * w + i) : (i * w + o)) * 4;
				for (int c = 0; c < 4; ++c) dst[idx + c] = static_cast<BYTE>(sum[c] / n);
			}
		}
	};
	for (int r = 0; r < 3; ++r) {
		pass(s.pixels.data(), tmp.data(), true);
		pass(tmp.data(), s.pixels.data(), false);
	}
}

bool decodeSmall(IWICImagingFactory* factory, const std::wstring& image, Small& out) {
	IWICBitmapDecoder* decoder = nullptr;
	IWICBitmapFrameDecode* frame = nullptr;
	IWICBitmapScaler* scaler = nullptr;
	IWICFormatConverter* converter = nullptr;
	bool ok = false;
	UINT iw = 0;
	UINT ih = 0;
	if (SUCCEEDED(factory->CreateDecoderFromFilename(image.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	    && SUCCEEDED(decoder->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&iw, &ih)) && iw > 0 && ih > 0)
	{
		out.width = std::min<UINT>(SMALL_WIDTH, iw);
		out.height = std::max<UINT>(1, static_cast<UINT>(static_cast<double>(ih) * out.width / iw + 0.5));
		// The JPEG decoder scales while decoding (a fraction of the work of a full decode).
		if (SUCCEEDED(factory->CreateBitmapScaler(&scaler)) && SUCCEEDED(scaler->Initialize(frame, out.width, out.height, WICBitmapInterpolationModeFant))
		    && SUCCEEDED(factory->CreateFormatConverter(&converter))
		    && SUCCEEDED(converter->Initialize(scaler, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)))
		{
			out.pixels.resize(static_cast<size_t>(out.width) * out.height * 4);
			ok = SUCCEEDED(converter->CopyPixels(nullptr, out.width * 4, static_cast<UINT>(out.pixels.size()), out.pixels.data()));
		}
	}
	if (converter) converter->Release();
	if (scaler) scaler->Release();
	if (frame) frame->Release();
	if (decoder) decoder->Release();
	return ok;
}

// The small blurred copy, cropped to the screen's shape like the wallpaper, smoothly scaled up and
// dimmed like Windows' sign-in screen.
HBITMAP coverBitmap(IWICImagingFactory* factory, const Small& s, int width, int height) {
	if (width <= 0 || height <= 0) return nullptr;
	IWICBitmap* source = nullptr;
	IWICBitmapClipper* clipper = nullptr;
	IWICBitmapScaler* scaler = nullptr;
	HBITMAP result = nullptr;
	// Crop to the screen's aspect (the wallpaper fills the screen, centred).
	double screenAspect = static_cast<double>(width) / height;
	double imageAspect = static_cast<double>(s.width) / s.height;
	WICRect crop {0, 0, static_cast<INT>(s.width), static_cast<INT>(s.height)};
	if (imageAspect > screenAspect) {
		crop.Width = std::max(1, static_cast<INT>(s.height * screenAspect + 0.5));
		crop.X = (static_cast<INT>(s.width) - crop.Width) / 2;
	} else {
		crop.Height = std::max(1, static_cast<INT>(s.width / screenAspect + 0.5));
		crop.Y = (static_cast<INT>(s.height) - crop.Height) / 2;
	}
	if (SUCCEEDED(factory->CreateBitmapFromMemory(s.width, s.height, GUID_WICPixelFormat32bppBGRA, s.width * 4,
	                                              static_cast<UINT>(s.pixels.size()), const_cast<BYTE*>(s.pixels.data()), &source))
	    && SUCCEEDED(factory->CreateBitmapClipper(&clipper)) && SUCCEEDED(clipper->Initialize(source, &crop))
	    && SUCCEEDED(factory->CreateBitmapScaler(&scaler))
	    && SUCCEEDED(scaler->Initialize(clipper, static_cast<UINT>(width), static_cast<UINT>(height), WICBitmapInterpolationModeHighQualityCubic)))
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
			auto stride = static_cast<UINT>(width) * 4;
			if (FAILED(scaler->CopyPixels(nullptr, stride, stride * static_cast<UINT>(height), static_cast<BYTE*>(bits)))) {
				DeleteObject(result);
				result = nullptr;
			} else {
				// Dim: a dark veil, a little stronger at the bottom.
				auto* p = static_cast<BYTE*>(bits);
				for (int y = 0; y < height; ++y) {
					double k = 0.58 - 0.10 * y / height;
					auto mul = static_cast<int>(k * 256);
					for (int x = 0; x < width; ++x, p += 4) {
						p[0] = static_cast<BYTE>((p[0] * mul) >> 8);
						p[1] = static_cast<BYTE>((p[1] * mul) >> 8);
						p[2] = static_cast<BYTE>((p[2] * mul) >> 8);
						p[3] = 255;
					}
				}
			}
		}
	}
	if (scaler) scaler->Release();
	if (clipper) clipper->Release();
	if (source) source->Release();
	return result;
}

COLORREF averageColour(const Small& s) {
	uint64_t sum[3] {};
	size_t n = static_cast<size_t>(s.width) * s.height;
	if (n == 0) return plainColour;
	for (size_t i = 0; i < n; ++i) for (int c = 0; c < 3; ++c) sum[c] += s.pixels[i * 4 + c];
	auto d = [&](int c) { return static_cast<BYTE>(sum[c] / n * 0.53); };
	return RGB(d(2), d(1), d(0));
}

// The account picture Windows shows on its sign-in screen (none on many local accounts).
std::wstring accountPicturePath() {
	HANDLE token = nullptr;
	if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
	std::wstring sid;
	DWORD size = 0;
	GetTokenInformation(token, TokenUser, nullptr, 0, &size);
	std::vector<BYTE> buffer(size);
	if (size && GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
		LPWSTR text = nullptr;
		if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &text)) { // NOLINT
			sid = text;
			LocalFree(text);
		}
	}
	CloseHandle(token);
	if (sid.empty()) return {};
	auto key = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AccountPicture\\Users\\" + sid;
	for (const wchar_t* value: {L"Image448", L"Image240", L"Image192", L"Image208"}) {
		wchar_t path[MAX_PATH] {};
		DWORD bytes = sizeof(path);
		if (RegGetValueW(HKEY_LOCAL_MACHINE, key.c_str(), value, RRF_RT_REG_SZ, nullptr, path, &bytes) == ERROR_SUCCESS
		    && GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES)
			return path;
	}
	return {};
}

AvatarImage* decodeAvatar(IWICImagingFactory* factory, const std::wstring& path) {
	if (path.empty()) return nullptr;
	IWICBitmapDecoder* decoder = nullptr;
	IWICBitmapFrameDecode* frame = nullptr;
	IWICFormatConverter* converter = nullptr;
	AvatarImage* result = nullptr;
	UINT w = 0;
	UINT h = 0;
	if (SUCCEEDED(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	    && SUCCEEDED(decoder->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&w, &h)) && w > 0 && h > 0 && w <= 2048 && h <= 2048
	    && SUCCEEDED(factory->CreateFormatConverter(&converter))
	    && SUCCEEDED(converter->Initialize(frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)))
	{
		auto* a = new AvatarImage;
		a->width = w;
		a->height = h;
		a->pixels.resize(static_cast<size_t>(w) * h * 4);
		if (SUCCEEDED(converter->CopyPixels(nullptr, w * 4, static_cast<UINT>(a->pixels.size()), a->pixels.data()))) result = a;
		else delete a;
	}
	if (converter) converter->Release();
	if (frame) frame->Release();
	if (decoder) decoder->Release();
	return result;
}

struct WorkerArgs {
	int generation = 0;
	HWND controller = nullptr;
	std::vector<RECT> rects;
};

DWORD WINAPI worker(LPVOID param) {
	auto* args = static_cast<WorkerArgs*>(param);
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
	auto initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
	IWICImagingFactory* factory = nullptr;
	if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
		auto started = GetTickCount64();
		Small reduced;
		std::wstring image;
		bool cached = readCache(reduced, {}, &image);
		bool ok = cached;
		if (!ok) {
			// No copy yet (the first logon after installing): Windows' sign-in picture, else ii's wallpaper.
			for (auto candidate: {lockScreenPath(), wallpaperPath()}) {
				if (candidate.empty() || !decodeSmall(factory, candidate, reduced)) continue;
				image = candidate;
				blur(reduced, 2);
				writeCache(image, reduced);
				ok = true;
				break;
			}
		}
		if (ok) {
			for (size_t i = 0; i < args->rects.size(); ++i) {
				if (args->generation != generation.load()) break;
				const auto& r = args->rects[i];
				auto* bitmap = coverBitmap(factory, reduced, r.right - r.left, r.bottom - r.top);
				if (bitmap && !PostMessageW(args->controller, WM_SPLASH_IMAGE, i, reinterpret_cast<LPARAM>(bitmap))) DeleteObject(bitmap);
			}
			log(L"splash: background ready in %llu ms (%s%s)", GetTickCount64() - started, cached ? L"cached copy of " : L"", image.c_str());
		} else {
			log(L"splash: no usable picture, plain cover");
		}
		auto* face = decodeAvatar(factory, accountPicturePath());
		if (face && !PostMessageW(args->controller, WM_SPLASH_AVATAR, 0, reinterpret_cast<LPARAM>(face))) delete face;
		factory->Release();
	}
	if (initialized) CoUninitialize();
	delete args;
	return 0;
}

// ---- drawing ------------------------------------------------------------------------------------

std::wstring userDisplayName() {
	wchar_t name[256] {};
	ULONG size = 256;
	if (GetUserNameExW(NameDisplay, name, &size) && name[0]) return name;
	DWORD n = 256;
	if (GetUserNameW(name, &n)) return name;
	return {};
}

// Windows' sign-in screen: the picture in a circle, the name, then the turning dots and "Bienvenido".
// Drawn into a DC holding only the dirty rectangle that starts at (originX, originY) of the window.
void paintContent(HDC dc, const RECT& client, int originX, int originY, RECT* drawn) {
	if (!gdiplusToken || !contentOn) return;
	using namespace Gdiplus;
	Graphics g(dc);
	g.TranslateTransform(static_cast<REAL>(-originX), static_cast<REAL>(-originY));
	g.SetSmoothingMode(SmoothingModeAntiAlias);
	g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
	g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
	auto s = static_cast<REAL>(GetDeviceCaps(dc, LOGPIXELSY)) / 96.0F;
	auto now = GetTickCount64();
	auto cw = static_cast<REAL>(client.right);
	auto ch = static_cast<REAL>(client.bottom);

	// Windows 11's own faces when they are there (they are on 11), Segoe UI otherwise.
	FontFamily display(L"Segoe UI Variable Display");
	FontFamily body(L"Segoe UI Variable Text");
	FontFamily plain(L"Segoe UI");
	auto* nameFamily = display.GetLastStatus() == Ok ? &display : &plain;
	auto* textFamily = body.GetLastStatus() == Ok ? &body : &plain;
	Font nameFont(nameFamily, 30.0F * s, FontStyleBold, UnitPixel);
	Font welcomeFont(textFamily, 20.0F * s, FontStyleRegular, UnitPixel);
	Font smallFont(textFamily, 14.0F * s, FontStyleRegular, UnitPixel);
	StringFormat centre;
	centre.SetAlignment(StringAlignmentCenter);

	auto diameter = 192.0F * s;
	auto cx = cw / 2;
	auto top = ch * 0.5F - diameter * 0.5F - 70.0F * s;
	RectF face(cx - diameter / 2, top, diameter, diameter);

	if (drawn) {
		RECT r {static_cast<LONG>(cx - 260 * s), static_cast<LONG>(top - 8 * s), static_cast<LONG>(cx + 260 * s), static_cast<LONG>(top + diameter + 200 * s)};
		if (drawn->right <= drawn->left) *drawn = r;
		else UnionRect(drawn, drawn, &r);
	}

	// The picture, or Windows' generic person.
	GraphicsPath circle;
	circle.AddEllipse(face);
	if (avatar) {
		Bitmap picture(static_cast<INT>(avatar->width), static_cast<INT>(avatar->height), static_cast<INT>(avatar->width * 4),
		               PixelFormat32bppPARGB, avatar->pixels.data());
		g.SetClip(&circle);
		auto side = std::min(avatar->width, avatar->height);
		g.DrawImage(&picture, face, static_cast<REAL>((avatar->width - side) / 2), static_cast<REAL>((avatar->height - side) / 2),
		            static_cast<REAL>(side), static_cast<REAL>(side), UnitPixel);
		g.ResetClip();
	} else {
		SolidBrush plate(Color(255, 0xcf, 0xcf, 0xd4));
		g.FillPath(&plate, &circle);
		SolidBrush person(Color(255, 0x8a, 0x8a, 0x92));
		g.SetClip(&circle);
		auto head = diameter * 0.36F;
		g.FillEllipse(&person, cx - head / 2, top + diameter * 0.2F, head, head);
		auto body = diameter * 0.74F;
		g.FillEllipse(&person, cx - body / 2, top + diameter * 0.62F, body, diameter * 0.7F);
		g.ResetClip();
	}

	SolidBrush ink(Color(255, 0xff, 0xff, 0xff));
	SolidBrush soft(Color(200, 0xff, 0xff, 0xff));
	auto y = top + diameter + 22.0F * s;
	if (!displayName.empty()) {
		g.DrawString(displayName.c_str(), -1, &nameFont, RectF(cx - 400 * s, y, 800 * s, 46 * s), &centre, &ink);
		y += 46.0F * s;
	}
	y += 22.0F * s;

	const wchar_t* welcome = spanish ? L"Bienvenido" : L"Welcome";
	RectF measured;
	g.MeasureString(welcome, -1, &welcomeFont, PointF(0, 0), &measured);
	auto ring = 22.0F * s;
	auto gap = 14.0F * s;
	auto rowWidth = ring + gap + measured.Width;
	auto rx = cx - rowWidth / 2;
	auto ringCx = rx + ring / 2;
	auto ringCy = y + measured.Height / 2;

	// Five dots running round a ring, bunching up and spreading out (Windows' progress ring).
	constexpr double cycle = 2600.0;
	for (int i = 0; i < 5; ++i) {
		double t = std::fmod((static_cast<double>(now) - i * 110.0) / cycle, 1.0);
		if (t < 0) t += 1.0;
		double eased = t - std::sin(2 * 3.14159265358979 * t) / (2 * 3.14159265358979) * 0.85;
		double angle = -3.14159265358979 / 2 + eased * 2 * 3.14159265358979 * 2; // two laps per cycle
		auto dot = 2.6F * s;
		auto px = ringCx + static_cast<REAL>(std::cos(angle)) * (ring / 2);
		auto py = ringCy + static_cast<REAL>(std::sin(angle)) * (ring / 2);
		g.FillEllipse(&ink, px - dot, py - dot, dot * 2, dot * 2);
	}
	g.DrawString(welcome, -1, &welcomeFont, PointF(rx + ring + gap, y), &ink);

	const wchar_t* note = nullptr;
	if (now - shownAt > SLOW_MS) note = spanish ? L"Esto está tardando un poco más de lo normal…" : L"This is taking a little longer than usual…";
	else if (firstRun) note = spanish ? L"Preparando ii por primera vez…" : L"Getting ii ready for the first time…";
	if (note) g.DrawString(note, -1, &smallFont, RectF(cx - 400 * s, y + measured.Height + 16 * s, 800 * s, 30 * s), &centre, &soft);
}

LRESULT CALLBACK coverProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	switch (msg) {
	case WM_PAINT: {
		PAINTSTRUCT ps;
		auto* dc = BeginPaint(hwnd, &ps);
		RECT client;
		GetClientRect(hwnd, &client);
		auto it = std::find_if(covers.begin(), covers.end(), [&](const Cover& c) { return c.hwnd == hwnd; });
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
				auto* brush = CreateSolidBrush(plainColour);
				RECT all {0, 0, w, h};
				FillRect(frame, &all, brush);
				DeleteObject(brush);
			}
			paintContent(frame, client, x0, y0, it != covers.end() ? &it->content : nullptr);
			BitBlt(dc, x0, y0, w, h, frame, 0, 0, SRCCOPY);
			SelectObject(frame, frameOld);
			DeleteObject(frameBitmap);
			DeleteDC(frame);
		}
		EndPaint(hwnd, &ps);
		return 0;
	}
	case WM_ERASEBKGND: return 1;
	case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
	case WM_SETCURSOR:
		SetCursor(LoadCursorW(nullptr, IDC_APPSTARTING)); // "working in the background", as Windows shows
		return TRUE;
	case WM_SPLASH_IMAGE: {
		auto* bitmap = reinterpret_cast<HBITMAP>(lParam); // NOLINT
		auto i = static_cast<size_t>(wParam);
		if (i < covers.size() && covers[i].hwnd && !covers[i].bitmap) {
			covers[i].bitmap = bitmap;
			InvalidateRect(covers[i].hwnd, nullptr, FALSE);
		} else {
			DeleteObject(bitmap);
		}
		return 0;
	}
	case WM_SPLASH_AVATAR: {
		auto* face = reinterpret_cast<AvatarImage*>(lParam); // NOLINT
		if (covers.empty()) { delete face; return 0; }
		delete avatar;
		avatar = face;
		for (auto& c: covers) if (c.hwnd) InvalidateRect(c.hwnd, c.content.right > c.content.left ? &c.content : nullptr, FALSE);
		return 0;
	}
	case WM_TIMER:
		if (wParam == TIMER_WATCH) watch();
		else if (wParam == TIMER_SPIN) {
			bool first = !contentOn;
			contentOn = true;
			for (auto& c: covers) {
				if (!c.hwnd || c.fading) continue;
				// Before the first paint of the content its place is unknown: repaint everything once.
				InvalidateRect(c.hwnd, (!first && c.content.right > c.content.left) ? &c.content : nullptr, FALSE);
			}
		}
		else if (wParam == TIMER_FADE) {
			bool any = false;
			auto now = GetTickCount64();
			for (auto& c: covers) {
				if (!c.hwnd || !c.fading) continue;
				double t = std::min(1.0, static_cast<double>(now - c.fadeStart) / FADE_MS);
				double eased = 1 - (1 - t) * (1 - t) * (1 - t);
				if (t >= 1.0) {
					DestroyWindow(c.hwnd);
					c.hwnd = nullptr;
					if (c.bitmap) DeleteObject(c.bitmap);
					c.bitmap = nullptr;
				} else {
					SetLayeredWindowAttributes(c.hwnd, 0, static_cast<BYTE>(255 * (1 - eased)), LWA_ALPHA);
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
	c.fadeStart = GetTickCount64();
	SetTimer(controller, TIMER_FADE, 15, nullptr);
}

} // namespace

// The cover windows: a plain colour at once (the average of the cached picture when there is one),
// the blurred wallpaper and the welcome text a moment later.
void show() {
	if (!covers.empty()) return;
	shownAt = GetTickCount64();
	spanish = PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_SPANISH;
	{
		// No compiled QML yet (quickshell/cache/by-shell): the first start takes longer.
		wchar_t* base = nullptr;
		if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) {
			firstRun = GetFileAttributesW((std::wstring(base) + L"\\quickshell\\cache\\by-shell").c_str()) == INVALID_FILE_ATTRIBUTES;
		}
		CoTaskMemFree(base);
	}
	// The shell of an earlier run must not count as ready.
	DeleteFileW(readyFile().c_str());
	{
		// The cached reduced picture is a few KB: its average colour is the first frame.
		std::ifstream f(cacheFile(), std::ios::binary);
		uint32_t head[4] {};
		if (f.read(reinterpret_cast<char*>(head), sizeof(head)) && head[0] == CACHE_MAGIC && head[1] == CACHE_VERSION && head[2] && head[3] && head[2] <= 1024 && head[3] <= 1024) {
			uint32_t chars = 0;
			f.read(reinterpret_cast<char*>(&chars), sizeof(chars));
			if (f && chars <= 4096) {
				f.seekg(static_cast<std::streamoff>(chars * sizeof(wchar_t) + sizeof(FileStamp)), std::ios::cur);
				Small s;
				s.width = head[2];
				s.height = head[3];
				s.pixels.resize(static_cast<size_t>(s.width) * s.height * 4);
				if (f.read(reinterpret_cast<char*>(s.pixels.data()), static_cast<std::streamsize>(s.pixels.size()))) plainColour = averageColour(s);
			}
		}
	}
	EnumDisplayMonitors(nullptr, nullptr, addMonitor, 0);

	WNDCLASSW wc {};
	wc.lpfnWndProc = coverProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"IiSplash";
	wc.hCursor = LoadCursorW(nullptr, IDC_APPSTARTING);
	RegisterClassW(&wc);
	for (auto& c: covers) {
		auto w = c.rect.right - c.rect.left;
		auto h = c.rect.bottom - c.rect.top;
		c.hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TOPMOST, wc.lpszClassName, L"ii-windows", WS_POPUP,
		                         c.rect.left, c.rect.top, w, h, nullptr, nullptr, wc.hInstance, nullptr);
		SetLayeredWindowAttributes(c.hwnd, 0, 255, LWA_ALPHA);
		ShowWindow(c.hwnd, SW_SHOWNOACTIVATE);
		UpdateWindow(c.hwnd); // the plain colour right now, not at the next message-loop turn
	}
	firstReadyAt = 0;
	shellSeenAt = 0;
	contentOn = false;
	topmost = true;
	if (covers.empty()) return;
	controller = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
	SetTimer(controller, TIMER_WATCH, 150, nullptr);
	SetTimer(controller, TIMER_SPIN, 33, nullptr);
	log(L"splash: shown on %d screen(s)", static_cast<int>(covers.size()));

	// After the first frame: GDI+ (fonts) and the user's name, then the picture on its own thread.
	Gdiplus::GdiplusStartupInput gdiplusInput;
	if (Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusInput, nullptr) != Gdiplus::Ok) gdiplusToken = 0;
	displayName = userDisplayName();
	auto* args = new WorkerArgs;
	args->generation = ++generation;
	args->controller = controller;
	for (const auto& c: covers) args->rects.push_back(c.rect);
	if (auto* t = CreateThread(nullptr, 0, worker, args, 0, nullptr)) CloseHandle(t);
	else delete args;
}

// Kept for the call site: the picture is prepared by show()'s worker thread now.
void loadImages() {}

void setShellPid(DWORD pid) { shellPid = pid; }

void watch() {
	if (covers.empty()) return;
	auto now = GetTickCount64();
	std::vector<bool> covered(covers.size(), false);
	if (shellPid) EnumWindows(markCoveredScreens, reinterpret_cast<LPARAM>(&covered)); // NOLINT
	bool anyCovered = std::find(covered.begin(), covered.end(), true) != covered.end();
	if (anyCovered && shellSeenAt == 0) shellSeenAt = now;
	// The shell writes this once its desktop is complete (bar, dock, widgets, icons).
	bool signalled = GetFileAttributesW(readyFile().c_str()) != INVALID_FILE_ATTRIBUTES;
	bool noSignal = shellSeenAt != 0 && now - shellSeenAt > NO_SIGNAL_MS;

	// Above everything while ii loads: windows the shell (or anything else) shows come up under it.
	auto topmostFor = firstRun ? TOPMOST_FIRST_RUN_MS : TOPMOST_MS;
	if (topmost && now - shownAt > topmostFor) {
		topmost = false;
		log(L"splash: still loading after %llu ms, the cover no longer stays above other windows", now - shownAt);
		for (auto& c: covers) if (c.hwnd) SetWindowPos(c.hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
	}
	if (topmost) {
		for (auto& c: covers) {
			if (!c.hwnd || c.fading) continue;
			if (GetWindow(c.hwnd, GW_HWNDPREV)) SetWindowPos(c.hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
		}
	}

	size_t ready = 0;
	for (size_t i = 0; i < covers.size(); ++i) {
		auto& c = covers[i];
		if (!c.hwnd) continue;
		if (covered[i] && (signalled || noSignal) && c.readySince == 0) {
			c.readySince = now;
			log(L"splash: screen %zu ready after %llu ms (%s)", i, now - shownAt, signalled ? L"the shell's desktop is complete" : L"no signal from the shell");
		}
		if (c.readySince) ++ready;
		if (c.readySince && now - c.readySince > SETTLE_MS) {
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
	bool waiting = std::any_of(covers.begin(), covers.end(), [](const Cover& c) { return c.hwnd && !c.fading; });
	if (!waiting) {
		KillTimer(controller, TIMER_WATCH);
		KillTimer(controller, TIMER_SPIN);
	}
}

void close() {
	if (!covers.empty()) bench(L"splash-closed");
	++generation; // a worker still running drops what it makes
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
	delete avatar;
	avatar = nullptr;
	if (gdiplusToken) Gdiplus::GdiplusShutdown(gdiplusToken);
	gdiplusToken = 0;
}

namespace {
std::atomic<bool> refreshing {false};

// Keeps the cached copy on the picture Windows' sign-in screen shows now (Spotlight changes it), so
// the next logon's cover has it at once.
DWORD WINAPI refreshCacheThread(LPVOID) {
	auto image = lockScreenPath();
	if (image.empty()) image = wallpaperPath();
	Small s;
	if (image.empty() || readCache(s, image)) { refreshing = false; return 0; }
	auto initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
	IWICImagingFactory* factory = nullptr;
	if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
		if (decodeSmall(factory, image, s)) {
			blur(s, 2);
			writeCache(image, s);
			log(L"splash: cover picture cached for %s", image.c_str());
		}
		factory->Release();
	}
	if (initialized) CoUninitialize();
	refreshing = false;
	return 0;
}
} // namespace

void refreshCache() {
	// Every ten minutes at most (the caller ticks every second), never while the cover is up (its own
	// worker does it at start).
	static ULONGLONG last = 0;
	auto now = GetTickCount64();
	if (!covers.empty() || (last && now - last < 600000)) return;
	if (refreshing.exchange(true)) return;
	last = now;
	if (auto* t = CreateThread(nullptr, 0, refreshCacheThread, nullptr, 0, nullptr)) CloseHandle(t);
	else refreshing = false;
}

} // namespace ii::splash
