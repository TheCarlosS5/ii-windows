// top: the programs that use the most processor and memory right now, for the bar's resources popup.
//   ii-shim top [count]      JSON: {"threads":N,"cpu":[...],"memory":[...]}, each entry
//                            {"name":"Google Chrome","exe":"chrome.exe","cpu":12.5,"memMB":1450,"processes":14}
// One system snapshot (NtQuerySystemInformation: every process, elevated ones too, without opening them), a second one
// 0.6 s later; processor use is the difference, in % of the whole machine like Task Manager. Processes of the same
// program are added up. Memory is the private working set (Task Manager's "Memory" column).
#include "common.h"
#include <winternl.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#pragma comment(lib, "ntdll.lib")
#pragma comment(lib, "version.lib")

namespace {

struct Sample {
	std::wstring exe;
	ULONGLONG cpuTime = 0; // 100 ns
	ULONGLONG privateBytes = 0;
};

// pid -> sample
std::map<ULONG_PTR, Sample> snapshot() {
	std::map<ULONG_PTR, Sample> out;
	ULONG size = 1 << 20;
	std::vector<BYTE> buffer;
	NTSTATUS status;
	do {
		buffer.resize(size);
		status = NtQuerySystemInformation(SystemProcessInformation, buffer.data(), size, &size);
		size += 64 * 1024;
	} while (status == static_cast<NTSTATUS>(0xC0000004L)); // STATUS_INFO_LENGTH_MISMATCH
	if (status < 0) return out;
	for (size_t offset = 0;;) {
		auto* p = reinterpret_cast<SYSTEM_PROCESS_INFORMATION*>(buffer.data() + offset);
		auto pid = reinterpret_cast<ULONG_PTR>(p->UniqueProcessId);
		if (pid > 4 && p->ImageName.Buffer) {
			// Reserved1 = WorkingSetPrivateSize(8) HardFaultCount(4) ThreadsHighWatermark(4) CycleTime(8)
			//             CreateTime(8) UserTime(8) KernelTime(8)
			LARGE_INTEGER privateWs {}, user {}, kernel {};
			std::memcpy(&privateWs, p->Reserved1, 8);
			std::memcpy(&user, p->Reserved1 + 32, 8);
			std::memcpy(&kernel, p->Reserved1 + 40, 8);
			Sample s;
			s.exe.assign(p->ImageName.Buffer, p->ImageName.Length / sizeof(wchar_t));
			s.cpuTime = static_cast<ULONGLONG>(user.QuadPart + kernel.QuadPart);
			s.privateBytes = static_cast<ULONGLONG>(privateWs.QuadPart);
			out[pid] = std::move(s);
		}
		if (!p->NextEntryOffset) break;
		offset += p->NextEntryOffset;
	}
	return out;
}

std::wstring lower(std::wstring s) {
	for (auto& c: s) c = static_cast<wchar_t>(towlower(c));
	return s;
}

// "Google Chrome" for chrome.exe: the file's description, else its name without .exe.
std::wstring friendlyName(ULONG_PTR pid, const std::wstring& exe) {
	auto fallback = exe.size() > 4 && lower(exe.substr(exe.size() - 4)) == L".exe" ? exe.substr(0, exe.size() - 4) : exe;
	HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
	if (!process) return fallback;
	wchar_t path[MAX_PATH * 2];
	DWORD length = _countof(path);
	auto ok = QueryFullProcessImageNameW(process, 0, path, &length);
	CloseHandle(process);
	if (!ok) return fallback;
	DWORD handle = 0;
	auto size = GetFileVersionInfoSizeW(path, &handle);
	if (!size) return fallback;
	std::vector<BYTE> data(size);
	if (!GetFileVersionInfoW(path, 0, size, data.data())) return fallback;
	struct Translation { WORD language, codePage; }* translations = nullptr;
	UINT bytes = 0;
	if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation", reinterpret_cast<void**>(&translations), &bytes) || bytes < sizeof(Translation))
		return fallback;
	wchar_t key[64];
	swprintf_s(key, L"\\StringFileInfo\\%04x%04x\\FileDescription", translations[0].language, translations[0].codePage);
	wchar_t* description = nullptr;
	UINT chars = 0;
	if (!VerQueryValueW(data.data(), key, reinterpret_cast<void**>(&description), &chars) || chars < 2) return fallback;
	std::wstring text(description);
	while (!text.empty() && iswspace(text.back())) text.pop_back();
	return text.empty() ? fallback : text;
}

std::string json(const std::wstring& value) {
	int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
	std::string utf8(size, '\0'), out = "\"";
	WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), utf8.data(), size, nullptr, nullptr);
	for (unsigned char c: utf8) {
		if (c == '"' || c == '\\') {
			out += '\\';
			out += static_cast<char>(c);
		} else if (c < 32) {
			char hex[7];
			std::snprintf(hex, sizeof(hex), "\\u%04x", c);
			out += hex;
		} else {
			out += static_cast<char>(c);
		}
	}
	return out + '"';
}

struct Program {
	std::wstring exe;
	ULONG_PTR anyPid = 0;
	double cpu = 0;
	ULONGLONG privateBytes = 0;
	int processes = 0;
};

} // namespace

int top(const std::vector<std::wstring>& args) {
	int count = args.empty() ? 5 : std::clamp(_wtoi(args[0].c_str()), 1, 20);
	auto threads = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
	LARGE_INTEGER frequency, start, end;
	QueryPerformanceFrequency(&frequency);
	auto before = snapshot();
	QueryPerformanceCounter(&start);
	Sleep(600);
	auto after = snapshot();
	QueryPerformanceCounter(&end);
	double elapsed100ns = double(end.QuadPart - start.QuadPart) * 1e7 / double(frequency.QuadPart);

	std::map<std::wstring, Program> programs; // by lower-case exe name
	for (auto& [pid, s]: after) {
		static const wchar_t* system[] = {L"registry", L"memory compression", L"secure system", L"system", L"idle"};
		auto key = lower(s.exe);
		if (std::any_of(std::begin(system), std::end(system), [&](const wchar_t* n) { return key == n; })) continue;
		auto& program = programs[key];
		program.exe = s.exe;
		if (!program.anyPid) program.anyPid = pid;
		auto old = before.find(pid);
		if (old != before.end() && old->second.exe == s.exe && s.cpuTime >= old->second.cpuTime)
			program.cpu += double(s.cpuTime - old->second.cpuTime) / (elapsed100ns * threads) * 100.0;
		program.privateBytes += s.privateBytes;
		program.processes++;
	}
	std::vector<Program*> list;
	for (auto& [_, program]: programs) list.push_back(&program);

	auto print = [&](const char* name, auto better) {
		std::sort(list.begin(), list.end(), better);
		std::printf("\"%s\":[", name);
		for (int i = 0; i < count && i < static_cast<int>(list.size()); ++i) {
			auto* p = list[i];
			std::printf("%s{\"name\":%s,\"exe\":%s,\"cpu\":%.1f,\"memMB\":%llu,\"processes\":%d}", i ? "," : "",
			            json(friendlyName(p->anyPid, p->exe)).c_str(), json(p->exe).c_str(), std::min(p->cpu, 100.0),
			            p->privateBytes / (1024 * 1024), p->processes);
		}
		std::printf("]");
	};
	std::printf("{\"threads\":%lu,", threads);
	print("cpu", [](Program* a, Program* b) { return a->cpu > b->cpu; });
	std::printf(",");
	print("memory", [](Program* a, Program* b) { return a->privateBytes > b->privateBytes; });
	std::printf("}\n");
	return 0;
}
