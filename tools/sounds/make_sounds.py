"""Synthesizes ii-windows' interface sounds (overlay/ii/assets/sounds/ui/*.wav). Our own work, released with the
project (no third-party samples). 44.1 kHz, 16-bit PCM, mono.

    python -I tools/sounds/make_sounds.py

Soft and warm on purpose (users found the first set sharp and tiring): low-mid pitches (about 260-660 Hz), almost pure
sines with two voices a few cents apart, unhurried attacks (15-30 ms, no click), a round release, a gentle low-pass on
everything and quiet peaks. Settings > Sound > interface volume makes them louder for whoever wants that.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'overlay', 'ii', 'assets', 'sounds', 'ui')


def envelope(t, length, attack, release):
    """Raised-cosine attack, a held middle that fades slowly, raised-cosine release: no corner anywhere."""
    if t < attack:
        a = 0.5 - 0.5 * math.cos(math.pi * t / attack)
    else:
        a = 1.0
    body = math.exp(-1.6 * t / length)
    left = length - t
    r = 0.5 - 0.5 * math.cos(math.pi * min(1.0, left / release)) if left < release else 1.0
    return a * body * r


def note(freq, length, gain=1.0, attack=0.02, release=None, detune_cents=4.0, second=0.06):
    """A warm sine: two voices a few cents apart (a slow beat, like a felt piano) and a whisper of the octave."""
    release = release if release is not None else length * 0.6
    n = int(RATE * length)
    f2 = freq * 2 ** (detune_cents / 1200)
    out = [0.0] * n
    for i in range(n):
        t = i / RATE
        s = 0.5 * math.sin(2 * math.pi * freq * t) + 0.5 * math.sin(2 * math.pi * f2 * t)
        s += second * math.sin(4 * math.pi * freq * t)
        out[i] = gain * envelope(t, length, attack, release) * s
    return out


def glide(f0, f1, length, gain=1.0, attack=0.02, release=None):
    """A soft pitch glide (for open/close), exponential so it sounds even."""
    release = release if release is not None else length * 0.6
    n = int(RATE * length)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / length)
        phase += 2 * math.pi * f / RATE
        out[i] = gain * envelope(t, length, attack, release) * (math.sin(phase) + 0.05 * math.sin(2 * phase))
    return out


def breath(length, gain):
    """A low, airy puff (desktop switch): noise through two one-pole low-passes, cutoff well under 1 kHz."""
    random.seed(7)
    n = int(RATE * length)
    out = [0.0] * n
    y1 = y2 = 0.0
    for i in range(n):
        t = i / RATE
        k = 0.010 + 0.025 * math.sin(math.pi * t / length)  # ~70-250 Hz
        y1 += k * (random.uniform(-1, 1) - y1)
        y2 += k * (y1 - y2)
        out[i] = gain * y2 * math.sin(math.pi * t / length) ** 2
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


def lowpass(samples, cutoff=2200.0):
    """Two passes of a one-pole low-pass: takes the edge off whatever is left above a couple of kHz."""
    k = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    for _ in range(2):
        y = 0.0
        out = []
        for v in samples:
            y += k * (v - y)
            out.append(y)
        samples = out
    return samples


def save(name, samples, peak):
    samples = lowpass(samples)
    top = max(1e-9, max(abs(v) for v in samples))
    scale = peak / top
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * scale)) * 32767)) for v in samples))
    print(name, f'{len(samples) / RATE * 1000:.0f} ms')


# Panel / overview opens: a soft rising fourth (G4 -> C5).
save('open', mix((0, note(392.0, 0.16, 1.0, attack=0.018)), (0.06, note(523.3, 0.20, 0.8, attack=0.022))), peak=0.26)
# Closes: the same, falling (C5 -> G4), a touch quieter.
save('close', mix((0, note(523.3, 0.14, 0.9, attack=0.018)), (0.055, note(392.0, 0.18, 0.75, attack=0.022))), peak=0.22)
# Notification: a warm two-note bell, low (A4 then D5), long and slow to fade.
save('notify', mix((0, note(440.0, 0.55, 1.0, attack=0.025, second=0.08)), (0.13, note(587.3, 0.65, 0.85, attack=0.03, second=0.08))), peak=0.28)
# Virtual desktop switch: a low breath with a faint low tone, no hiss.
save('switch', mix((0, breath(0.26, 1.0)), (0.03, glide(260, 330, 0.20, 0.35, attack=0.03))), peak=0.20)
# A widget dropped into the grid: a small soft drop.
save('snap', glide(520, 410, 0.09, 1.0, attack=0.012, release=0.06), peak=0.22)
# A toggle switched: a quiet round tick.
save('toggle', note(659.3, 0.07, 1.0, attack=0.012, release=0.05, second=0.03), peak=0.18)
# Edit mode on: a gentle rising arpeggio, low (G4 B4 D5).
save('edit', mix((0, note(392.0, 0.22, 1.0)), (0.08, note(493.9, 0.22, 0.85)), (0.16, note(587.3, 0.30, 0.75))), peak=0.24)
