"""Обработка записанных звуков мира (tools/sound_recorder.html, папка assets/src/sfx_rec) -> assets/sounds/<звук>_<N>.wav.
Запуск через Blender (модуль aud читает прежние ogg/mp3, чтобы выровнять громкость по ним):
  D:\\ai3d\\blender\\blender.exe -b --python scripts/ai3d/sfx_proc.py -- [stats] [звук ...]
Без списка — все звуки, для которых есть записи. stats — только уровни сырых записей.

Новая запись заменяет прежнюю: старые файлы звука уезжают в assets/src/_backup_sounds/<звук>/. Громкость новых
подгоняется под прежние (медиана пиков для ударов, RMS для протяжных) — баланс в игре не меняется; для новых звуков —
по таблице SFX. Петли (фон): самая длинная запись, без шумоподавления, края сводятся перекрёстным затуханием."""
import os
import sys
import glob
import shutil
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_proc as vp   # noqa: E402

ROOT = vp.ROOT
SRC = os.environ.get("SFX_SRC", os.path.join(ROOT, "assets", "src", "sfx_rec"))     # переопределение — для проверки
OUT = os.environ.get("SFX_OUT", vp.OUT)
BACKUP = os.environ.get("SFX_BACKUP", os.path.join(ROOT, "assets", "src", "_backup_sounds"))
SR = vp.SR_OUT

# звук: (тип, срез низов Гц, шумоподавление, громкость по умолчанию дБ) ; тип: hit — пик, sus — RMS, loop — фон
SFX = {
    "step_grass": ("hit", 70, 1.4, -6), "step_gravel": ("hit", 70, 1.4, -6), "step_hard": ("hit", 60, 1.4, -6),
    "step_wood": ("hit", 60, 1.4, -6), "player_hurt": ("sus", 90, 1.6, -16), "swing": ("hit", 120, 1.2, -8),
    "eat": ("sus", 80, 1.4, -18), "drink": ("sus", 80, 1.4, -18),
    "hit_wood": ("hit", 50, 1.6, -3), "hit_stone": ("hit", 60, 1.6, -3), "hit_dirt": ("hit", 50, 1.6, -4),
    "hit_flesh": ("hit", 60, 1.6, -3), "rustle": ("sus", 120, 1.2, -18), "hit_metal": ("hit", 60, 1.6, -3),
    "block_break": ("hit", 50, 1.6, -3), "tree_fall": ("hit", 40, 1.4, -2),
    "gun_shot": ("hit", 40, 1.2, -1), "gun_reload": ("hit", 80, 1.6, -6), "gun_dry": ("hit", 100, 1.6, -8),
    "door_open": ("sus", 60, 1.4, -16), "door_close": ("hit", 50, 1.4, -4),
    "pickup": ("hit", 100, 1.6, -10), "loot_open": ("sus", 90, 1.4, -18),
    "wind_loop": ("loop", 30, 0.0, -24), "crickets_loop": ("loop", 300, 0.0, -24), "birds_loop": ("loop", 200, 0.0, -26),
    "crow": ("sus", 150, 1.4, -14),
}
XFADE = 2.0   # с: сведение краёв петли


def read_any(path):
    if path.endswith(".wav"):
        try:
            return vp.read_wav(path)
        except Exception:
            pass
    import aud
    s = aud.Sound(path)
    rate = int(s.specs[0])
    d = np.asarray(s.data(), dtype=np.float64)
    return (d.mean(axis=1) if d.ndim > 1 else d), rate


def old_files(sid):
    out = []
    for ext in ("ogg", "mp3", "wav"):
        out += glob.glob(os.path.join(OUT, "%s_*.%s" % (sid, ext))) + glob.glob(os.path.join(OUT, "%s.%s" % (sid, ext)))
    return [f for f in out if os.path.basename(f).rsplit(".", 1)[0][len(sid):].lstrip("_").isdigit()
            or os.path.basename(f).rsplit(".", 1)[0] == sid]


def reference(sid, kind):
    """Громкость прежних вариантов: медиана пика (hit) или RMS активной части (sus/loop), дБ."""
    vals = []
    for f in old_files(sid):
        try:
            x, sr = read_any(f)
        except Exception as e:
            print("  не прочитал", os.path.basename(f), e)
            continue
        vals.append(vp.db(np.abs(x).max()) if kind == "hit" else vp.db(vp.active_rms(x, sr)))
    return float(np.median(vals)) if vals else None


def backup_old(sid):
    fs = old_files(sid)
    if not fs:
        return 0
    d = os.path.join(BACKUP, sid)
    os.makedirs(d, exist_ok=True)
    for f in fs:
        for p in (f, f + ".import"):
            if not os.path.exists(p):
                continue
            to = os.path.join(d, os.path.basename(p))
            if os.path.exists(to):
                os.remove(p)        # оригинал уже в копии (повторная обработка) — текущий файл наш, пересоздаётся
            else:
                shutil.move(p, to)
    return len(fs)


def punch(x):
    """Выстрел: плотнее и «бахает» — подъём низов и насыщение."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    X *= 1.0 + 1.5 / (1.0 + (f / 180.0) ** 2)
    y = np.fft.irfft(X, n=len(x))
    return np.tanh(y / max(np.abs(y).max(), 1e-6) * 2.5)


def make_loop(x):
    n = int(XFADE * SR)
    cut = int(0.5 * SR)
    x = x[cut:len(x) - cut] if len(x) > 2 * cut + 3 * n else x
    if len(x) < 3 * n:
        return x
    t = np.linspace(0, np.pi / 2, n)
    head, tail = x[:n], x[-n:]
    y = x[n:].copy()                        # длина = len - n; начало y — сразу после head
    y[-n:] = tail * np.cos(t) + head * np.sin(t)   # конец плавно переходит в начало (head идёт перед y[0])
    return y


def limit(x, ceil_db=-1.0):
    lim = 10 ** (ceil_db / 20)
    k = lim * 0.8
    a = np.abs(x)
    return np.where(a > k, np.sign(x) * (k + (lim - k) * np.tanh((a - k) / (lim - k))), x)


MIN_SNR = 14.0   # дБ: пик дубля над фоном комнаты; тише — после подъёма громкости останется шипение, дубль пропускаем


def snr(path):
    x, sr = vp.read_wav(path)
    r, _ = vp.frames_rms(x - x.mean(), sr)
    return vp.db(np.abs(x - x.mean()).max()) - vp.db(np.percentile(r, 10))


def process(sid, files, noise_mag):
    kind, hp, dn, default = SFX.get(sid, ("hit", 60, 1.4, -4))
    if kind != "loop":
        good = [f for f in files if snr(f) >= MIN_SNR]
        for f in files:
            if f not in good:
                print("  пропущен (тихо, %.0f дБ над фоном): %s" % (snr(f), os.path.basename(f)))
        if not good:
            print("%-14s все дубли слишком тихие — остаётся прежний звук" % sid)
            return None
        files = good
    ref = reference(sid, kind)
    target = ref if ref is not None else default
    if kind == "loop":
        files = [max(files, key=os.path.getsize)]
    outs = []
    for f in files:
        x, sr = vp.read_wav(f)
        x -= x.mean()
        if dn > 0:
            x, _ = vp.denoise(x, noise_mag, strength=dn)
        x = vp.fft_filter(x, sr, hp, 0.0)
        if kind != "loop":
            x = vp.trim(x, sr, -42.0 if kind == "sus" else -36.0, main_only=True,
                        gap=0.45 if sid in ("eat", "drink", "loot_open") else (0.25 if kind == "sus" else 0.1))
        x = vp.to_rate(x, sr, SR)
        if sid == "gun_shot":
            x = punch(x)
        if kind == "loop":
            x = make_loop(x)
        if kind == "hit":
            x *= 10 ** (target / 20) / max(np.abs(x).max(), 1e-6)
        else:
            x *= 10 ** (target / 20) / max(vp.active_rms(x, SR), 1e-6)
        outs.append(limit(x))
    moved = backup_old(sid)
    for k, y in enumerate(outs):
        vp.write_wav(os.path.join(OUT, "%s_%d.wav" % (sid, k)), y, SR)
        print("    %s_%d.wav  %.2f с" % (sid, k, len(y) / SR))
    print("%-14s %2d зап. -> %d файлов, громкость %s %.1f дБ%s" % (
        sid, len(files), len(outs), "пик" if kind == "hit" else "RMS", target,
        " (как у прежних, старые %d -> _backup_sounds)" % moved if ref is not None else " (по таблице, новый звук)"))
    return sid


def note_sources(sids):
    p = os.path.join(OUT, "SOURCES.txt")
    lines = open(p, encoding="utf-8").read().splitlines() if os.path.exists(p) else []
    prefix = "Свои записи (tools/sound_recorder.html, scripts/ai3d/sfx_proc.py): "
    old = next((l for l in lines if l.startswith(prefix)), None)
    have = set(old[len(prefix):].split(", ")) if old else set()
    have |= set(sids)
    lines = [l for l in lines if not l.startswith(prefix)] + [prefix + ", ".join(sorted(have))]
    open(p, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stats = "stats" in args
    want = [a for a in args if a != "stats"]
    files = sorted(glob.glob(os.path.join(SRC, "*.wav")))
    groups = {}
    for f in files:
        b = os.path.basename(f)[:-4]
        sid, _, num = b.rpartition("_")
        if sid and num.isdigit() and not sid.startswith("roomtone"):
            groups.setdefault(sid, []).append(f)
    if want:
        groups = {k: v for k, v in groups.items() if k in want}
    if not groups:
        print("Нет записей в", SRC)
        return
    tone = sorted(glob.glob(os.path.join(SRC, "roomtone_*.wav")))
    noise_mag = None
    if tone:
        t, _ = vp.read_wav(tone[-1])
        noise_mag = np.abs(vp.stft(t - t.mean())[0]).mean(axis=0)
        print("шум по", os.path.basename(tone[-1]))
    done = []
    for sid, fs in sorted(groups.items()):
        if sid not in SFX:
            print("?? неизвестный звук", sid, "— пропущен")
            continue
        if stats:
            for f in fs:
                x, sr = vp.read_wav(f)
                r, _ = vp.frames_rms(x, sr)
                print("%-22s %5.2f с  пик %6.1f дБ  RMS %6.1f  фон %6.1f  перегруз %d" % (
                    os.path.basename(f), len(x) / sr, vp.db(np.abs(x).max()), vp.db(vp.active_rms(x, sr)),
                    vp.db(np.percentile(r, 10)), int((np.abs(x) > 0.985).sum())))
            continue
        r = process(sid, fs, noise_mag)
        if r:
            done.append(r)
    if done:
        note_sources(done)


main()
