// Console helpers for the Windows sidebar. status/preview never write settings.
#include "nightlight.h"
#include "common.h"
#include <powrprof.h>
#include <shellapi.h>
#include <objbase.h>
#include <algorithm>
#include <cstdio>

namespace {
using Args = std::vector<std::wstring>;
std::string json(const std::wstring& value) {
    int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    std::string utf8(size, '\0'), out = "\"";
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), utf8.data(), size, nullptr, nullptr);
    for (unsigned char c: utf8) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c < 32) { char hex[7]; std::snprintf(hex, sizeof(hex), "\\u%04x", c); out += hex; }
        else out += c;
    }
    return out + '"';
}
bool number(const std::wstring& text, int low, int high, int& value) {
    if (text.empty() || text.find_first_not_of(L"0123456789") != std::wstring::npos || text.size() > 5) return false;
    value = _wtoi(text.c_str()); return value >= low && value <= high;
}
void printStatus(const ii::nightlight::Status& s) {
    std::printf("{\"available\":%s,\"active\":%s,\"kelvin\":%d,\"gamma\":%d,\"minimumKelvin\":%d,\"minimumVerified\":%s,\"error\":%d}\n",
        s.available ? "true" : "false", s.active ? "true" : "false", s.kelvin, s.gamma, s.minimum, s.minimumVerified ? "true" : "false", s.error);
}
struct Standard { const wchar_t* id; GUID guid; };
const Standard standards[] = {
    {L"power-saver", {0xa1841308, 0x3541, 0x4fab, {0xbc,0x81,0xf7,0x15,0x56,0xf2,0x0b,0x4a}}},
    {L"balanced", {0x381b4222, 0xf694, 0x41f0, {0x96,0x85,0xff,0x5b,0xb2,0x60,0xdf,0x2e}}},
    {L"performance", {0x8c5e7fda, 0xe8bf, 0x4a96, {0x9a,0x85,0xa6,0xe2,0x3a,0x8c,0x63,0x5c}}}
};
std::wstring guidString(const GUID& guid) { wchar_t str[40]; StringFromGUID2(guid, str, 40); return str; }
std::wstring friendly(const GUID& guid) {
    DWORD size = 0;
    if (PowerReadFriendlyName(nullptr, &guid, nullptr, nullptr, nullptr, &size) != ERROR_SUCCESS || size > 8192 || size < 2) return L"";
    std::vector<wchar_t> name(size / sizeof(wchar_t) + 1);
    if (PowerReadFriendlyName(nullptr, &guid, nullptr, nullptr, reinterpret_cast<BYTE*>(name.data()), &size) != ERROR_SUCCESS) return L"";
    return name.data();
}
std::wstring registryText(const wchar_t* name) {
    wchar_t text[512]{}; DWORD size = sizeof(text);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", name,
        RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, text, &size) != ERROR_SUCCESS) return L"";
    return text;
}
}
int nightlightCommand(const std::vector<std::wstring>& args) {
    using namespace ii::nightlight;
    Request request;
    if (args.empty()) return 2;
    if (args[0] == L"preview") {
        if (args.size() < 2 || args.size() > 3 || !number(args[1], 1200, 6500, request.kelvin)
            || (args.size() == 3 && !number(args[2], 25, 100, request.gamma))) return 2;
        const auto plan = compute(request.kelvin, request.gamma, identity());
        std::printf("{\"kelvin\":%d,\"gamma\":%d,\"minimumKelvin\":%d,\"ramps\":[", plan.kelvin, plan.gamma, minimumKelvin());
        for (int c = 0; c < 3; ++c) {
            std::printf("%s[", c ? "," : "");
            for (int i = 0; i < 256; ++i) std::printf("%s%u", i ? "," : "", plan.ramp[c][i]);
            std::printf("]");
        }
        std::puts("]}"); return 0;
    }
    if (args[0] == L"status" && args.size() == 1) request.action = Action::Status;
    else if (args[0] == L"off" && args.size() == 1) request.action = Action::Off;
    else {
        request.action = Action::Apply;
        if (args.size() > 2 || !number(args[0], 1200, 6500, request.kelvin)
            || (args.size() == 2 && !number(args[1], 25, 100, request.gamma))) return 2;
    }
    auto hwnd = FindWindowW(L"IiHostWindow", nullptr);
    DWORD_PTR result = 0;
    COPYDATASTRUCT data{COPYDATA, sizeof(request), &request};
    if (!hwnd || !SendMessageTimeoutW(hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG | SMTO_BLOCK, 2000, &result) || !(result & 1)) {
        Status missing; missing.error = 1; printStatus(missing); return 1;
    }
    auto status = unpack(result); printStatus(status); return status.error ? 1 : 0;
}
int powerCommand(const std::vector<std::wstring>& args) {
    if (args.empty() || args.size() > 2 || (args[0] != L"status" && args[0] != L"next" && args[0] != L"set")
        || (args[0] == L"set" ? args.size() != 2 : args.size() != 1)) return 2;
    GUID* active = nullptr;
    if (PowerGetActiveScheme(nullptr, &active) != ERROR_SUCCESS || !active) { std::puts("{\"error\":1,\"plans\":[]}"); return 1; }
    GUID current = *active; LocalFree(active);
    std::vector<const Standard*> present;
    for (DWORD i = 0;; ++i) {
        GUID guid{}; DWORD size = sizeof(guid);
        auto rc = PowerEnumerate(nullptr, nullptr, nullptr, ACCESS_SCHEME, i, reinterpret_cast<BYTE*>(&guid), &size);
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc != ERROR_SUCCESS) { std::puts("{\"error\":2,\"plans\":[]}"); return 1; }
        for (const auto& s: standards) if (guid == s.guid) present.push_back(&s);
    }
    std::sort(present.begin(), present.end(), [](auto a, auto b) { return a < b; });
    DWORD error = 0;
    if (args[0] != L"status") {
        const Standard* target = nullptr;
        if (args[0] == L"set") {
            for (auto s: present) if (args[1] == s->id) target = s;
        } else if (present.size() > 1) {
            auto it = std::find_if(present.begin(), present.end(), [&](auto s) { return s->guid == current; });
            target = it == present.end() || ++it == present.end() ? present.front() : *it;
        }
        if (!target) error = ERROR_NOT_SUPPORTED;
        else {
            error = PowerSetActiveScheme(nullptr, &target->guid);
            if (!error) {
                GUID* verified = nullptr;
                error = PowerGetActiveScheme(nullptr, &verified);
                if (!error && verified) { current = *verified; if (current != target->guid) error = ERROR_ACCESS_DENIED; }
                else if (!error) error = ERROR_INVALID_DATA;
                LocalFree(verified);
            }
        }
    }
    std::wstring activeId = L"custom", name = friendly(current);
    for (auto s: present) if (s->guid == current) activeId = s->id;
    std::printf("{\"error\":%lu,\"active\":%s,\"activeGuid\":%s,\"name\":%s,\"plans\":[", error,
        json(activeId).c_str(), json(guidString(current)).c_str(), json(name).c_str());
    for (size_t i = 0; i < present.size(); ++i) std::printf("%s{\"id\":%s,\"guid\":%s,\"name\":%s}", i ? "," : "",
        json(present[i]->id).c_str(), json(guidString(present[i]->guid)).c_str(), json(friendly(present[i]->guid)).c_str());
    std::puts("]}"); return error ? 1 : 0;
}
int systemInfoCommand(const std::vector<std::wstring>& args) {
    if (!args.empty()) return 2;
    auto name = registryText(L"ProductName"), edition = registryText(L"EditionID");
    int build = _wtoi(registryText(L"CurrentBuildNumber").c_str());
    // ProductName on Windows 11 often still says Windows 10; build is read-only.
    if (build >= 22000 && name.rfind(L"Windows 10", 0) == 0) name.replace(0, 10, L"Windows 11");
    if (name.empty()) name = L"Windows";
    std::printf("{\"name\":%s,\"edition\":%s,\"build\":%d}\n", json(name).c_str(), json(edition).c_str(), build);
    return 0;
}
int systemSoundCommand(const std::vector<std::wstring>& args) {
    if (args.size() != 1) return 2;
    // Windows' configured system sound, no external player or window.
    return MessageBeep(MB_ICONINFORMATION) ? 0 : 1;
}
