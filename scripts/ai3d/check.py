"""Report for assets/ready/*.glb: triangles, size (m, Godot axes), UV, texture, flags.
Usage: check.py [objects.json] [--only name] ; exit code 1 if any model is flagged.
Needs trimesh + numpy + PIL (SF3D venv python)."""
import argparse, json, sys
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parents[2]
BUDGETS = {"prop_small": 2000, "prop_medium": 5000, "prop_large": 12000}
MARGIN = 0.05
TOL = 0.02


def check(o):
    path = ROOT / "assets" / "ready" / f"{o['name']}.glb"
    if not path.exists():
        return None, ["MISSING"]
    scene = trimesh.load(str(path), force="scene")
    geoms = [g for g in scene.geometry.values() if isinstance(g, trimesh.Trimesh)]
    if not geoms:
        return None, ["EMPTY"]
    tris = sum(len(g.faces) for g in geoms)
    lo, hi = scene.bounds
    size = hi - lo  # glTF: x, y-up, z
    has_uv = all(getattr(g.visual, "uv", None) is not None and len(g.visual.uv) > 0 for g in geoms)
    tex, tex_mean = False, None
    for g in geoms:
        m = getattr(g.visual, "material", None)
        img = getattr(m, "baseColorTexture", None) if m is not None else None
        if img is not None:
            tex = True
            arr = np.asarray(img.convert("RGB"), dtype=np.float32)
            tex_mean = float(arr.mean())
    flags = []
    if tris == 0:
        flags.append("EMPTY")
    if tris > BUDGETS.get(o["kind"], 5000):
        flags.append(f"OVER_BUDGET>{BUDGETS.get(o['kind'], 5000)}")
    cx, cy, cz = o["cells"]
    for axis, s, c in zip("xyz", size, (cx, cy, cz)):
        if s > c + TOL:
            flags.append(f"TOO_BIG_{axis}({s:.2f}>{c})")
    if max(size[0] / cx, size[1] / cy, size[2] / cz) < 0.5:
        flags.append("TOO_SMALL")
    if abs(lo[1]) > 0.01:
        flags.append(f"NOT_ON_GROUND(y_min={lo[1]:.3f})")
    if not has_uv:
        flags.append("NO_UV")
    if not tex:
        flags.append("NO_TEXTURE")
    elif tex_mean is not None and tex_mean < 8:
        flags.append("BLACK_TEXTURE")
    info = dict(tris=tris, size=tuple(round(float(v), 3) for v in size),
                y_min=round(float(lo[1]), 3), uv=has_uv, texture=tex,
                tex_mean=None if tex_mean is None else round(tex_mean, 1))
    return info, flags


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("objects", nargs="?", default=str(ROOT / "objects.json"))
    ap.add_argument("--only")
    a = ap.parse_args()
    bad = False
    for o in json.loads(Path(a.objects).read_text(encoding="utf-8")):
        if a.only and o["name"] != a.only:
            continue
        info, flags = check(o)
        status = "OK" if not flags else "FLAGGED: " + ", ".join(flags)
        print(f"{o['name']} [{o['kind']}, cells={o['cells']}] {info} -> {status}")
        bad |= bool(flags)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
