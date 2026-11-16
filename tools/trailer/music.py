#!/usr/bin/env python3
"""Original trailer score for OpenShooter, synthesized with numpy only.

    python3 tools/trailer/music.py OUT.wav [--length 59.2] [--intro 7.2] [--cards 3]

The first `--intro` seconds score the title cards (a low drone with a deep hit
on each card). The times below are counted after the intro.

Structure (seconds, matched to the trailer cuts every 9.5 s from 10.5):
  0.0 - 10.5  dark D-minor drone swelling, heartbeat sub, riser into the cut
 10.5 - 39.0  impact on every cut; kick + pulsing bass, hats from 20.0,
              arpeggio from 29.5, riser and drop-out before the logo
 40.0 - end   big impact on the logo reveal, a soft resolution when the
              platform row appears (44.0), pad tail and fade out
"""
import sys
import wave

import numpy as np

SR = 48000
BEAT = 9.5 / 16.0          # 101 BPM: every cut lands on a beat
GRID0 = 10.5 - 16 * BEAT   # first beat of the grid (1.0 s)
CUTS = [10.5, 20.0, 29.5]
LOGO = 40.0
## The platform row appears 4 s after the logo.
PLATFORMS = 44.0
rng = np.random.default_rng(7)


def note(n: str) -> float:
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3,
             "G": -2, "G#": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}
    pitch, octave = n[:-1], int(n[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def saw(freq: float, seconds: float, harmonics: int = 24) -> np.ndarray:
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2 - 1000:
            break
        out += np.sin(2 * np.pi * freq * k * t + k * 0.3) / k
    return out * 0.6


def spectral(x: np.ndarray, low: float | None = None, high: float | None = None) -> np.ndarray:
    """Smooth FFT band filter (low/high cut-offs in Hz)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = np.ones_like(f)
    if high is not None:
        gain *= 1 / np.sqrt(1 + (f / high) ** 4)
    if low is not None:
        gain *= 1 / np.sqrt(1 + (low / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(spec * gain, len(x))


def env(seconds: float, attack: float, decay: float) -> np.ndarray:
    t = t_axis(seconds)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def place(track: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = int(at * SR)
    if i < 0:
        sound = sound[-i:]
        i = 0
    if i >= len(track) or len(sound) == 0:
        return
    j = min(len(track), i + len(sound))
    track[i:j] += sound[: j - i] * gain


def reverb(x: np.ndarray, seconds: float = 2.6, mix: float = 0.3) -> np.ndarray:
    n = int(seconds * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * seconds / 6.0))
    ir = spectral(ir, high=6000)
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return x * (1 - mix) + wet * mix * 2.2


# ------------------------------------------------------------------ instruments

def kick(seconds=0.45, f0=125.0, f1=44.0, punch=0.012) -> np.ndarray:
    t = t_axis(seconds)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.045)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t / (seconds * 0.4))
    click = rng.standard_normal(len(t)) * np.exp(-t / punch) * 0.25
    return body + spectral(click, high=4000)


def boom(seconds=3.2) -> np.ndarray:
    t = t_axis(seconds)
    k = kick(seconds, f0=95.0, f1=31.0, punch=0.02) * 1.4
    noise = spectral(rng.standard_normal(len(t)), high=900) * np.exp(-t / 0.5) * 0.9
    metal = spectral(rng.standard_normal(len(t)), low=2500, high=9000) * np.exp(-t / 0.18) * 0.25
    return k + noise + metal


def hat(seconds=0.06) -> np.ndarray:
    n = rng.standard_normal(int(seconds * SR))
    return spectral(n, low=7000) * env(seconds, 0.001, seconds / 4)


def pluck(freq: float, seconds=0.35) -> np.ndarray:
    x = saw(freq, seconds, 14) + 0.5 * saw(freq * 1.005, seconds, 14)
    return spectral(x, high=2200) * env(seconds, 0.003, 0.09)


def riser(seconds: float) -> np.ndarray:
    t = t_axis(seconds)
    noise = spectral(rng.standard_normal(len(t)), low=600, high=7000)
    sweep = np.sin(2 * np.pi * np.cumsum(180 + 900 * (t / seconds) ** 2) / SR)
    shape = (t / seconds) ** 2.4
    return (noise * 0.6 + sweep * 0.25) * shape


def pad(chord: list[str], seconds: float, cutoff: float = 900.0) -> np.ndarray:
    out = np.zeros(int(seconds * SR))
    for n in chord:
        f = note(n)
        for d in (-0.07, 0.0, 0.06):
            out += saw(f * 2 ** (d / 12), seconds, 16)
    return spectral(out / (len(chord) * 3), high=cutoff)


# ------------------------------------------------------------------ score

def score(length: float) -> np.ndarray:
    """Main score (after the title cards), mono, before mastering."""
    n = int(length * SR)
    t = np.arange(n) / SR
    drums = np.zeros(n)
    bass = np.zeros(n)
    music = np.zeros(n)
    fx = np.zeros(n)

    # Drone: D minor, swelling over the intro and returning under the logo.
    drone = pad(["D2", "A2", "D3", "F3"], length, cutoff=700)
    swell = 0.2 + np.clip(t / 9.0, 0, 1) ** 1.5 * 0.3
    swell = np.where(t > 10.5, 0.32, swell)
    swell = np.where(t > 37.8, 0.32 * np.clip((39.4 - t) / 1.6, 0, 1), swell)
    swell = np.where(t > LOGO, 0.6 * np.exp(-(t - LOGO) / 12.0), swell)
    music += drone * swell

    # Heartbeat sub during the intro (from the second caption).
    beat = GRID0
    while beat < 10.4:
        if beat > 3.5:
            place(drums, kick(0.5, 80, 38, 0.02), beat, 0.55)
            place(drums, kick(0.4, 70, 36, 0.02), beat + BEAT * 0.45, 0.3)
        beat += BEAT * 2

    # Main section: chord roots change every 4 beats.
    progression = [("D", ["D3", "F3", "A3"]), ("A#", ["A#2", "D3", "F3"]),
                   ("G", ["G2", "A#2", "D3"]), ("A", ["A2", "C#3", "E3"])]
    arp_notes = {"D": ["D4", "F4", "A4", "D5"], "A#": ["A#3", "D4", "F4", "A#4"],
                 "G": ["G3", "A#3", "D4", "G4"], "A": ["A3", "C#4", "E4", "A4"]}
    chord_pad = np.zeros(n)
    i = 0
    beat = 10.5
    while beat < 39.0 - 1e-6:
        bar = int((beat - 10.5) / BEAT) // 4
        root, chord = progression[bar % 4]
        in_drop = beat >= 38.4
        if not in_drop:
            place(drums, kick(), beat, 0.9)
            for half in (0.0, 0.5):
                f = note(root + ("1" if root in ("A#", "G", "A") else "2"))
                b = spectral(saw(f, BEAT * 0.48, 12) + 0.4 * np.sin(2 * np.pi * f * t_axis(BEAT * 0.48)), high=520)
                place(bass, b * env(BEAT * 0.48, 0.008, 0.16), beat + half * BEAT, 0.55)
            if beat >= 20.0:
                for q in (0.25, 0.5, 0.75):
                    place(drums, hat(), beat + q * BEAT, 0.16 if q == 0.5 else 0.08)
            if beat >= 29.5:
                arp = arp_notes[root]
                for q in range(4):
                    place(music, pluck(note(arp[(i + q) % 4])), beat + q * BEAT / 4, 0.16)
        if (beat - 10.5) / BEAT % 4 < 1e-6 and not in_drop:
            p = pad(chord, BEAT * 4 + 0.3, cutoff=1500) * env(BEAT * 4 + 0.3, 0.25, 3.0)
            place(chord_pad, p, beat, 0.32)
        beat += BEAT
        i += 1
    music += chord_pad

    # Impacts on every cut and the logo; risers into them.
    for c in CUTS:
        place(fx, boom(), c, 0.75)
    place(fx, riser(2.0), 8.5, 0.35)
    place(fx, riser(2.2), 37.8, 0.5)
    place(fx, boom(4.5), LOGO, 1.15)
    shimmer = pad(["D4", "A4", "D5", "F5"], 8.0, cutoff=5000) * env(8.0, 0.6, 3.0)
    place(fx, shimmer, LOGO, 0.22)
    # Platform row: a soft, bright resolution (D major colour) and a low pulse.
    resolve = pad(["D3", "F#3", "A3", "D4", "F#4"], 7.0, cutoff=3500) * env(7.0, 0.4, 3.5)
    place(fx, resolve, PLATFORMS, 0.3)
    place(fx, kick(1.2, 70, 34, 0.03), PLATFORMS, 0.45)

    return drums * 0.9 + bass * 0.8 + reverb(music, 2.8, 0.35) * 0.9 + reverb(fx, 3.5, 0.3)


def intro_part(seconds: float, cards: int) -> np.ndarray:
    """Title cards on black: a low drone with a deep hit on each card."""
    tail = 3.0
    n = int((seconds + tail) * SR)
    t = np.arange(n) / SR
    drone = pad(["D1", "D2", "A2"], seconds + tail, cutoff=420)
    level = np.clip(t / 1.2, 0, 1) * 0.28 * np.clip((seconds + tail - t) / tail, 0, 1)
    out = drone * level
    hits = np.zeros(n)
    slot = seconds / cards
    for i in range(cards):
        at = i * slot + 0.15
        place(hits, kick(2.4, 70, 30, 0.03), at, 0.8)
        place(hits, spectral(rng.standard_normal(int(1.5 * SR)), low=3000, high=9000)
              * env(1.5, 0.4, 0.3), at - 0.4, 0.05)
    return out + reverb(hits, 3.5, 0.45)


def main() -> None:
    out_path = sys.argv[1]

    def arg(name: str, default: float) -> float:
        return float(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default

    length = arg("--length", 48.0)
    intro = arg("--intro", 0.0)
    cards = int(arg("--cards", 3))
    n = int(length * SR)
    t = np.arange(n) / SR
    mix = np.zeros(n)
    place(mix, score(length - intro), intro)
    if intro > 0.0:
        place(mix, intro_part(intro, cards), 0.0)

    # Master: fades, normalize, soft clip.
    fade = np.clip(t / 0.3, 0, 1) * np.clip((length - t) / 2.5, 0, 1)
    mix *= fade
    mix /= np.max(np.abs(mix)) + 1e-9
    mix = np.tanh(mix * 1.6) / np.tanh(1.6) * 0.89
    # Gentle stereo width: a few ms of offset on a quiet copy for the right.
    d = int(0.011 * SR)
    right = mix.copy()
    right[d:] = mix[d:] * 0.94 + mix[:-d] * 0.06
    stereo = np.clip(np.stack([mix, right], axis=1), -1, 1)
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("music written:", out_path)


if __name__ == "__main__":
    main()
