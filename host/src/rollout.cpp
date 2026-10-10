#include "rollout.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <string>

namespace ii::rollout {

namespace {

std::wstring currentPath(const std::wstring& root) { return root + L"\\current.txt"; }

std::wstring widen(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::string narrow(const std::wstring& text) {
	if (text.empty()) return {};
	auto n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(n), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
	return out;
}

} // namespace

bool validId(const std::wstring& id) {
	if (id.empty() || id.size() > 64) return false;
	if (id == L"." || id == L"..") return false;
	for (auto c: id) {
		auto ok = (c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') || (c >= L'0' && c <= L'9') || c == L'.' || c == L'_' || c == L'-';
		if (!ok) return false;
	}
	return id.front() != L'.';
}

bool read(const std::wstring& root, Current& out) {
	out = {};
	auto* file = _wfopen(currentPath(root).c_str(), L"rb");
	if (!file) return false;
	std::string text;
	char buffer[1024];
	size_t n = 0;
	while ((n = fread(buffer, 1, sizeof(buffer), file)) > 0 && text.size() < 8192) text.append(buffer, n);
	fclose(file);

	size_t pos = 0;
	while (pos < text.size()) {
		auto end = text.find('\n', pos);
		auto line = text.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
		pos = end == std::string::npos ? text.size() : end + 1;
		while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
		auto eq = line.find('=');
		if (eq == std::string::npos) continue;
		auto key = line.substr(0, eq);
		auto value = widen(line.substr(eq + 1));
		if (key == "active") out.active = value;
		else if (key == "previous") out.previous = value;
		else if (key == "state") out.state = value;
		else if (key == "attempts") out.attempts = _wtoi(value.c_str());
	}
	// Anything that is not a plain id (a tampered or half-understood file) is not trusted.
	if (!(out.active == L"legacy" || validId(out.active))) return false;
	if (!(out.previous == L"none" || out.previous == L"legacy" || validId(out.previous))) out.previous = L"none";
	if (out.state != L"pending" && out.state != L"verified" && out.state != L"rolled-back") out.state = L"verified";
	out.present = true;
	return true;
}

bool write(const std::wstring& root, const Current& value) {
	if (!(value.active == L"legacy" || validId(value.active))) return false;
	auto path = currentPath(root);
	auto temp = path + L".tmp";
	SYSTEMTIME t;
	GetLocalTime(&t);
	char stamp[40];
	sprintf_s(stamp, "%04d-%02d-%02dT%02d:%02d:%02d", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
	std::string text = "active=" + narrow(value.active) + "\r\nprevious=" + narrow(value.previous.empty() ? L"none" : value.previous)
	                 + "\r\nstate=" + narrow(value.state) + "\r\nattempts=" + std::to_string(value.attempts) + "\r\nupdated=" + stamp + "\r\n";
	auto* file = _wfopen(temp.c_str(), L"wb");
	if (!file) return false;
	auto ok = fwrite(text.data(), 1, text.size(), file) == text.size();
	ok = (fflush(file) == 0) && ok;
	fclose(file);
	// The old file or the new one, never half of either.
	return ok && MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

std::wstring versionDir(const std::wstring& root, const std::wstring& id) {
	if (id == L"legacy") return root;
	if (!validId(id)) return {};
	return root + L"\\versions\\" + id;
}

bool locate(const std::wstring& exeDir, std::wstring& root, std::wstring& id) {
	auto last = exeDir.find_last_of(L"\\/");
	if (last == std::wstring::npos) return false;
	id = exeDir.substr(last + 1);
	auto parent = exeDir.substr(0, last);
	auto versions = parent.find_last_of(L"\\/");
	if (versions == std::wstring::npos) return false;
	if (_wcsicmp(parent.substr(versions + 1).c_str(), L"versions") != 0) return false;
	root = parent.substr(0, versions);
	return validId(id);
}

bool markVerified(const std::wstring& exeDir) {
	std::wstring root;
	std::wstring id;
	if (!locate(exeDir, root, id)) return false;
	Current current;
	if (!read(root, current) || current.active != id || current.state != L"pending") return false;
	current.state = L"verified";
	current.attempts = 0;
	return write(root, current);
}

} // namespace ii::rollout
