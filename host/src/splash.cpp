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
constexpr ULONGLONG SETTLE_MS = 500;
constexpr ULONGLONG FADE_MS = 450;

// The small blurred copy of the wallpaper (wallpaper aspect, this wide).
constexpr UINT SMALL_WIDTH = 160;
constexpr uint32_t CACHE_MAGIC = 0x56434949; // "IICV"
constexpr uint32_t CACHE_VERSION = 2;

struct Cover {
	HWND hwnd = nullptr;
	HBITMAP bitmap = nullptr;
	RECT rect {};
	RECT content {}; // the picture, ring and text in the middle: the part that repaints every frame
	RECT clock {};   // time and date in the corner
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

// How far ii has got: the shell process runs, its first window is up (QML loaded), its wallpaper
// covers the screen (bar and dock follow), its desktop is complete.
enum class Stage { Starting, Interface, Desktop, Ready };
Stage stage = Stage::Starting;
double progressShown = 0;
ULONGLONG expectedMs = 9000; // the last start took this long (startup-ms), for a progress that keeps moving
ULONGLONG lastFrame = 0;
ULONGLONG contentAt = 0;
std::wstring labelNow;
std::wstring labelBefore;
ULONGLONG labelAt = 0;
std::wstring lastClock;
bool reduceMotion = false;
double paintCost = 0;   // ms per content paint, smoothed
bool slowFrames = false;
// ii's palette (dark scheme defaults until colors.json is read).
uint32_t colPrimary = 0xFFA6C8FF;
uint32_t colPrimaryContainer = 0xFF234776;
uint32_t colOnPrimaryContainer = 0xFFD5E3FF;
Gdiplus::PrivateFontCollection* privateFonts = nullptr;
Gdiplus::FontFamily* brandFamily = nullptr;
Gdiplus::FontFamily* textFamily = nullptr; // brandFamily, or a copy of Windows' own face
// The faces at one screen's scale (each screen can have its own).
struct Fonts {
	UINT dpi = 96;
	Gdiplus::Font* greeting = nullptr;
	Gdiplus::Font* status = nullptr;
	Gdiplus::Font* note = nullptr;
	Gdiplus::Font* clock = nullptr;
	Gdiplus::Font* date = nullptr;
	Gdiplus::Font* initial = nullptr;
};
std::vector<Fonts> fontSets;
Gdiplus::Bitmap* avatarBitmap = nullptr;
Gdiplus::TextureBrush* avatarBrush = nullptr;

void frame();

std::wstring widen(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::wstring readyFile() { return dataDir() + L"\\shell-visual-ready"; }
std::wstring cacheFile() { return dataDir() + L"\\cover-cache.bin"; }
std::wstring timingFile() { return dataDir() + L"\\startup-ms"; }

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
				// Dim: a dark veil, a little stronger at the bottom, with a touch of ii's colour.
				auto* p = static_cast<BYTE*>(bits);
				int tint[3] {static_cast<int>(colPrimaryContainer & 0xFF), static_cast<int>((colPrimaryContainer >> 8) & 0xFF), static_cast<int>((colPrimaryContainer >> 16) & 0xFF)};
				for (int y = 0; y < height; ++y) {
					double k = 0.52 - 0.12 * y / height;
					auto mul = static_cast<int>(k * 256);
					for (int x = 0; x < width; ++x, p += 4) {
						for (int c = 0; c < 3; ++c) p[c] = static_cast<BYTE>((((p[c] * mul) >> 8) * 228 + tint[c] * 28) >> 8);
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
	// No picture in Windows: the one Linux shells (and ii there) read, if there is one.
	wchar_t* home = nullptr;
	std::wstring found;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Profile, 0, nullptr, &home))) {
		for (const wchar_t* name: {L"\\.face", L"\\.face.icon"}) {
			auto path = std::wstring(home) + name;
			if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
				found = path;
				break;
			}
		}
	}
	CoTaskMemFree(home);
	return found;
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
			// No copy yet (the first logon after installing): ii's wallpaper (the cover then fades into the
			// same picture), else Windows' sign-in picture.
			for (auto candidate: {wallpaperPath(), lockScreenPath()}) {
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
// Material 3 Expressive, the way Pixels greet you: the account picture in a circle on a slowly turning
// "cookie" shape in the wallpaper's colour, a wavy progress ring round it that fills as ii really loads
// (and flattens out when it is done), a greeting with the first name, what is loading right now, and
// the time and date in the corner like the lock screen's.

std::wstring userDisplayName() {
	wchar_t name[256] {};
	ULONG size = 256;
	if (GetUserNameExW(NameDisplay, name, &size) && name[0]) return name;
	DWORD n = 256;
	if (GetUserNameW(name, &n)) return name;
	return {};
}

// "Carlos Gutiérrez" -> "Carlos" (an e-mail-like name keeps what is before the @).
std::wstring firstName(const std::wstring& full) {
	auto end = full.find_first_of(L" @");
	return end == std::wstring::npos ? full : full.substr(0, end);
}

// A colour of ii's palette (State\user\generated\colors.json, written by switchwall): "#rrggbb" -> ARGB.
bool paletteColour(const std::string& text, const char* key, uint32_t& out) {
	auto at = text.find(std::string("\"") + key + "\"");
	if (at == std::string::npos) return false;
	auto hash = text.find('#', at);
	if (hash == std::string::npos || hash + 7 > text.size()) return false;
	char* end = nullptr;
	auto value = std::strtoul(text.substr(hash + 1, 6).c_str(), &end, 16);
	if (!end || *end) return false;
	out = 0xFF000000u | static_cast<uint32_t>(value);
	return true;
}

void loadPalette() {
	wchar_t* base = nullptr;
	if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) return;
	std::wstring path = std::wstring(base) + L"\\quickshell\\State\\user\\generated\\colors.json";
	CoTaskMemFree(base);
	std::ifstream file(path, std::ios::binary);
	if (!file) return;
	std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	uint32_t c = 0;
	if (paletteColour(text, "primary", c)) colPrimary = c;
	if (paletteColour(text, "primary_container", c)) colPrimaryContainer = c;
	if (paletteColour(text, "on_primary_container", c)) colOnPrimaryContainer = c;
}

// Google Sans Flex, the face ii's own text uses (shipped in quickshell\fonts next to ii-host), else
// Windows 11's Segoe UI Variable.
void loadFonts() {
	using namespace Gdiplus;
	wchar_t self[MAX_PATH] {};
	GetModuleFileNameW(nullptr, self, MAX_PATH);
	std::wstring dir(self);
	dir = dir.substr(0, dir.find_last_of(L"\\/"));
	for (const auto& folder: {dir + L"\\quickshell\\fonts", dir + L"\\..\\..\\..\\quickshell\\fonts"}) {
		WIN32_FIND_DATAW found {};
		auto* find = FindFirstFileW((folder + L"\\GoogleSansFlex*.ttf").c_str(), &found);
		if (find == INVALID_HANDLE_VALUE) continue;
		FindClose(find);
		privateFonts = new PrivateFontCollection;
		if (privateFonts->AddFontFile((folder + L"\\" + found.cFileName).c_str()) == Ok && privateFonts->GetFamilyCount() > 0) {
			int count = 0;
			brandFamily = new FontFamily;
			privateFonts->GetFamilies(1, brandFamily, &count);
			if (count == 1 && brandFamily->GetLastStatus() == Ok) break;
			delete brandFamily;
			brandFamily = nullptr;
		}
		delete privateFonts;
		privateFonts = nullptr;
	}
	if (brandFamily) {
		textFamily = brandFamily->Clone();
	} else {
		FontFamily display(L"Segoe UI Variable Display");
		textFamily = display.GetLastStatus() == Ok ? display.Clone() : FontFamily(L"Segoe UI").Clone();
	}
}

const Fonts& fontsFor(UINT dpi) {
	using namespace Gdiplus;
	for (const auto& f: fontSets) if (f.dpi == dpi) return f;
	auto s = static_cast<REAL>(dpi) / 96.0F;
	Fonts f;
	f.dpi = dpi;
	f.greeting = new Font(textFamily, 34.0F * s, FontStyleRegular, UnitPixel);
	f.status = new Font(textFamily, 17.0F * s, FontStyleRegular, UnitPixel);
	f.note = new Font(textFamily, 14.0F * s, FontStyleRegular, UnitPixel);
	f.clock = new Font(textFamily, 76.0F * s, FontStyleRegular, UnitPixel);
	f.date = new Font(textFamily, 20.0F * s, FontStyleRegular, UnitPixel);
	f.initial = new Font(textFamily, 72.0F * s, FontStyleRegular, UnitPixel);
	fontSets.push_back(f);
	return fontSets.back();
}

void freeDrawing() {
	for (auto& f: fontSets) {
		for (auto* font: {f.greeting, f.status, f.note, f.clock, f.date, f.initial}) delete font;
	}
	fontSets.clear();
	delete textFamily;
	textFamily = nullptr;
	delete avatarBrush;
	avatarBrush = nullptr;
	delete avatarBitmap;
	avatarBitmap = nullptr;
	delete brandFamily;
	brandFamily = nullptr;
	delete privateFonts;
	privateFonts = nullptr;
}

const wchar_t* stageLabel(Stage s) {
	switch (s) {
	case Stage::Starting: return firstRun ? (spanish ? L"Preparando ii por primera vez…" : L"Getting ii ready for the first time…")
	                                      : (spanish ? L"Iniciando ii…" : L"Starting ii…");
	case Stage::Interface: return spanish ? L"Cargando la interfaz…" : L"Loading the interface…";
	case Stage::Desktop: return spanish ? L"Preparando tu escritorio…" : L"Setting up your desktop…";
	case Stage::Ready: return spanish ? L"Todo listo" : L"All set";
	}
	return L"";
}

void setStage(Stage s, ULONGLONG now) {
	if (s <= stage) return;
	stage = s;
	labelBefore = labelNow;
	labelNow = stageLabel(s);
	labelAt = now;
}

// Where the progress should be: real stages set a floor and a ceiling, the time of the last start
// (startup-ms) moves it between them so it never sits still, and never runs ahead of what is done.
double targetProgress(ULONGLONG now) {
	static constexpr double floors[] = {0.03, 0.45, 0.74, 1.0};
	static constexpr double ceilings[] = {0.42, 0.70, 0.95, 1.0};
	auto f = static_cast<double>(now - shownAt) / static_cast<double>(expectedMs);
	auto byTime = 0.92 * (1.0 - std::exp(-2.2 * f));
	auto i = static_cast<int>(stage);
	return std::clamp(byTime, floors[i], ceilings[i]);
}

double easeOutCubic(double t) {
	t = std::clamp(t, 0.0, 1.0);
	return 1 - (1 - t) * (1 - t) * (1 - t);
}

// A spring with a little overshoot (M3 Expressive's "spatial" motion).
double easeOutBack(double t) {
	t = std::clamp(t, 0.0, 1.0);
	constexpr double c1 = 1.5;
	constexpr double c3 = c1 + 1;
	return 1 + c3 * std::pow(t - 1, 3) + c1 * std::pow(t - 1, 2);
}

Gdiplus::Color withAlpha(uint32_t argb, double alpha) {
	auto a = static_cast<BYTE>(std::clamp(alpha, 0.0, 1.0) * ((argb >> 24) & 0xFF));
	return Gdiplus::Color(a, static_cast<BYTE>(argb >> 16), static_cast<BYTE>(argb >> 8), static_cast<BYTE>(argb));
}

// A round shape with soft scallops: M3 Expressive's "cookie" / "sunny".
void addCookie(Gdiplus::GraphicsPath& path, float cx, float cy, float r, int lobes, float depth, double rotation) {
	constexpr int n = 160;
	Gdiplus::PointF points[n];
	for (int i = 0; i < n; ++i) {
		auto a = 2 * 3.14159265358979 * i / n;
		auto rr = r * (1.0F - depth * static_cast<float>(0.5 - 0.5 * std::cos(lobes * (a - rotation))));
		points[i] = Gdiplus::PointF(cx + rr * static_cast<float>(std::cos(a)), cy + rr * static_cast<float>(std::sin(a)));
	}
	path.AddPolygon(points, n);
}

struct Layout {
	UINT dpi = 96;
	float s = 1, cx = 0, cy = 0, face = 0, ring = 0;
	RECT centre {}; // the picture, ring, greeting and status: repainted every frame
	RECT clock {};  // time and date: repainted when the minute changes
};

Layout layoutFor(HWND hwnd, const RECT& client) {
	Layout l;
	l.dpi = GetDpiForWindow(hwnd);
	if (l.dpi == 0) l.dpi = 96;
	l.s = static_cast<float>(l.dpi) / 96.0F;
	auto s = l.s;
	l.cx = static_cast<float>(client.right) / 2;
	l.cy = static_cast<float>(client.bottom) * 0.43F;
	l.face = 184.0F * s;
	l.ring = l.face / 2 + 30.0F * s;
	auto top = l.cy - l.ring - 14 * s;
	auto bottom = l.cy + l.ring + 150 * s;
	l.centre = {static_cast<LONG>(l.cx - 380 * s), static_cast<LONG>(top), static_cast<LONG>(l.cx + 380 * s), static_cast<LONG>(bottom)};
	l.clock = {static_cast<LONG>(40 * s), static_cast<LONG>(28 * s), static_cast<LONG>(720 * s), static_cast<LONG>(190 * s)};
	return l;
}

std::wstring clockText() {
	wchar_t text[64] {};
	GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, nullptr, nullptr, text, 64);
	return text;
}

std::wstring dateText() {
	wchar_t text[128] {};
	GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, 0, nullptr, spanish ? L"dddd, d 'de' MMMM" : L"dddd, MMMM d", text, 128, nullptr);
	std::wstring out = text;
	if (!out.empty()) out[0] = static_cast<wchar_t>(towupper(out[0]));
	return out;
}

void drawCentre(Gdiplus::Graphics& g, const Layout& l, ULONGLONG now) {
	using namespace Gdiplus;
	auto s = l.s;
	const auto& fonts = fontsFor(l.dpi);
	auto t = static_cast<double>(now - contentAt);
	auto still = reduceMotion ? 0.0 : 1.0;

	// Entrance: the picture springs in, the ring follows, the text rises into place.
	auto pop = reduceMotion ? 1.0 : easeOutBack(t / 650.0);
	auto faceAlpha = std::clamp(t / 260.0, 0.0, 1.0);
	auto ringAlpha = std::clamp((t - 150) / 350.0, 0.0, 1.0);
	auto textIn = easeOutCubic((t - 220) / 480.0);

	// The cookie behind the picture, turning slowly.
	auto rotation = still * static_cast<double>(now % 36000) / 36000.0 * 2 * 3.14159265358979;
	auto faceR = static_cast<float>(l.face / 2 * (0.72 + 0.28 * pop));
	{
		GraphicsPath cookie;
		addCookie(cookie, l.cx, l.cy, faceR + 15.0F * s, 12, 0.085F, rotation);
		SolidBrush fill(withAlpha(colPrimaryContainer, 0.95 * faceAlpha));
		g.FillPath(&fill, &cookie);
		GraphicsPath inner;
		addCookie(inner, l.cx, l.cy, faceR + 6.0F * s, 9, 0.07F, -rotation * 1.6);
		SolidBrush fill2(withAlpha(colPrimary, 0.55 * faceAlpha));
		g.FillPath(&fill2, &inner);
	}

	// The picture (or the first letter of the name, like a Google account without one).
	RectF face(l.cx - faceR, l.cy - faceR, faceR * 2, faceR * 2);
	if (avatarBrush && avatarBitmap) {
		auto side = static_cast<REAL>(std::min(avatarBitmap->GetWidth(), avatarBitmap->GetHeight()));
		auto k = face.Width / side;
		Matrix m;
		m.Translate(face.X - (static_cast<REAL>(avatarBitmap->GetWidth()) - side) / 2 * k, face.Y - (static_cast<REAL>(avatarBitmap->GetHeight()) - side) / 2 * k);
		m.Scale(k, k);
		avatarBrush->SetTransform(&m);
		GraphicsPath circle;
		circle.AddEllipse(face);
		if (faceAlpha >= 1.0) {
			g.FillPath(avatarBrush, &circle);
		} else {
			// Fading in: the picture over the plate, through a translucent layer of its own.
			SolidBrush plate(withAlpha(colPrimaryContainer, faceAlpha));
			g.FillPath(&plate, &circle);
			ColorMatrix fade = {{{1, 0, 0, 0, 0}, {0, 1, 0, 0, 0}, {0, 0, 1, 0, 0}, {0, 0, 0, static_cast<REAL>(faceAlpha), 0}, {0, 0, 0, 0, 1}}};
			ImageAttributes attributes;
			attributes.SetColorMatrix(&fade);
			g.SetClip(&circle);
			auto w = static_cast<REAL>(avatarBitmap->GetWidth());
			auto h = static_cast<REAL>(avatarBitmap->GetHeight());
			g.DrawImage(avatarBitmap, face, (w - side) / 2, (h - side) / 2, side, side, UnitPixel, &attributes);
			g.ResetClip();
		}
	} else {
		GraphicsPath circle;
		circle.AddEllipse(face);
		SolidBrush plate(withAlpha(colPrimary, faceAlpha));
		g.FillPath(&plate, &circle);
		auto initial = displayName.empty() ? std::wstring(L"ii") : std::wstring(1, static_cast<wchar_t>(towupper(displayName[0])));
		StringFormat centred;
		centred.SetAlignment(StringAlignmentCenter);
		centred.SetLineAlignment(StringAlignmentCenter);
		SolidBrush letter(withAlpha(colPrimaryContainer, faceAlpha));
		g.DrawString(initial.c_str(), -1, fonts.initial, face, &centred, &letter);
	}

	// The wavy progress ring: the filled part waves and travels, the rest is a quiet track; the wave
	// flattens as it reaches the end.
	auto p = std::clamp(progressShown, 0.0, 1.0);
	auto gapDeg = static_cast<REAL>(9.0F * s / l.ring * 180.0F / 3.14159265358979F);
	auto activeDeg = static_cast<REAL>(p * 360.0);
	auto pw = 5.5F * s;
	Pen track(withAlpha(0xFFFFFFFF, 0.22 * ringAlpha), pw);
	track.SetStartCap(LineCapRound);
	track.SetEndCap(LineCapRound);
	RectF ringBox(l.cx - l.ring, l.cy - l.ring, l.ring * 2, l.ring * 2);
	if (p < 0.999) {
		auto from = -90.0F + activeDeg + (p > 0.002 ? gapDeg : 0);
		auto sweep = 360.0F - activeDeg - (p > 0.002 ? 2 * gapDeg : gapDeg);
		if (sweep > 0.5F) g.DrawArc(&track, ringBox, from, sweep);
	}
	if (p > 0.002) {
		Pen active(withAlpha(colPrimary, ringAlpha), pw);
		active.SetStartCap(LineCapRound);
		active.SetEndCap(LineCapRound);
		active.SetLineJoin(LineJoinRound);
		auto amp = 3.0F * s * static_cast<float>(std::clamp((1.0 - p) * 12.0, 0.0, 1.0) * std::clamp(p * 25.0, 0.0, 1.0)) * static_cast<float>(still);
		constexpr int waves = 15;
		auto phase = still * static_cast<double>(now % 1300) / 1300.0 * 2 * 3.14159265358979;
		auto sweepRad = activeDeg * 3.14159265358979 / 180.0;
		auto n = std::clamp(static_cast<int>(sweepRad * l.ring / (2.0F * s)), 2, 720);
		std::vector<PointF> points(static_cast<size_t>(n));
		for (int i = 0; i < n; ++i) {
			auto a = -3.14159265358979 / 2 + sweepRad * i / (n - 1);
			auto r = l.ring + amp * static_cast<float>(std::sin(waves * a - phase));
			points[static_cast<size_t>(i)] = PointF(l.cx + r * static_cast<float>(std::cos(a)), l.cy + r * static_cast<float>(std::sin(a)));
		}
		g.DrawLines(&active, points.data(), n);
	}

	// Greeting, then what is loading now (the old line slides up and out, the new one rises in).
	StringFormat centre;
	centre.SetAlignment(StringAlignmentCenter);
	centre.SetFormatFlags(StringFormatFlagsNoWrap);
	centre.SetTrimming(StringTrimmingEllipsisCharacter);
	auto rise = static_cast<REAL>((1 - textIn) * 14.0 * s);
	auto y = l.cy + l.ring + 34.0F * s + rise;
	{
		SYSTEMTIME local {};
		GetLocalTime(&local);
		const wchar_t* hello = local.wHour >= 5 && local.wHour < 12 ? (spanish ? L"Buenos días" : L"Good morning")
		                     : local.wHour >= 12 && local.wHour < 19 ? (spanish ? L"Buenas tardes" : L"Good afternoon")
		                                                             : (spanish ? L"Buenas noches" : L"Good evening");
		std::wstring greeting = hello;
		auto first = firstName(displayName);
		if (!first.empty()) greeting += L", " + first;
		SolidBrush ink(withAlpha(0xFFFFFFFF, textIn));
		g.DrawString(greeting.c_str(), -1, fonts.greeting, RectF(l.cx - 370 * s, y, 740 * s, 50 * s), &centre, &ink);
	}
	y += 56.0F * s;
	auto swap = reduceMotion ? 1.0 : easeOutCubic(static_cast<double>(now - labelAt) / 320.0);
	if (!labelBefore.empty() && swap < 1.0) {
		SolidBrush old(withAlpha(0xFFFFFFFF, 0.78 * (1 - swap) * textIn));
		g.DrawString(labelBefore.c_str(), -1, fonts.status, RectF(l.cx - 370 * s, y - static_cast<REAL>(swap * 12 * s), 740 * s, 28 * s), &centre, &old);
	}
	SolidBrush status(withAlpha(0xFFFFFFFF, 0.78 * swap * textIn));
	g.DrawString(labelNow.c_str(), -1, fonts.status, RectF(l.cx - 370 * s, y + static_cast<REAL>((1 - swap) * 12 * s), 740 * s, 28 * s), &centre, &status);

	if (now - shownAt > SLOW_MS && stage != Stage::Ready) {
		const wchar_t* note = spanish ? L"Esto está tardando un poco más de lo normal…" : L"This is taking a little longer than usual…";
		SolidBrush soft(withAlpha(0xFFFFFFFF, 0.55 * textIn));
		g.DrawString(note, -1, fonts.note, RectF(l.cx - 370 * s, y + 34 * s, 740 * s, 24 * s), &centre, &soft);
	}
}

void drawClock(Gdiplus::Graphics& g, const Layout& l, ULONGLONG now) {
	using namespace Gdiplus;
	auto s = l.s;
	const auto& fonts = fontsFor(l.dpi);
	auto in = reduceMotion ? 1.0 : easeOutCubic(static_cast<double>(now - contentAt - 80) / 520.0);
	auto x = static_cast<REAL>(l.clock.left) + static_cast<REAL>((1 - in) * -10 * s);
	auto y = static_cast<REAL>(l.clock.top);
	SolidBrush ink(withAlpha(0xFFFFFFFF, 0.96 * in));
	SolidBrush soft(withAlpha(colOnPrimaryContainer, 0.92 * in));
	auto time = clockText();
	g.DrawString(time.c_str(), -1, fonts.clock, PointF(x, y), &ink);
	auto date = dateText();
	g.DrawString(date.c_str(), -1, fonts.date, PointF(x + 6 * s, y + 104 * s), &soft);
}

void paintContent(HDC dc, Cover& c, const RECT& client, const RECT& dirty) {
	if (!gdiplusToken || !contentOn || !textFamily) return;
	using namespace Gdiplus;
	auto l = layoutFor(c.hwnd, client);
	c.content = l.centre;
	c.clock = l.clock;
	Graphics g(dc);
	g.TranslateTransform(static_cast<REAL>(-dirty.left), static_cast<REAL>(-dirty.top));
	g.SetSmoothingMode(SmoothingModeAntiAlias);
	g.SetPixelOffsetMode(PixelOffsetModeHalf);
	g.SetTextRenderingHint(TextRenderingHintAntiAlias);
	g.SetInterpolationMode(InterpolationModeHighQualityBilinear);
	auto now = GetTickCount64();
	RECT overlap {};
	if (IntersectRect(&overlap, &dirty, &l.centre)) drawCentre(g, l, now);
	if (IntersectRect(&overlap, &dirty, &l.clock)) drawClock(g, l, now);
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
			if (it != covers.end()) {
				LARGE_INTEGER t0 {}, t1 {}, hz {};
				QueryPerformanceCounter(&t0);
				paintContent(frame, *it, client, ps.rcPaint);
				QueryPerformanceCounter(&t1);
				QueryPerformanceFrequency(&hz);
				// A PC that needs long for a frame gets half the frames: the shell loading behind needs the CPU more.
				auto ms = static_cast<double>(t1.QuadPart - t0.QuadPart) * 1000.0 / static_cast<double>(hz.QuadPart);
				paintCost = paintCost * 0.9 + ms * 0.1;
				if (!slowFrames && paintCost > 5.0 && controller && contentOn && GetTickCount64() - contentAt > 1000) {
					slowFrames = true;
					SetTimer(controller, TIMER_SPIN, 33, nullptr);
					log(L"splash: %.1f ms per frame, 30 frames a second", paintCost);
				}
			}
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
		if (covers.empty() || !gdiplusToken) { delete face; return 0; }
		delete avatar;
		avatar = face;
		delete avatarBrush;
		delete avatarBitmap;
		avatarBitmap = new Gdiplus::Bitmap(static_cast<INT>(avatar->width), static_cast<INT>(avatar->height), static_cast<INT>(avatar->width * 4),
		                                   PixelFormat32bppPARGB, avatar->pixels.data());
		avatarBrush = new Gdiplus::TextureBrush(avatarBitmap, Gdiplus::WrapModeClamp);
		return 0;
	}
	case WM_TIMER:
		if (wParam == TIMER_WATCH) watch();
		else if (wParam == TIMER_SPIN) frame();
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

// One animation frame: the progress eases toward where it should be, the parts that move repaint.
void frame() {
	auto now = GetTickCount64();
	bool first = !contentOn;
	if (first) {
		contentOn = true;
		contentAt = now;
		labelNow = stageLabel(stage);
		labelAt = now - 1000;
	}
	auto dt = lastFrame ? static_cast<double>(now - lastFrame) : 16.0;
	lastFrame = now;
	auto target = targetProgress(now);
	auto tau = stage == Stage::Ready ? 110.0 : 320.0;
	if (target > progressShown) progressShown += (target - progressShown) * (1 - std::exp(-dt / tau));
	auto minute = clockText();
	bool clockChanged = minute != lastClock;
	lastClock = minute;
	bool entering = now - contentAt < 900;
	for (auto& c: covers) {
		if (!c.hwnd || c.fading) continue;
		// Before the first paint of the content its place is unknown: repaint everything once.
		if (first || c.content.right <= c.content.left) {
			InvalidateRect(c.hwnd, nullptr, FALSE);
			continue;
		}
		InvalidateRect(c.hwnd, &c.content, FALSE);
		if (entering || clockChanged) InvalidateRect(c.hwnd, &c.clock, FALSE);
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
bool shellWindowSeen = false;

BOOL CALLBACK markCoveredScreens(HWND hwnd, LPARAM data) {
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid != shellPid || !IsWindowVisible(hwnd)) return TRUE;
	wchar_t cls[16] {};
	if (GetClassNameW(hwnd, cls, 16) && wcscmp(cls, L"IiSplash") == 0) return TRUE; // the cover itself (the preview runs it in the "shell")
	shellWindowSeen = true;
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
	// The covers are made per-monitor DPI aware (ii-host as a whole is not): real pixels, sharp text at
	// 125 % or 150 %, instead of a 96 DPI picture Windows stretches.
	auto previousDpi = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
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
	if (previousDpi) SetThreadDpiAwarenessContext(previousDpi);
	firstReadyAt = 0;
	shellSeenAt = 0;
	contentOn = false;
	topmost = true;
	stage = Stage::Starting;
	progressShown = 0;
	paintCost = 0;
	slowFrames = false;
	lastFrame = 0;
	labelBefore.clear();
	lastClock.clear();
	if (covers.empty()) return;
	keyboard::setCoverUp(true);
	controller = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
	SetTimer(controller, TIMER_WATCH, 150, nullptr);
	SetTimer(controller, TIMER_SPIN, 16, nullptr);
	log(L"splash: shown on %d screen(s)", static_cast<int>(covers.size()));

	// After the first frame: GDI+ (fonts), the palette and the user's name, then the picture on its own thread.
	{
		BOOL animations = TRUE;
		SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
		reduceMotion = !animations;
		std::ifstream f(timingFile());
		unsigned long long ms = 0;
		expectedMs = (f >> ms) && ms >= 1500 && ms <= 120000 ? ms : (firstRun ? 20000 : 9000);
	}
	loadPalette();
	Gdiplus::GdiplusStartupInput gdiplusInput;
	if (Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusInput, nullptr) != Gdiplus::Ok) gdiplusToken = 0;
	if (gdiplusToken) loadFonts();
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
	shellWindowSeen = false;
	if (shellPid) EnumWindows(markCoveredScreens, reinterpret_cast<LPARAM>(&covered)); // NOLINT
	bool anyCovered = std::find(covered.begin(), covered.end(), true) != covered.end();
	if (anyCovered && shellSeenAt == 0) shellSeenAt = now;
	if (shellWindowSeen) setStage(Stage::Interface, now);
	if (anyCovered) setStage(Stage::Desktop, now);
	// The shell writes this once its desktop is complete (bar, dock, widgets, icons).
	bool signalled = GetFileAttributesW(readyFile().c_str()) != INVALID_FILE_ATTRIBUTES;
	bool noSignal = shellSeenAt != 0 && now - shellSeenAt > NO_SIGNAL_MS;

	// Above everything while ii loads: windows the shell (or anything else) shows come up under it.
	auto topmostFor = firstRun ? TOPMOST_FIRST_RUN_MS : TOPMOST_MS;
	if (topmost && now - shownAt > topmostFor) {
		topmost = false;
		log(L"splash: still loading after %llu ms, the cover no longer stays above other windows", now - shownAt);
		keyboard::setCoverUp(false);
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
			if (stage != Stage::Ready && signalled) {
				std::ofstream f(timingFile(), std::ios::trunc);
				f << (now - shownAt);
			}
			setStage(Stage::Ready, now);
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
		keyboard::setCoverUp(false);
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
	keyboard::setCoverUp(false);
	freeDrawing();
	delete avatar;
	avatar = nullptr;
	if (gdiplusToken) Gdiplus::GdiplusShutdown(gdiplusToken);
	gdiplusToken = 0;
}

namespace {
std::atomic<bool> refreshing {false};

// Keeps the cached copy on ii's wallpaper (or Windows' sign-in picture when ii has none), so the next
// logon's cover has it at once.
DWORD WINAPI refreshCacheThread(LPVOID) {
	auto image = wallpaperPath();
	if (image.empty() || GetFileAttributesW(image.c_str()) == INVALID_FILE_ATTRIBUTES) image = lockScreenPath();
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
