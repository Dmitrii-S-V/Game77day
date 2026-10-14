"""Batch pipeline: objects.json -> image (ComfyUI) -> mesh (SF3D) -> Blender -> check -> Godot import.
Usage: run_batch.py [objects.json] [--only a,b] [--attempts 3] [--no-import]
Bad results (flagged by check.py or failed steps) are regenerated with a new seed, max N attempts.
ComfyUI and SF3D never run at the same time (6 GB VRAM): ComfyUI is started/stopped here.
Writes batch_log.md in the project root. Run with any python (stdlib only)."""
import argparse, json, os, random, subprocess, sys, time, urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
S = ROOT / "scripts" / "ai3d"
PY_COMFY = r"D:\ai3d\ComfyUI\venv\Scripts\python.exe"
PY_SF3D = r"D:\ai3d\stable-fast-3d\venv\Scripts\python.exe"
LOG = ROOT / "batch_log.md"
TMP = ROOT / "assets" / "ai3d_src" / "_batch.json"


def log(line):
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def comfy_start():
    env = dict(os.environ, HF_HOME=r"D:\ai3d\cache\hf", TORCH_HOME=r"D:\ai3d\cache\torch")
    p = subprocess.Popen([PY_COMFY, "main.py", "--force-fp32", "--lowvram", "--disable-pinned-memory",
                          "--disable-auto-launch", "--listen", "127.0.0.1", "--port", "8188"],
                         cwd=r"D:\ai3d\ComfyUI", env=env,
                         stdout=open(ROOT / "assets" / "ai3d_src" / "_comfy.log", "w"), stderr=subprocess.STDOUT)
    for _ in range(300):
        try:
            urllib.request.urlopen("http://127.0.0.1:8188/system_stats", timeout=2)
            return p
        except Exception:
            if p.poll() is not None:
                raise RuntimeError("ComfyUI exited at startup")
            time.sleep(3)
    raise TimeoutError("ComfyUI did not start")


def comfy_stop(p):
    subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
    p.wait()
    time.sleep(3)  # let the driver release VRAM


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("objects", nargs="?", default=str(ROOT / "objects.json"))
    ap.add_argument("--only")
    ap.add_argument("--attempts", type=int, default=3)
    ap.add_argument("--no-import", action="store_true")
    a = ap.parse_args()

    objs = json.loads(Path(a.objects).read_text(encoding="utf-8"))
    if a.only:
        names = set(a.only.split(","))
        objs = [o for o in objs if o["name"] in names]
    log(f"\n## Batch {datetime.now():%Y-%m-%d %H:%M} ({len(objs)} objects)")

    pending = {o["name"]: o for o in objs}
    attempts = {n: 0 for n in pending}
    done, failed = [], {}
    seeds = {}

    while pending:
        cur = list(pending.values())
        for o in cur:
            attempts[o["name"]] += 1
            seeds[o["name"]] = o["seed"] if attempts[o["name"]] == 1 and "seed" in o else random.randrange(2**32)
        TMP.write_text(json.dumps(cur), encoding="utf-8")

        # A: images (ComfyUI only)
        errs = {}
        comfy = comfy_start()
        try:
            for o in cur:
                r = run([PY_COMFY, str(S / "gen_image.py"), str(TMP), "--only", o["name"],
                         "--seed", str(seeds[o["name"]]), "--force"])
                if r.returncode != 0:
                    errs[o["name"]] = "gen_image: " + r.stderr[-400:]
        finally:
            comfy_stop(comfy)
        ok = [o for o in cur if o["name"] not in errs]

        # B: meshes (SF3D only)
        if ok:
            TMP.write_text(json.dumps(ok), encoding="utf-8")
            for o in ok:
                r = run([PY_SF3D, "-W", "ignore", str(S / "gen_mesh.py"), str(TMP), "--only", o["name"], "--force"])
                if r.returncode != 0:
                    errs[o["name"]] = "gen_mesh: " + r.stderr[-400:]

        # C: Blender + check
        for o in cur:
            n = o["name"]
            if n in errs:
                continue
            r = run([PY_SF3D, str(S / "process.py"), str(TMP), "--only", n])
            if r.returncode != 0:
                errs[n] = "blender: " + r.stderr[-400:]
                continue
            r = run([PY_SF3D, "-W", "ignore", str(S / "check.py"), str(TMP), "--only", n])
            if r.returncode != 0:
                errs[n] = "check: " + r.stdout.strip()[-400:]
                (ROOT / "assets" / "ready" / f"{n}.glb").unlink(missing_ok=True)

        for o in cur:
            n = o["name"]
            if n not in errs:
                log(f"- OK {n} (attempt {attempts[n]}, seed {seeds[n]})")
                done.append(n); pending.pop(n)
            elif attempts[n] >= a.attempts:
                log(f"- FAILED {n} after {attempts[n]} attempts: {errs[n]}")
                failed[n] = errs[n]; pending.pop(n)
            else:
                log(f"- REGEN {n} (attempt {attempts[n]}, seed {seeds[n]}): {errs[n]}")

    TMP.unlink(missing_ok=True)
    if done and not a.no_import:
        r = run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(S / "import_godot.ps1")])
        log(f"- godot import exit={r.returncode}")
    log(f"Summary: ready={len(done)} failed={len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
