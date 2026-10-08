#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace ii::nightlight {
using Ramp = std::array<std::array<uint16_t, 256>, 3>;
struct Plan { int kelvin; int gamma; Ramp ramp; };
Ramp identity();
int minimumKelvin();
Plan compute(int kelvin, int gamma, const Ramp& original);
bool matches(const Ramp& a, const Ramp& b);
struct Original { std::wstring device; Ramp ramp; };
// Kept separate so safety paths can be exercised without touching a display.
struct Backend {
    virtual ~Backend() = default;
    virtual std::vector<std::wstring> devices() = 0;
    virtual bool read(const std::wstring&, Ramp&) = 0;
    virtual bool set(const std::wstring&, const Ramp&) = 0;
    virtual bool save(const std::vector<Original>&) = 0;
    virtual bool load(std::vector<Original>&) = 0;
    virtual void erase() = 0;
    virtual bool cancelled() { return false; }
};
struct Status {
    bool available = false;
    bool active = false;
    bool minimumVerified = false;
    int kelvin = 6500;
    int gamma = 100;
    int minimum = minimumKelvin();
    int error = 0; // 1: unavailable, 2: read/HDR, 3: backup, 4: rejected, 5: restore
};
class Engine {
    Backend& backend;
    std::vector<Original> originals;
    uint64_t heartbeat = 0;
    bool leased = false;
    bool calibrated = false;
    bool journalKnown = false;
    bool restorePending = false;
    uint64_t nextRestoreAttempt = 0;
    std::vector<std::wstring> calibratedDevices;
public:
    Status status;
    explicit Engine(Backend& b): backend(b) {}
    bool recover();
    bool apply(int kelvin, int gamma, uint64_t now);
    bool restore();
    void tick(uint64_t now);
    // Read-only: can every display's ramp be read? Some drivers refuse GDI gamma entirely.
    bool probe();
};

// Private ii protocol over documented WM_COPYDATA, not a Windows private message.
constexpr uintptr_t COPYDATA = 0x49490030;
enum class Action: uint32_t { Status, Apply, Off };
struct Request { uint32_t version = 1; Action action = Action::Status; int32_t kelvin = 6500; int32_t gamma = 100; };
uint64_t pack(const Status&);
Status unpack(uint64_t);
// Host only. All writes are behind these entry points.
void start(bool guardReady);
intptr_t receive(const void* data, uint32_t size);
void tick();
void restore();
}
