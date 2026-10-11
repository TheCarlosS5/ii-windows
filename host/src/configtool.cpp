#include "configtool.h"

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <map>
#include <set>
#include <unordered_map>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace configtool {

namespace {

// ---- the schema (generated) ---------------------------------------------------------------------
enum Kind { K_BOOL, K_INT, K_REAL, K_STRING, K_STRINGS, K_LIST, K_ANY };
struct SchemaObject {
	const char* path;
};
struct SchemaKey {
	const char* path;
	Kind kind;
	bool hasRange;
	double low;
	double high;
	std::vector<int> enumValues;
};
#include "config_schema.inc"

const std::unordered_map<std::string, const SchemaKey*>& keyMap() {
	static const auto map = [] {
		std::unordered_map<std::string, const SchemaKey*> m;
		for (const auto& key: SCHEMA_KEYS) m[key.path] = &key;
		return m;
	}();
	return map;
}

const std::set<std::string>& objectSet() {
	static const auto set = [] {
		std::set<std::string> s;
		for (const auto& object: SCHEMA_OBJECTS) s.insert(object.path);
		return s;
	}();
	return set;
}

// ---- text and files -----------------------------------------------------------------------------
std::wstring toWide(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::string toUtf8(const std::wstring& text) {
	if (text.empty()) return {};
	auto n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(n), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
	return out;
}

std::wstring env(const wchar_t* name) {
	wchar_t buffer[2048];
	auto n = GetEnvironmentVariableW(name, buffer, 2048);
	return n > 0 && n < 2048 ? std::wstring(buffer, n) : std::wstring();
}

enum class ReadStatus { Ok, Missing, Failed };

ReadStatus readFile(const std::wstring& path, std::string& out, size_t limit = 16u << 20) {
	out.clear();
	auto handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (handle == INVALID_HANDLE_VALUE) {
		auto error = GetLastError();
		return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? ReadStatus::Missing : ReadStatus::Failed;
	}
	LARGE_INTEGER size {};
	if (!GetFileSizeEx(handle, &size) || size.QuadPart < 0 || static_cast<unsigned long long>(size.QuadPart) > limit) {
		CloseHandle(handle);
		return ReadStatus::Failed;
	}
	out.resize(static_cast<size_t>(size.QuadPart));
	size_t done = 0;
	while (done < out.size()) {
		DWORD got = 0;
		if (!ReadFile(handle, out.data() + done, static_cast<DWORD>(std::min<size_t>(out.size() - done, 1u << 20)), &got, nullptr) || got == 0) break;
		done += got;
	}
	CloseHandle(handle);
	if (done != out.size()) {
		out.clear();
		return ReadStatus::Failed;
	}
	return ReadStatus::Ok;
}

bool exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }
bool isDirectory(const std::wstring& path) {
	auto a = GetFileAttributesW(path.c_str());
	return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}

struct Expect {
	bool check = false;
	bool missing = false; // the file must not exist
	std::string bytes;    // or must have exactly these bytes
};

enum class WriteStatus { Ok, Conflict, Failed };

// Writes next to the target and renames over it: the target is either the old file or the whole new
// one, never a partial one. With `expect`, the target is compared right before the rename, so a
// writer that got in between (ii itself, an editor) is noticed and nothing is replaced.
WriteStatus writeAtomic(const std::wstring& path, const std::string& bytes, const Expect& expect, std::string& why) {
	auto slash = path.find_last_of(L"\\/");
	if (slash != std::wstring::npos) CreateDirectoryW(path.substr(0, slash).c_str(), nullptr); // the folder itself, if missing
	auto fault = env(L"II_CONFIG_TEST_FAULT");
	auto temp = path + L".tmp-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
	auto handle = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (handle == INVALID_HANDLE_VALUE) {
		why = "cannot create a temporary file next to it (error " + std::to_string(GetLastError()) + ")";
		return WriteStatus::Failed;
	}
	bool ok = true;
	size_t limit = fault == L"disk-full" ? bytes.size() / 2 : bytes.size();
	size_t done = 0;
	while (done < limit) {
		DWORD wrote = 0;
		if (!WriteFile(handle, bytes.data() + done, static_cast<DWORD>(std::min<size_t>(limit - done, 1u << 20)), &wrote, nullptr) || wrote == 0) {
			ok = false;
			break;
		}
		done += wrote;
	}
	if (fault == L"disk-full") {
		ok = false;
		why = "disk full (simulated)";
	} else if (!ok) {
		why = "write failed (error " + std::to_string(GetLastError()) + ")";
	}
	if (ok && !FlushFileBuffers(handle)) {
		ok = false;
		why = "flush failed (error " + std::to_string(GetLastError()) + ")";
	}
	CloseHandle(handle);
	if (!ok) {
		DeleteFileW(temp.c_str());
		return WriteStatus::Failed;
	}
	if (expect.check) {
		if (fault == L"race") { // test: another writer gets in between
			auto other = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
			if (other != INVALID_HANDLE_VALUE) {
				DWORD wrote = 0;
				WriteFile(other, "\n", 1, &wrote, nullptr);
				CloseHandle(other);
			}
		}
		std::string now;
		auto status = readFile(path, now);
		bool same = expect.missing ? status == ReadStatus::Missing : (status == ReadStatus::Ok && now == expect.bytes);
		if (!same) {
			DeleteFileW(temp.c_str());
			why = "the file changed while it was being prepared; nothing was replaced";
			return WriteStatus::Conflict;
		}
	}
	if (fault == L"no-replace") {
		DeleteFileW(temp.c_str());
		why = "cannot replace the file (simulated)";
		return WriteStatus::Failed;
	}
	if (!MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
		why = "cannot replace the file (error " + std::to_string(GetLastError()) + ")";
		DeleteFileW(temp.c_str());
		return WriteStatus::Failed;
	}
	return WriteStatus::Ok;
}

std::wstring stamp() {
	SYSTEMTIME t;
	GetLocalTime(&t);
	wchar_t buffer[32];
	swprintf(buffer, 32, L"%04d%02d%02d-%02d%02d%02d", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
	return buffer;
}

// A name that does not exist yet: base + stamp [+ -n] + suffix.
std::wstring freshName(const std::wstring& base, const std::wstring& suffix) {
	auto name = base + stamp() + suffix;
	for (int n = 1; exists(name) && n < 1000; ++n) name = base + stamp() + L"-" + std::to_wstring(n) + suffix;
	return name;
}

void pruneCopies(const std::wstring& dir, const std::wstring& pattern, size_t keep) {
	WIN32_FIND_DATAW data;
	auto find = FindFirstFileW((dir + L"\\" + pattern).c_str(), &data);
	if (find == INVALID_HANDLE_VALUE) return;
	std::vector<std::wstring> names;
	do {
		if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) names.emplace_back(data.cFileName);
	} while (FindNextFileW(find, &data));
	FindClose(find);
	std::sort(names.begin(), names.end(), std::greater<>());
	for (size_t i = keep; i < names.size(); ++i) DeleteFileW((dir + L"\\" + names[i]).c_str());
}

// ---- validation ---------------------------------------------------------------------------------
using jsonlite::Type;
using jsonlite::Value;

const char* typeName(const Value& v) {
	switch (v.type) {
	case Type::Null: return "null";
	case Type::Bool: return "a boolean";
	case Type::Number: return v.isInteger() ? "an integer" : "a number";
	case Type::String: return "a string";
	case Type::Array: return "a list";
	case Type::Object: return "an object";
	}
	return "?";
}

const char* kindName(Kind k) {
	switch (k) {
	case K_BOOL: return "a boolean";
	case K_INT: return "an integer";
	case K_REAL: return "a number";
	case K_STRING: return "a string";
	case K_STRINGS: return "a list of strings";
	case K_LIST: return "a list";
	case K_ANY: return "anything";
	}
	return "?";
}

bool kindMatches(Kind kind, const Value& v) {
	switch (kind) {
	case K_BOOL: return v.type == Type::Bool;
	case K_INT: return v.type == Type::Number && v.isInteger();
	case K_REAL: return v.type == Type::Number;
	case K_STRING: return v.type == Type::String;
	case K_STRINGS:
		return v.type == Type::Array && std::all_of(v.items.begin(), v.items.end(), [](const Value& item) { return item.type == Type::String; });
	case K_LIST: return v.type == Type::Array;
	case K_ANY: return true;
	}
	return false;
}

std::string numberText(double d) {
	char buffer[64];
	snprintf(buffer, sizeof(buffer), "%g", d);
	return buffer;
}

// The problems of one option, given its schema row.
void checkKey(const SchemaKey& key, const std::string& path, const Value& v, std::vector<Problem>& out) {
	if (!kindMatches(key.kind, v)) {
		out.push_back({path, Severity::Error, "type", std::string("expected ") + kindName(key.kind) + ", found " + typeName(v)});
		return;
	}
	if (v.type != Type::Number) return;
	auto number = v.asDouble();
	if (!key.enumValues.empty() && std::find(key.enumValues.begin(), key.enumValues.end(), static_cast<int>(number)) == key.enumValues.end()) {
		std::string allowed;
		for (auto e: key.enumValues) allowed += (allowed.empty() ? "" : ", ") + std::to_string(e);
		out.push_back({path, Severity::Warning, "enum", "found " + v.number + ", the documented values are " + allowed});
	}
	if (key.hasRange && (number < key.low || number > key.high)) {
		out.push_back({path, Severity::Warning, "range", "found " + v.number + ", the settings allow " + numberText(key.low) + " to " + numberText(key.high)});
	}
}

void walk(const Value& v, const std::string& path, std::vector<Problem>& out) {
	if (objectSet().count(path)) {
		if (v.type != Type::Object) {
			out.push_back({path, Severity::Error, "type", std::string("expected an object, found ") + typeName(v)});
			return;
		}
		for (const auto& member: v.members) walk(member.second, path + "." + member.first, out);
		return;
	}
	auto it = keyMap().find(path);
	if (it != keyMap().end()) checkKey(*it->second, path, v, out);
	// anything else is an option this build does not know: not our business
}

void walkRoot(const Value& root, std::vector<Problem>& out) {
	for (const auto& member: root.members) {
		const auto& name = member.first;
		if (objectSet().count(name)) {
			if (member.second.type != Type::Object) out.push_back({name, Severity::Error, "type", std::string("expected an object, found ") + typeName(member.second)});
			else for (const auto& child: member.second.members) walk(child.second, name + "." + child.first, out);
		} else {
			auto it = keyMap().find(name);
			if (it != keyMap().end()) checkKey(*it->second, name, member.second, out);
		}
	}
}

// Removes the option at a dotted path; empty parents stay (the loader fills defaults either way).
bool erasePath(Value& root, const std::string& path) {
	Value* node = &root;
	size_t start = 0;
	while (true) {
		auto dot = path.find('.', start);
		auto name = path.substr(start, dot == std::string::npos ? std::string::npos : dot - start);
		if (dot == std::string::npos) return node->erase(name);
		node = node->find(name);
		if (!node || node->type != Type::Object) return false;
		start = dot + 1;
	}
}

void setPath(Value& root, const std::string& path, const Value& value) {
	Value* node = &root;
	size_t start = 0;
	while (true) {
		auto dot = path.find('.', start);
		auto name = path.substr(start, dot == std::string::npos ? std::string::npos : dot - start);
		if (dot == std::string::npos) {
			node->set(name, value);
			return;
		}
		auto* child = node->find(name);
		if (!child || child->type != Type::Object) child = &node->set(name, Value::makeObject());
		node = child;
		start = dot + 1;
	}
}

const Value* getPath(const Value& root, const std::string& path) {
	const Value* node = &root;
	size_t start = 0;
	while (true) {
		auto dot = path.find('.', start);
		auto name = path.substr(start, dot == std::string::npos ? std::string::npos : dot - start);
		node = node->type == Type::Object ? node->find(name) : nullptr;
		if (!node || dot == std::string::npos) return node;
		start = dot + 1;
	}
}

int versionOf(const Value& root, bool* wrongType = nullptr) {
	const auto* v = root.find("configVersion");
	if (wrongType) *wrongType = false;
	if (!v) return 0;
	if (v->type == Type::Number && v->isInteger()) return static_cast<int>(v->asDouble());
	if (wrongType) *wrongType = true;
	return 0;
}

bool parseConfig(const std::string& bytes, Value& out, std::string& error) {
	auto parsed = jsonlite::parse(bytes);
	if (!parsed.ok) {
		error = parsed.error;
		return false;
	}
	if (!parsed.value.isObject()) {
		error = "the top level is not a JSON object";
		return false;
	}
	out = std::move(parsed.value);
	return true;
}

std::vector<Problem> errorsOf(const std::vector<Problem>& problems) {
	std::vector<Problem> errors;
	for (const auto& p: problems) if (p.severity == Severity::Error) errors.push_back(p);
	return errors;
}

// ---- secrets, paths, monitors -------------------------------------------------------------------
std::string lower(std::string s) {
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return s;
}

bool endsWith(const std::string& s, const std::string& suffix) {
	return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// A member whose name says it holds a credential, with a plain value. (An object called "cookie" is
// a clock style, not a credential: only scalars count.)
bool isSecretMember(const std::string& name, const Value& v) {
	if (v.type != Type::String && v.type != Type::Number) return false;
	auto n = lower(name);
	for (const char* suffix: {"apikey", "api_key", "api-key", "token", "secret", "password", "passwd", "privatekey", "private_key", "authorization", "userid", "user_id"}) {
		if (endsWith(n, suffix)) return true;
	}
	return n == "cookie" || n == "cookies";
}

// Drops credential-looking members at any depth (inside lists of custom models, for instance).
void stripSecrets(Value& v, const std::string& path, std::vector<std::string>* removed) {
	if (v.type == Type::Object) {
		for (size_t i = 0; i < v.members.size();) {
			if (isSecretMember(v.members[i].first, v.members[i].second)) {
				if (removed) removed->push_back(path + "." + v.members[i].first);
				v.members.erase(v.members.begin() + static_cast<std::ptrdiff_t>(i));
			} else {
				stripSecrets(v.members[i].second, path + "." + v.members[i].first, removed);
				++i;
			}
		}
	} else if (v.type == Type::Array) {
		for (size_t i = 0; i < v.items.size(); ++i) stripSecrets(v.items[i], path + "[" + std::to_string(i) + "]", removed);
	}
}

bool isPathKey(const std::string& path) {
	auto key = keyMap().find(path);
	if (key == keyMap().end() || key->second->kind != K_STRING) return false;
	auto last = lower(path.substr(path.find_last_of('.') + 1));
	return last == "path" || endsWith(last, "path");
}

bool isDirectoryKey(const std::string& path) { return endsWith(lower(path), "savepath") || path == "background.widgets.folder.path"; }

std::vector<std::string> monitorNames() {
	std::vector<std::string> names;
	auto test = env(L"II_CONFIG_TEST_MONITORS");
	if (!test.empty()) {
		size_t start = 0;
		while (start <= test.size()) {
			auto end = test.find(L';', start);
			if (end == std::wstring::npos) end = test.size();
			if (end > start) names.push_back(toUtf8(test.substr(start, end - start)));
			start = end + 1;
		}
		return names;
	}
	EnumDisplayMonitors(nullptr, nullptr, [](HMONITOR m, HDC, LPRECT, LPARAM l) -> BOOL {
		MONITORINFOEXW info {};
		info.cbSize = sizeof(info);
		if (GetMonitorInfoW(m, &info)) reinterpret_cast<std::vector<std::string>*>(l)->push_back(toUtf8(info.szDevice)); // NOLINT
		return TRUE;
	}, reinterpret_cast<LPARAM>(&names)); // NOLINT
	return names;
}

bool isMonitorListKey(const std::string& path) { return path == "bar.screenList"; }
bool isMonitorNameKey(const std::string& path) { return path == "notifications.monitor.name"; }

// ---- guard / keep-good --------------------------------------------------------------------------
Outcome unreadable(const std::string& message) {
	Outcome o;
	o.action = Outcome::Action::Unreadable;
	o.message = message;
	return o;
}

Outcome quarantine(const Paths& p, const std::string& bytes, const std::string& reason) {
	Outcome o;
	auto aside = freshName(p.file + L".invalid-", L"");
	if (!MoveFileExW(p.file.c_str(), aside.c_str(), 0)) {
		return unreadable("config.json is damaged (" + reason + ") but could not be moved aside (error " + std::to_string(GetLastError()) + "); left as it is");
	}
	pruneCopies(p.dir, L"config.json.invalid-*", 10);
	o.details.push_back("kept as " + toUtf8(aside.substr(aside.find_last_of(L'\\') + 1)));
	std::string lastBytes;
	Value last;
	std::string lastError;
	if (readFile(p.lastGood, lastBytes) == ReadStatus::Ok && parseConfig(lastBytes, last, lastError) && errorsOf([&] { std::vector<Problem> v; walkRoot(last, v); return v; }()).empty()) {
		std::string why;
		Expect expect;
		expect.check = true;
		expect.missing = true;
		if (writeAtomic(p.file, lastBytes, expect, why) == WriteStatus::Ok) {
			o.action = Outcome::Action::RestoredLastGood;
			o.message = "config.json was damaged (" + reason + "); it was kept aside and the last good one was put back";
			return o;
		}
		o.details.push_back("the last good copy could not be put back: " + why);
	}
	o.action = Outcome::Action::StartedFromDefaults;
	o.message = "config.json was damaged (" + reason + "); it was kept aside and ii starts from its defaults";
	(void)bytes;
	return o;
}

} // namespace

std::vector<Problem> validate(const Value& root) {
	std::vector<Problem> problems;
	if (!root.isObject()) {
		problems.push_back({"", Severity::Error, "type", "the top level is not a JSON object"});
		return problems;
	}
	walkRoot(root, problems);
	return problems;
}

Paths paths() {
	Paths p;
	p.dir = env(L"II_CONFIG_DIR");
	if (p.dir.empty()) {
		auto base = env(L"LOCALAPPDATA");
		p.dir = base + L"\\quickshell\\illogical-impulse";
	}
	while (p.dir.size() > 3 && (p.dir.back() == L'\\' || p.dir.back() == L'/')) p.dir.pop_back();
	p.file = p.dir + L"\\config.json";
	p.lastGood = p.dir + L"\\config.last-good.json";
	return p;
}

Outcome guard() {
	auto p = paths();
	std::string bytes;
	auto status = readFile(p.file, bytes);
	Outcome o;
	if (status == ReadStatus::Missing) {
		o.action = Outcome::Action::Missing;
		o.message = "no config.json yet (ii writes its defaults)";
		return o;
	}
	if (status == ReadStatus::Failed) return unreadable("config.json could not be read; left as it is");

	Value root;
	std::string error;
	if (!parseConfig(bytes, root, error)) return quarantine(p, bytes, error);

	bool wrongType = false;
	auto version = versionOf(root, &wrongType);
	if (version > SUPPORTED_VERSION) {
		o.action = Outcome::Action::NewerVersion;
		o.message = "config.json was written by a newer ii (configVersion " + std::to_string(version) + "); it is left as it is";
		return o;
	}
	// The first time this build sees a file without a version: keep a copy of it as it was.
	if (version == 0 && !wrongType) {
		auto old = p.dir + L"\\config.pre-v1.json";
		std::string why;
		Expect expect;
		expect.check = true;
		expect.missing = true;
		if (!exists(old) && writeAtomic(old, bytes, expect, why) == WriteStatus::Ok) o.details.push_back("a copy of the unversioned file was kept as config.pre-v1.json");
	}

	auto errors = errorsOf(validate(root));
	if (errors.empty()) {
		o.action = Outcome::Action::Nothing;
		o.message = "config.json is fine";
		return o;
	}

	auto backup = freshName(p.dir + L"\\config.before-repair-", L".json");
	std::string why;
	Expect none;
	if (writeAtomic(backup, bytes, none, why) != WriteStatus::Ok) return unreadable("config.json has wrong-typed options but a backup could not be written (" + why + "); left as it is");
	for (const auto& problem: errors) {
		if (erasePath(root, problem.path)) o.details.push_back(problem.path + ": " + problem.detail + " (reset to its default)");
	}
	Expect expect;
	expect.check = true;
	expect.bytes = bytes;
	switch (writeAtomic(p.file, jsonlite::stringify(root), expect, why)) {
	case WriteStatus::Ok:
		o.action = Outcome::Action::Repaired;
		o.message = std::to_string(o.details.size()) + " option(s) in config.json had the wrong type and were reset to their defaults; the original was kept as " + toUtf8(backup.substr(backup.find_last_of(L'\\') + 1));
		return o;
	case WriteStatus::Conflict:
	case WriteStatus::Failed:
	default: DeleteFileW(backup.c_str()); return unreadable("config.json could not be repaired (" + why + "); left as it is");
	}
}

Outcome keepGood() {
	auto p = paths();
	Outcome o;
	o.action = Outcome::Action::NotSaved;
	std::string bytes;
	if (readFile(p.file, bytes) != ReadStatus::Ok) {
		o.message = "no readable config.json to remember";
		return o;
	}
	Value root;
	std::string error;
	if (!parseConfig(bytes, root, error)) {
		o.message = "config.json is not valid (" + error + "): the last good copy is not replaced";
		return o;
	}
	auto version = versionOf(root);
	if (version > SUPPORTED_VERSION) {
		o.message = "config.json is from a newer ii: the last good copy is not replaced";
		return o;
	}
	auto errors = errorsOf(validate(root));
	if (!errors.empty()) {
		o.message = std::to_string(errors.size()) + " wrong-typed option(s): the last good copy is not replaced";
		return o;
	}
	std::string last;
	if (readFile(p.lastGood, last) == ReadStatus::Ok && last == bytes) {
		o.action = Outcome::Action::Nothing;
		o.message = "already the last good copy";
		return o;
	}
	std::string why;
	Expect none;
	if (writeAtomic(p.lastGood, bytes, none, why) != WriteStatus::Ok) {
		o.message = "the last good copy could not be written: " + why;
		return o;
	}
	o.action = Outcome::Action::Saved;
	o.message = "config.json remembered as the last good copy";
	return o;
}

// ---- export / import ----------------------------------------------------------------------------
namespace {

// Copies the known options of `config` into a fresh tree; reports what was left out.
void collect(const Value& in, const std::string& path, Value& out, std::vector<std::string>* excluded) {
	for (const auto& member: in.members) {
		auto child = path.empty() ? member.first : path + "." + member.first;
		if (objectSet().count(child) && member.second.type == Type::Object) {
			Value sub = Value::makeObject();
			collect(member.second, child, sub, excluded);
			if (!sub.members.empty()) out.set(member.first, std::move(sub));
		} else if (keyMap().count(child)) {
			if (isSecretMember(member.first, member.second)) {
				if (excluded) excluded->push_back(child + " (credential)");
				continue;
			}
			Value copy = member.second;
			std::vector<std::string> inner;
			stripSecrets(copy, child, &inner);
			if (excluded) for (const auto& s: inner) excluded->push_back(s + " (credential)");
			out.set(member.first, std::move(copy));
		} else if (excluded) {
			excluded->push_back(child + " (not a known option)");
		}
	}
}

} // namespace

Value makePack(const Value& config, std::vector<std::string>* excluded) {
	Value pack = Value::makeObject();
	pack.set("ii-config-pack", Value::makeNumber("1"));
	pack.set("configVersion", Value::makeNumber(std::to_string(SUPPORTED_VERSION)));
	Value options = Value::makeObject();
	collect(config, "", options, excluded);
	options.erase("configVersion"); // set by the importing side
	pack.set("options", std::move(options));
	return pack;
}

namespace {

struct Step {
	std::string action; // set | same | keep | skip
	std::string path;
	std::string detail;
};

struct Plan {
	std::vector<Step> steps;
	Value merged;
	int sets = 0, same = 0, kept = 0, skipped = 0;
};

constexpr size_t PACK_LIMIT = 1u << 20;
constexpr size_t STRING_LIMIT = 64u << 10;
constexpr size_t LIST_LIMIT = 1000;

bool tooBig(const Value& v) {
	if (v.type == Type::String) return v.text.size() > STRING_LIMIT;
	if (v.type == Type::Array) {
		if (v.items.size() > LIST_LIMIT) return true;
		return std::any_of(v.items.begin(), v.items.end(), tooBig);
	}
	if (v.type == Type::Object) {
		if (v.members.size() > LIST_LIMIT) return true;
		return std::any_of(v.members.begin(), v.members.end(), [](const auto& m) { return tooBig(m.second); });
	}
	return false;
}

std::string normalizePath(std::string path) {
	if (path.rfind("file:///", 0) == 0) path = path.substr(8);
	std::replace(path.begin(), path.end(), '/', '\\');
	return path;
}

struct ImportContext {
	const Value& current;
	bool preferPack;
	std::vector<std::string> monitors;
	std::map<std::string, std::string> monitorMap;
	Plan plan;
};

// Decides one leaf of the pack; adds to the plan.
void consider(ImportContext& c, const std::string& path, Value value) {
	auto& plan = c.plan;
	auto skip = [&](const std::string& why) {
		plan.steps.push_back({"skip", path, why});
		++plan.skipped;
	};
	const auto& key = *keyMap().at(path);
	if (isSecretMember(path.substr(path.find_last_of('.') + 1), value)) return skip("looks like a credential; credentials are never imported");
	std::vector<std::string> removed;
	stripSecrets(value, path, &removed);
	if (tooBig(value)) return skip("too large");
	std::vector<Problem> problems;
	checkKey(key, path, value, problems);
	for (const auto& problem: problems) return skip(problem.kind == "type" ? "wrong type: " + problem.detail : "out of range: " + problem.detail);

	if (isMonitorNameKey(path) && value.type == Type::String && !value.text.empty()) {
		auto mapped = c.monitorMap.count(value.text) ? c.monitorMap[value.text] : value.text;
		if (std::find(c.monitors.begin(), c.monitors.end(), mapped) == c.monitors.end()) return skip("monitor " + value.text + " is not connected here (use --map-monitor " + value.text + "=<name>)");
		value = Value::makeString(mapped);
	}
	if (isMonitorListKey(path) && value.type == Type::Array) {
		Value kept = Value::makeArray();
		for (const auto& item : value.items) {
			auto mapped = c.monitorMap.count(item.text) ? c.monitorMap[item.text] : item.text;
			if (std::find(c.monitors.begin(), c.monitors.end(), mapped) != c.monitors.end()) kept.items.push_back(Value::makeString(mapped));
		}
		if (kept.items.empty() && !value.items.empty()) return skip("none of its monitors is connected here (use --map-monitor old=new)");
		value = kept;
	}
	if (isPathKey(path) && value.type == Type::String && !value.text.empty()) {
		auto wide = toWide(normalizePath(value.text));
		bool found = isDirectoryKey(path) ? isDirectory(wide) : exists(wide);
		if (!found) return skip("path " + value.text + " does not exist on this PC");
	}

	const auto* mine = getPath(c.current, path);
	if (mine && jsonlite::equal(*mine, value)) {
		plan.steps.push_back({"same", path, ""});
		++plan.same;
		return;
	}
	if (mine && !c.preferPack) {
		plan.steps.push_back({"keep", path, "yours is " + jsonlite::stringify(*mine, false).substr(0, 60) + ", the pack has " + jsonlite::stringify(value, false).substr(0, 60)});
		++plan.kept;
		return;
	}
	plan.steps.push_back({"set", path, mine ? "replaces " + jsonlite::stringify(*mine, false).substr(0, 60) : "new"});
	++plan.sets;
	setPath(plan.merged, path, value);
}

void flatten(ImportContext& c, const Value& v, const std::string& path) {
	for (const auto& member: v.members) {
		auto child = path.empty() ? member.first : path + "." + member.first;
		if (objectSet().count(child)) {
			if (member.second.type == Type::Object) flatten(c, member.second, child);
			else {
				c.plan.steps.push_back({"skip", child, "expected an object"});
				++c.plan.skipped;
			}
		} else if (keyMap().count(child)) {
			consider(c, child, member.second);
		} else {
			c.plan.steps.push_back({"skip", child, "not a known option"});
			++c.plan.skipped;
		}
	}
}

std::string line(const Step& s) {
	return s.action + " " + s.path + (s.detail.empty() ? "" : "  (" + s.detail + ")") + "\n";
}

int exportCommand(const std::vector<std::wstring>& args, std::string& out) {
	std::wstring target;
	bool force = false;
	auto p = paths();
	auto source = p.file;
	for (size_t i = 0; i < args.size(); ++i) {
		if (args[i] == L"--force") force = true;
		else if (args[i] == L"--config" && i + 1 < args.size()) source = args[++i];
		else if (target.empty() && args[i].rfind(L"--", 0) != 0) target = args[i];
		else { out += "usage: ii-shim config export <out.json> [--force] [--config <file>]\n"; return 64; }
	}
	if (target.empty()) { out += "usage: ii-shim config export <out.json> [--force]\n"; return 64; }
	std::string bytes;
	if (readFile(source, bytes) != ReadStatus::Ok) { out += "unreadable " + toUtf8(source) + "\n"; return 2; }
	Value config;
	std::string error;
	if (!parseConfig(bytes, config, error)) { out += "unreadable config: " + error + "\n"; return 2; }
	std::vector<std::string> excluded;
	auto pack = makePack(config, &excluded);
	if (exists(target) && !force) { out += "refused: " + toUtf8(target) + " exists (use --force)\n"; return 1; }
	std::string why;
	Expect none;
	if (writeAtomic(target, jsonlite::stringify(pack), none, why) != WriteStatus::Ok) { out += "failed: " + why + "\n"; return 3; }
	for (const auto& e: excluded) out += "left out " + e + "\n";
	out += "exported " + toUtf8(target) + "\nok\n";
	return 0;
}

int importCommand(const std::vector<std::wstring>& args, std::string& out) {
	std::wstring packPath;
	bool apply = false, preferPack = false;
	std::map<std::string, std::string> monitorMap;
	for (size_t i = 0; i < args.size(); ++i) {
		if (args[i] == L"--apply") apply = true;
		else if (args[i] == L"--prefer" && i + 1 < args.size()) {
			auto v = args[++i];
			if (v == L"pack") preferPack = true;
			else if (v != L"mine") { out += "usage: --prefer pack|mine\n"; return 64; }
		} else if (args[i] == L"--map-monitor" && i + 1 < args.size()) {
			auto spec = toUtf8(args[++i]);
			auto eq = spec.find('=');
			if (eq == std::string::npos || eq == 0 || eq + 1 == spec.size()) { out += "usage: --map-monitor old=new\n"; return 64; }
			monitorMap[spec.substr(0, eq)] = spec.substr(eq + 1);
		} else if (packPath.empty() && args[i].rfind(L"--", 0) != 0) packPath = args[i];
		else { out += "usage: ii-shim config import <pack> [--apply] [--prefer pack|mine] [--map-monitor old=new]\n"; return 64; }
	}
	if (packPath.empty()) { out += "usage: ii-shim config import <pack> [--apply]\n"; return 64; }

	std::string packBytes;
	if (readFile(packPath, packBytes, PACK_LIMIT + 1) != ReadStatus::Ok || packBytes.size() > PACK_LIMIT) { out += "unreadable or larger than 1 MiB: " + toUtf8(packPath) + "\n"; return 2; }
	auto parsed = jsonlite::parse(packBytes, 32);
	if (!parsed.ok || !parsed.value.isObject()) { out += "not a valid pack: " + (parsed.ok ? std::string("not an object") : parsed.error) + "\n"; return 2; }
	const auto* marker = parsed.value.find("ii-config-pack");
	const auto* options = parsed.value.find("options");
	if (!marker || marker->type != Type::Number || !options || options->type != Type::Object) { out += "not an ii config pack\n"; return 2; }
	const auto* packVersion = parsed.value.find("configVersion");
	if (packVersion && packVersion->type == Type::Number && packVersion->isInteger() && packVersion->asDouble() > SUPPORTED_VERSION) {
		out += "refused: the pack was made by a newer ii (configVersion " + packVersion->number + ")\n";
		return 1;
	}

	auto p = paths();
	std::string currentBytes;
	auto status = readFile(p.file, currentBytes);
	Value current = Value::makeObject();
	if (status == ReadStatus::Failed) { out += "unreadable " + toUtf8(p.file) + "\n"; return 2; }
	if (status == ReadStatus::Ok) {
		std::string error;
		if (!parseConfig(currentBytes, current, error)) { out += "your config.json is not valid (" + error + "); run `ii-shim config guard` first\n"; return 2; }
	}

	ImportContext c {current, preferPack, monitorNames(), monitorMap, {}};
	c.plan.merged = current;
	flatten(c, *options, "");
	for (const auto& s: c.plan.steps) out += line(s);
	out += "plan: " + std::to_string(c.plan.sets) + " to set, " + std::to_string(c.plan.same) + " already the same, " + std::to_string(c.plan.kept) + " of yours kept, " + std::to_string(c.plan.skipped) + " skipped\n";
	if (!apply) {
		out += "preview only: nothing was changed (add --apply to write it)\n";
		return 0;
	}
	if (c.plan.sets == 0) { out += "nothing to write\nok\n"; return 0; }

	// Backup, then one atomic replace that only happens if the file is still what was planned on.
	std::string why;
	Expect none;
	auto backup = freshName(p.dir + L"\\config.before-import-", L".json");
	if (status == ReadStatus::Ok && writeAtomic(backup, currentBytes, none, why) != WriteStatus::Ok) { out += "failed: backup could not be written (" + why + "); nothing changed\n"; return 3; }
	Expect expect;
	expect.check = true;
	expect.missing = status == ReadStatus::Missing;
	expect.bytes = currentBytes;
	auto written = writeAtomic(p.file, jsonlite::stringify(c.plan.merged), expect, why);
	if (written != WriteStatus::Ok) {
		DeleteFileW(backup.c_str());
		out += "failed: " + why + "; nothing changed\n";
		return 3;
	}
	pruneCopies(p.dir, L"config.before-import-*.json", 10);
	out += "written; the previous file was kept as " + toUtf8(backup.substr(backup.find_last_of(L'\\') + 1)) + "\nok\n";
	return 0;
}

} // namespace

int run(const std::vector<std::wstring>& args, std::string& out) {
	if (args.empty()) {
		out += "usage: ii-shim config where|check|guard|keep-good|export|import ...\n";
		return 64;
	}
	const auto& cmd = args[0];
	std::vector<std::wstring> rest(args.begin() + 1, args.end());
	auto p = paths();
	if (cmd == L"where") {
		out += "dir " + toUtf8(p.dir) + "\nfile " + toUtf8(p.file) + "\nlast-good " + toUtf8(p.lastGood) + "\nschema keys " + std::to_string(sizeof(SCHEMA_KEYS) / sizeof(SCHEMA_KEYS[0])) + "\nconfigVersion " + std::to_string(SUPPORTED_VERSION) + "\n";
		return 0;
	}
	if (cmd == L"check") {
		auto file = p.file;
		for (size_t i = 0; i < rest.size(); ++i) {
			if (rest[i] == L"--file" && i + 1 < rest.size()) file = rest[++i];
			else { out += "usage: ii-shim config check [--file F]\n"; return 64; }
		}
		std::string bytes;
		auto status = readFile(file, bytes);
		if (status != ReadStatus::Ok) { out += std::string(status == ReadStatus::Missing ? "missing " : "unreadable ") + toUtf8(file) + "\n"; return 2; }
		Value root;
		std::string error;
		if (!parseConfig(bytes, root, error)) { out += "invalid " + error + "\n"; return 2; }
		auto problems = validate(root);
		int errors = 0, warnings = 0;
		for (const auto& problem: problems) {
			out += std::string(problem.severity == Severity::Error ? "error " : "warning ") + problem.path + " " + problem.kind + ": " + problem.detail + "\n";
			(problem.severity == Severity::Error ? errors : warnings)++;
		}
		auto version = versionOf(root);
		out += "configVersion " + std::to_string(version) + (version > SUPPORTED_VERSION ? " (newer than this build understands)" : "") + "\n";
		out += errors == 0 ? "ok\n" : "fail " + std::to_string(errors) + " error(s)\n";
		(void)warnings;
		return errors == 0 ? 0 : 1;
	}
	if (cmd == L"guard" || cmd == L"keep-good") {
		auto outcome = cmd == L"guard" ? guard() : keepGood();
		out += outcome.message + "\n";
		for (const auto& d: outcome.details) out += "  " + d + "\n";
		return outcome.action == Outcome::Action::Unreadable ? 3 : 0;
	}
	if (cmd == L"export") return exportCommand(rest, out);
	if (cmd == L"import") return importCommand(rest, out);
	out += "unknown command\n";
	return 64;
}

int command(const std::vector<std::wstring>& args) {
	std::string out;
	auto code = run(args, out);
	fwrite(out.data(), 1, out.size(), stdout);
	fflush(stdout);
	return code;
}

} // namespace configtool
