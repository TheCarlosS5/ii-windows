// extwall: which live-wallpaper program (Wallpaper Engine or Lively) is running, and what it shows.
//
//   ii-shim extwall status [--we-dir <dir>] [--lively-dir <dir>] [--assume-running]
//
// Prints one line of JSON:
//   {"provider":"wallpaperengine|lively|none","running":true,"title":"...","preview":"C:\\...\\preview.jpg",
//    "source":"C:\\...\\project.json","type":"scene"}
// ii uses it to let the live wallpaper show through ii's (transparent) background window and to take the
// palette from `preview`, the picture the program itself keeps for each wallpaper.
//
// Read-only: it never starts, stops or changes those programs, never writes to their folders and never runs or
// opens anything their metadata names (a preview is only decoded as a picture). The files are parsed
// leniently: a missing key just leaves its field empty. --we-dir / --lively-dir point at an install (or a
// copy of one) for tests; --assume-running skips the process check.
//
// What is read:
//   Wallpaper Engine   <install>\config.json -> "selectedwallpapers" -> a monitor's "file" -> project.json
//                      (title, type, preview).
//   Lively             <data>\WallpaperLayout.json -> "LivelyInfoFolderPath" -> LivelyInfo.json
//                      (Title, Thumbnail / Preview, Type).

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <tlhelp32.h>
#include <wincodec.h>
#include <wrl/client.h>

#include "jsonlite.h"

using Microsoft::WRL::ComPtr;
using Args = std::vector<std::wstring>;

namespace {

std::string utf8(const std::wstring& text) {
	if (text.empty()) return {};
	auto size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(size), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
	return out;
}

std::wstring wide(const std::string& text) {
	if (text.empty()) return {};
	auto size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(size), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
	return out;
}

std::string lower(std::string text) {
	for (auto& c: text) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
	return text;
}

std::wstring lowerW(std::wstring text) {
	for (auto& c: text) c = static_cast<wchar_t>(std::towlower(c));
	return text;
}

bool endsWithI(const std::wstring& text, const std::wstring& suffix) {
	auto a = lowerW(text);
	auto b = lowerW(suffix);
	return a.size() >= b.size() && a.compare(a.size() - b.size(), b.size(), b) == 0;
}

std::wstring slashes(std::wstring path) {
	std::replace(path.begin(), path.end(), L'/', L'\\');
	return path;
}

bool fileExists(const std::wstring& path) {
	auto attrs = GetFileAttributesW(path.c_str());
	return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

bool dirExists(const std::wstring& path) {
	auto attrs = GetFileAttributesW(path.c_str());
	return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring dirName(const std::wstring& path) {
	auto at = path.find_last_of(L"\\/");
	return at == std::wstring::npos ? std::wstring() : path.substr(0, at);
}

std::wstring baseName(const std::wstring& path) {
	auto at = path.find_last_of(L"\\/");
	return at == std::wstring::npos ? path : path.substr(at + 1);
}

bool isAbsolute(const std::wstring& path) {
	return (path.size() >= 3 && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) || path.rfind(L"\\\\", 0) == 0;
}

// A path from a metadata file: absolute as is, otherwise relative to the folder of that file.
std::wstring resolve(const std::wstring& folder, const std::wstring& path) {
	auto p = slashes(path);
	return isAbsolute(p) || folder.empty() ? p : folder + L"\\" + p;
}

bool isPictureName(const std::wstring& path) {
	for (const wchar_t* ext: {L".jpg", L".jpeg", L".png", L".gif", L".bmp", L".webp", L".tif", L".tiff"})
		if (endsWithI(path, ext)) return true;
	return false;
}

bool isMediaName(const std::wstring& path) {
	if (isPictureName(path)) return true;
	for (const wchar_t* ext: {L".mp4", L".webm", L".mkv", L".mov", L".avi", L".wmv"})
		if (endsWithI(path, ext)) return true;
	return false;
}

// Text of a small metadata file (at most 8 MB), without a UTF-8 BOM.
bool readFile(const std::wstring& path, std::string& out) {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	if (!file) return false;
	auto size = file.tellg();
	if (size < 0 || size > 8 * 1024 * 1024) return false;
	file.seekg(0);
	std::ostringstream text;
	text << file.rdbuf();
	out = text.str();
	if (out.rfind("\xEF\xBB\xBF", 0) == 0) out.erase(0, 3);
	return true;
}

bool loadJson(const std::wstring& path, jsonlite::Value& out) {
	std::string text;
	if (!readFile(path, text)) return false;
	auto parsed = jsonlite::parse(text);
	if (!parsed.ok) return false;
	out = std::move(parsed.value);
	return true;
}

// First member called `key` (any case) anywhere below `value`: the files nest it differently between
// versions (and Wallpaper Engine's config.json starts with the Steam user's name).
const jsonlite::Value* findKey(const jsonlite::Value& value, const std::string& key, int depth = 0) {
	if (depth > 12) return nullptr;
	if (value.type == jsonlite::Type::Object) {
		for (const auto& [name, child]: value.members)
			if (lower(name) == key) return &child;
		for (const auto& [name, child]: value.members)
			if (auto* found = findKey(child, key, depth + 1)) return found;
	} else if (value.type == jsonlite::Type::Array) {
		for (const auto& item: value.items)
			if (auto* found = findKey(item, key, depth + 1)) return found;
	}
	return nullptr;
}

std::string textOf(const jsonlite::Value* value) {
	if (!value) return {};
	if (value->type == jsonlite::Type::String) return value->text;
	if (value->type == jsonlite::Type::Number) return value->number;
	return {};
}

std::wstring localAppData() {
	wchar_t buffer[MAX_PATH * 2] {};
	auto n = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, static_cast<DWORD>(std::size(buffer)));
	return std::wstring(buffer, n);
}

struct Info {
	std::string provider = "none";
	bool running = false;
	std::string title;
	std::string preview;
	std::string source;
	std::string type;
};

// ---- Wallpaper Engine ----------------------------------------------------------------------------------

bool wallpaperEngineInfo(const std::wstring& dir, Info& info) {
	jsonlite::Value config;
	if (!loadJson(dir + L"\\config.json", config)) return false;
	auto* selected = findKey(config, "selectedwallpapers");
	if (!selected || !selected->isObject()) return false;

	std::string file;
	if (auto* direct = selected->find("file"); direct && direct->type == jsonlite::Type::String) {
		file = direct->text;
	} else {
		// One entry per monitor ("Monitor0": {"file": ...}); the first with a file is the main one.
		for (const auto& [name, monitor]: selected->members) {
			auto candidate = monitor.isObject() ? textOf(monitor.find("file")) : std::string();
			if (!candidate.empty()) {
				file = candidate;
				break;
			}
		}
	}
	if (file.empty()) return false;

	auto path = resolve(dir, wide(file));
	info.source = utf8(path);
	std::wstring project;
	if (endsWithI(path, L"project.json")) project = path;
	else if (fileExists(dirName(path) + L"\\project.json")) project = dirName(path) + L"\\project.json";

	if (!project.empty()) {
		jsonlite::Value meta;
		if (loadJson(project, meta)) {
			auto folder = dirName(project);
			info.title = textOf(meta.find("title"));
			info.type = lower(textOf(meta.find("type")));
			auto preview = resolve(folder, wide(textOf(meta.find("preview"))));
			if (!textOf(meta.find("preview")).empty() && isPictureName(preview) && fileExists(preview)) info.preview = utf8(preview);
			// A video or picture project: the file itself can stand in for a missing preview.
			auto own = textOf(meta.find("file"));
			if (info.preview.empty() && !own.empty() && isMediaName(wide(own))) info.source = utf8(resolve(folder, wide(own)));
		}
	}
	if (info.title.empty()) info.title = utf8(baseName(dirName(path).empty() ? path : dirName(path)));
	return true;
}

// ---- Lively ---------------------------------------------------------------------------------------------

std::vector<std::wstring> livelyDataDirs() {
	std::vector<std::wstring> dirs;
	auto local = localAppData();
	if (local.empty()) return dirs;
	dirs.push_back(local + L"\\Lively Wallpaper");
	// The Microsoft Store build keeps its data under its package.
	WIN32_FIND_DATAW found {};
	auto handle = FindFirstFileW((local + L"\\Packages\\12030rocksdanister.LivelyWallpaper_*").c_str(), &found);
	if (handle != INVALID_HANDLE_VALUE) {
		do {
			if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				dirs.push_back(local + L"\\Packages\\" + found.cFileName + L"\\LocalCache\\Local\\Lively Wallpaper");
		} while (FindNextFileW(handle, &found));
		FindClose(handle);
	}
	return dirs;
}

bool livelyInfoIn(const std::wstring& dataDir, Info& info) {
	jsonlite::Value layout;
	if (!loadJson(dataDir + L"\\WallpaperLayout.json", layout)) return false;
	std::wstring folder = wide(textOf(findKey(layout, "livelyinfofolderpath")));
	if (folder.empty()) {
		auto infoPath = wide(textOf(findKey(layout, "livelyinfopath")));
		if (endsWithI(infoPath, L"LivelyInfo.json")) folder = dirName(infoPath);
	}
	if (folder.empty()) return false;
	folder = resolve(dataDir, folder);

	jsonlite::Value meta;
	if (!loadJson(folder + L"\\LivelyInfo.json", meta)) return false;
	info.title = textOf(meta.find("Title"));
	info.type = lower(textOf(meta.find("Type")));
	auto fileName = textOf(meta.find("FileName"));
	info.source = utf8(fileName.empty() ? folder : resolve(folder, wide(fileName)));
	for (const char* key: {"Thumbnail", "Preview"}) {
		auto name = textOf(meta.find(key));
		if (name.empty()) continue;
		auto path = resolve(folder, wide(name));
		if (isPictureName(path) && fileExists(path)) {
			info.preview = utf8(path);
			break;
		}
	}
	if (info.title.empty()) info.title = utf8(baseName(folder));
	return true;
}

// ---- processes -------------------------------------------------------------------------------------------

// Full path of the first running process with this exe name, or empty.
std::wstring runningPath(const wchar_t* exe) {
	auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snapshot == INVALID_HANDLE_VALUE) return {};
	std::wstring path;
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	for (auto ok = Process32FirstW(snapshot, &entry); ok && path.empty(); ok = Process32NextW(snapshot, &entry)) {
		if (_wcsicmp(entry.szExeFile, exe) != 0) continue;
		if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID)) {
			wchar_t buffer[MAX_PATH * 2] {};
			DWORD size = static_cast<DWORD>(std::size(buffer));
			if (QueryFullProcessImageNameW(process, 0, buffer, &size)) path.assign(buffer, size);
			CloseHandle(process);
		}
		if (path.empty()) path = exe; // running, but its folder is not readable
	}
	CloseHandle(snapshot);
	return path;
}

// ---- a preview for wallpapers that have none (a plain video) ------------------------------------------------

// Explorer's own thumbnail of a picture or video, saved as a PNG next to ii's data.
bool makeThumbnail(const std::wstring& media, const std::wstring& png) {
	ComPtr<IShellItemImageFactory> factory;
	if (FAILED(SHCreateItemFromParsingName(media.c_str(), nullptr, IID_PPV_ARGS(&factory)))) return false;
	HBITMAP bitmap = nullptr;
	if (FAILED(factory->GetImage(SIZE {256, 256}, SIIGBF_BIGGERSIZEOK, &bitmap)) || !bitmap) return false;

	ComPtr<IWICImagingFactory> wic;
	ComPtr<IWICBitmap> source;
	ComPtr<IWICStream> stream;
	ComPtr<IWICBitmapEncoder> encoder;
	ComPtr<IWICBitmapFrameEncode> frame;
	ComPtr<IPropertyBag2> options;
	auto ok = SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))
	       && SUCCEEDED(wic->CreateBitmapFromHBITMAP(bitmap, nullptr, WICBitmapUseAlpha, &source))
	       && SUCCEEDED(wic->CreateStream(&stream)) && SUCCEEDED(stream->InitializeFromFilename(png.c_str(), GENERIC_WRITE))
	       && SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder))
	       && SUCCEEDED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) && SUCCEEDED(encoder->CreateNewFrame(&frame, &options))
	       && SUCCEEDED(frame->Initialize(options.Get()));
	if (ok) {
		UINT width = 0, height = 0;
		source->GetSize(&width, &height);
		WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
		ok = SUCCEEDED(frame->SetSize(width, height)) && SUCCEEDED(frame->SetPixelFormat(&format))
		  && SUCCEEDED(frame->WriteSource(source.Get(), nullptr)) && SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
	}
	DeleteObject(bitmap);
	return ok;
}

} // namespace

int extwall(const Args& args) {
	if (args.empty() || args[0] != L"status") {
		std::fputs("usage: extwall status [--we-dir <dir>] [--lively-dir <dir>] [--assume-running]\n", stderr);
		return 2;
	}
	std::wstring weDir, livelyDir;
	auto assume = false;
	for (size_t i = 1; i < args.size(); ++i) {
		if (args[i] == L"--we-dir" && i + 1 < args.size()) weDir = args[++i];
		else if (args[i] == L"--lively-dir" && i + 1 < args.size()) livelyDir = args[++i];
		else if (args[i] == L"--assume-running") assume = true;
	}
	auto initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED));

	Info info;
	// Wallpaper Engine (its folder is where the running exe is, or where config.json is one level up).
	auto weExe = weDir.empty() ? runningPath(L"wallpaper64.exe") : std::wstring();
	if (weExe.empty() && weDir.empty()) weExe = runningPath(L"wallpaper32.exe");
	auto weRunning = assume || !weExe.empty();
	if (weDir.empty() && !weExe.empty()) {
		weDir = dirName(weExe);
		if (!fileExists(weDir + L"\\config.json") && fileExists(dirName(weDir) + L"\\config.json")) weDir = dirName(weDir);
	}
	if (weRunning && !weDir.empty() && dirExists(weDir)) {
		info.provider = "wallpaperengine";
		info.running = true;
		wallpaperEngineInfo(weDir, info);
	} else if (weRunning && weDir.empty() && !assume) {
		info.provider = "wallpaperengine";
		info.running = true;
	}

	// Lively, when Wallpaper Engine is not the one showing.
	if (!info.running) {
		auto livelyExe = livelyDir.empty() ? runningPath(L"Lively.exe") : std::wstring();
		auto livelyRunning = assume || !livelyExe.empty();
		if (livelyRunning && (!livelyDir.empty() || !livelyExe.empty())) {
			info.provider = "lively";
			info.running = true;
			if (!livelyDir.empty()) livelyInfoIn(livelyDir, info);
			else
				for (const auto& dir: livelyDataDirs())
					if (livelyInfoIn(dir, info)) break;
		}
	}

	// No preview of its own: Explorer's thumbnail of the wallpaper file (a plain video, a picture).
	if (info.running && info.preview.empty() && !info.source.empty() && isMediaName(wide(info.source)) && fileExists(wide(info.source))) {
		auto folder = localAppData() + L"\\ii-windows";
		CreateDirectoryW(folder.c_str(), nullptr);
		auto name = folder + L"\\extwall-" + std::to_wstring(std::hash<std::wstring>()(wide(info.source))) + L".png";
		if (fileExists(name) || makeThumbnail(wide(info.source), name)) info.preview = utf8(name);
	}

	auto out = jsonlite::Value::makeObject();
	out.set("provider", jsonlite::Value::makeString(info.provider));
	out.set("running", jsonlite::Value::makeBool(info.running));
	out.set("title", jsonlite::Value::makeString(info.title));
	out.set("preview", jsonlite::Value::makeString(info.preview));
	out.set("source", jsonlite::Value::makeString(info.source));
	out.set("type", jsonlite::Value::makeString(info.type));
	auto text = jsonlite::stringify(out, false) + "\n";
	std::fwrite(text.data(), 1, text.size(), stdout);
	if (initialized) CoUninitialize();
	return 0;
}
