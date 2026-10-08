// Documented Monitor Configuration + WMI APIs only. All driver calls are made in a
// disposable console child process, with a deadline enforced by its parent.
#define NOMINMAX
#include <windows.h>
#include <physicalmonitorenumerationapi.h>
#include <highlevelmonitorconfigurationapi.h>
#include <lowlevelmonitorconfigurationapi.h>
#include <wbemidl.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <string>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

using Args = std::vector<std::wstring>;
using Microsoft::WRL::ComPtr;
namespace {
struct Handle {
	HANDLE value = nullptr;
	~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
struct Bstr {
	BSTR value;
	explicit Bstr(const wchar_t* text): value(SysAllocString(text)) {}
	~Bstr() { SysFreeString(value); }
	operator BSTR() const { return value; }
};
struct Variant {
	VARIANT value;
	Variant() { VariantInit(&value); }
	~Variant() { VariantClear(&value); }
};
std::string utf8(const std::wstring& text) {
	if (text.empty()) return {};
	int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), int(text.size()), nullptr, 0, nullptr, nullptr);
	std::string result(size, '\0'); WideCharToMultiByte(CP_UTF8, 0, text.c_str(), int(text.size()), result.data(), size, nullptr, nullptr); return result;
}
std::string json(const std::wstring& text) {
	std::string result = "\"";
	for (unsigned char c: utf8(text)) {
		if (c == '"' || c == '\\') { result += '\\'; result += c; }
		else if (c < 32) { char escape[7]; std::snprintf(escape, sizeof(escape), "\\u%04x", c); result += escape; }
		else result += c;
	}
	return result + '"';
}
std::wstring hash(const std::wstring& text) {
	unsigned long long value = 14695981039346656037ULL;
	for (auto c: text) { value ^= static_cast<unsigned short>(c); value *= 1099511628211ULL; }
	wchar_t result[17]; swprintf_s(result, L"%016llx", value); return result;
}
bool numeric(const std::wstring& text, DWORD& number, DWORD max = 100000) {
	if (text.empty() || text.find_first_not_of(L"0123456789") != std::wstring::npos) return false;
	unsigned long long value = 0;
	for (auto c: text) { value = value * 10 + c - L'0'; if (value > max) return false; }
	number = DWORD(value); return true;
}
std::wstring instance(std::wstring id) {
	if (id.rfind(L"\\\\?\\", 0) == 0) id.erase(0, 4);
	std::replace(id.begin(), id.end(), L'#', L'\\');
	auto guid = id.find(L"\\{"); if (guid != std::wstring::npos) id.resize(guid);
	auto suffix = id.find_last_of(L'_');
	if (suffix != std::wstring::npos && id.find_first_not_of(L"0123456789", suffix + 1) == std::wstring::npos) id.resize(suffix);
	for (auto& c: id) c = std::towupper(c);
	return id;
}
struct Panel {
	std::wstring screen, id, wmiPath;
	HANDLE physical = nullptr;
	DWORD minimum = 0, current = 0, maximum = 0;
	bool supported = false, highLevel = false, ambiguous = false;
};
struct Monitors {
	std::vector<Panel> panels;
	std::vector<PHYSICAL_MONITOR> handles;
	~Monitors() { if (!handles.empty()) DestroyPhysicalMonitors(DWORD(handles.size()), handles.data()); }
	static BOOL CALLBACK enumerate(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
		auto& self = *reinterpret_cast<Monitors*>(data);
		MONITORINFOEXW info {}; info.cbSize = sizeof(info);
		if (!GetMonitorInfoW(monitor, &info)) return TRUE;
		DISPLAY_DEVICEW device {}; device.cb = sizeof(device);
		EnumDisplayDevicesW(info.szDevice, 0, &device, EDD_GET_DEVICE_INTERFACE_NAME);
		std::wstring identity = device.DeviceID[0] ? device.DeviceID : info.szDevice;
		DWORD count = 0;
		if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0 || count > 32) {
			Panel panel; panel.screen = info.szDevice; panel.id = L"ddc-" + hash(identity + L"#0");
			self.panels.push_back(std::move(panel)); return TRUE;
		}
		std::vector<PHYSICAL_MONITOR> physical(count);
		if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical.data())) return TRUE;
		for (DWORD i = 0; i < count; ++i) {
			Panel panel; panel.screen = info.szDevice; panel.id = L"ddc-" + hash(identity + L"#" + std::to_wstring(i));
			panel.physical = physical[i].hPhysicalMonitor; panel.ambiguous = count != 1;
			self.panels.push_back(std::move(panel)); self.handles.push_back(physical[i]);
		}
		return TRUE;
	}
	Monitors() { EnumDisplayMonitors(nullptr, nullptr, enumerate, reinterpret_cast<LPARAM>(this)); }
};
bool read(Panel& panel) {
	if (!panel.physical) return false;
	panel.highLevel = GetMonitorBrightness(panel.physical, &panel.minimum, &panel.current, &panel.maximum);
	if (!panel.highLevel) {
		MC_VCP_CODE_TYPE type {}; panel.minimum = 0;
		if (!GetVCPFeatureAndVCPFeatureReply(panel.physical, 0x10, &type, &panel.current, &panel.maximum)) return false;
		if (type != MC_SET_PARAMETER) return false;
	}
	panel.supported = panel.maximum > panel.minimum && panel.current >= panel.minimum && panel.current <= panel.maximum;
	return panel.supported;
}
std::wstring textProperty(IWbemClassObject* object, const wchar_t* name) {
	Variant value; if (FAILED(object->Get(name, 0, &value.value, nullptr, nullptr)) || value.value.vt != VT_BSTR) return {};
	return value.value.bstrVal ? value.value.bstrVal : L"";
}
class Wmi {
	bool initialized = false;
public:
	ComPtr<IWbemServices> service;
	Wmi() {
		auto hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED); if (FAILED(hr)) return; initialized = true;
		CoInitializeSecurity(nullptr, -1, nullptr, nullptr, RPC_C_AUTHN_LEVEL_DEFAULT, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE, nullptr);
		ComPtr<IWbemLocator> locator;
		if (FAILED(CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&locator)))) return;
		if (FAILED(locator->ConnectServer(Bstr(L"ROOT\\WMI"), nullptr, nullptr, nullptr, 0, nullptr, nullptr, &service))) return;
		if (FAILED(CoSetProxyBlanket(service.Get(), RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr,
			RPC_C_AUTHN_LEVEL_PKT_PRIVACY, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE))) service.Reset();
	}
	~Wmi() { service.Reset(); if (initialized) CoUninitialize(); }
	std::vector<ComPtr<IWbemClassObject>> query(const wchar_t* query) {
		std::vector<ComPtr<IWbemClassObject>> result;
		if (!service) return result;
		ComPtr<IEnumWbemClassObject> enumerator;
		if (FAILED(service->ExecQuery(Bstr(L"WQL"), Bstr(query), WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, nullptr, &enumerator))) return result;
		for (unsigned int i = 0; i < 32; ++i) {
			ComPtr<IWbemClassObject> object; ULONG returned = 0;
			if (enumerator->Next(1000, 1, &object, &returned) != S_OK || !returned) break;
			result.push_back(object);
		}
		return result;
	}
	std::vector<Panel> panels() {
		std::vector<Panel> result;
		for (auto const& object: query(L"SELECT * FROM WmiMonitorBrightness WHERE Active=TRUE")) {
			auto id = instance(textProperty(object.Get(), L"InstanceName"));
			Variant brightness;
			if (FAILED(object->Get(L"CurrentBrightness", 0, &brightness.value, nullptr, nullptr))) continue;
			if (FAILED(VariantChangeType(&brightness.value, &brightness.value, 0, VT_UI4))) continue;
			// Match the WMI instance to the interface of the active GDI screen.
			for (DWORD i = 0; i < 32; ++i) {
				DISPLAY_DEVICEW source {}; source.cb = sizeof(source);
				if (!EnumDisplayDevicesW(nullptr, i, &source, 0)) break;
				if (!(source.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) continue;
				for (DWORD j = 0; j < 32; ++j) {
					DISPLAY_DEVICEW target {}; target.cb = sizeof(target);
					if (!EnumDisplayDevicesW(source.DeviceName, j, &target, EDD_GET_DEVICE_INTERFACE_NAME)) break;
					if (instance(target.DeviceID) != id) continue;
					Panel panel; panel.screen = source.DeviceName; panel.id = L"wmi-" + hash(id);
					panel.current = brightness.value.ulVal; panel.maximum = 100; panel.supported = panel.current <= 100;
					for (auto const& method: query(L"SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE"))
						if (instance(textProperty(method.Get(), L"InstanceName")) == id) panel.wmiPath = textProperty(method.Get(), L"__PATH");
					panel.supported = panel.supported && !panel.wmiPath.empty(); result.push_back(std::move(panel));
				}
			}
		}
		return result;
	}
	bool set(const Panel& panel, DWORD brightness) {
		ComPtr<IWbemClassObject> definition, inputDefinition, input, output;
		if (!service || panel.wmiPath.empty() || brightness > 100) return false;
		if (FAILED(service->GetObject(Bstr(L"WmiMonitorBrightnessMethods"), 0, nullptr, &definition, nullptr))
			|| FAILED(definition->GetMethod(L"WmiSetBrightness", 0, &inputDefinition, nullptr))
			|| FAILED(inputDefinition->SpawnInstance(0, &input))) return false;
		Variant timeout, level;
		timeout.value.vt = VT_I4; timeout.value.lVal = 0;
		level.value.vt = VT_UI1; level.value.bVal = BYTE(brightness);
		if (FAILED(input->Put(L"Timeout", 0, &timeout.value, 0)) || FAILED(input->Put(L"Brightness", 0, &level.value, 0))) return false;
		if (FAILED(service->ExecMethod(Bstr(panel.wmiPath.c_str()), Bstr(L"WmiSetBrightness"), 0, nullptr, input.Get(), &output, nullptr))) return false;
		Variant status;
		return output && SUCCEEDED(output->Get(L"ReturnValue", 0, &status.value, nullptr, nullptr))
			&& SUCCEEDED(VariantChangeType(&status.value, &status.value, 0, VT_UI4)) && status.value.ulVal == 0;
	}
};
std::wstring quote(const std::wstring& value) {
	std::wstring result = L"\""; unsigned int slashes = 0;
	for (auto c: value) {
		if (c == L'\\') { ++slashes; continue; }
		if (c == L'"') result.append(slashes * 2 + 1, L'\\'); else result.append(slashes, L'\\');
		slashes = 0; result += c;
	}
	result.append(slashes * 2, L'\\'); return result + L'"';
}
int supervise(const Args& args, DWORD timeout, bool reportTimeout = true) {
	wchar_t path[32768]; DWORD count = GetModuleFileNameW(nullptr, path, DWORD(std::size(path)));
	if (!count || count >= std::size(path)) return 1;
	std::wstring command = quote(path) + L" _brightness-worker";
	for (auto const& arg: args) command += L" " + quote(arg);
	STARTUPINFOW startup {}; startup.cb = sizeof(startup);
	// Preserve the QML Process pipes in the worker; it never creates a console/window.
	startup.dwFlags = STARTF_USESTDHANDLES;
	startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE); startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE); startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
	PROCESS_INFORMATION process {};
	Handle job {CreateJobObjectW(nullptr, nullptr)};
	JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits {};
	limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
	if (!job.value || !SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return 1;
	if (!CreateProcessW(path, command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &process)) return 1;
	Handle child {process.hProcess}, thread {process.hThread};
	if (!AssignProcessToJobObject(job.value, child.value)) { TerminateProcess(child.value, 1); return 1; }
	if (ResumeThread(thread.value) == DWORD(-1)) return 1;
	if (WaitForSingleObject(child.value, timeout) != WAIT_OBJECT_0) {
		TerminateProcess(child.value, 124); WaitForSingleObject(child.value, 1000);
		if (reportTimeout) std::fputs("brightness: driver query timed out\n", stderr); return 124;
	}
	DWORD code = 1; GetExitCodeProcess(child.value, &code); return int(code);
}
struct Pending { ULONGLONG serial = 0, processed = 0; DWORD value = 0, kind = 0; int result = 0; };
int coalesce(const std::wstring& mode, const std::wstring& target, DWORD value,
    const std::function<int(DWORD)>& fake = {}, const std::function<void()>& submitted = {}, DWORD ownerBudget = 10000) {
	// Volatile kernel objects, scoped to this login session. Contending processes
	// overwrite the pending value; exactly one owner writes the latest request.
	auto name = L"Local\\ii-brightness-" + hash(target);
	Handle mapping {CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(Pending), (name + L"-pending").c_str())};
	Handle queue {CreateMutexW(nullptr, FALSE, (name + L"-queue").c_str())};
	Handle writer {CreateMutexW(nullptr, FALSE, (name + L"-writer").c_str())};
	if (!mapping.value || !queue.value || !writer.value) return 1;
	auto* pending = static_cast<Pending*>(MapViewOfFile(mapping.value, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Pending)));
	if (!pending) return 1;
	auto lock = WaitForSingleObject(queue.value, 1000);
	if (lock != WAIT_OBJECT_0 && lock != WAIT_ABANDONED) { UnmapViewOfFile(pending); return 124; }
	pending->value = value; pending->kind = mode == L"percent" ? 1 : mode == L"backlight" ? 2 : 0;
	const auto ticket = ++pending->serial; ReleaseMutex(queue.value);
	if (submitted) submitted(); // fake-writer tests only
	// Keep the shared queue alive until this request is acknowledged. A waiter
	// takes over if the previous writer fails, exits, or exhausts its budget.
	lock = WaitForSingleObject(writer.value, 12000);
	if (lock != WAIT_OBJECT_0 && lock != WAIT_ABANDONED) { UnmapViewOfFile(pending); return 124; }
	int result = 124; auto deadline = GetTickCount64() + ownerBudget;
	while (GetTickCount64() < deadline) {
		lock = WaitForSingleObject(queue.value, 1000);
		if (lock != WAIT_OBJECT_0 && lock != WAIT_ABANDONED) { result = 124; break; }
		if (pending->processed >= ticket && pending->processed == pending->serial) {
			result = pending->result;
			ReleaseMutex(writer.value); ReleaseMutex(queue.value);
			UnmapViewOfFile(pending); return result;
		}
		ReleaseMutex(queue.value);
		Sleep(300); // rate limit; requests arriving here replace the pending value
		if (GetTickCount64() >= deadline) { result = 124; break; }
		lock = WaitForSingleObject(queue.value, 1000);
		if (lock != WAIT_OBJECT_0 && lock != WAIT_ABANDONED) { result = 124; break; }
		auto request = *pending; ReleaseMutex(queue.value);
		const std::wstring writeMode = request.kind == 1 ? L"percent" : request.kind == 2 ? L"backlight" : L"raw";
		const auto now = GetTickCount64();
		if (now >= deadline) { result = 124; break; }
		result = fake ? fake(request.value) : supervise({L"set", writeMode, target, std::to_wstring(request.value)},
			DWORD(std::min<ULONGLONG>(4000, deadline - now)));
		lock = WaitForSingleObject(queue.value, 1000);
		if (lock != WAIT_OBJECT_0 && lock != WAIT_ABANDONED) { result = 124; break; }
		pending->processed = request.serial; pending->result = result;
		if (pending->serial == request.serial) {
			ReleaseMutex(writer.value); ReleaseMutex(queue.value);
			UnmapViewOfFile(pending); return result;
		}
		ReleaseMutex(queue.value);
		// A failed older write does not discard a newer value.
	}
	// Release writer while queue is held: a new request cannot slip into the
	// shutdown gap, observe an old writer, and leave its last value unapplied.
	lock = WaitForSingleObject(queue.value, 1000);
	if (lock == WAIT_OBJECT_0 || lock == WAIT_ABANDONED) {
		if (pending->processed < pending->serial) result = 124;
		ReleaseMutex(writer.value); ReleaseMutex(queue.value);
	}
	else ReleaseMutex(writer.value);
	UnmapViewOfFile(pending); return result;
}
int worker(const Args& args) {
	if (args.empty()) return 2;
	// Read-only timeout fixture; before any monitor enumeration or driver call.
	if (args.size() == 2 && args[0] == L"test-delay") {
		DWORD duration = 0; if (!numeric(args[1], duration, 2000)) return 2;
		Sleep(duration); return 0;
	}
	Monitors external;
	if (args[0] == L"detect" && args.size() == 1) {
		unsigned int index = 0;
		for (auto const& panel: external.panels) std::printf("Display %u\n   I2C bus: /dev/i2c-%s\n   DRM connector: Windows-%s\n\n",
			++index, utf8(panel.id).c_str(), utf8(panel.screen).c_str());
		return 0;
	}
	if (args[0] == L"get" && args.size() == 2) {
		for (auto& panel: external.panels) if (panel.id == args[1] && read(panel)) {
			std::printf("VCP 10 C %lu %lu\n", panel.current, panel.maximum); return 0;
		}
		std::fputs("brightness: DDC/CI unavailable\n", stderr); return 1;
	}
	if (args[0] == L"list" && args.size() == 1) {
		Wmi wmi; auto internal = wmi.panels(); bool comma = false;
		for (auto& panel: internal) {
			const auto matches = std::count_if(internal.begin(), internal.end(), [&](auto const& item) { return item.screen == panel.screen; });
			const bool mirrored = std::any_of(external.panels.begin(), external.panels.end(), [&](auto const& item) { return item.screen == panel.screen && item.ambiguous; });
			panel.ambiguous = matches != 1 || mirrored;
			panel.supported = panel.supported && !panel.ambiguous;
		}
		std::fputs("[", stdout);
		for (auto& panel: external.panels) {
			// WMI takes precedence for internal panels; mirrored targets are ambiguous.
			if (std::any_of(internal.begin(), internal.end(), [&](auto const& item) { return item.screen == panel.screen && item.supported; })) continue;
			if (std::any_of(internal.begin(), internal.end(), [&](auto const& item) { return item.screen == panel.screen && item.ambiguous; })) panel.ambiguous = true;
			bool supported = !panel.ambiguous && read(panel);
			std::printf("%s{\"screen\":%s,\"id\":%s,\"available\":%s,\"current\":%lu,\"max\":%lu}", comma ? "," : "", json(panel.screen).c_str(), json(panel.id).c_str(),
				supported ? "true" : "false", supported ? panel.current - panel.minimum : 0, supported ? panel.maximum - panel.minimum : 0); comma = true;
		}
		for (auto const& panel: internal) {
			std::printf("%s{\"screen\":%s,\"id\":%s,\"available\":%s,\"current\":%lu,\"max\":100}", comma ? "," : "", json(panel.screen).c_str(), json(panel.id).c_str(), panel.supported ? "true" : "false", panel.current); comma = true;
		}
		std::puts("]"); return 0;
	}
	if (args[0] == L"backlight" && args.size() == 2) {
		Wmi wmi; auto panels = wmi.panels();
		if (panels.size() != 1 || !panels[0].supported) return 1;
		std::printf("%lu\n", args[1] == L"g" ? panels[0].current : 100UL); return 0;
	}
	if (args[0] == L"set" && args.size() == 4) {
		DWORD value = 0; if (!numeric(args[3], value)) return 2;
		if (args[1] == L"backlight" || args[2].rfind(L"wmi-", 0) == 0) {
			Wmi wmi; auto panels = wmi.panels();
			for (auto const& panel: panels) if (panel.supported && (panel.id == args[2] || (args[1] == L"backlight" && panels.size() == 1)))
				return wmi.set(panel, std::clamp(value, 1UL, 100UL)) ? 0 : 1;
			return 1;
		}
		for (auto& panel: external.panels) if (panel.id == args[2] && read(panel)) {
			if (args[1] == L"percent") value = panel.minimum + DWORD((panel.maximum - panel.minimum) * std::clamp(value, 1UL, 100UL) / 100);
			value = std::clamp(value, std::max(panel.minimum, 1UL), panel.maximum);
			return (panel.highLevel ? SetMonitorBrightness(panel.physical, value) : SetVCPFeature(panel.physical, 0x10, value)) ? 0 : 1;
		}
		return 1;
	}
	return 2;
}
int selfTest() {
	int failures = 0; DWORD value = 0;
	auto check = [&](bool condition) { if (!condition) ++failures; };
	check(!numeric(L"-1", value) && !numeric(L"101", value, 100) && !numeric(L"100000000000000000000", value));
	check(numeric(L"100", value, 100) && value == 100);
	check(instance(L"\\\\?\\DISPLAY#ABC#123#{guid}") == instance(L"DISPLAY\\ABC\\123_0"));
	check(quote(L"x\\\"y\\") == L"\"x\\\\\\\"y\\\\\"");
	std::mutex mutex; std::vector<DWORD> applied;
	std::function<int(DWORD)> fake = [&](DWORD request) { std::scoped_lock lock(mutex); applied.push_back(request); return 0; };
	auto target = L"self-test-" + std::to_wstring(GetCurrentProcessId());
	Handle secondSubmitted {CreateEventW(nullptr, TRUE, FALSE, nullptr)};
	Handle thirdSubmitted {CreateEventW(nullptr, TRUE, FALSE, nullptr)};
	int ownerCode = -1, secondCode = -1, thirdCode = -1;
	std::thread owner([&] { ownerCode = coalesce(L"test", target, 1, fake); });
	Sleep(50);
	std::thread second([&] { secondCode = coalesce(L"test", target, 2, fake, [&] { SetEvent(secondSubmitted.value); }); });
	WaitForSingleObject(secondSubmitted.value, 3000);
	std::thread third([&] { thirdCode = coalesce(L"test", target, 3, fake, [&] { SetEvent(thirdSubmitted.value); }); });
	WaitForSingleObject(thirdSubmitted.value, 3000);
	owner.join(); second.join(); third.join();
	check(secondCode == 0); check(thirdCode == 0);
	check(ownerCode == 0 && applied.size() == 1 && applied.back() == 3);
	// A newer request must survive an older driver's failure. Only fake writers.
	Handle started {CreateEventW(nullptr, TRUE, FALSE, nullptr)};
	Handle release {CreateEventW(nullptr, TRUE, FALSE, nullptr)};
	std::vector<DWORD> retryApplied;
	std::function<int(DWORD)> failFirst = [&](DWORD request) {
		{ std::scoped_lock lock(mutex); retryApplied.push_back(request); }
		if (request == 1) { SetEvent(started.value); WaitForSingleObject(release.value, 3000); return 1; }
		return 0;
	};
	std::thread older([&] { coalesce(L"test", target + L"-failure", 1, failFirst); });
	if (WaitForSingleObject(started.value, 3000) != WAIT_OBJECT_0) ++failures;
	ResetEvent(secondSubmitted.value); int newerCode = -1;
	std::thread newer([&] { newerCode = coalesce(L"test", target + L"-failure", 2, failFirst, [&] { SetEvent(secondSubmitted.value); }); });
	WaitForSingleObject(secondSubmitted.value, 3000);
	SetEvent(release.value); older.join(); newer.join();
	check(newerCode == 0 && retryApplied.back() == 2);
	// A request arriving during the last write survives owner-budget exhaustion.
	ResetEvent(started.value); ResetEvent(release.value); ResetEvent(secondSubmitted.value);
	retryApplied.clear(); int expiredCode = -1; newerCode = -1;
	std::thread expired([&] { expiredCode = coalesce(L"test", target + L"-deadline", 1, failFirst, {}, 600); });
	if (WaitForSingleObject(started.value, 3000) != WAIT_OBJECT_0) ++failures;
	std::thread takeover([&] { newerCode = coalesce(L"test", target + L"-deadline", 2, failFirst, [&] { SetEvent(secondSubmitted.value); }); });
	WaitForSingleObject(secondSubmitted.value, 3000); Sleep(350); SetEvent(release.value);
	expired.join(); takeover.join();
	check(expiredCode == 124 && newerCode == 0 && retryApplied.back() == 2);
	// Deadline kills our console fixture, never a driver, host, shell or app.
	check(supervise({L"test-delay", L"1500"}, 100, false) == 124);
	std::printf("brightness checks=10 failures=%d\n", failures); return failures ? 1 : 0;
}
}
int brightnessCommand(const std::wstring& command, const Args& args) {
	SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
	if (command == L"_brightness-worker") return worker(args);
	if (command == L"brightness-win") {
		if (args == Args {L"self-test"}) return selfTest();
		if (args == Args {L"list"}) return supervise({L"list"}, 8000);
		if (args.size() == 3 && args[0] == L"set") {
			DWORD value = 0; if (!numeric(args[2], value, 100)) return 2;
			return coalesce(L"percent", args[1], std::max(value, 1UL));
		}
		return 2;
	}
	if (command == L"ddcutil") {
		if (args == Args {L"detect", L"--brief"}) return supervise({L"detect"}, 5000);
		if (args.size() == 5 && args[0] == L"-b" && args[3] == L"10") {
			if (args[2] == L"getvcp" && args[4] == L"--brief") return supervise({L"get", args[1]}, 4000);
			DWORD value = 0;
			if (args[2] == L"setvcp" && numeric(args[4], value)) return coalesce(L"raw", args[1], value);
		}
		return 2;
	}
	if (command == L"brightnessctl") {
		Args values;
		for (size_t i = 0; i < args.size(); ++i) {
			if (args[i] == L"--class" && i + 1 < args.size() && args[i + 1] == L"backlight") ++i;
			else if (args[i] != L"--quiet") values.push_back(args[i]);
		}
		if (values == Args {L"g"} || values == Args {L"m"}) return supervise({L"backlight", values[0]}, 5000);
		if (values.size() == 2 && values[0] == L"s") {
			auto text = values[1]; if (!text.empty() && text.back() == L'%') text.pop_back();
			DWORD value = 0; if (!numeric(text, value, 100)) return 2;
			return coalesce(L"backlight", L"internal", std::max(value, 1UL));
		}
	}
	return 2;
}
