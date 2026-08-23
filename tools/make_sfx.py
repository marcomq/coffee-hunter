#!/usr/bin/env python3
"""Generate Coffee Hunter's sound effects.

The game ships no recorded audio; every clip is synthesised here so the set can
be re-tuned and regenerated instead of being an opaque binary. Chiptune-ish on
purpose: square/triangle/noise voices, matching the 16-bit pixel-art direction.

    python3 tools/make_sfx.py            # writes assets/audio/*.wav
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def square(phase):
    return 1.0 if phase % 1.0 < 0.5 else -1.0


def triangle(phase):
    x = phase % 1.0
    return 4.0 * abs(x - 0.5) - 1.0


def sine(phase):
    return math.sin(phase * math.tau)


VOICES = {"square": square, "triangle": triangle, "sine": sine}


def tone(buf, start, duration, f0, f1=None, wave_name="square", gain=0.5, attack=0.005, curve=3.0):
    """Mix one pitch-swept voice into buf with a fast attack and an exponential tail."""
    f1 = f0 if f1 is None else f1
    voice = VOICES[wave_name]
    count = int(duration * RATE)
    phase = 0.0
    for i in range(count):
        t = i / count
        freq = f0 * (f1 / f0) ** t
        phase += freq / RATE
        env = min(1.0, (i / RATE) / attack) * (1.0 - t) ** curve
        index = start + i
        if index < len(buf):
            buf[index] += voice(phase) * env * gain


def noise(buf, start, duration, gain=0.5, f0=1.0, f1=1.0, curve=3.0):
    """Lowpassed noise; f0..f1 sweeps the filter from dull to bright (0..1)."""
    count = int(duration * RATE)
    state = 0.0
    for i in range(count):
        t = i / count
        cutoff = f0 * (f1 / f0) ** t if f0 > 0 and f1 > 0 else f0
        state += (random.uniform(-1.0, 1.0) - state) * min(1.0, cutoff)
        env = (1.0 - t) ** curve
        index = start + i
        if index < len(buf):
            buf[index] += state * env * gain


def blank(duration):
    return [0.0] * int(duration * RATE)


def write(name, buf, peak=0.85):
    loudest = max((abs(v) for v in buf), default=0.0)
    scale = peak / loudest if loudest > 0.0 else 0.0
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in buf)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)
    print("wrote %s (%.2fs)" % (path, len(buf) / RATE))


def build():
    random.seed(0xC0FFEE)

    # Digging: a dry scrape, one per step, so it has to stay short and dull.
    buf = blank(0.09)
    noise(buf, 0, 0.09, gain=0.55, f0=0.05, f1=0.012, curve=2.0)
    tone(buf, 0, 0.05, 150, 90, "triangle", gain=0.25)
    write("dig", buf, peak=0.42)

    # Collecting a bean: bright two-step blip. main.gd pitches it up per tier.
    buf = blank(0.24)
    tone(buf, 0, 0.07, 880, 880, "square", gain=0.4)
    tone(buf, int(0.06 * RATE), 0.17, 1320, 1400, "square", gain=0.4)
    write("coffee", buf, peak=0.6)

    # A filter hitting the ground: weight, not sparkle.
    buf = blank(0.3)
    tone(buf, 0, 0.28, 190, 55, "sine", gain=0.9, curve=2.5)
    noise(buf, 0, 0.12, gain=0.35, f0=0.09, f1=0.02, curve=2.0)
    write("filter_land", buf, peak=0.8)

    # Squashing a tea-pod: wet splat plus a comedy pitch drop.
    buf = blank(0.34)
    noise(buf, 0, 0.18, gain=0.6, f0=0.3, f1=0.03, curve=2.0)
    tone(buf, 0, 0.32, 520, 70, "triangle", gain=0.55, curve=2.0)
    write("squash", buf, peak=0.78)

    # Losing a life: a four-step tumble downwards.
    buf = blank(0.75)
    for step, freq in enumerate([660, 520, 400, 300]):
        tone(buf, int(step * 0.13 * RATE), 0.22, freq, freq * 0.86, "square", gain=0.4)
    tone(buf, int(0.5 * RATE), 0.25, 220, 110, "triangle", gain=0.45, curve=2.0)
    write("life_lost", buf, peak=0.75)

    # Extra life: a clean major arpeggio, the most positive sound in the set.
    buf = blank(0.6)
    for step, freq in enumerate([523, 659, 784, 1047]):
        tone(buf, int(step * 0.075 * RATE), 0.3, freq, freq, "square", gain=0.32)
    write("life_gained", buf, peak=0.7)

    # Level cleared: the same idea, longer and with a held final note.
    buf = blank(1.15)
    for step, freq in enumerate([523, 659, 784, 1047, 1319]):
        tone(buf, int(step * 0.09 * RATE), 0.32, freq, freq, "square", gain=0.3)
    tone(buf, int(0.45 * RATE), 0.68, 1568, 1568, "triangle", gain=0.42, curve=2.0)
    write("level_clear", buf, peak=0.8)

    # Close call: a single warning tick. Fires often, so it must not grate.
    buf = blank(0.11)
    tone(buf, 0, 0.1, 1500, 1150, "triangle", gain=0.5, curve=4.0)
    write("close_call", buf, peak=0.45)

    # Ground shifts: a low rumble under a rising sweep.
    buf = blank(0.9)
    noise(buf, 0, 0.85, gain=0.6, f0=0.01, f1=0.06, curve=1.2)
    tone(buf, 0, 0.85, 80, 300, "triangle", gain=0.5, curve=1.2)
    write("reshuffle", buf, peak=0.72)

    # A pod climbing back out of the nest: bubbling upwards, clearly a threat.
    buf = blank(0.5)
    for step in range(4):
        base = 180 + step * 70
        tone(buf, int(step * 0.1 * RATE), 0.16, base, base * 1.7, "triangle", gain=0.4, curve=2.5)
    write("enemy_respawn", buf, peak=0.6)

    # Menu blip and the start/confirm chord.
    buf = blank(0.09)
    tone(buf, 0, 0.08, 660, 880, "square", gain=0.4, curve=3.0)
    write("ui", buf, peak=0.45)

    buf = blank(0.5)
    for freq in [392, 523, 659]:
        tone(buf, 0, 0.45, freq, freq, "square", gain=0.26, curve=2.0)
    write("start", buf, peak=0.72)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    build()
