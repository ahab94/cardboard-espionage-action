#!/usr/bin/env python3
"""Synthesizes every sound in the game from scratch: no samples, no
third-party audio, Python standard library only.

    python3 tools/make_audio.py

Writes 16-bit mono WAVs (Godot compresses them on import):
  audio/sfx/*.wav             short effects, 44.1 kHz
  audio/music/*.wav           seamless loops at 22.05 kHz: sneak, tension (a
                              layer synced to sneak that fades in with
                              detection), menu
  audio/sfx/drone_loop.wav    rotor hum, looped per drone

Loops are exact to the sample: notes that run past the end wrap round to the
start. The game sets the loop points when it loads them (scripts/sound.gd).

The output is deterministic (fixed random seeds), so re-running it
reproduces the same files.
"""
import array
import math
import os
import random
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "audio")
TAU = 2 * math.pi

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
              "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(note):
    """'D3', 'Bb4', 'F#2' -> frequency in Hz (A4 = 440)."""
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


# --- Sound sources ---------------------------------------------------------

def tone(freq, dur, shape="sine", vol=0.3, attack=0.005, decay=None, release=0.03,
         glide_to=None, lowpass=None, detune=0.0, tremolo=0.0, tremolo_hz=0.0):
    """One note. `decay` = exponential fade time constant (None = sustain).
    `glide_to` slides the pitch, `detune` adds a second slightly sharp oscillator."""
    n = int(dur * SR)
    out = [0.0] * n
    p1 = p2 = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * lowpass / SR) if lowpass else None
    for i in range(n):
        t = i / SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        p1 = (p1 + f / SR) % 1.0
        s = _wave(shape, p1)
        if detune:
            p2 = (p2 + f * (1 + detune) / SR) % 1.0
            s = 0.5 * (s + _wave(shape, p2))
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay:
            env *= math.exp(-t / decay)
        if t > dur - release:
            env *= max(0.0, (dur - t) / release)
        if tremolo:
            env *= 1 - tremolo * (0.5 + 0.5 * math.sin(TAU * tremolo_hz * t))
        out[i] = s * env * vol
    return out


def _wave(shape, p):
    if shape == "sine":
        return math.sin(TAU * p)
    if shape == "saw":
        return 2 * p - 1
    if shape == "square":
        return 1.0 if p < 0.5 else -1.0
    if shape == "tri":
        return 4 * abs(p - 0.5) - 1
    raise ValueError(shape)


def noise(dur, vol=0.3, decay=0.05, lowpass=None, highpass=None, seed=1, attack=0.001,
          sweep_to=None):
    """Filtered white noise burst. `sweep_to` moves the lowpass cutoff over time."""
    rng = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    lo = hi_lp = 0.0
    for i in range(n):
        t = i / SR
        s = rng.uniform(-1, 1)
        if lowpass:
            fc = lowpass if sweep_to is None else lowpass * (sweep_to / lowpass) ** (t / dur)
            lo += (1 - math.exp(-TAU * fc / SR)) * (s - lo)
            s = lo
        if highpass:
            hi_lp += (1 - math.exp(-TAU * highpass / SR)) * (s - hi_lp)
            s = s - hi_lp
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0)
        if t > dur - 0.01:
            env *= max(0.0, (dur - t) / 0.01)
        out[i] = s * env * vol
    return out


# --- Mixing ------------------------------------------------------------------

class Track:
    """A mono buffer. With loop=True, anything that runs past the end wraps
    to the start, so the file loops seamlessly."""

    def __init__(self, seconds, loop=False):
        self.buf = array.array("f", bytes(4 * int(seconds * SR)))
        self.loop = loop

    def add(self, start, samples, gain=1.0):
        b = self.buf
        n = len(b)
        i0 = int(start * SR)
        for i, s in enumerate(samples):
            j = i0 + i
            if j >= n:
                if not self.loop:
                    break
                j %= n
            b[j] += s * gain

    def mix(self, other, gain=1.0):
        self.add(0, other.buf, gain)

    def echo(self, delay, feedback=0.35, mix=0.3):
        """Feedback delay. On a loop, run it twice so the tail wraps too."""
        b = self.buf
        n = len(b)
        d = int(delay * SR)
        wet = array.array("f", bytes(4 * n))
        for _ in range(2 if self.loop else 1):
            for i in range(n):
                j = i - d
                if j < 0 and not self.loop:
                    continue
                wet[i] = b[j % n] + feedback * wet[j % n]
        for i in range(n):
            b[i] += wet[i] * mix


def write_wav(path, samples, peak=0.89):
    """Soft-clip, normalize to `peak`, write 16-bit mono."""
    m = max(1e-9, max(abs(s) for s in samples))
    data = array.array("h", (int(32767 * peak * math.tanh(1.2 * s / m) / math.tanh(1.2)) for s in samples))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def cat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def at(offset, samples):
    """Prefix with silence."""
    return [0.0] * int(offset * SR) + samples


def layer(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out


# --- Music -------------------------------------------------------------------
# D minor, 96 BPM. Two-bar chords: Dm, Bb, Gm, A (the major A is the
# harmonic-minor dominant: it leans back to Dm and keeps things uneasy).

BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
CHORDS = [  # (bass root, pad voicing, arpeggio notes)
    ("D2", ["D3", "A3", "F4"], ["D5", "F5", "A5", "D6"]),
    ("Bb1", ["Bb2", "F3", "D4"], ["Bb4", "D5", "F5", "Bb5"]),
    ("G1", ["G2", "D3", "Bb3"], ["G4", "Bb4", "D5", "G5"]),
    ("A1", ["A2", "E3", "C#4"], ["A4", "C#5", "E5", "A5"]),
]
BARS = 16


def chord_at(bar):
    return CHORDS[(bar // 2) % 4]


def sneak():
    """The base loop: pulsing bass, slow pads, a sparse arpeggio and a sonar ping."""
    length = BARS * BAR
    mix = Track(length, loop=True)
    arp = Track(length, loop=True)
    for bar in range(BARS):
        root, pad, notes = chord_at(bar)
        t0 = bar * BAR
        # Bass: eighth notes, octave jump on the 3rd, fifth on the 7th.
        r = hz(root)
        for k, mult in enumerate([1, 1, 2, 1, 1, 1, 1.5, 1]):
            mix.add(t0 + k * BEAT / 2, tone(r * mult, BEAT / 2, "saw", 0.30, decay=0.16, lowpass=420))
        # Pads: held for two bars, slow swell.
        if bar % 2 == 0:
            for note in pad:
                mix.add(t0, tone(hz(note), 2 * BAR, "tri", 0.085, attack=0.9, release=0.9,
                                 detune=0.004, lowpass=1400))
        # Closed hats on the off-beats.
        for k in range(4):
            mix.add(t0 + k * BEAT + BEAT / 2, noise(0.05, 0.05, decay=0.012, highpass=6000, seed=bar * 8 + k))
        # Arpeggio in the second half of each 8-bar phrase.
        if bar % 8 >= 4:
            for k in range(8):
                note = notes[[0, 1, 2, 3, 2, 1, 2, 3][k]]
                arp.add(t0 + k * BEAT / 2, tone(hz(note), 0.2, "square", 0.05, decay=0.07, lowpass=2600))
        # Sonar ping every four bars.
        if bar % 4 == 0:
            arp.add(t0 + BEAT, tone(hz("A6"), 1.2, "sine", 0.09, decay=0.35))
    arp.echo(BEAT * 0.75, feedback=0.4, mix=0.45)
    mix.mix(arp)
    return mix.buf


def tension():
    """Layered on top of sneak (same tempo and length): drums and a creeping
    string ostinato. The game raises its volume as detection rises."""
    length = BARS * BAR
    mix = Track(length, loop=True)
    for bar in range(BARS):
        _, _, notes = chord_at(bar)
        t0 = bar * BAR
        for k in (0, 2):  # kick
            mix.add(t0 + k * BEAT, tone(120, 0.3, "sine", 0.55, decay=0.12, glide_to=42))
        for k in (1, 3):  # snare: noise plus a tonal body
            mix.add(t0 + k * BEAT, noise(0.25, 0.22, decay=0.07, lowpass=5000, highpass=800, seed=100 + bar * 4 + k))
            mix.add(t0 + k * BEAT, tone(190, 0.12, "tri", 0.12, decay=0.05))
        for k in range(16):  # sixteenth hats
            mix.add(t0 + k * BEAT / 4, noise(0.03, 0.035 if k % 2 else 0.05, decay=0.008, highpass=7000, seed=300 + bar * 16 + k))
        # Strings: the chord's fifth rubbing against the note a half step above.
        fifth = hz(notes[2])
        for k in range(8):
            f = fifth if k % 2 == 0 else fifth * 2 ** (1 / 12)
            mix.add(t0 + k * BEAT / 2, tone(f, BEAT / 2, "saw", 0.055, attack=0.02, release=0.05, lowpass=3200, detune=0.006))
    return mix.buf


def menu():
    """Calm and sparse: pads and a slow bell arpeggio, 60 BPM, 8 bars."""
    beat = 1.0
    bar = 4 * beat
    length = 8 * bar
    mix = Track(length, loop=True)
    bells = Track(length, loop=True)
    for b in range(8):
        _, pad, notes = CHORDS[(b // 2) % 4]
        t0 = b * bar
        if b % 2 == 0:
            for note in pad:
                mix.add(t0, tone(hz(note), 2 * bar, "tri", 0.09, attack=1.5, release=1.5, detune=0.003, lowpass=1100))
            mix.add(t0, tone(hz(pad[0]) / 2, 2 * bar, "sine", 0.18, attack=1.0, release=1.0))
        for k in range(4):
            note = notes[[0, 2, 1, 3][k]]
            bells.add(t0 + k * beat, tone(hz(note), 1.8, "sine", 0.08, decay=0.45))
            bells.add(t0 + k * beat, tone(hz(note) * 3, 0.6, "sine", 0.015, decay=0.15))
    bells.echo(0.75, feedback=0.45, mix=0.5)
    mix.mix(bells)
    return mix.buf


# --- Sound effects -------------------------------------------------------------

def sfx():
    s = {}
    # Alert: two hard, dissonant stabs over a noise crash. Unmistakably "caught".
    s["alert"] = layer(
        tone(hz("E5"), 0.09, "square", 0.25, decay=0.08, lowpass=4000),
        tone(hz("A#5"), 0.09, "square", 0.25, decay=0.08, lowpass=4000),
        at(0.1, tone(hz("A5"), 0.55, "square", 0.3, decay=0.22, lowpass=5000, detune=0.01)),
        at(0.1, tone(hz("D#6"), 0.55, "square", 0.25, decay=0.22, lowpass=5000, detune=0.01)),
        at(0.1, noise(0.5, 0.25, decay=0.15, lowpass=7000, seed=7)),
    )
    # Suspicion "?": a rising two-note question.
    s["suspicious"] = layer(
        tone(hz("E5"), 0.09, "sine", 0.35, decay=0.08),
        at(0.08, tone(hz("B5"), 0.22, "sine", 0.35, decay=0.1, glide_to=hz("C#6"))),
    )
    # A soft, muffled cardboard brush for each step (pitch is varied when played).
    # Kept dark and gentle on purpose: it repeats constantly while moving.
    s["step"] = noise(0.12, 0.4, decay=0.035, lowpass=420, highpass=90, seed=11, attack=0.015)
    # Dropping the box: a soft low thump.
    s["hide"] = layer(
        tone(130, 0.2, "sine", 0.6, decay=0.07, glide_to=55),
        noise(0.12, 0.25, decay=0.03, lowpass=500, seed=12),
    )
    # Laser switching on: a quick descending zap with a buzzy tail.
    s["laser"] = layer(
        tone(2200, 0.18, "saw", 0.18, decay=0.07, glide_to=500, lowpass=6000),
        tone(120, 0.25, "square", 0.05, decay=0.1, lowpass=900),
    )
    # Keycard: a bright rising bell arpeggio.
    s["keycard"] = layer(*[
        at(i * 0.07, layer(tone(hz(n), 0.6, "sine", 0.25, decay=0.18), tone(hz(n) * 2.01, 0.3, "sine", 0.06, decay=0.08)))
        for i, n in enumerate(["C6", "E6", "G6", "C7"])
    ])
    # Vault door: hydraulic hiss sweeping open, then a clunk.
    s["door"] = layer(
        noise(0.55, 0.35, decay=0.3, lowpass=300, sweep_to=3500, highpass=150, seed=13, attack=0.05),
        at(0.45, tone(90, 0.2, "sine", 0.5, decay=0.06, glide_to=60)),
        at(0.45, noise(0.08, 0.25, decay=0.02, lowpass=800, seed=14)),
    )
    # Mission complete: a short triumphant run up the D major chord.
    run = ["D5", "F#5", "A5"]
    s["complete"] = layer(
        *[at(i * 0.11, tone(hz(n), 0.14, "square", 0.14, decay=0.12, lowpass=3500)) for i, n in enumerate(run)],
        at(0.33, tone(hz("D6"), 0.9, "square", 0.14, decay=0.4, lowpass=3500, detune=0.005)),
        at(0.33, tone(hz("A5"), 0.9, "tri", 0.18, decay=0.4)),
        at(0.33, tone(hz("F#5"), 0.9, "tri", 0.14, decay=0.4)),
        at(0.33, tone(hz("D3"), 0.9, "saw", 0.12, decay=0.35, lowpass=600)),
    )
    s["menu_move"] = tone(hz("A5"), 0.05, "sine", 0.3, decay=0.02)
    s["menu_select"] = layer(tone(hz("D5"), 0.08, "sine", 0.3, decay=0.05),
                             at(0.06, tone(hz("A5"), 0.16, "sine", 0.3, decay=0.07)))
    return s


def drone_loop():
    """One second of rotor hum. Every frequency is a whole number of Hz, so
    the end lines up with the start and it loops without a click."""
    t = Track(1.0, loop=True)
    t.add(0, tone(110, 1.0, "saw", 0.2, attack=0, release=0, lowpass=700, tremolo=0.5, tremolo_hz=30))
    t.add(0, tone(112, 1.0, "saw", 0.2, attack=0, release=0, lowpass=700))
    t.add(0, tone(220, 1.0, "sine", 0.08, attack=0, release=0, tremolo=0.6, tremolo_hz=45))
    return t.buf


def main():
    global SR
    for name, samples in sfx().items():
        write_wav(os.path.join(OUT, "sfx", name + ".wav"), samples)
    write_wav(os.path.join(OUT, "sfx", "drone_loop.wav"), drone_loop(), peak=0.6)
    SR = 22050  # music: lowpassed synths sound the same at half the size
    write_wav(os.path.join(OUT, "music", "sneak.wav"), sneak(), peak=0.7)
    write_wav(os.path.join(OUT, "music", "tension.wav"), tension(), peak=0.7)
    write_wav(os.path.join(OUT, "music", "menu.wav"), menu(), peak=0.6)


if __name__ == "__main__":
    main()
