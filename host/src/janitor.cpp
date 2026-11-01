// ii-shim janitor (plan 2026-10-31, D4): keeps ii's caches bounded. ii-host runs it once a day, hidden, with the PC idle
// (no game, nobody at the keyboard for 5 minutes). Nothing a running ii needs is touched:
//   %TEMP%\ii-windows\mpris                       the media covers' old place (now <data>\cache\media-art): removed
//   %TEMP%\ii-windows\tray, \notification-icons    newest 500 / 300 kept
//   <data>\cache\media-art                         newest 200 kept (the media backend trims it too)
//   %LOCALAPPDATA%\quickshell\cache\by-shell\<id>  a config's prepared tree not used for 30 days (the 2 newest always stay)
//   %LOCALAPPDATA%\quickshell\cache\qmlcache       compiled QML not written for 30 days (Qt makes it again if needed)
//   %TEMP%\quickshell\by-pid, by-id                shell logs older than 7 days
//   <data>\update\<id>                             downloads of versions that are not the latest offered
// Prints what it removed (and "dry run" with --dry-run). II_DATA_DIR / II_JANITOR_LOCALAPPDATA / II_JANITOR_TEMP move
// everything for tests.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include "jsonlite.h"

namespace fs = std::filesystem;

namespace {

bool dryRun = false;
unsigned long long removedFiles = 0;
unsigned long long removedBytes = 0;

std::wstring env(const wchar_t* name) {
	wchar_t value[1024];
	auto n = GetEnvironmentVariableW(name, value, 1024);
	return n > 0 && n < 1024 ? std::wstring(value, n) : std::wstring();
}

// Never follows a link: a junction inside a cache is removed as a link, what it points to stays.
void removeTree(const fs::path& path) {
	std::error_code e;
	auto status = fs::symlink_status(path, e);
	if (e) return;
	if (fs::is_directory(status) && !fs::is_symlink(status)) {
		for (const auto& entry: fs::directory_iterator(path, e)) removeTree(entry.path());
		if (!dryRun) fs::remove(path, e);
		return;
	}
	auto size = fs::is_regular_file(status) ? fs::file_size(path, e) : 0;
	if (dryRun || fs::remove(path, e)) {
		++removedFiles;
		removedBytes += size;
	}
}

double ageDays(const fs::path& path) {
	std::error_code e;
	auto written = fs::last_write_time(path, e);
	if (e) return 0;
	return std::chrono::duration<double, std::ratio<86400>>(fs::file_time_type::clock::now() - written).count();
}

// The newest `keep` files of a folder stay, the rest go.
void keepNewest(const fs::path& dir, size_t keep) {
	std::error_code e;
	std::vector<fs::directory_entry> files;
	for (const auto& entry: fs::directory_iterator(dir, e)) {
		if (entry.is_regular_file()) files.push_back(entry);
	}
	if (files.size() <= keep) return;
	std::sort(files.begin(), files.end(), [](const auto& a, const auto& b) { return a.last_write_time() > b.last_write_time(); });
	for (size_t i = keep; i < files.size(); ++i) removeTree(files[i].path());
}

// Entries older than `days`; the `keep` most recent ones always stay (the config in use may not change for weeks).
// iiOnly: only quickshell's prepared trees of ii's own configs (qmltree\qs\modules\ii), never another shell's.
void olderThan(const fs::path& dir, double days, bool foldersOnly, size_t keep = 0, bool iiOnly = false) {
	std::error_code e;
	std::vector<fs::directory_entry> entries;
	for (const auto& entry: fs::directory_iterator(dir, e)) {
		if (foldersOnly && !entry.is_directory()) continue;
		if (iiOnly && !fs::exists(entry.path() / L"qmltree" / L"qs" / L"modules" / L"ii", e)) continue;
		entries.push_back(entry);
	}
	std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return a.last_write_time() > b.last_write_time(); });
	for (size_t i = keep; i < entries.size(); ++i) {
		if (ageDays(entries[i].path()) > days) removeTree(entries[i].path());
	}
}

std::string readText(const fs::path& path) {
	std::string text;
	if (auto* f = _wfopen(path.c_str(), L"rb")) {
		char buffer[4096];
		size_t n = 0;
		while ((n = fread(buffer, 1, sizeof(buffer), f)) > 0 && text.size() < (1 << 20)) text.append(buffer, n);
		fclose(f);
	}
	return text;
}

} // namespace

int janitor(const std::vector<std::wstring>& args) {
	dryRun = std::find(args.begin(), args.end(), L"--dry-run") != args.end();
	auto local = env(L"II_JANITOR_LOCALAPPDATA");
	if (local.empty()) local = env(L"LOCALAPPDATA");
	auto temp = env(L"II_JANITOR_TEMP");
	if (temp.empty()) temp = env(L"TEMP");
	auto data = env(L"II_DATA_DIR");
	if (data.empty()) data = local + L"\\ii-windows";
	if (local.empty() || temp.empty()) return 2;

	removeTree(fs::path(temp) / L"ii-windows" / L"mpris");
	keepNewest(fs::path(temp) / L"ii-windows" / L"tray", 500);
	keepNewest(fs::path(temp) / L"ii-windows" / L"notification-icons", 300);
	keepNewest(fs::path(data) / L"cache" / L"media-art", 200);
	olderThan(fs::path(local) / L"quickshell" / L"cache" / L"by-shell", 30, true, 2, true);
	olderThan(fs::path(local) / L"quickshell" / L"cache" / L"qmlcache", 30, false);
	olderThan(fs::path(temp) / L"quickshell" / L"by-pid", 7, false);
	olderThan(fs::path(temp) / L"quickshell" / L"by-id", 7, true);

	// Downloads: only the version the updater offers now is kept.
	auto parsed = jsonlite::parse(readText(fs::path(data) / L"update" / L"state.json"));
	std::string keepId;
	if (parsed.ok && parsed.value.isObject()) {
		if (const auto* latest = parsed.value.find("latest"); latest && latest->isObject()) {
			if (const auto* id = latest->find("id"); id && id->type == jsonlite::Type::String) keepId = id->text;
		}
	}
	std::error_code e;
	for (const auto& entry: fs::directory_iterator(fs::path(data) / L"update", e)) {
		if (!entry.is_directory()) continue;
		auto name = entry.path().filename().string();
		if (name != keepId) removeTree(entry.path());
	}

	std::printf("%s%llu files, %.1f MB\n", dryRun ? "dry run: would remove " : "removed ", removedFiles, static_cast<double>(removedBytes) / (1024.0 * 1024.0));
	return 0;
}
