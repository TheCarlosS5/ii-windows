// mkdir, rm, which and reset-dir for ii-shim: the few file commands ii's QML starts (Directories.qml
// creates and empties its cache folders on start, the welcome window deletes a marker file,
// Updates asks `which checkupdates`). Not general tools: every path they change must be below one of
// the user's own folders, deep enough not to be a top-level folder, and not reached through a link.
//
//   mkdir [-p] <dir>...        create folders (and parents)
//   rm [-f] [-r|-R|-rf] <path>...   delete files; with -r also folders
//   reset-dir <dir>...         make the folders exist and be empty (rm -rf + mkdir -p in one typed step)
//   which <name>               print the full path of a program on PATH; exit 1 if there is none

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fs = std::filesystem;

namespace {

using Args = std::vector<std::wstring>;

std::wstring envVar(const wchar_t* name) {
	wchar_t buffer[MAX_PATH * 2];
	auto n = GetEnvironmentVariableW(name, buffer, static_cast<DWORD>(_countof(buffer)));
	return n > 0 && n < _countof(buffer) ? std::wstring(buffer, n) : std::wstring();
}

std::wstring lower(std::wstring s) {
	std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
	return s;
}

bool isLink(const fs::path& p) {
	auto attributes = GetFileAttributesW(p.c_str());
	return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT);
}

// /C:/x (what QML's trimFileProtocol leaves) and forward slashes to a Windows path.
fs::path normalize(std::wstring text) {
	if (text.size() > 3 && text[0] == L'/' && text[2] == L':' && iswalpha(text[1])) text.erase(0, 1);
	std::replace(text.begin(), text.end(), L'/', L'\\');
	return fs::path(text).lexically_normal();
}

// Below one of the user's own folders by at least `minDepth` components, with no link on the way.
bool allowed(const fs::path& target, size_t minDepth) {
	if (!target.is_absolute()) return false;
	for (const auto& part: target) {
		if (part == L"..") return false;
	}
	for (auto* name: {L"LOCALAPPDATA", L"APPDATA", L"TEMP", L"USERPROFILE"}) {
		auto rootText = envVar(name);
		if (rootText.empty()) continue;
		auto root = fs::path(rootText).lexically_normal();
		if (root.root_path() == root) continue; // never a drive root
		auto relative = target.lexically_relative(root);
		if (relative.empty() || relative.native().rfind(L"..", 0) == 0) continue;
		size_t depth = 0;
		for (const auto& part: relative) {
			if (part != L"." && !part.empty()) ++depth;
		}
		if (depth < minDepth) return false;
		// No link between the root and the target (an existing prefix of it): that path leads elsewhere.
		fs::path cursor = root;
		for (const auto& part: relative) {
			cursor /= part;
			std::error_code ec;
			if (fs::exists(cursor, ec) && isLink(cursor)) return false;
		}
		return true;
	}
	return false;
}

} // namespace

int mkdirCommand(const Args& args) {
	std::vector<fs::path> dirs;
	for (const auto& a: args) {
		if (!a.empty() && a[0] == L'-') continue; // -p, -m ...: creating parents is always on
		dirs.push_back(normalize(a));
	}
	if (dirs.empty()) return 1;
	int rc = 0;
	for (const auto& dir: dirs) { // one refused or failed folder does not skip the others
		if (!allowed(dir, 1)) {
			fwprintf(stderr, L"mkdir: refusing %s (not below one of your own folders)\n", dir.c_str());
			rc = 1;
			continue;
		}
		std::error_code ec;
		fs::create_directories(dir, ec);
		if (ec && !fs::is_directory(dir)) rc = 1;
	}
	return rc;
}

int rmCommand(const Args& args) {
	bool recursive = false;
	bool force = false;
	std::vector<fs::path> targets;
	for (const auto& a: args) {
		if (a.size() > 1 && a[0] == L'-') {
			for (size_t i = 1; i < a.size(); ++i) {
				if (a[i] == L'r' || a[i] == L'R') recursive = true;
				else if (a[i] == L'f') force = true;
			}
			continue;
		}
		targets.push_back(normalize(a));
	}
	if (targets.empty()) return force ? 0 : 1;
	int rc = 0;
	for (const auto& target : targets) {
		// A folder tree must be deep enough not to be one of the user's top-level folders.
		if (!allowed(target, recursive ? 2 : 1)) {
			fwprintf(stderr, L"rm: refusing %s\n", target.c_str());
			rc = 1;
			continue;
		}
		std::error_code ec;
		if (!fs::exists(fs::symlink_status(target, ec))) {
			if (!force) rc = 1;
			continue;
		}
		if (isLink(target)) {
			fs::remove(target, ec); // the link itself, never what it points to
		} else if (fs::is_directory(target, ec)) {
			if (!recursive) {
				fwprintf(stderr, L"rm: %s is a folder (use -r)\n", target.c_str());
				rc = 1;
				continue;
			}
			fs::remove_all(target, ec);
		} else {
			fs::remove(target, ec);
		}
		if (ec) rc = 1;
	}
	return rc;
}

int resetDirCommand(const Args& args) {
	if (args.empty()) return 1;
	int rc = 0;
	for (const auto& arg: args) { // several folders in one start: every process start counts on a slow PC
		auto dir = normalize(arg);
		if (!allowed(dir, 2)) {
			fwprintf(stderr, L"reset-dir: refusing %s\n", dir.c_str());
			rc = 1;
			continue;
		}
		std::error_code ec;
		if (fs::exists(fs::symlink_status(dir, ec))) {
			if (isLink(dir)) fs::remove(dir, ec);
			else fs::remove_all(dir, ec);
		}
		ec.clear();
		fs::create_directories(dir, ec);
		if (ec && !fs::is_directory(dir)) rc = 1;
	}
	return rc;
}

int whichCommand(const Args& args) {
	if (args.size() != 1 || args[0].empty() || args[0].find_first_of(L"\\/:*?\"<>|") != std::wstring::npos) return 1;
	wchar_t found[MAX_PATH];
	for (auto* extension: {L".exe", L".cmd", L".bat", L".com"}) {
		if (SearchPathW(nullptr, args[0].c_str(), extension, MAX_PATH, found, nullptr)) {
			fwprintf(stdout, L"%s\n", found);
			return 0;
		}
	}
	return 1;
}
