// display (plan 2026-10-31, F6/F7): HDR and the refresh rate of the main screen, for two quick toggles.
//   ii-shim display                 JSON: {"hdr":{"supported":true,"on":false},"hz":144,"rates":[60,120,144]}
//   ii-shim display hdr on|off      HDR on every screen that supports it (Windows' own switch, per user)
//   ii-shim display hz <rate>       the main screen's refresh rate at its current resolution
// The rate is changed for this session only (ChangeDisplaySettingsEx without CDS_UPDATEREGISTRY): Windows' saved
// rate comes back after a restart, so nothing stays changed by surprise. HDR is the same switch as Configuración >
// Pantalla > HDR, which Windows keeps.
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "user32.lib")

namespace {

struct Target {
	LUID adapter {};
	UINT32 id = 0;
	bool primary = false;
};

std::vector<Target> activeTargets() {
	std::vector<Target> out;
	UINT32 pathCount = 0, modeCount = 0;
	if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) return out;
	std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
	std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
	if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount, modes.data(), nullptr) != ERROR_SUCCESS) return out;
	paths.resize(pathCount);
	for (const auto& path: paths) {
		Target t;
		t.adapter = path.targetInfo.adapterId;
		t.id = path.targetInfo.id;
		const auto index = path.sourceInfo.modeInfoIdx;
		if (index != DISPLAYCONFIG_PATH_MODE_IDX_INVALID && index < modes.size() &&
		    modes[index].infoType == DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE) {
			const auto& position = modes[index].sourceMode.position;
			t.primary = position.x == 0 && position.y == 0;
		}
		out.push_back(t);
	}
	return out;
}

bool advancedColor(const Target& t, bool& supported, bool& on) {
	DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info {};
	info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
	info.header.size = sizeof(info);
	info.header.adapterId = t.adapter;
	info.header.id = t.id;
	if (DisplayConfigGetDeviceInfo(&info.header) != ERROR_SUCCESS) return false;
	supported = info.advancedColorSupported && !info.advancedColorForceDisabled;
	on = info.advancedColorEnabled;
	return true;
}

// The main screen's GDI name (\\.\DISPLAY1).
std::wstring primaryDevice() {
	DISPLAY_DEVICEW device {};
	device.cb = sizeof(device);
	for (DWORD i = 0; EnumDisplayDevicesW(nullptr, i, &device, 0); ++i) {
		if (device.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) return device.DeviceName;
		device.cb = sizeof(device);
	}
	return {};
}

// The rates offered at the current resolution and color depth, ascending.
std::vector<DWORD> rates(const std::wstring& device, const DEVMODEW& current) {
	std::vector<DWORD> out;
	DEVMODEW mode {};
	mode.dmSize = sizeof(mode);
	for (DWORD i = 0; EnumDisplaySettingsW(device.c_str(), i, &mode); ++i) {
		if (mode.dmPelsWidth == current.dmPelsWidth && mode.dmPelsHeight == current.dmPelsHeight &&
		    mode.dmBitsPerPel == current.dmBitsPerPel && mode.dmDisplayFrequency > 1 &&
		    std::find(out.begin(), out.end(), mode.dmDisplayFrequency) == out.end())
			out.push_back(mode.dmDisplayFrequency);
		mode = {};
		mode.dmSize = sizeof(mode);
	}
	std::sort(out.begin(), out.end());
	return out;
}

int info() {
	bool anySupported = false, allOn = true;
	for (const auto& t: activeTargets()) {
		bool supported = false, on = false;
		if (!advancedColor(t, supported, on) || !supported) continue;
		anySupported = true;
		allOn = allOn && on;
	}
	const auto device = primaryDevice();
	DEVMODEW current {};
	current.dmSize = sizeof(current);
	DWORD hz = 0;
	std::vector<DWORD> list;
	if (!device.empty() && EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &current)) {
		hz = current.dmDisplayFrequency;
		list = rates(device, current);
	}
	std::string out = std::string("{\"hdr\":{\"supported\":") + (anySupported ? "true" : "false") +
	                  ",\"on\":" + (anySupported && allOn ? "true" : "false") + "},\"hz\":" + std::to_string(hz) + ",\"rates\":[";
	for (size_t i = 0; i < list.size(); ++i) out += (i ? "," : "") + std::to_string(list[i]);
	out += "]}\n";
	std::fputs(out.c_str(), stdout);
	return 0;
}

int setHdr(bool enable) {
	int changed = 0, supportedCount = 0;
	for (const auto& t: activeTargets()) {
		bool supported = false, on = false;
		if (!advancedColor(t, supported, on) || !supported) continue;
		++supportedCount;
		if (on == enable) continue;
		DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE state {};
		state.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE;
		state.header.size = sizeof(state);
		state.header.adapterId = t.adapter;
		state.header.id = t.id;
		state.enableAdvancedColor = enable ? 1 : 0;
		if (DisplayConfigSetDeviceInfo(&state.header) == ERROR_SUCCESS) ++changed;
		else std::fprintf(stderr, "display: could not switch HDR on one screen\n");
	}
	if (!supportedCount) {
		std::fprintf(stderr, "display: no screen supports HDR\n");
		return 2;
	}
	return 0;
}

int setRate(DWORD hz) {
	const auto device = primaryDevice();
	DEVMODEW current {};
	current.dmSize = sizeof(current);
	if (device.empty() || !EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &current)) return 1;
	const auto list = rates(device, current);
	if (std::find(list.begin(), list.end(), hz) == list.end()) {
		std::fprintf(stderr, "display: %lu Hz is not offered at this resolution\n", hz);
		return 2;
	}
	if (current.dmDisplayFrequency == hz) return 0;
	DEVMODEW mode {};
	mode.dmSize = sizeof(mode);
	mode.dmFields = DM_DISPLAYFREQUENCY;
	mode.dmDisplayFrequency = hz;
	const auto result = ChangeDisplaySettingsExW(device.c_str(), &mode, nullptr, 0, nullptr);
	if (result != DISP_CHANGE_SUCCESSFUL) {
		std::fprintf(stderr, "display: Windows refused the change (%ld)\n", result);
		return 1;
	}
	return 0;
}

} // namespace

int display(const std::vector<std::wstring>& args) {
	if (args.empty()) return info();
	if (args[0] == L"hdr" && args.size() == 2 && (args[1] == L"on" || args[1] == L"off")) return setHdr(args[1] == L"on");
	if (args[0] == L"hz" && args.size() == 2) {
		const auto hz = wcstoul(args[1].c_str(), nullptr, 10);
		if (hz >= 24 && hz <= 1000) return setRate(hz);
	}
	std::fprintf(stderr, "usage: ii-shim display [hdr on|off | hz <rate>]\n");
	return 2;
}
