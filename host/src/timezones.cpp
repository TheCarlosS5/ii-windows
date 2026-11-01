// timezones (plan 2026-10-31, E1): every time zone Windows knows, with its offset from UTC right now (daylight saving
// included) and its names in the language of Windows, for the launcher's "hora en tokio".
//   ii-shim timezones     JSON: [{"id":"Tokyo Standard Time","offset":540,"name":"(UTC+09:00) Osaka, Sapporo, Tokio",
//                                 "std":"Hora estándar de Tokio","dst":false}, ...]
// The names come from the registry's MUI strings (HKLM\...\Time Zones, read only), so a Spanish Windows says "Tokio".
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace {

std::string utf8(const std::wstring& text) {
	if (text.empty()) return {};
	int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(size), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
	return out;
}

std::string quoted(const std::wstring& text) {
	std::string out = "\"";
	for (char c: utf8(text)) {
		if (c == '"' || c == '\\') out += '\\', out += c;
		else if (static_cast<unsigned char>(c) < 0x20) {
			char buf[8];
			std::snprintf(buf, sizeof(buf), "\\u%04x", c);
			out += buf;
		} else out += c;
	}
	return out + "\"";
}

// The zone's localized display name ("(UTC+09:00) Osaka, Sapporo, Tokio"): MUI_Display, else Display.
std::wstring displayName(const std::wstring& id) {
	HKEY key = nullptr;
	auto path = L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\" + id;
	if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, path.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) return {};
	wchar_t buffer[256] {};
	DWORD size = sizeof(buffer);
	std::wstring out;
	if (RegLoadMUIStringW(key, L"MUI_Display", buffer, sizeof(buffer), &size, 0, nullptr) == ERROR_SUCCESS) out = buffer;
	else {
		size = sizeof(buffer);
		DWORD type = 0;
		if (RegQueryValueExW(key, L"Display", nullptr, &type, reinterpret_cast<BYTE*>(buffer), &size) == ERROR_SUCCESS && type == REG_SZ)
			out = buffer;
	}
	RegCloseKey(key);
	return out;
}

ULONGLONG ticks(const SYSTEMTIME& time) {
	FILETIME file {};
	SystemTimeToFileTime(&time, &file);
	return (static_cast<ULONGLONG>(file.dwHighDateTime) << 32) | file.dwLowDateTime;
}

} // namespace

int timezones(const std::vector<std::wstring>&) {
	SYSTEMTIME utc {};
	GetSystemTime(&utc);
	const auto now = ticks(utc);
	std::string out = "[";
	DYNAMIC_TIME_ZONE_INFORMATION zone {};
	for (DWORD i = 0; EnumDynamicTimeZoneInformation(i, &zone) == ERROR_SUCCESS; ++i) {
		SYSTEMTIME local {};
		if (!SystemTimeToTzSpecificLocalTimeEx(&zone, &utc, &local)) continue;
		const auto there = ticks(local);
		const long long minutes = (static_cast<long long>(there) - static_cast<long long>(now)) / 600000000LL;
		const bool daylight = minutes != -static_cast<long long>(zone.Bias + zone.StandardBias);
		std::wstring id = zone.TimeZoneKeyName;
		char number[32];
		std::snprintf(number, sizeof(number), "%lld", minutes);
		if (out.size() > 1) out += ",";
		out += "{\"id\":" + quoted(id) + ",\"offset\":" + number + ",\"name\":" + quoted(displayName(id)) +
		       ",\"std\":" + quoted(daylight ? zone.DaylightName : zone.StandardName) + ",\"dst\":" + (daylight ? "true" : "false") + "}";
	}
	out += "]\n";
	std::fwrite(out.data(), 1, out.size(), stdout);
	return out.size() > 3 ? 0 : 1;
}
