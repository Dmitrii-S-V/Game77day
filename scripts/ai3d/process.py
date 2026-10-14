"""raw .glb -> Blender (decimate, normals, fit to cells, origin, previews) -> assets/ready.
Usage: process.py [objects.json] [--only name]   (stdlib only, any python)"""
import argparse, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path(r"D:\ai3d\blender\blender.exe")
SCRIPT = ROOT / "scripts" / "ai3d" / "blender_process.py"


def process(o):
    src = ROOT / "assets" / "raw" / f"{o['name']}.glb"
    dst = ROOT / "assets" / "ready" / f"{o['name']}.glb"
    prev = ROOT / "assets" / "preview" / o["name"]
    for p in (dst.parent, prev.parent):
        p.mkdir(parents=True, exist_ok=True)
    cx, cy, cz = o["cells"]
    # headless Workbench needs a GPU backend: OpenGL has no context in -b here, Vulkan works
    r = subprocess.run([str(BLENDER), "-b", "--gpu-backend", "vulkan", "-P", str(SCRIPT), "--", str(src), str(dst),
                        o["kind"], str(cx), str(cy), str(cz), str(prev)],
                       capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.startswith(("RESULT", "PREVIEWS", "EMPTY"))]
    if r.returncode != 0 or not dst.exists():
        raise RuntimeError((r.stderr or r.stdout)[-1500:])
    print(o["name"], *lines)
    return dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("objects", nargs="?", default=str(ROOT / "objects.json"))
    ap.add_argument("--only")
    a = ap.parse_args()
    for o in json.loads(Path(a.objects).read_text(encoding="utf-8")):
        if not a.only or o["name"] == a.only:
            process(o)


if __name__ == "__main__":
    sys.exit(main())
