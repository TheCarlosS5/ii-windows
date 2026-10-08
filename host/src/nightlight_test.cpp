#include "nightlight.h"
#include <cstdio>
#include <cstdlib>
#include <map>
using namespace ii::nightlight;
void check(bool ok, const char* text) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", text); std::exit(1); } }
struct Fake: Backend {
    std::map<std::wstring, Ramp> current{{L"a", identity()}, {L"b", identity()}};
    std::vector<Original> journal;
    bool saveOk = true, loadOk = true, reject = false, restoreFails = false;
    int sets = 0;
    int cancelAfter = 0;
    std::vector<std::wstring> devices() override { std::vector<std::wstring> out; for (const auto& [id, ramp]: current) out.push_back(id); return out; }
    bool read(const std::wstring& id, Ramp& r) override { r = current.at(id); return true; }
    bool set(const std::wstring& id, const Ramp& r) override {
        check(!journal.empty(), "durable originals before every display write"); ++sets;
        if (restoreFails) return false;
        if (!reject || matches(r, identity())) current[id] = r;
        return true; // model Windows' silent rejection
    }
    bool save(const std::vector<Original>& values) override { if (saveOk) journal = values; return saveOk; }
    bool load(std::vector<Original>& values) override { if (!loadOk) return false; values = journal; return true; }
    void erase() override { journal.clear(); }
    bool cancelled() override { return cancelAfter > 0 && sets >= cancelAfter; }
};
int main() {
    Fake b; Engine e(b); check(e.recover(), "initial journal loaded"); e.status.available = true;
    b.saveOk = false;
    check(!e.apply(5000, 100, 0) && b.sets == 0, "failed backup prevents writes");
    check(e.restore() && b.sets == 0, "off after failed backup also writes nothing");
    b.saveOk = true;
    check(e.apply(5000, 100, 100) && e.status.active, "apply supported warm ramp");
    check(b.journal.size() == 2 && b.journal[0].ramp == identity(), "original per monitor captured");
    const auto sets = b.sets;
    check(e.apply(5000, 100, 5000) && b.sets == sets, "heartbeat doesn't rewrite matching ramps");
    e.tick(20000); check(e.status.active, "lease valid at 15 seconds");
    e.tick(20001); check(!e.status.active && b.journal.empty() && b.current[L"a"] == identity(), "dead shell restores originals");
    // Non-identity calibration must survive multiple intensity changes and a new process.
    auto calibrated = identity(); for (auto& ch: calibrated) for (auto& v: ch) v = static_cast<uint16_t>(v * 0.95);
    b.current[L"a"] = calibrated;
    check(e.apply(4500, 90, 0) && e.apply(5500, 100, 1), "multiple changes");
    Engine guard(b); check(guard.recover() && b.current[L"a"] == calibrated, "fresh guard restores exact calibrated original");
    b.current[L"a"] = identity(); b.reject = true;
    Engine rejected(b); check(rejected.recover(), "rejection setup recovery"); rejected.status.available = true;
    check(!rejected.apply(5000, 100, 0) && !rejected.status.active && rejected.status.minimum > 5000 && rejected.status.minimumVerified, "TRUE without readback backs off to neutral and reports rejection");
    rejected.restore(); b.reject = false;
    Engine failed(b); check(failed.recover(), "restore failure setup recovery"); failed.status.available = true; check(failed.apply(5000, 100, 0), "setup restore failure");
    b.restoreFails = true;
    check(!failed.restore() && !b.journal.empty(), "failed restore retains backup");
    b.restoreFails = false; failed.tick(1000); check(b.journal.empty(), "live worker automatically retries failed restore");
    Engine hotplug(b); check(hotplug.recover(), "hotplug setup recovery"); hotplug.status.available = true;
    check(hotplug.apply(5000, 100, 0), "hotplug setup");
    b.current[L"c"] = calibrated;
    check(hotplug.apply(5000, 100, 1) && b.journal.size() == 3, "new display original saved before tint");
    b.current.erase(L"c");
    check(!hotplug.restore() && !b.journal.empty(), "disconnected display retains original");
    b.current[L"c"] = identity();
    hotplug.tick(6001); check(b.current[L"c"] == calibrated && b.journal.empty(), "live worker retries after reconnect");
    Engine reconnected(b); check(reconnected.recover() && b.current[L"c"] == calibrated && b.journal.empty(), "rescue after reconnect restores by device ID");
    Engine tinted(b); check(tinted.recover(), "unreadable backup setup"); tinted.status.available = true;
    check(tinted.apply(5000, 100, 0), "unreadable backup tint setup");
    const auto backup = b.journal;
    const auto writes = b.sets;
    b.loadOk = false;
    Engine unreadable(b);
    check(!unreadable.recover() && !unreadable.restore() && b.sets == writes && b.journal.size() == backup.size(), "failed load plus Off never erases original backup");
    b.loadOk = true;
    unreadable.tick(5001); check(b.journal.empty() && b.current[L"a"] == identity(), "failed load automatically retried without erasing originals");
    check(tinted.recover() && tinted.apply(5000, 100, 0), "unavailable guard recovery setup");
    Engine unsupported(b); // availability false models startup without a guard
    check(unsupported.recover() && b.journal.empty() && b.current[L"a"] == identity(), "unsupported startup still restores durable originals");
    auto roundtrip = unpack(pack(e.status)); check(roundtrip.kelvin == e.status.kelvin && roundtrip.minimum == e.status.minimum, "status protocol roundtrip");
    Fake cancelling; Engine stopped(cancelling); check(stopped.recover(), "cancellation setup"); stopped.status.available = true;
    cancelling.cancelAfter = 1;
    check(!stopped.apply(5000, 100, 0) && cancelling.journal.empty() && cancelling.current[L"a"] == identity() && cancelling.current[L"b"] == identity(), "panic/off cancellation between display probes restores originals");
    std::puts("PASS: gamma safety (fake displays): backup/load failure + off, guard unavailable, two monitors, heartbeat, exact originals, silent rejection, restore retry, hotplug/reconnect, protocol");
}
