#!/usr/bin/env python3
"""Comedy sound effects and a playful "sneaky" theme for the marketing videos
(not used in the game). Original, synthesized from scratch with the same
building blocks as tools/make_audio.py.

    python3 tools/video/make_video_audio.py   ->  build/video_audio/*.wav
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import make_audio as A  # noqa: E402  (tone, noise, layer, at, Track, write_wav, hz)

OUT = os.path.join(A.HERE, "..", "build", "video_audio")
tone, noise, layer, at, hz = A.tone, A.noise, A.layer, A.at, A.hz


def vibrato(freq, dur, vol, depth, rate, shape="sine", glide_to=None, decay=None, lowpass=None):
    """A note with wobble: the basis of slide whistles and trombones."""
    n = int(dur * A.SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    k = 1 - math.exp(-A.TAU * lowpass / A.SR) if lowpass else None
    for i in range(n):
        t = i / A.SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        f *= 1 + depth * math.sin(A.TAU * rate * t)
        p = (p + f / A.SR) % 1.0
        s = A._wave(shape, p)
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / 0.02) * (math.exp(-t / decay) if decay else 1.0)
        env *= min(1.0, (dur - t) / 0.04)
        out[i] = s * env * vol
    return out


def sfx():
    s = {}
    # Slide whistle up and down: the classic cartoon "zip".
    s["slide_up"] = vibrato(500, 0.55, 0.5, 0.012, 7, glide_to=1900)
    s["slide_down"] = vibrato(1900, 0.6, 0.5, 0.012, 7, glide_to=420)
    # Boing: a spring, a pitch that bends up and down while wobbling hard.
    s["boing"] = vibrato(180, 0.6, 0.6, 0.35, 11, shape="tri", glide_to=320, decay=0.25)
    # Sad trombone: wah, wah, wah, waaaah (descending, with a buzzy brassy tone).
    notes = [("D4", 0.32), ("C#4", 0.32), ("C4", 0.32), ("B3", 1.1)]
    t = 0.0
    parts = []
    for i, (n, d) in enumerate(notes):
        last = i == len(notes) - 1
        parts.append(at(t, vibrato(hz(n), d, 0.35, 0.03 if last else 0.012, 5.5, shape="saw",
                                   glide_to=hz(n) * (0.97 if last else 0.995), lowpass=1500)))
        t += d * 0.95
    s["sad_trombone"] = layer(*parts)
    # Record scratch: a fast up-down noise sweep with a tonal rasp.
    s["record_scratch"] = layer(
        noise(0.12, 0.6, decay=0.08, lowpass=900, sweep_to=4500, seed=21),
        at(0.1, noise(0.16, 0.6, decay=0.1, lowpass=4500, sweep_to=600, seed=22)),
        tone(300, 0.26, "saw", 0.12, glide_to=900, lowpass=2500, decay=0.12),
    )
    # Bonk: a hollow wood-block knock.
    s["bonk"] = layer(tone(620, 0.25, "sine", 0.6, decay=0.05, glide_to=380),
                      tone(1240, 0.1, "sine", 0.2, decay=0.02))
    # Pop: a tiny cork pop.
    s["pop"] = layer(tone(900, 0.08, "sine", 0.6, decay=0.015, glide_to=1800),
                     noise(0.03, 0.2, decay=0.006, highpass=2000, seed=23))
    # Whoosh: a breathy sweep for transitions.
    s["whoosh"] = noise(0.45, 0.5, decay=None, lowpass=300, sweep_to=5000, highpass=150, seed=24, attack=0.2)
    # Ding: a bright bell, "correct!".
    s["ding"] = layer(tone(hz("E6"), 0.9, "sine", 0.4, decay=0.3), tone(hz("E6") * 2.76, 0.4, "sine", 0.1, decay=0.1))
    # Tiptoe: two tiny plucks, for sneaky moments.
    s["tiptoe"] = layer(tone(hz("E5"), 0.09, "tri", 0.4, decay=0.03),
                        at(0.16, tone(hz("G5"), 0.09, "tri", 0.4, decay=0.03)))
    # Gasp-like "uh oh": two falling notes.
    s["uh_oh"] = layer(vibrato(hz("A5"), 0.18, 0.4, 0.01, 6, shape="tri"),
                       at(0.2, vibrato(hz("E5"), 0.32, 0.4, 0.01, 6, shape="tri", glide_to=hz("D5"))))
    return s


def sneaky_theme():
    """A playful tiptoe tune in A minor, 112 BPM: staccato walking bass, pizzicato
    melody and a light shaker. 16 bars, loops seamlessly."""
    bpm = 112
    beat = 60 / bpm
    bar = 4 * beat
    length = 16 * bar
    mix = A.Track(length, loop=True)
    # Walking bass, one note per beat, short and plucky (the "creeping" feel).
    bass_bars = [["A2", "C3", "E3", "C3"], ["A2", "C3", "E3", "G#2"],
                 ["F2", "A2", "C3", "A2"], ["E2", "G#2", "B2", "E3"]]
    # Melody: tiptoe eighth notes with rests, then a cheeky run.
    melody = [
        ["A4", None, "C5", None, "E5", "D#5", "E5", None],
        ["A4", None, "C5", None, "B4", None, "G#4", None],
        ["F4", None, "A4", None, "C5", "B4", "C5", None],
        ["E5", "D5", "C5", "B4", "G#4", None, "E4", None],
    ]
    rng = random.Random(5)
    for b in range(16):
        t0 = b * bar
        for k, n in enumerate(bass_bars[b % 4]):
            mix.add(t0 + k * beat, tone(hz(n), beat * 0.45, "tri", 0.38, decay=0.09, lowpass=900))
        if b >= 2:  # melody enters after two bars of bass
            for k, n in enumerate(melody[b % 4]):
                if n:
                    oct_up = 2 if (b // 4) % 2 else 1
                    mix.add(t0 + k * beat / 2, tone(hz(n) * oct_up / 1, beat * 0.3, "square", 0.07,
                                                    decay=0.05, lowpass=2800))
                    mix.add(t0 + k * beat / 2, tone(hz(n) * oct_up, beat * 0.3, "sine", 0.12, decay=0.06))
        for k in range(8):  # shaker on eighths, accent on the off-beat
            mix.add(t0 + k * beat / 2, noise(0.05, 0.05 if k % 2 else 0.025, decay=0.015, highpass=5000,
                                             seed=rng.randrange(10 ** 6)))
        for k in (0, 2):  # soft kick to keep it bouncing
            mix.add(t0 + k * beat, tone(110, 0.15, "sine", 0.35, decay=0.06, glide_to=50))
        if b % 4 == 3:  # finger-snap on the last beat of each phrase
            mix.add(t0 + 3.5 * beat, noise(0.06, 0.25, decay=0.012, lowpass=6000, highpass=1500, seed=900 + b))
    return mix.buf


def main():
    for name, samples in sfx().items():
        A.write_wav(os.path.join(OUT, name + ".wav"), samples)
    A.SR = 22050
    A.write_wav(os.path.join(OUT, "sneaky_theme.wav"), sneaky_theme(), peak=0.7)


if __name__ == "__main__":
    main()
