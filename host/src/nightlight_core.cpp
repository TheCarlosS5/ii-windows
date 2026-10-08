#include "nightlight.h"
#include <algorithm>
#include <cmath>

namespace ii::nightlight {
namespace {
// Smooth black-body approximation, normalized to an exactly neutral 6500 K.
std::array<double, 3> rgb(int kelvin) {
    auto raw = [](double t) {
        t /= 100;
        return std::array<double, 3>{1, std::clamp((99.4708025861 * std::log(t) - 161.1195681661) / 255, 0.0, 1.0),
            t <= 19 ? 0 : std::clamp((138.5177312231 * std::log(t - 10) - 305.0447927307) / 255, 0.0, 1.0)};
    };
    auto values = raw(kelvin), white = raw(6500);
    for (int c = 0; c < 3; ++c) values[c] = std::clamp(values[c] / white[c], 0.0, 1.0);
    return values;
}
}
Ramp identity() {
    Ramp ramp{};
    for (auto& channel: ramp) for (int i = 0; i < 256; ++i) channel[i] = static_cast<uint16_t>(i * 257);
    return ramp;
}
int minimumKelvin() {
    // Conservative engineering bound, not a claim about a particular driver's heuristics.
    for (int k = 1200; k <= 6500; k += 50) if (rgb(k)[2] >= 0.55) return k;
    return 6500;
}
Plan compute(int kelvin, int gamma, const Ramp& original) {
    kelvin = std::clamp(kelvin, minimumKelvin(), 6500);
    auto gains = rgb(kelvin);
    gamma = std::clamp(gamma, static_cast<int>(std::ceil(55 / *std::min_element(gains.begin(), gains.end()))), 100);
    Plan plan{kelvin, gamma, {}};
    for (int c = 0; c < 3; ++c) for (int i = 0; i < 256; ++i) {
        auto value = static_cast<int>(std::lround(original[c][i] * gains[c] * gamma / 100));
        // Leave a margin inside the commonly accepted identity band; verify on hardware too.
        plan.ramp[c][i] = static_cast<uint16_t>(std::clamp(value, std::max(0, i * 257 - 30000), std::min(65535, i * 257 + 30000)));
    }
    return plan;
}
bool matches(const Ramp& a, const Ramp& b) {
    for (int c = 0; c < 3; ++c) for (int i = 0; i < 256; ++i)
        if (std::abs(static_cast<int>(a[c][i]) - b[c][i]) > 256) return false; // 8-bit DAC rounding
    return true;
}
bool Engine::recover() {
    calibrated = false;
    calibratedDevices.clear();
    status.minimumVerified = false;
    status.minimum = minimumKelvin();
    journalKnown = false;
    if (!backend.load(originals)) { status.error = 3; restorePending = true; return false; }
    journalKnown = true;
    return restore();
}
bool Engine::restore() {
    leased = false;
    // An empty vector after a failed load does not mean there is no durable backup.
    if (!journalKnown) { status.error = 3; restorePending = true; return false; }
    bool ok = true;
    const auto present = backend.devices();
    for (const auto& o: originals) {
        // Disconnected displays keep their backup for a later rescue/reconnect.
        if (std::find(present.begin(), present.end(), o.device) == present.end()) { ok = false; continue; }
        Ramp readback{};
        if (!backend.set(o.device, o.ramp) || !backend.read(o.device, readback) || !matches(o.ramp, readback)) ok = false;
    }
    if (ok) { originals.clear(); backend.erase(); }
    status.active = false;
    status.kelvin = 6500;
    status.gamma = 100;
    status.error = ok ? 0 : 5;
    restorePending = !ok;
    return ok;
}
bool Engine::probe() {
    auto names = backend.devices();
    if (names.empty()) { status.error = 2; return false; }
    for (const auto& name: names) {
        Ramp ramp{};
        if (!backend.read(name, ramp)) { status.error = 2; return false; }
    }
    return true;
}
bool Engine::apply(int kelvin, int gamma, uint64_t now) {
    if (!status.available) { status.error = 1; return false; }
    if (!journalKnown) { status.error = 3; return false; }
    if (kelvin == 6500 && gamma == 100) return restore();
    auto names = backend.devices();
    if (names.empty()) { status.error = 2; return false; }
    if (names != calibratedDevices) calibrated = false;
    // Capture every new monitor and durably save the whole journal BEFORE any set.
    auto proposed = originals;
    for (const auto& name: names) if (std::none_of(proposed.begin(), proposed.end(), [&](const Original& o) { return o.device == name; })) {
        Original o{name, {}};
        if (!backend.read(name, o.ramp)) { restore(); status.error = 2; return false; }
        proposed.push_back(o);
    }
    if (!backend.save(proposed)) { status.error = 3; return false; }
    originals = std::move(proposed);
    auto applyPlan = [&](const Plan& plan) {
        bool ok = true;
        for (const auto& name: names) {
            if (backend.cancelled()) return false;
            const auto& original = *std::find_if(originals.begin(), originals.end(), [&](const Original& o) { return o.device == name; });
            const auto desired = compute(plan.kelvin, plan.gamma, original.ramp).ramp;
            Ramp current{};
            // Heartbeats don't rewrite the display unless its ramp changed externally.
            if (backend.read(name, current) && matches(current, desired)) continue;
            Ramp readback{};
            if (!backend.set(name, desired) || !backend.read(name, readback) || !matches(readback, desired)) { ok = false; break; }
        }
        return ok;
    };
    if (!calibrated) {
        // Probe the lowest conservative temperature once, after saving originals. Readback
        // determines the common limit across monitors; never claim an untested bound works.
        status.minimum = minimumKelvin();
        for (;;) {
            if (applyPlan(compute(status.minimum, 100, identity()))) break;
            if (backend.cancelled()) { restore(); return false; }
            if (status.minimum >= 6500) { restore(); status.error = 4; return false; }
            status.minimum = std::min(6500, status.minimum + 100);
        }
        calibrated = true;
        calibratedDevices = names;
        status.minimumVerified = true;
    }
    auto plan = compute(std::max(kelvin, status.minimum), gamma, identity());
    for (;;) {
        if (applyPlan(plan)) {
            status.active = plan.kelvin < 6500;
            status.kelvin = plan.kelvin;
            status.gamma = plan.gamma;
            status.error = 0;
            heartbeat = now;
            leased = true;
            restorePending = false;
            if (kelvin < 6500 && plan.kelvin == 6500) { status.error = 4; return false; }
            return true;
        }
        if (backend.cancelled()) { restore(); return false; }
        // TRUE alone is not success. Back off brightness first, then increase temperature.
        if (plan.gamma < 100) plan = compute(plan.kelvin, 100, identity());
        else if (plan.kelvin < 6500) {
            plan = compute(std::min(6500, plan.kelvin + 100), 100, identity());
            status.minimum = plan.kelvin;
        } else { restore(); status.error = 4; return false; }
    }
}
void Engine::tick(uint64_t now) {
    if (leased && now - heartbeat > 15000) {
        restore();
        nextRestoreAttempt = now + 5000;
    } else if (restorePending && now >= nextRestoreAttempt) {
        if (journalKnown) restore(); else recover();
        nextRestoreAttempt = now + 5000;
    }
}
uint64_t pack(const Status& s) {
    return 1ull | (uint64_t(s.available) << 1) | (uint64_t(s.active) << 2) | (uint64_t(s.error) << 3)
        | (uint64_t(s.kelvin) << 8) | (uint64_t(s.gamma) << 24) | (uint64_t(s.minimum) << 32) | (uint64_t(s.minimumVerified) << 48);
}
Status unpack(uint64_t value) {
    Status s;
    s.available = (value & 2) != 0; s.active = (value & 4) != 0; s.error = (value >> 3) & 31;
    s.kelvin = (value >> 8) & 65535; s.gamma = (value >> 24) & 255; s.minimum = (value >> 32) & 65535;
    s.minimumVerified = (value & (1ull << 48)) != 0;
    return s;
}
}
