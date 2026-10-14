"""prompt -> image (ComfyUI) -> background removed PNG (rembg isnet, CPU).
Usage: gen_image.py [objects.json] [--only name] [--seed N] [--force]
Requires ComfyUI running on 127.0.0.1:8188. Run with the ComfyUI venv python."""
import argparse, json, os, random, sys, time, urllib.request, urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WF = ROOT / "workflows" / "txt2img_api.json"
OUT = ROOT / "assets" / "ai3d_src"
HOST = "http://127.0.0.1:8188"
os.environ.setdefault("U2NET_HOME", r"D:\ai3d\cache\u2net")
os.environ.setdefault("MODEL_CHECKSUM_DISABLED", "1")  # isnet-general-use from an HF mirror, md5 differs from rembg's pin


def api(path, data=None):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode() if data else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def render(prompt, seed, dst, timeout=3600):
    wf = json.loads(WF.read_text(encoding="utf-8"))
    wf["2"]["inputs"]["text"] = prompt
    wf["5"]["inputs"]["seed"] = seed
    pid = api("/prompt", {"prompt": wf})["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        h = api("/history/" + pid)
        if pid in h and h[pid].get("status", {}).get("completed") is not None:
            st = h[pid]["status"]
            if st.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI error: {st}")
            im = h[pid]["outputs"]["7"]["images"][0]
            url = "/view?" + urllib.parse.urlencode(
                {"filename": im["filename"], "subfolder": im["subfolder"], "type": im["type"]})
            with urllib.request.urlopen(HOST + url) as r:
                dst.write_bytes(r.read())
            return
        time.sleep(3)
    raise TimeoutError(dst.name)


def remove_bg(src, dst):
    from rembg import new_session, remove
    from PIL import Image
    out = remove(Image.open(src).convert("RGB"), session=new_session("isnet-general-use"))
    out.save(dst)
    a = out.split()[3]
    return a.getbbox(), sum(1 for v in a.getdata() if v > 128) / (out.width * out.height)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("objects", nargs="?", default=str(ROOT / "objects.json"))
    ap.add_argument("--only")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for o in json.loads(Path(a.objects).read_text(encoding="utf-8")):
        if a.only and o["name"] != a.only:
            continue
        color, nobg = OUT / f"{o['name']}_color.png", OUT / f"{o['name']}_nobg.png"
        if nobg.exists() and not a.force:
            print("skip", o["name"]); continue
        seed = a.seed if a.seed is not None else o.get("seed", random.randrange(2**32))
        print("gen", o["name"], "seed", seed, flush=True)
        if not color.exists() or a.force:
            render(o["prompt"], seed, color)
        bbox, cov = remove_bg(color, nobg)
        print(f"-> {nobg} bbox={bbox} coverage={cov:.3f}")


if __name__ == "__main__":
    sys.exit(main())
