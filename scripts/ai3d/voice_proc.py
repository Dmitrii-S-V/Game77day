"""Обработка записанных голосов зомби (tools/voice_recorder.html) -> assets/sounds/zombie_<тип>_<событие>_<N>.wav.
Запуск (Python с numpy, например из Blender):
  D:\\ai3d\\blender\\4.5\\python\\bin\\python.exe scripts/ai3d/voice_proc.py [stats] [friend|mudworn]
stats — только показать уровни сырых записей.

Шаги: шумоподавление (спектральное, профиль шума — по тихим участкам самой записи или roomtone_*.wav),
срез гула < 80 Гц, обрезка тишины по краям, характер голоса типа (сдвиг высоты передискретизацией, лёгкая
окраска), выравнивание громкости по событию, мягкий ограничитель, 16 бит моно 44.1 кГц."""
import os
import sys
import glob
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "src", "voice")
OUT = os.path.join(ROOT, "assets", "sounds")
SR_OUT = 44100

# характер типа: semis — сдвиг высоты (полутона, вместе с темпом: ниже — медленнее, тяжелее), dark — завал верхов,
# grit — перегруз (хрип)
VOICE = {
    "friend": {"semis": -2.5, "dark": 0.5, "grit": 0.15},
    "mudworn": {"semis": 0.5, "dark": 0.0, "grit": 0.35},
}
# целевая громкость активной части (RMS, дБFS) по событию
LOUD = {"groan": -19, "alert": -15, "chase": -17, "attack": -15, "hurt": -16, "death": -17,
        "sleep": -24, "crouch": -19, "leap": -14}


def read_wav(path):
    with wave.open(path, "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        x = (b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16))
        x = np.where(x >= 1 << 23, x - (1 << 24), x) / float(1 << 23)
    elif sw == 2:
        x = np.frombuffer(raw, np.int16) / 32768.0
    else:
        raise ValueError("формат %d байт" % sw)
    x = x.reshape(-1, ch).mean(axis=1)
    return x.astype(np.float64), sr


def write_wav(path, x, sr):
    y = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(y.tobytes())


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def frames_rms(x, sr, win=0.02):
    n = max(1, int(sr * win))
    m = len(x) // n
    return np.sqrt((x[:m * n].reshape(m, n) ** 2).mean(axis=1) + 1e-12), n


def stft(x, n=1024, hop=256):
    w = np.hanning(n)
    pad = np.concatenate([np.zeros(n), x, np.zeros(n)])
    m = 1 + (len(pad) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(m)[:, None]
    return np.fft.rfft(pad[idx] * w, axis=1), w, len(x)


def istft(S, w, length, n=1024, hop=256):
    fr = np.fft.irfft(S, n=n, axis=1) * w
    out = np.zeros(hop * (len(S) - 1) + n)
    norm = np.zeros_like(out)
    for i in range(len(S)):
        out[i * hop:i * hop + n] += fr[i]
        norm[i * hop:i * hop + n] += w * w
    out /= np.maximum(norm, 1e-8)
    return out[n:n + length]


def denoise(x, noise_mag=None, strength=1.6, floor=0.12):
    """Спектральное вычитание: профиль шума — заданный или по 15% самых тихих кадров записи."""
    S, w, L = stft(x)
    mag = np.abs(S)
    if noise_mag is None:
        e = mag.sum(axis=1)
        q = e <= np.percentile(e, 15)
        noise_mag = mag[q].mean(axis=0)
    gain = np.maximum(1.0 - strength * noise_mag[None, :] / np.maximum(mag, 1e-9), floor)
    # сгладить маску по времени (меньше «булькающих» артефактов)
    k = np.array([0.25, 0.5, 0.25])
    g2 = gain.copy()
    g2[1:-1] = k[0] * gain[:-2] + k[1] * gain[1:-1] + k[2] * gain[2:]
    return istft(S * g2, w, L), noise_mag


def fft_filter(x, sr, hp=80.0, dark=0.0):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    g = 1.0 / np.sqrt(1.0 + (hp / np.maximum(f, 1e-3)) ** 8)        # срез гула (4-й порядок)
    if dark > 0:
        g *= 1.0 / np.sqrt(1.0 + (f / 5500.0) ** 4) ** dark          # завал верхов
    return np.fft.irfft(X * g, n=len(x))


def resample(x, ratio):
    """ratio > 1 — длиннее (ниже). Линейная интерполяция после сглаживания (достаточно для голоса)."""
    n = int(len(x) * ratio)
    t = np.linspace(0, len(x) - 1, n)
    return np.interp(t, np.arange(len(x)), x)


def to_rate(x, sr, sr2):
    if sr == sr2:
        return x
    if sr2 < sr:
        X = np.fft.rfft(x)
        f = np.fft.rfftfreq(len(x), 1.0 / sr)
        X[f > sr2 * 0.47] = 0
        x = np.fft.irfft(X, n=len(x))
    return resample(x, sr2 / sr)


def trim(x, sr, rel_db=-38.0, pad=0.04, main_only=False, gap=0.12):
    """Обрезка тишины. main_only — только основной звук: от самого громкого места в обе стороны, пока тишина между
    кусками не длиннее gap (отбрасывает щелчок клавиши записи и посторонние звуки, отделённые паузой)."""
    r, n = frames_rms(x, sr, 0.01)
    # порог: ниже пика на rel_db, но не ниже фона + 10 дБ (у тихих дублей иначе остаются паузы с шумом)
    thr = max(r.max() * 10 ** (rel_db / 20), np.percentile(r, 20) * 10 ** (10 / 20))
    on = np.where(r > thr)[0]
    if len(on) == 0:
        return x
    lo, hi = on[0], on[-1]
    if main_only:
        g = max(1, int(gap / 0.01))
        lo = hi = int(np.argmax(r))
        while True:
            left = [i for i in range(max(0, lo - g), lo) if r[i] > thr]
            if not left:
                break
            lo = left[0]
        while True:
            right = [i for i in range(hi + 1, min(len(r), hi + 1 + g)) if r[i] > thr]
            if not right:
                break
            hi = right[-1]
    a = max(0, lo * n - int(pad * sr))
    b = min(len(x), (hi + 1) * n + int(pad * 2 * sr))
    y = x[a:b].copy()
    fi, fo = int(0.008 * sr), int(0.06 * sr)
    y[:fi] *= np.linspace(0, 1, fi)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def active_rms(x, sr):
    r, _ = frames_rms(x, sr, 0.02)
    act = r[r > r.max() * 0.15]
    return float(np.sqrt((act ** 2).mean())) if len(act) else float(r.max())


def process(path, ztype, ev, noise_mag):
    x, sr = read_wav(path)
    x -= x.mean()
    x, _ = denoise(x, noise_mag)
    v = VOICE[ztype]
    x = fft_filter(x, sr, 80.0, v["dark"])
    x = trim(x, sr)
    if v["semis"]:
        x = resample(x, 2 ** (-v["semis"] / 12.0))
    x = to_rate(x, sr, SR_OUT)
    # громкость активной части
    x *= 10 ** (LOUD.get(ev, -17) / 20) / max(active_rms(x, SR_OUT), 1e-6)
    if v["grit"]:
        d = 1.0 + 3.0 * v["grit"]
        x = (1 - v["grit"]) * x + v["grit"] * np.tanh(x * d) / d * 1.8
    # мягкий ограничитель: пики не выше −1 дБ
    lim = 10 ** (-1 / 20)
    x = np.where(np.abs(x) > lim * 0.8, np.sign(x) * (lim * 0.8 + (lim * 0.2) * np.tanh((np.abs(x) - lim * 0.8) / (lim * 0.2))), x)
    return x


def main():
    args = sys.argv[1:]
    stats = "stats" in args
    types = [a for a in args if a in VOICE] or list(VOICE)
    tone = sorted(glob.glob(os.path.join(SRC, "roomtone_*.wav")))
    noise_mag = None
    if tone:
        t, _ = read_wav(tone[-1])
        noise_mag = np.abs(stft(t - t.mean())[0]).mean(axis=0)
        print("шум по", os.path.basename(tone[-1]))
    for zt in types:
        files = sorted(glob.glob(os.path.join(SRC, zt + "_*.wav")))
        groups = {}
        for f in files:
            ev = os.path.basename(f).split("_")[1]
            groups.setdefault(ev, []).append(f)
        for ev, fs in sorted(groups.items()):
            for k, f in enumerate(fs):
                if stats:
                    x, sr = read_wav(f)
                    r, _ = frames_rms(x, sr)
                    print("%-22s %5.2f с  пик %6.1f дБ  RMS акт %6.1f  фон %6.1f  перегруз %d" % (
                        os.path.basename(f), len(x) / sr, db(np.abs(x).max()), db(active_rms(x, sr)),
                        db(np.percentile(r, 10)), int((np.abs(x) > 0.985).sum())))
                    continue
                y = process(f, zt, ev, noise_mag)
                name = "zombie_%s_%s_%d.wav" % (zt, ev, k)
                write_wav(os.path.join(OUT, name), y, SR_OUT)
                print("%-30s %5.2f с  пик %6.1f дБ" % (name, len(y) / SR_OUT, db(np.abs(y).max())))


if __name__ == "__main__":
    main()
