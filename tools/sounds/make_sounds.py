"""Synthesizes ii-windows' interface sounds (overlay/ii/assets/sounds/ui/*.wav): short, soft
Material-like blips and chimes made from sine partials with smooth envelopes. Our own work,
released with the project (no third-party samples). 44.1 kHz, 16-bit PCM, mono.

    python -I tools/sounds/make_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'overlay', 'ii', 'assets', 'sounds', 'ui')


def envelope(t, length, attack=0.006, decay=8.0):
    """Quick fade in, exponential fade out, and a short fade to zero at the very end."""
    a = min(1.0, t / attack) if attack > 0 else 1.0
    tail = min(1.0, (length - t) / 0.012)
    return a * math.exp(-decay * t / length) * max(0.0, tail)


def tone(f0, f1, length, gain, decay=6.0, partials=((1, 1.0), (2, 0.18), (3, 0.05)), attack=0.006):
    """A pitch glide from f0 to f1 (Hz) with a few harmonics."""
    n = int(RATE * length)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        # exponential glide sounds more natural than linear
        f = f0 * (f1 / f0) ** (t / length) if f0 != f1 else f0
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin(k * phase) for k, a in partials)
        out[i] = gain * envelope(t, length, attack, decay) * s
    return out


def mix(*parts):
    """parts: (offset_seconds, samples)."""
    n = max(int(off * RATE) + len(s) for off, s in parts)
    out = [0.0] * n
    for off, s in parts:
        o = int(off * RATE)
        for i, v in enumerate(s):
            out[o + i] += v
    return out


def noise_sweep(length, gain, lo=0.02, hi=0.25):
    """Soft airy whoosh: low-passed noise whose cutoff rises then falls."""
    random.seed(7)
    n = int(RATE * length)
    out = [0.0] * n
    y = 0.0
    for i in range(n):
        t = i / RATE
        k = lo + (hi - lo) * math.sin(math.pi * t / length)
        y += k * (random.uniform(-1, 1) - y)
        out[i] = gain * y * math.sin(math.pi * t / length) ** 2
    return out


def save(name, samples, peak=0.5):
    top = max(1e-9, max(abs(v) for v in samples))
    scale = peak / top
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * scale)) * 32767)) for v in samples))
    print(name, f'{len(samples) / RATE * 1000:.0f} ms')


# Panel / overview opens: a light upward blip.
save('open', mix((0, tone(620, 930, 0.11, 1.0, decay=5)), (0.035, tone(930, 1240, 0.09, 0.45, decay=6))), peak=0.42)
# Closes: the same, downward and a touch softer.
save('close', mix((0, tone(880, 600, 0.10, 1.0, decay=6)), (0.03, tone(600, 520, 0.08, 0.35, decay=7))), peak=0.36)
# Notification: two-note glassy chime (C6 then E6).
save('notify', mix((0, tone(1046.5, 1046.5, 0.42, 1.0, decay=5, partials=((1, 1), (2, 0.25), (4, 0.06)), attack=0.004)),
                   (0.11, tone(1318.5, 1318.5, 0.48, 0.9, decay=5, partials=((1, 1), (2, 0.25), (4, 0.06)), attack=0.004))), peak=0.45)
# Virtual desktop switch: a soft whoosh with a hint of pitch.
save('switch', mix((0, noise_sweep(0.22, 1.0)), (0.02, tone(420, 700, 0.16, 0.22, decay=4))), peak=0.30)
# A widget dropped / snapped into the grid: a small pop.
save('snap', mix((0, tone(1500, 900, 0.045, 1.0, decay=9, attack=0.002)), (0, tone(300, 200, 0.05, 0.4, decay=10, attack=0.002))), peak=0.40)
# A toggle switched / small click.
save('toggle', tone(1700, 1500, 0.035, 1.0, decay=10, partials=((1, 1), (2, 0.1)), attack=0.002), peak=0.30)
# Edit mode on: a gentle rising arpeggio.
save('edit', mix((0, tone(784, 784, 0.16, 1.0, decay=6)), (0.06, tone(988, 988, 0.16, 0.8, decay=6)), (0.12, tone(1175, 1175, 0.22, 0.7, decay=6))), peak=0.38)
