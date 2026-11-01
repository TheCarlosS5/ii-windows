// compat (plan 2026-10-31, E9): which of the customization apps ii knows are on this PC.
//   ii-shim compat <compat.json>     JSON: [{"id":"powertoys","found":"process PowerToys.exe"}, ...]
// An app is found by a running process (its exe name), an installed file (%VARIABLES% expanded) or a registry key
// (HKCU\... or HKLM\..., opened read only). Nothing is changed.
#include "jsonlite.h"

#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::wstring wide(const std::string& text) {
	if (text.empty()) return {};
	int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(size), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
	return out;
}

std::wstring lower(std::wstring text) {
	std::transform(text.begin(), text.end(), text.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
	return text;
}

std::set<std::wstring> runningExes() {
	std::set<std::wstring> names;
	auto* snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) return names;
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	for (BOOL ok = Process32FirstW(snap, &entry); ok; ok = Process32NextW(snap, &entry)) names.insert(lower(entry.szExeFile));
	CloseHandle(snap);
	return names;
}

bool fileExists(const std::wstring& pattern) {
	wchar_t path[MAX_PATH * 2] {};
	auto n = ExpandEnvironmentStringsW(pattern.c_str(), path, MAX_PATH * 2);
	if (n == 0 || n > MAX_PATH * 2 || wcschr(path, L'%')) return false; // a variable this PC does not have
	auto attributes = GetFileAttributesW(path);
	return attributes != INVALID_FILE_ATTRIBUTES;
}

bool keyExists(const std::wstring& key) {
	HKEY root = nullptr;
	std::wstring sub;
	if (key.rfind(L"HKCU\\", 0) == 0) { root = HKEY_CURRENT_USER; sub = key.substr(5); }
	else if (key.rfind(L"HKLM\\", 0) == 0) { root = HKEY_LOCAL_MACHINE; sub = key.substr(5); }
	else return false;
	HKEY opened = nullptr;
	if (RegOpenKeyExW(root, sub.c_str(), 0, KEY_READ, &opened) != ERROR_SUCCESS) return false;
	RegCloseKey(opened);
	return true;
}

std::string quoted(const std::string& text) {
	std::string out = "\"";
	for (char c: text) {
		if (c == '"' || c == '\\') out += '\\';
		if (static_cast<unsigned char>(c) >= 0x20) out += c;
	}
	return out + "\"";
}

} // namespace

int compat(const std::vector<std::wstring>& args) {
	if (args.empty()) {
		std::fputs("usage: compat <compat.json>\n", stderr);
		return 2;
	}
	std::ifstream in(args[0], std::ios::binary);
	if (!in) {
		std::fputs("compat: cannot read the table\n", stderr);
		return 1;
	}
	std::stringstream buffer;
	buffer << in.rdbuf();
	auto parsed = jsonlite::parse(buffer.str());
	const auto* apps = parsed.ok ? parsed.value.find("apps") : nullptr;
	if (!apps || apps->type != jsonlite::Type::Array) {
		std::fputs("compat: not a compat table\n", stderr);
		return 1;
	}
	auto running = runningExes();
	std::string out = "[";
	for (const auto& app: apps->items) {
		const auto* id = app.find("id");
		if (!id || id->type != jsonlite::Type::String) continue;
		std::string found;
		auto each = [&](const char* field, auto test, const char* what) {
			const auto* list = app.find(field);
			if (!found.empty() || !list || list->type != jsonlite::Type::Array) return;
			for (const auto& item: list->items) {
				if (item.type == jsonlite::Type::String && test(wide(item.text))) {
					found = std::string(what) + " " + item.text;
					return;
				}
			}
		};
		each("processes", [&](const std::wstring& exe) { return running.count(lower(exe)) > 0; }, "process");
		each("files", fileExists, "file");
		each("keys", keyExists, "key");
		if (found.empty()) continue;
		if (out.size() > 1) out += ",";
		out += "{\"id\":" + quoted(id->text) + ",\"found\":" + quoted(found) + "}";
	}
	out += "]\n";
	std::fwrite(out.data(), 1, out.size(), stdout);
	return 0;
}
