#include "common.h"
#include "nightlight.h"
#include <algorithm>
#include <cstring>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace ii::nightlight {
namespace {
struct Display { std::wstring id, name; };
std::vector<Display> displays() {
    std::vector<Display> result;
    DISPLAY_DEVICEW adapter{};
    adapter.cb = sizeof(adapter);
    for (DWORD i = 0; EnumDisplayDevicesW(nullptr, i, &adapter, 0); ++i) {
        if (!(adapter.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) || (adapter.StateFlags & DISPLAY_DEVICE_MIRRORING_DRIVER)) continue;
        DISPLAY_DEVICEW monitor{};
        monitor.cb = sizeof(monitor);
        if (!EnumDisplayDevicesW(adapter.DeviceName, 0, &monitor, EDD_GET_DEVICE_INTERFACE_NAME) || !monitor.DeviceID[0]) continue;
        result.push_back({monitor.DeviceID, adapter.DeviceName});
    }
    return result;
}
// Public display configuration API. Fail closed if HDR/advanced-color state cannot be read.
bool sdr(const std::wstring& name) {
    UINT32 pathsCount = 0, modesCount = 0;
    for (int retry = 0; retry < 3; ++retry) {
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathsCount, &modesCount) != ERROR_SUCCESS) return false;
        std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathsCount);
        std::vector<DISPLAYCONFIG_MODE_INFO> modes(modesCount);
        auto rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathsCount, paths.data(), &modesCount, modes.data(), nullptr);
        if (rc == ERROR_INSUFFICIENT_BUFFER) continue;
        if (rc != ERROR_SUCCESS) return false;
        bool found = false;
        for (UINT32 i = 0; i < pathsCount; ++i) {
            const auto& path = paths[i];
            DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
            source.header = {DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME, sizeof(source), path.sourceInfo.adapterId, path.sourceInfo.id};
            if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS || name != source.viewGdiDeviceName) continue;
            found = true;
            DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO color{};
            color.header = {DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO, sizeof(color), path.targetInfo.adapterId, path.targetInfo.id};
            if (DisplayConfigGetDeviceInfo(&color.header) != ERROR_SUCCESS || color.advancedColorEnabled) return false;
        }
        return found;
    }
    return false;
}
std::wstring backupPath() { return dataDir() + L"\\gamma.bin"; }
bool cancelling();
class WindowsBackend: public Backend {
    HDC dc(const std::wstring& id) {
        for (const auto& d: displays()) if (d.id == id && sdr(d.name)) return CreateDCW(L"DISPLAY", d.name.c_str(), nullptr, nullptr);
        return nullptr;
    }
public:
    std::vector<std::wstring> devices() override {
        std::vector<std::wstring> ids;
        for (const auto& d: displays()) if (sdr(d.name)) ids.push_back(d.id);
        return ids;
    }
    bool read(const std::wstring& id, Ramp& ramp) override {
        auto h = dc(id); if (!h) return false;
        auto ok = GetDeviceGammaRamp(h, ramp.data()) != FALSE;
        DeleteDC(h); return ok;
    }
    bool set(const std::wstring& id, const Ramp& ramp) override {
        auto h = dc(id); if (!h) return false;
        auto ok = SetDeviceGammaRamp(h, const_cast<Ramp&>(ramp).data()) != FALSE;
        DeleteDC(h); return ok;
    }
    bool save(const std::vector<Original>& values) override {
        auto path = backupPath(), temp = path + L".tmp";
        auto file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
        if (file == INVALID_HANDLE_VALUE) return false;
        bool ok = true;
        auto write = [&](const void* data, DWORD size) { DWORD n = 0; if (!WriteFile(file, data, size, &n, nullptr) || n != size) ok = false; };
        uint32_t header[] = {0x49494731, static_cast<uint32_t>(values.size())}; // IIG1
        write(header, sizeof(header));
        for (const auto& value: values) {
            auto size = static_cast<uint32_t>(value.device.size());
            write(&size, sizeof(size)); write(value.device.data(), size * sizeof(wchar_t)); write(&value.ramp, sizeof(Ramp));
        }
        if (!FlushFileBuffers(file)) ok = false;
        CloseHandle(file);
        if (ok) ok = MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
        if (!ok) DeleteFileW(temp.c_str());
        return ok;
    }
    bool load(std::vector<Original>& values) override {
        auto file = CreateFileW(backupPath().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) {
            if (GetLastError() != ERROR_FILE_NOT_FOUND) return false;
            values.clear(); return true;
        }
        auto read = [&](void* data, DWORD size) { DWORD n = 0; return ReadFile(file, data, size, &n, nullptr) && n == size; };
        uint32_t header[2]{};
        bool ok = read(header, sizeof(header)) && header[0] == 0x49494731 && header[1] <= 64;
        std::vector<Original> loaded;
        for (uint32_t i = 0; ok && i < header[1]; ++i) {
            uint32_t size = 0;
            ok = read(&size, sizeof(size)) && size > 0 && size <= 1024;
            if (!ok) break;
            Original value{std::wstring(size, L'\0'), {}};
            ok = read(value.device.data(), size * sizeof(wchar_t)) && read(&value.ramp, sizeof(Ramp)) && value.device.find(L'\0') == std::wstring::npos;
            loaded.push_back(std::move(value));
        }
        BYTE extra = 0; DWORD n = 0;
        ok = ok && ReadFile(file, &extra, 1, &n, nullptr) && n == 0;
        CloseHandle(file);
        if (ok) values = std::move(loaded);
        return ok;
    }
    void erase() override { DeleteFileW(backupPath().c_str()); }
    bool cancelled() override { return cancelling(); }
};
// Serializes host, guard, --rescue and the independent PowerShell rescue.
struct Lock {
    HANDLE handle = CreateMutexW(nullptr, FALSE, L"Local\\ii-windows-nightlight");
    bool held = false;
    Lock() { if (handle) { auto rc = WaitForSingleObject(handle, 10000); held = rc == WAIT_OBJECT_0 || rc == WAIT_ABANDONED; } }
    ~Lock() { if (held) ReleaseMutex(handle); if (handle) CloseHandle(handle); }
};
WindowsBackend backend;
Engine engine(backend);
std::mutex queueMutex;
std::condition_variable changed;
std::thread worker;
bool stopping = false, pending = false;
Request latest;
Status published;
bool cancelling() {
    std::scoped_lock lock(queueMutex);
    return stopping || (pending && latest.action == Action::Off);
}
void stopWorker() {
    { std::scoped_lock lock(queueMutex); stopping = true; }
    changed.notify_one();
    if (worker.joinable()) worker.join();
}
}
void start(bool guardReady) {
    stopWorker();
    Lock lock; if (!lock.held) return;
    const bool recovered = engine.recover(); // rescue old ramps even if a new guard couldn't start
    // Unavailable up front on displays that refuse gamma ramps, so the shell can offer Windows'
    // own night light instead of a toggle that does nothing.
    engine.status.available = guardReady && recovered && engine.probe();
    { std::scoped_lock qlock(queueMutex); published = engine.status; stopping = false; pending = false; }
    // GDI can take 200ms per call. Keep the host's keyboard/message thread responsive.
    worker = std::thread([] {
        for (;;) {
            Request request; bool haveRequest = false;
            {
                std::unique_lock qlock(queueMutex);
                changed.wait_for(qlock, std::chrono::seconds(1), [] { return stopping || pending; });
                if (stopping) return;
                haveRequest = pending; request = latest; pending = false;
            }
            Lock lock;
            if (!lock.held) continue;
            if (haveRequest && request.action == Action::Apply) engine.apply(request.kelvin, request.gamma, GetTickCount64());
            else if (haveRequest && request.action == Action::Off) engine.restore();
            engine.tick(GetTickCount64());
            { std::scoped_lock qlock(queueMutex); published = engine.status; }
        }
    });
}
intptr_t receive(const void* data, uint32_t size) {
    if (!data || size != sizeof(Request)) return 0;
    Request request; std::memcpy(&request, data, sizeof(request));
    if (request.version != 1 || request.action > Action::Off || request.kelvin < 1200 || request.kelvin > 6500 || request.gamma < 25 || request.gamma > 100) return 0;
    std::scoped_lock lock(queueMutex);
    if (!stopping && request.action != Action::Status) { latest = request; pending = true; changed.notify_one(); }
    return static_cast<intptr_t>(pack(published));
}
void tick() { changed.notify_one(); }
void restore() {
    stopWorker();
    Lock lock; if (!lock.held) return;
    engine.status.available = false;
    // Load the durable originals, including from a different process (guard/rescue).
    if (!engine.recover()) log(L"nightlight: originals retained; restore failed or monitor disconnected");
    { std::scoped_lock qlock(queueMutex); published = engine.status; }
}
}
