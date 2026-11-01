#include "crashpolicy.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cwctype>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "jsonlite.h"

namespace ii::crashpolicy {

namespace {

std::wstring wide(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::wstring lower(std::wstring text) {
	std::transform(text.begin(), text.end(), text.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
	return text;
}

std::wstring textOf(const jsonlite::Value& object, const char* key) {
	const auto* v = object.find(key);
	return v && v->type == jsonlite::Type::String ? wide(v->text) : std::wstring();
}

} // namespace

Report parse(const std::string& json) {
	Report report;
	auto parsed = jsonlite::parse(json);
	if (!parsed.ok || !parsed.value.isObject()) return report;
	const auto& v = parsed.value;
	report.found = true;
	report.code = textOf(v, "code");
	report.where = textOf(v, "where");
	report.subsystem = textOf(v, "subsystem");
	if (report.subsystem.empty()) report.subsystem = L"gui";
	report.kind = textOf(v, "kind");
	report.dump = textOf(v, "dump");
	if (const auto* up = v.find("uptimeSeconds"); up && up->type == jsonlite::Type::Number) {
		report.uptimeSeconds = static_cast<unsigned long long>(std::max(0.0, up->asDouble()));
	}
	return report;
}

Report find(const std::wstring& dir, unsigned long pid) {
	Report best;
	FILETIME bestTime {};
	WIN32_FIND_DATAW found {};
	auto handle = FindFirstFileW((dir + L"\\*.json").c_str(), &found);
	if (handle == INVALID_HANDLE_VALUE) return best;
	const std::string needle = "\"pid\":" + std::to_string(pid);
	do {
		auto path = dir + L"\\" + found.cFileName;
		auto* f = _wfopen(path.c_str(), L"rb");
		if (!f) continue;
		std::string text;
		char buffer[2048];
		size_t n = 0;
		while ((n = fread(buffer, 1, sizeof(buffer), f)) > 0 && text.size() < 64 * 1024) text.append(buffer, n);
		fclose(f);
		auto at = text.find(needle);
		// The pid must be the whole number ("pid":12 is not "pid":123).
		if (at == std::string::npos || (at + needle.size() < text.size() && std::isdigit(static_cast<unsigned char>(text[at + needle.size()])))) continue;
		if (best.found && CompareFileTime(&found.ftLastWriteTime, &bestTime) <= 0) continue;
		auto report = parse(text);
		if (!report.found) continue;
		report.file = path;
		best = report;
		bestTime = found.ftLastWriteTime;
	} while (FindNextFileW(handle, &found));
	FindClose(handle);
	return best;
}

std::wstring subsystemOf(const Report& report, unsigned long exitCode) {
	if (exitCode == 70) return L"render";
	if (!report.found) return L"unknown";
	auto module = lower(report.where.substr(0, report.where.find(L'+')));
	static const wchar_t* graphics[] = {L"qt6quick", L"qt6gui", L"d3d11", L"d3d12", L"dxgi", L"d3d10warp", L"atio6axx", L"amdxx",
	                                    L"aticfx", L"nvwgf2um", L"nvldumd", L"nvd3dum", L"igd10", L"igd12", L"igc64"};
	for (const auto* name: graphics) {
		if (module.rfind(name, 0) == 0) return L"render";
	}
	return report.subsystem.empty() ? L"gui" : report.subsystem;
}

bool canDisable(const std::wstring& subsystem) {
	static const wchar_t* parts[] = {L"mpris", L"notifications", L"battery", L"bluetooth", L"render"};
	return std::any_of(std::begin(parts), std::end(parts), [&](const wchar_t* p) { return subsystem == p; });
}

std::wstring describe(const std::wstring& s) {
	if (s == L"mpris") return L"la música y los videos (panel multimedia)";
	if (s == L"notifications") return L"la lectura de notificaciones de Windows";
	if (s == L"battery") return L"la batería";
	if (s == L"bluetooth") return L"el Bluetooth";
	if (s == L"tray") return L"la bandeja del sistema";
	if (s == L"toplevels") return L"la lista de ventanas";
	if (s == L"render") return L"el dibujo con la tarjeta gráfica";
	if (s == L"gui") return L"la interfaz";
	return L"una parte desconocida";
}

int Policy::recent(unsigned long long nowMs) const {
	return static_cast<int>(std::count_if(this->events.begin(), this->events.end(), [&](const Event& e) {
		return nowMs - e.at < WINDOW_MS;
	}));
}

Decision Policy::onCrash(unsigned long long nowMs, const std::wstring& subsystem, const std::vector<std::wstring>& alreadyDisabled,
                         bool alreadySafe) {
	this->events.erase(std::remove_if(this->events.begin(), this->events.end(), [&](const Event& e) {
		return nowMs - e.at >= WINDOW_MS;
	}), this->events.end());
	this->events.push_back({nowMs, subsystem});
	Decision d;
	d.crashes = static_cast<int>(this->events.size());
	auto same = static_cast<int>(std::count_if(this->events.begin(), this->events.end(), [&](const Event& e) {
		return e.subsystem == subsystem;
	}));
	auto disabled = std::find(alreadyDisabled.begin(), alreadyDisabled.end(), subsystem) != alreadyDisabled.end();
	if (d.crashes >= 5 || (d.crashes >= 4 && alreadySafe)) {
		d.action = Action::GiveUp;
	} else if (d.crashes >= 4) {
		d.action = Action::SafeMode;
	} else if (same >= 3 && canDisable(subsystem) && !disabled) {
		d.action = Action::Disable;
		d.subsystem = subsystem;
	} else if (same >= 3 && !alreadySafe) {
		// The same part again, and it cannot be switched off on its own (or it was and it still crashes).
		d.action = Action::SafeMode;
	} else {
		d.action = Action::Restart;
	}
	return d;
}

} // namespace ii::crashpolicy
