// Screenshots for ii's region selector, in place of grim / magick / wl-copy / tesseract:
//
//   ii-shim screenshot --output <DISPLAY1> <file.png>     whole monitor, physical pixels
//   ii-shim screenshot [--output <DISPLAY1>] --copy [--delay <ms>]   ...straight to the clipboard
//   ii-shim crop <file.png> <x> <y> <w> <h> <action> [<save dir>]
//       action: copy | save | edit | ocr     (the source file is deleted afterwards)
//
// Everything uses what ships with Windows: GDI to capture, WIC to read/write PNG, the clipboard,
// Paint for editing and Windows' own OCR (Windows.Media.Ocr, the user's display languages).

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
// clang-format on

using Microsoft::WRL::ComPtr;
using Args = std::vector<std::wstring>;

namespace {

void notify(const std::wstring& summary, const std::wstring& body) {
	// Same channel as notify-send: the shell's notification sink.
	auto payload = std::wstring(L"Screenshot") + L'\x1f' + summary + L'\x1f' + body + L'\x1f' + L"" + L'\x1f' + L"normal"
	             + L'\x1f' + L"" + L'\x1f' + L"0";
	auto* sink = FindWindowW(L"IiShellNotificationSink", nullptr);
	if (!sink) return;
	COPYDATASTRUCT data {};
	data.dwData = 0x49490010;
	data.cbData = static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
	data.lpData = payload.data();
	DWORD_PTR result = 0;
	SendMessageTimeoutW(sink, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 2000, &result);
}

std::wstring windowsPath(std::wstring path) {
	if (path.rfind(L"file://", 0) == 0) path = path.substr(7);
	if (path.size() > 3 && path[0] == L'/' && path[2] == L':') path = path.substr(1);
	for (auto& c: path) {
		if (c == L'/') c = L'\\';
	}
	return path;
}

void makeParentDirs(const std::wstring& file) {
	auto slash = file.find_last_of(L'\\');
	if (slash == std::wstring::npos) return;
	SHCreateDirectoryExW(nullptr, file.substr(0, slash).c_str(), nullptr);
}

ComPtr<IWICImagingFactory> wic() {
	ComPtr<IWICImagingFactory> factory;
	CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
	return factory;
}

bool savePng(IWICImagingFactory* factory, IWICBitmapSource* source, const std::wstring& path) {
	makeParentDirs(path);
	ComPtr<IWICStream> stream;
	ComPtr<IWICBitmapEncoder> encoder;
	ComPtr<IWICBitmapFrameEncode> frame;
	if (FAILED(factory->CreateStream(&stream)) || FAILED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE))) return false;
	if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder))) return false;
	encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
	encoder->CreateNewFrame(&frame, nullptr);
	frame->Initialize(nullptr);
	UINT width = 0;
	UINT height = 0;
	source->GetSize(&width, &height);
	frame->SetSize(width, height);
	auto format = GUID_WICPixelFormat32bppBGRA;
	frame->SetPixelFormat(&format);
	auto ok = SUCCEEDED(frame->WriteSource(source, nullptr));
	frame->Commit();
	encoder->Commit();
	return ok;
}

std::vector<BYTE> readFile(const std::wstring& path) {
	std::vector<BYTE> bytes;
	auto* file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
	if (file == INVALID_HANDLE_VALUE) return bytes;
	LARGE_INTEGER size {};
	GetFileSizeEx(file, &size);
	bytes.resize(static_cast<size_t>(size.QuadPart));
	DWORD read = 0;
	ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr);
	CloseHandle(file);
	bytes.resize(read);
	return bytes;
}

HGLOBAL toGlobal(const void* data, size_t size) {
	auto* global = GlobalAlloc(GMEM_MOVEABLE, size);
	if (!global) return nullptr;
	std::memcpy(GlobalLock(global), data, size);
	GlobalUnlock(global);
	return global;
}

// Image on the clipboard twice: "PNG" (keeps transparency, what browsers and chat apps prefer)
// and CF_DIB (what every other app reads).
bool copyImage(IWICBitmapSource* source, const std::wstring& pngPath) {
	UINT width = 0;
	UINT height = 0;
	source->GetSize(&width, &height);
	std::vector<BYTE> pixels(static_cast<size_t>(width) * height * 4);
	ComPtr<IWICFormatConverter> converter;
	auto factory = wic();
	factory->CreateFormatConverter(&converter);
	converter->Initialize(source, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom);
	converter->CopyPixels(nullptr, width * 4, static_cast<UINT>(pixels.size()), pixels.data());

	BITMAPINFOHEADER header {};
	header.biSize = sizeof(header);
	header.biWidth = static_cast<LONG>(width);
	header.biHeight = static_cast<LONG>(height); // bottom-up: top-down DIBs confuse many apps
	header.biPlanes = 1;
	header.biBitCount = 32;
	header.biCompression = BI_RGB;
	std::vector<BYTE> dib(sizeof(header) + pixels.size());
	std::memcpy(dib.data(), &header, sizeof(header));
	auto stride = static_cast<size_t>(width) * 4;
	for (UINT row = 0; row < height; ++row) {
		std::memcpy(dib.data() + sizeof(header) + (height - 1 - row) * stride, pixels.data() + row * stride, stride);
	}

	auto png = readFile(pngPath);
	for (int attempt = 0; attempt < 10 && !OpenClipboard(nullptr); ++attempt) Sleep(50);
	EmptyClipboard();
	SetClipboardData(CF_DIB, toGlobal(dib.data(), dib.size()));
	if (!png.empty()) SetClipboardData(RegisterClipboardFormatW(L"PNG"), toGlobal(png.data(), png.size()));
	CloseClipboard();
	return true;
}

bool copyText(const std::wstring& text) {
	for (int attempt = 0; attempt < 10 && !OpenClipboard(nullptr); ++attempt) Sleep(50);
	EmptyClipboard();
	SetClipboardData(CF_UNICODETEXT, toGlobal(text.c_str(), (text.size() + 1) * sizeof(wchar_t)));
	CloseClipboard();
	return true;
}

std::wstring tempPng(const wchar_t* name) {
	wchar_t dir[MAX_PATH];
	GetTempPathW(MAX_PATH, dir);
	return std::wstring(dir) + L"ii-windows\\" + name;
}

std::wstring timestampName() {
	auto now = std::time(nullptr);
	std::tm local {};
	localtime_s(&local, &now);
	wchar_t name[64];
	wcsftime(name, 64, L"screenshot-%Y-%m-%d_%H.%M.%S.png", &local);
	return name;
}

// Throws std::wstring when no OCR language is installed.
std::wstring recognizeText(const std::wstring& pngPath) {
	using namespace winrt::Windows;
	winrt::init_apartment(winrt::apartment_type::multi_threaded);
	auto engine = Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
	// Not for the display language: any installed OCR language will do.
	if (!engine) {
		auto languages = Media::Ocr::OcrEngine::AvailableRecognizerLanguages();
		if (languages.Size() > 0) engine = Media::Ocr::OcrEngine::TryCreateFromLanguage(languages.GetAt(0));
	}
	if (!engine) throw std::wstring(L"Windows has no OCR language installed (Settings > Time & language > Language: add one with \"Optical character recognition\").");
	auto file = Storage::StorageFile::GetFileFromPathAsync(pngPath).get();
	auto stream = file.OpenAsync(Storage::FileAccessMode::Read).get();
	auto decoder = Graphics::Imaging::BitmapDecoder::CreateAsync(stream).get();
	auto bitmap = decoder.GetSoftwareBitmapAsync().get();
	auto result = engine.RecognizeAsync(bitmap).get();
	std::wstring text;
	for (const auto& line: result.Lines()) {
		if (!text.empty()) text += L"\r\n";
		text += line.Text().c_str();
	}
	return text;
}

struct MonitorQuery {
	std::wstring name;
	RECT rect {};
	bool found = false;
};

BOOL CALLBACK findMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM param) {
	auto* query = reinterpret_cast<MonitorQuery*>(param);
	MONITORINFOEXW info {};
	info.cbSize = sizeof(info);
	if (!GetMonitorInfoW(monitor, &info)) return TRUE;
	std::wstring device = info.szDevice;
	auto shortName = device.rfind(L"\\\\.\\", 0) == 0 ? device.substr(4) : device;
	if (query->name.empty() || query->name == device || query->name == shortName) {
		query->rect = info.rcMonitor;
		query->found = true;
		return query->name.empty() && !(info.dwFlags & MONITORINFOF_PRIMARY);
	}
	return TRUE;
}

} // namespace

int screenshot(const Args& args) {
	std::wstring output;
	std::wstring path;
	auto toClipboard = false;
	for (size_t i = 0; i < args.size(); ++i) {
		if ((args[i] == L"--output" || args[i] == L"-o") && i + 1 < args.size()) output = args[++i];
		else if (args[i] == L"--copy") toClipboard = true;
		else if (args[i] == L"--delay" && i + 1 < args.size()) Sleep(static_cast<DWORD>(_wtoi(args[++i].c_str())));
		else path = windowsPath(args[i]);
	}
	if (toClipboard && path.empty()) path = tempPng(L"screen.png");
	if (path.empty()) return 2;

	// Physical pixels, whatever the scaling.
	SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
	MonitorQuery query {output};
	EnumDisplayMonitors(nullptr, nullptr, findMonitor, reinterpret_cast<LPARAM>(&query));
	if (!query.found) return 1;
	auto width = query.rect.right - query.rect.left;
	auto height = query.rect.bottom - query.rect.top;

	auto* screen = GetDC(nullptr);
	auto* memory = CreateCompatibleDC(screen);
	auto* bitmap = CreateCompatibleBitmap(screen, width, height);
	auto* old = SelectObject(memory, bitmap);
	BitBlt(memory, 0, 0, width, height, screen, query.rect.left, query.rect.top, SRCCOPY | CAPTUREBLT);
	SelectObject(memory, old);

	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	auto factory = wic();
	ComPtr<IWICBitmap> wicBitmap;
	auto ok = factory && SUCCEEDED(factory->CreateBitmapFromHBITMAP(bitmap, nullptr, WICBitmapIgnoreAlpha, &wicBitmap))
	       && savePng(factory.Get(), wicBitmap.Get(), path);

	if (ok && toClipboard) copyImage(wicBitmap.Get(), path);

	DeleteObject(bitmap);
	DeleteDC(memory);
	ReleaseDC(nullptr, screen);
	return ok ? 0 : 1;
}

int crop(const Args& args) {
	if (args.size() < 6) return 2;
	auto source = windowsPath(args[0]);
	auto x = _wtoi(args[1].c_str());
	auto y = _wtoi(args[2].c_str());
	auto w = _wtoi(args[3].c_str());
	auto h = _wtoi(args[4].c_str());
	const auto& action = args[5];
	auto saveDir = args.size() > 6 ? windowsPath(args[6]) : std::wstring();
	if (w <= 0 || h <= 0) return 2;

	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	auto factory = wic();
	ComPtr<IWICBitmapDecoder> decoder;
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICBitmapClipper> clipper;
	if (!factory || FAILED(factory->CreateDecoderFromFilename(source.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))) {
		return 1;
	}
	decoder->GetFrame(0, &frame);
	factory->CreateBitmapClipper(&clipper);
	WICRect rect {x, y, w, h};
	if (FAILED(clipper->Initialize(frame.Get(), &rect))) return 1;

	// The crop as a real file first: the clipboard's PNG, Paint and OCR all read it.
	auto cropped = tempPng(L"region.png");
	if (!savePng(factory.Get(), clipper.Get(), cropped)) return 1;
	// WIC may read the source lazily: let go of it before deleting, then work from the crop.
	clipper.Reset();
	frame.Reset();
	decoder.Reset();
	DeleteFileW(source.c_str());
	ComPtr<IWICBitmapFrameDecode> image;
	if (FAILED(factory->CreateDecoderFromFilename(cropped.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad, &decoder))
	    || FAILED(decoder->GetFrame(0, &image)))
	{
		return 1;
	}

	if (action == L"copy" || action == L"save") {
		copyImage(image.Get(), cropped);
		if (action == L"save" || !saveDir.empty()) {
			if (saveDir.empty()) {
				PWSTR pictures = nullptr;
				SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pictures);
				saveDir = std::wstring(pictures) + L"\\Screenshots";
				CoTaskMemFree(pictures);
			}
			auto target = saveDir + L"\\" + timestampName();
			makeParentDirs(target);
			CopyFileW(cropped.c_str(), target.c_str(), FALSE);
			notify(L"Screenshot saved", target);
		}
		return 0;
	}
	if (action == L"edit") {
		auto target = tempPng(timestampName().c_str());
		CopyFileW(cropped.c_str(), target.c_str(), FALSE);
		copyImage(image.Get(), cropped);
		// Paint is Windows' default "edit" handler for PNG.
		auto r = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"edit", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
		if (r <= 32) ShellExecuteW(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
		return 0;
	}
	if (action == L"ocr") {
		std::wstring text;
		try {
			text = recognizeText(cropped);
		} catch (const std::wstring& reason) {
			notify(L"Text recognition unavailable", reason);
			return 1;
		} catch (...) {}
		if (text.empty()) {
			notify(L"No text found", L"Windows OCR found no text in that region.");
			return 1;
		}
		copyText(text);
		notify(L"Text copied", text.size() > 120 ? text.substr(0, 120) + L"…" : text);
		return 0;
	}
	notify(L"Not available on Windows yet", L"This capture action isn't ported yet.");
	return 1;
}

// Diagnostics: prints the text Windows OCR finds in an image, touching nothing else.
int ocrFile(const Args& args) {
	if (args.empty()) return 2;
	try {
		auto text = recognizeText(windowsPath(args[0]));
		DWORD written = 0;
		WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), text.c_str(), static_cast<DWORD>(text.size()), &written, nullptr);
		if (!written) {
			// Redirected: UTF-8.
			auto size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
			std::string utf8(static_cast<size_t>(size), '\0');
			WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), utf8.data(), size, nullptr, nullptr);
			fwrite(utf8.data(), 1, utf8.size(), stdout);
		}
		return text.empty() ? 1 : 0;
	} catch (const std::wstring& reason) {
		fwprintf(stderr, L"%ls\n", reason.c_str());
		return 3;
	} catch (...) {
		return 3;
	}
}

// --- thumbnails and image size (stand-ins for ImageMagick) -----------------------------------

namespace {

// Scales to fit within max x max (never up) and writes a PNG.
bool writeFitted(const std::wstring& source, UINT max, const std::wstring& target) {
	auto factory = wic();
	ComPtr<IWICBitmapDecoder> decoder;
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICBitmapScaler> scaler;
	if (!factory || FAILED(factory->CreateDecoderFromFilename(source.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	    || FAILED(decoder->GetFrame(0, &frame)))
	{
		return false;
	}
	UINT width = 0;
	UINT height = 0;
	frame->GetSize(&width, &height);
	if (width == 0 || height == 0) return false;
	auto scale = std::min(1.0, std::min(static_cast<double>(max) / width, static_cast<double>(max) / height));
	auto w = std::max(1u, static_cast<UINT>(width * scale + 0.5));
	auto h = std::max(1u, static_cast<UINT>(height * scale + 0.5));
	factory->CreateBitmapScaler(&scaler);
	if (FAILED(scaler->Initialize(frame.Get(), w, h, WICBitmapInterpolationModeHighQualityCubic))) return false;
	// Write beside and move, so a half-written thumbnail is never displayed.
	auto temp = target + L".part";
	if (!savePng(factory.Get(), scaler.Get(), temp)) return false;
	return MoveFileExW(temp.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}

} // namespace

// ii-shim thumbnail <source> <max size> <thumbnail.png>: 0 = already there, 1 = generated now
// (ii's ThumbnailImage reloads on 1), 2 = failed.
int thumbnail(const Args& args) {
	if (args.size() != 3) return 2;
	auto target = windowsPath(args[2]);
	if (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES) return 0;
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	return writeFitted(windowsPath(args[0]), static_cast<UINT>(_wtoi(args[1].c_str())), target) ? 1 : 2;
}

// magick identify -format "%w %h" <file>   |   magick <source> -resize <N>x<N> <target>
int magick(const Args& args) {
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (args.size() == 4 && args[0] == L"identify" && args[1] == L"-format" && args[2] == L"%w %h") {
		auto factory = wic();
		ComPtr<IWICBitmapDecoder> decoder;
		ComPtr<IWICBitmapFrameDecode> frame;
		if (!factory || FAILED(factory->CreateDecoderFromFilename(windowsPath(args[3]).c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
		    || FAILED(decoder->GetFrame(0, &frame)))
		{
			return 1;
		}
		UINT width = 0;
		UINT height = 0;
		frame->GetSize(&width, &height);
		std::printf("%u %u", width, height);
		return 0;
	}
	if (args.size() == 4 && args[1] == L"-resize") {
		auto max = static_cast<UINT>(_wtoi(args[2].c_str()));
		return writeFitted(windowsPath(args[0]), max, windowsPath(args[3])) ? 0 : 1;
	}
	return 1;
}
