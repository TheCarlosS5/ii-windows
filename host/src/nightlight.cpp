#include "common.h"
#include "nightlight.h"
#include <algorithm>
#include <cstring>
#include <condition_variable>
#include <functional>
#include <atomic>
#include <mutex>
#include <thread>
#include <magnification.h>

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
// Fallback for displays that refuse GDI gamma ramps (some drivers, and any display in HDR): the
// Magnification API tints the whole desktop with a colour matrix inside DWM. The tint belongs to this
// process: when ii-host ends, for whatever reason, the screen is back to normal by itself. The "ramp" the
// engine computes (white point per channel) becomes the diagonal of the matrix; the engine's readback
// check is answered from the last matrix set.
// The Magnification API belongs to the thread that initialized it: every call goes through one thread of its
// own, whichever thread asks (the host's, the worker's, the shutdown path's).
class MagThread {
    std::mutex callMutex, mutex;
    std::condition_variable cv;
    std::function<bool()> job;
    bool has = false, done = false, result = false;
    std::thread thread;
    void loop() {
        std::unique_lock lock(mutex);
        for (;;) {
            cv.wait(lock, [&] { return has; });
            auto work = std::move(job);
            has = false;
            lock.unlock();
            const bool ok = work();
            lock.lock();
            result = ok;
            done = true;
            cv.notify_all();
        }
    }
public:
    bool run(std::function<bool()> work) {
        std::scoped_lock call(callMutex);
        std::unique_lock lock(mutex);
        if (!thread.joinable()) thread = std::thread([this] { loop(); });
        job = std::move(work);
        has = true;
        done = false;
        cv.notify_all();
        cv.wait(lock, [&] { return done; });
        return result;
    }
};
MagThread& magThread() {
    static auto* instance = new MagThread(); // never destroyed: the process ending ends the tint too
    return *instance;
}
class MagBackend: public Backend {
    Ramp current = identity();
    bool inited = false; // only touched from the Magnification thread
    bool ensure() {
        if (inited) return true;
        inited = MagInitialize() != FALSE;
        return inited;
    }
    static bool apply(float r, float g, float b) {
        MAGCOLOREFFECT effect = {{{r, 0, 0, 0, 0}, {0, g, 0, 0, 0}, {0, 0, b, 0, 0}, {0, 0, 0, 1, 0}, {0, 0, 0, 0, 1}}};
        return MagSetFullscreenColorEffect(&effect) != FALSE;
    }
public:
    std::vector<std::wstring> devices() override { return {L"magnification"}; }
    bool read(const std::wstring&, Ramp& ramp) override { ramp = current; return true; }
    bool set(const std::wstring&, const Ramp& ramp) override {
        const float r = ramp[0][255] / 65535.0f, g = ramp[1][255] / 65535.0f, b = ramp[2][255] / 65535.0f;
        if (!magThread().run([this, r, g, b] { return ensure() && apply(r, g, b); })) return false;
        current = ramp;
        return true;
    }
    bool save(const std::vector<Original>&) override { return true; } // nothing to rescue: it dies with the process
    bool load(std::vector<Original>& values) override { values.clear(); return true; }
    void erase() override {}
    bool cancelled() override { return cancelling(); }
    // Can the API be started here at all? (Windows 8+; a Server Core or a policy may say no.)
    bool available() { return magThread().run([this] { return ensure(); }); }
    void off() {
        magThread().run([this] { return inited && apply(1, 1, 1); });
        current = identity();
    }
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
MagBackend magBackend;
Engine magEngine(magBackend);
Engine* active = &engine;
std::mutex queueMutex;
std::condition_variable changed;
// Windows' own night light is on: ii's tint on top would double the yellow, so ii's colour temperature
// stays off and the panel says why (error 6). Gamma alone (no temperature) is still allowed.
std::atomic<bool> windowsOwn {false};
constexpr int ERROR_WINDOWS_NIGHT_LIGHT = 6;
// Settings > Display > Night light keeps its state in the per-user CloudStore. Byte 18 of the blob is
// 0x15 while it is on and 0x13 while off (no public API exposes this; an unknown layout reads as off).
bool windowsNightLightOn() {
    static const wchar_t* key = L"Software\\Microsoft\\Windows\\CurrentVersion\\CloudStore\\Store\\DefaultAccount\\Current\\"
        L"default$windows.data.bluelightreduction.bluelightreductionstate\\windows.data.bluelightreduction.bluelightreductionstate";
    BYTE data[64] {};
    DWORD size = sizeof(data);
    if (RegGetValueW(HKEY_CURRENT_USER, key, L"Data", RRF_RT_REG_BINARY, nullptr, data, &size) != ERROR_SUCCESS) return false;
    return size > 18 && data[18] == 0x15;
}
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
    // Gamma ramps first. A display that refuses them (some drivers, HDR) is tinted through the Magnification
    // API instead; only when neither works the shell offers Windows' own night light.
    engine.status.available = guardReady && recovered && engine.probe();
    active = &engine;
    if (!engine.status.available && guardReady) {
        magEngine.status = Status();
        if (magEngine.recover() && magBackend.available() && magEngine.probe()) {
            magEngine.status.available = true;
            active = &magEngine;
            log(L"nightlight: gamma ramps refused, tinting through the Magnification API");
        }
    }
    { std::scoped_lock qlock(queueMutex); published = active->status; stopping = false; pending = false; }
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
            const bool own = windowsNightLightOn();
            if (own != windowsOwn.exchange(own)) log(L"nightlight: Windows' own night light is %s", own ? L"on: ii's colour temperature stays off" : L"off");
            Lock lock;
            if (!lock.held) continue;
            // With Windows' night light on, only a gamma change goes through, never a second tint.
            if (own && active->status.active && active->status.kelvin < 6500) active->apply(6500, active->status.gamma, GetTickCount64());
            if (haveRequest && request.action == Action::Apply) active->apply(own ? 6500 : request.kelvin, request.gamma, GetTickCount64());
            else if (haveRequest && request.action == Action::Off) active->restore();
            active->tick(GetTickCount64());
            { std::scoped_lock qlock(queueMutex); published = active->status; }
        }
    });
}
intptr_t receive(const void* data, uint32_t size) {
    if (!data || size != sizeof(Request)) return 0;
    Request request; std::memcpy(&request, data, sizeof(request));
    if (request.version != 1 || request.action > Action::Off || request.kelvin < 1200 || request.kelvin > 6500 || request.gamma < 25 || request.gamma > 100) return 0;
    std::scoped_lock lock(queueMutex);
    if (!stopping && request.action != Action::Status) { latest = request; pending = true; changed.notify_one(); }
    auto status = published;
    if (windowsOwn.load() && !status.error) status.error = ERROR_WINDOWS_NIGHT_LIGHT;
    return static_cast<intptr_t>(pack(status));
}
void tick() { changed.notify_one(); }
void restore() {
    stopWorker();
    Lock lock; if (!lock.held) return;
    engine.status.available = false;
    magEngine.status.available = false;
    magEngine.restore();
    magBackend.off();
    // Load the durable originals, including from a different process (guard/rescue).
    if (!engine.recover()) log(L"nightlight: originals retained; restore failed or monitor disconnected");
    active = &engine;
    { std::scoped_lock qlock(queueMutex); published = engine.status; }
}
}
