#!/usr/bin/env python3
"""Generate Contrail's own ambient sounds and focus music.

Every sound is synthesised from noise and oscillators with fixed random seeds,
so the output is reproducible and contains no third-party recordings.

Each file is a seamless loop: the app can repeat it without an audible seam.

Usage:
    python3 generate.py OUT_DIR [--seconds 40] [--only cabin,rain_shelter]
"""
import argparse
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
XFADE = 3.0  # seconds used to join the end of a loop to its start


# ---------------------------------------------------------------- helpers

def secs(n):
    return np.arange(n) / SR


def colored_noise(r, n, exponent, channels=2, corr=0.25):
    """Stereo noise with power ~ 1/f**exponent (0 white, 1 pink, 2 brown)."""
    freqs = np.fft.rfftfreq(n, 1 / SR)
    scale = np.zeros_like(freqs)
    f = np.maximum(freqs, 20.0)
    scale[1:] = f[1:] ** (-exponent / 2)
    scale[freqs < 20] *= freqs[freqs < 20] / 20.0  # roll off sub-audio drift

    def one():
        spec = (r.standard_normal(len(freqs)) + 1j * r.standard_normal(len(freqs))) * scale
        x = np.fft.irfft(spec, n)
        return x / (np.std(x) + 1e-12)

    base = one()
    return np.stack([np.sqrt(corr) * base + np.sqrt(1 - corr) * one() for _ in range(channels)])


def sos_filter(x, kind, freq, order=2):
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x, axis=-1)


def bandpass(x, lo, hi, order=2):
    return sos_filter(x, "bandpass", [lo, hi], order)


def lowpass(x, f, order=2):
    return sos_filter(x, "lowpass", f, order)


def highpass(x, f, order=2):
    return sos_filter(x, "highpass", f, order)


def smooth_random(r, n, rate_hz, channels=1):
    """Slow random control signal in about [-1, 1] that changes at ~rate_hz."""
    k = max(4, int(n / SR * rate_hz) + 4)
    pts = r.uniform(-1, 1, (channels, k))
    xs = np.linspace(0, n, k)
    out = np.stack([np.interp(np.arange(n), xs, p) for p in pts])
    # cubic-like smoothing
    win = max(3, int(SR / rate_hz / 2))
    kernel = np.hanning(win)
    kernel /= kernel.sum()
    out = np.stack([signal.fftconvolve(o, kernel, mode="same") for o in out])
    return out / (np.max(np.abs(out)) + 1e-9)


def reverb(x, r, seconds=2.5, wet=0.3, damp=4000):
    """Simple stereo convolution reverb using decaying filtered noise."""
    m = int(seconds * SR)
    t = secs(m)
    ir = r.standard_normal((2, m)) * np.exp(-t * 6.9 / seconds)
    ir = lowpass(ir, damp)
    ir[:, : int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    mono_in = x if x.ndim == 2 else np.stack([x, x])
    wet_sig = np.stack([signal.fftconvolve(mono_in[c], ir[c])[: mono_in.shape[1]] for c in range(2)])
    return (1 - wet) * mono_in + wet * wet_sig


def pan(mono, p):
    """Equal-power pan, p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)])


def place_events(n, times, kernel_fn, r):
    """Mix kernels at given start times into a stereo buffer."""
    out = np.zeros((2, n))
    for t0 in times:
        k = kernel_fn(r)  # stereo (2, m)
        s = int(t0 * SR)
        e = min(n, s + k.shape[1])
        if s < n:
            out[:, s:e] += k[:, : e - s]
    return out


def drop_layer(r, n, rate, make_kernel, variants=16):
    """Dense random impulses (raindrops) built from a few kernel variants."""
    out = np.zeros((2, n))
    count = r.poisson(rate * n / SR)
    which = r.integers(0, variants, count)
    pos = r.integers(0, n, count)
    gains = r.lognormal(0, 0.5, count)
    pans = r.uniform(-1, 1, count)
    for v in range(variants):
        sel = which == v
        if not np.any(sel):
            continue
        kern = make_kernel(r)
        a = (pans[sel] + 1) * np.pi / 4
        for c, w in enumerate([np.cos(a), np.sin(a)]):
            train = np.zeros(n)
            np.add.at(train, pos[sel], gains[sel] * w)
            out[c] += signal.fftconvolve(train, kern)[:n]
    return out


def loudness_weight(x):
    """Rough K-weighting so different spectra land at a similar loudness."""
    y = highpass(x, 60)
    b, a = signal.iirfilter(2, 1500, btype="highpass", fs=SR, ftype="butter")
    return y + 0.6 * signal.filtfilt(b, a, y, axis=-1)


def finish(x, target_db=-26.0):
    """Normalise loudness, soft-limit peaks to about -1 dBFS."""
    x = x - np.mean(x, axis=1, keepdims=True)
    rms = np.sqrt(np.mean(loudness_weight(x) ** 2))
    x = x * (10 ** (target_db / 20) / (rms + 1e-12))
    ceiling = 10 ** (-1 / 20)
    return ceiling * np.tanh(x / ceiling)


def make_loop(x, n):
    """Cross-fade the overrun after n samples into the start (equal power)."""
    xf = int(XFADE * SR)
    y = x[:, :n].copy()
    t = np.linspace(0, np.pi / 2, xf)
    y[:, :xf] = x[:, n : n + xf] * np.cos(t) + x[:, :xf] * np.sin(t)
    return y


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").T.copy()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------- ambiences

def cabin(r, n):
    t = secs(n)
    roar = lowpass(colored_noise(r, n, 2.0, corr=0.6), 900)
    air = bandpass(colored_noise(r, n, 1.0), 300, 4000) * 0.22
    drift = smooth_random(r, n, 0.05)[0]
    f1 = 92 + 0.4 * drift
    phase = 2 * np.pi * np.cumsum(f1) / SR
    drone = (np.sin(phase) + 0.5 * np.sin(2 * phase + 1.3)) * 0.05
    swell = 1 + 0.05 * np.sin(2 * np.pi * 0.031 * t) + 0.04 * smooth_random(r, n, 0.1)[0]
    return (roar + air + drone) * swell


def waterfall(r, n):
    body = bandpass(colored_noise(r, n, 0.6), 150, 9000)
    turbulence = 1 + 0.18 * smooth_random(r, n, 12, channels=2)
    rumble = lowpass(colored_noise(r, n, 2.0), 300) * 0.6
    return body * turbulence + rumble


def _noise_drop(lo, hi, decay_ms):
    def make(r):
        m = int(0.08 * SR)
        k = r.standard_normal(m) * np.exp(-secs(m) * 1000 / r.uniform(*decay_ms))
        c = r.uniform(lo, hi)
        return bandpass(k, c * 0.6, min(c * 1.6, 18000))
    return make


def _plink(lo, hi):
    def make(r):
        m = int(0.25 * SR)
        t = secs(m)
        f0 = r.uniform(lo, hi)
        f = f0 * (1 + 0.5 * (1 - np.exp(-t / 0.015)))  # upward chirp of a water drop
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / r.uniform(0.03, 0.07))
        click = r.standard_normal(m) * np.exp(-t / 0.002) * 0.3
        return tone + click
    return make


def rain_shelter(r, n):
    bed = bandpass(colored_noise(r, n, 1.0), 400, 8000) * 0.5
    drops = drop_layer(r, n, 450, _noise_drop(2000, 6500, (3, 10))) * 0.35
    def tap(rr):
        m = int(0.12 * SR)
        t = secs(m)
        return np.sin(2 * np.pi * rr.uniform(250, 650) * t) * np.exp(-t / 0.025)
    taps = reverb(drop_layer(r, n, 14, tap, variants=8), r, 0.8, 0.35) * 0.25
    return bed + drops + taps


def heavy_rain(r, n):
    bed = bandpass(colored_noise(r, n, 0.7), 200, 12000)
    drops = drop_layer(r, n, 1600, _noise_drop(1500, 8000, (2, 8))) * 0.25
    rumble = lowpass(colored_noise(r, n, 2.0), 200) * 0.5
    return bed + drops + rumble


def raindrop(r, n):
    bed = lowpass(colored_noise(r, n, 1.0), 3000) * 0.12
    plinks = drop_layer(r, n, 5, _plink(900, 2600), variants=24)
    return bed + reverb(plinks, r, 2.2, 0.45) * 0.8


def thunderstorm(r, n):
    rain = rain_shelter(r, n) * 0.8
    dur = n / SR
    times, t = [], r.uniform(4, 12)
    while t < dur:
        times.append(t)
        t += r.uniform(20, 40)

    def thunder(rr):
        m = int(rr.uniform(6, 10) * SR)
        tt = secs(m)
        k = colored_noise(rr, m, 2.0, corr=0.5)
        k = lowpass(k, rr.uniform(140, 260))
        attack = rr.uniform(0.4, 0.9)
        env = np.minimum(tt / attack, 1) * np.exp(-np.maximum(tt - attack, 0) / rr.uniform(1.8, 3.0))
        rumble = 1 + 0.5 * smooth_random(rr, m, 4)[0]
        return k * env * rumble * rr.uniform(0.9, 1.5)

    thunder_layer = reverb(place_events(n, times, thunder, r), r, 3.5, 0.4, damp=800)
    return rain + thunder_layer * 1.4


def forest(r, n):
    gust = (smooth_random(r, n, 0.12)[0] + 1) / 2
    wind = bandpass(colored_noise(r, n, 1.0), 200, 2500) * (0.25 + 0.35 * gust)
    leaves = highpass(colored_noise(r, n, 0.3), 3000) * (0.04 + 0.12 * gust ** 2)

    species = []
    for _ in range(3):
        species.append(dict(
            f0=r.uniform(2200, 4800), span=r.uniform(-0.45, 0.35),
            syl=r.uniform(0.05, 0.16), count=(int(r.integers(2, 5)), int(r.integers(5, 9))),
            trill=r.uniform(0, 35), gap=r.uniform(0.03, 0.1),
        ))

    birds = np.zeros((2, n))
    for sp in species:
        t = r.uniform(1, 6)
        p = r.uniform(-0.8, 0.8)
        while t < n / SR - 2:
            phrase = []
            for _ in range(r.integers(*sp["count"])):
                m = int(sp["syl"] * r.uniform(0.8, 1.2) * SR)
                tt = np.linspace(0, 1, m)
                f = sp["f0"] * r.uniform(0.95, 1.05) * (1 + sp["span"] * tt)
                f = f * (1 + 0.04 * np.sin(2 * np.pi * sp["trill"] * tt * sp["syl"]))
                ph = 2 * np.pi * np.cumsum(f) / SR
                env = np.sin(np.pi * tt) ** 2
                phrase.append((np.sin(ph) + 0.15 * np.sin(2 * ph)) * env)
                phrase.append(np.zeros(int(sp["gap"] * SR)))
            mono = np.concatenate(phrase) * r.uniform(0.25, 0.6)
            s = int(t * SR)
            e = min(n, s + len(mono))
            birds[:, s:e] += pan(mono[: e - s], p + r.uniform(-0.15, 0.15))
            t += r.uniform(3, 9)
    birds = reverb(lowpass(birds, 7000), r, 1.8, 0.4, damp=5000)
    return wind + leaves + birds * 0.35


def ocean(r, n):
    low = lowpass(colored_noise(r, n, 2.0, corr=0.5), 500)
    mid = bandpass(colored_noise(r, n, 1.0, corr=0.5), 300, 3000)
    high = highpass(colored_noise(r, n, 0.2), 2500)
    env_low, env_mid, env_high = (np.zeros(n) for _ in range(3))
    t = secs(n)
    w = r.uniform(0, 3)
    while w < n / SR:
        period = r.uniform(7, 12)
        peak = w + r.uniform(2.0, 3.0)
        amp = r.uniform(0.7, 1.2)
        rise = np.clip((t - w) / (peak - w), 0, 1) ** 2
        fall = np.exp(-np.maximum(t - peak, 0) / r.uniform(1.5, 2.5))
        env_low += amp * rise * fall
        env_mid += amp * np.where(t >= peak, np.exp(-(t - peak) / r.uniform(1.2, 2.0)), rise ** 3)
        env_high += amp * np.where(t >= peak + 0.3, np.exp(-(t - peak - 0.3) / r.uniform(2.5, 4.0)), 0)
        w += period
    bed = lowpass(colored_noise(r, n, 2.0), 300) * 0.35
    return low * (0.3 + env_low) + mid * env_mid * 0.6 + high * env_high * 0.18 + bed


def blizzard(r, n):
    base = colored_noise(r, n, 0.8)
    centers = [250, 450, 800, 1400, 2400]
    bands = [bandpass(base, c / 1.4, c * 1.4) for c in centers]
    gust = (smooth_random(r, n, 0.15)[0] + 1) / 2  # 0..1
    pos = gust * (len(centers) - 1)
    wind = np.zeros_like(base)
    for i, b in enumerate(bands):
        wind += b * np.clip(1 - np.abs(pos - i), 0, 1)
    wind *= 0.35 + 0.65 * gust
    whistle_c = [650, 850, 1100]
    wsel = (smooth_random(r, n, 0.07)[0] + 1) / 2 * (len(whistle_c) - 1)
    whistle = np.zeros_like(base)
    for i, c in enumerate(whistle_c):
        whistle += bandpass(base, c * 0.97, c * 1.03) * np.clip(1 - np.abs(wsel - i), 0, 1)
    snow = highpass(colored_noise(r, n, 0.0), 4500) * 0.05
    rumble = lowpass(colored_noise(r, n, 2.0), 150) * 0.4
    return wind + whistle * 1.5 * gust ** 2 + snow + rumble


# ---------------------------------------------------------------- music

def hz(midi):
    return 440.0 * 2 ** ((np.asarray(midi) - 69) / 12)


def pad_note(r, freq, m, bright=6.0):
    t = secs(m)
    out = np.zeros((2, m))
    for c in range(2):
        for cents in (-5, 0, 5):
            f = freq * 2 ** ((cents + r.uniform(-1, 1)) / 1200)
            ph = r.uniform(0, 2 * np.pi, 13)
            for k in range(1, 13):
                if f * k > 9000:
                    break
                out[c] += np.sin(2 * np.pi * f * k * t + ph[k]) / k * np.exp(-k / bright)
    return out / 3


def chord_pad(r, n, chords, chord_secs, attack=4.0, release=5.0, bright=6.0):
    out = np.zeros((2, n))
    i, start = 0, 0.0
    while start < n / SR:
        notes = chords[i % len(chords)]
        m = int((chord_secs + release) * SR)
        t = secs(m)
        env = np.minimum(t / attack, 1) * np.clip((chord_secs + release - t) / release, 0, 1)
        voice = sum(pad_note(r, f, m, bright) for f in hz(notes)) / len(notes)
        s = int(start * SR)
        e = min(n, s + m)
        out[:, s:e] += (voice * env)[:, : e - s]
        start += chord_secs
        i += 1
    return out


def bell(r, freq, m, decay=2.5):
    t = secs(m)
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.4)
    return tone * np.exp(-t / decay) * np.minimum(t / 0.01, 1)


def music_drift(r, n):
    """Warm, open pad that slowly moves through four chords in D."""
    chords = [[50, 57, 61, 64, 66], [47, 54, 57, 62, 64], [43, 50, 54, 57, 59], [45, 52, 59, 61, 64]]
    pad = lowpass(chord_pad(r, n, chords, 12.0), 3200)
    shimmer = np.zeros((2, n))
    t = r.uniform(1, 3)
    while t < n / SR - 4:
        idx = int(t // 12) % len(chords)
        note = r.choice(chords[idx]) + 24
        b = bell(r, hz(note), int(4 * SR)) * r.uniform(0.05, 0.12)
        s = int(t * SR)
        e = min(n, s + len(b))
        shimmer[:, s:e] += pan(b[: e - s], r.uniform(-0.7, 0.7))
        t += r.uniform(2.5, 5.0)
    air = bandpass(colored_noise(r, n, 1.0), 2000, 9000) * 0.01
    return reverb(pad + shimmer, r, 4.0, 0.4) + air


def music_anchor(r, n):
    """Minimal low drone on C with slow breathing, for a grounded feel."""
    t = secs(n)
    drone = pad_note(r, hz(36), n, bright=4) + 0.8 * pad_note(r, hz(43), n, bright=4) + 0.5 * pad_note(r, hz(48), n, bright=5)
    breath = 0.75 + 0.25 * np.sin(2 * np.pi * t / 12.0)
    bright = (smooth_random(r, n, 0.04)[0] + 1) / 2
    dark = lowpass(drone, 500)
    light = lowpass(drone, 1800)
    body = (dark * (1 - bright) + light * bright) * breath
    bells = np.zeros((2, n))
    tt = r.uniform(3, 6)
    while tt < n / SR - 6:
        b = bell(r, hz(r.choice([64, 67, 72, 74])), int(6 * SR), decay=3.5) * 0.05
        s = int(tt * SR)
        e = min(n, s + len(b))
        bells[:, s:e] += pan(b[: e - s], r.uniform(-0.5, 0.5))
        tt += r.uniform(7, 11)
    bed = lowpass(colored_noise(r, n, 2.0), 400) * 0.05
    return reverb(body + bells, r, 4.5, 0.35) + bed


def music_current(r, n):
    """Soft pad with a gentle, sparse pentatonic pluck pattern for momentum."""
    chords = [[41, 48, 52, 57, 60], [43, 50, 55, 57, 62], [45, 52, 55, 60, 64], [48, 55, 59, 62, 64]]
    pad = lowpass(chord_pad(r, n, chords, 10.0, attack=3.0, release=4.0), 2500) * 0.7
    step = 60 / 72 / 2
    plucks = np.zeros((2, n))
    scale = [60, 62, 64, 67, 69, 72, 74, 76]
    t = 2.0
    k = 0
    while t < n / SR - 2:
        if r.random() > 0.3:
            note = scale[(k * 3 + int(r.integers(0, 3))) % len(scale)]
            m = int(1.4 * SR)
            tt = secs(m)
            f = hz(note)
            tone = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt) * np.exp(-tt / 0.15))
            tone *= np.exp(-tt / 0.5) * np.minimum(tt / 0.004, 1) * r.uniform(0.08, 0.16)
            s = int(t * SR)
            e = min(n, s + m)
            plucks[:, s:e] += pan(tone[: e - s], 0.35 * np.sin(k * 0.7))
        t += step
        k += 1
    # soft ping-pong echo, three eighths later
    d = int(3 * step * SR)
    echo = np.zeros_like(plucks)
    echo[0, d:] = plucks[1, :-d] * 0.35
    echo[1, d:] = plucks[0, :-d] * 0.35
    plucks = lowpass(plucks + echo, 5000)
    return reverb(pad + plucks, r, 3.0, 0.35)


def chime(r, n):
    """Soft two-note landing chime (not looped)."""
    out = np.zeros((2, n))
    for start, note, gain in ((0.0, 76, 0.5), (0.45, 83, 0.4)):
        b = bell(r, hz(note), int(3.0 * SR), decay=1.1) * gain
        s0 = int(start * SR)
        e = min(n, s0 + len(b))
        out[:, s0:e] += pan(b[: e - s0], 0.0)
    return reverb(out, r, 2.0, 0.3)


SOUNDS = {
    # id: (title, group, function, seed)
    "cabin": ("Cabin", "ambience", cabin, 11),
    "waterfall": ("Waterfall", "ambience", waterfall, 12),
    "rain_shelter": ("Rain on Roof", "ambience", rain_shelter, 13),
    "thunderstorm": ("Distant Storm", "ambience", thunderstorm, 14),
    "forest": ("Forest", "ambience", forest, 15),
    "ocean": ("Ocean", "ambience", ocean, 16),
    "raindrop": ("Dripping Eaves", "ambience", raindrop, 17),
    "heavy_rain": ("Downpour", "ambience", heavy_rain, 18),
    "blizzard": ("Snow Wind", "ambience", blizzard, 19),
    "music_drift": ("Drift", "music", music_drift, 21),
    "music_anchor": ("Anchor", "music", music_anchor, 22),
    "music_current": ("Current", "music", music_current, 23),
    "chime": ("Landing Chime", "alert", chime, 31),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--seconds", type=float, default=40.0)
    ap.add_argument("--only", default="")
    ap.add_argument("--keep-wav", action="store_true")
    ap.add_argument("--bitrate", type=int, default=192000)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    n = int(args.seconds * SR)
    for sid, (title, group, fn, seed) in SOUNDS.items():
        if only and sid not in only:
            continue
        r = np.random.default_rng(seed)
        if group == "alert":
            x = finish(fn(r, int(3.5 * SR)), target_db=-20.0)
        else:
            raw = fn(r, n + int(XFADE * SR))
            x = finish(make_loop(raw, n), target_db=-26.0 if group == "ambience" else -24.0)
        wav = args.out / f"{sid}.wav"
        write_wav(wav, x)
        m4a = args.out / f"{sid}.m4a"
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", str(args.bitrate), str(wav), str(m4a)], check=True)
        if not args.keep_wav:
            wav.unlink()
        print(f"{sid:14s} {title:16s} {group:8s} ok")


if __name__ == "__main__":
    main()
