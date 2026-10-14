"""image (bg removed RGBA) -> textured .glb via Stable Fast 3D.
Usage: gen_mesh.py [objects.json] [--only name] [--force] [--device cuda|cpu] [--tex 1024]
Run with the SF3D venv python. ComfyUI must NOT be running (6 GB VRAM)."""
import argparse, json, os, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SF3D_DIR = Path(r"D:\ai3d\stable-fast-3d")
SRC = ROOT / "assets" / "ai3d_src"
RAW = ROOT / "assets" / "raw"
os.environ.setdefault("HF_HOME", r"D:\ai3d\cache\hf")
os.environ.setdefault("TORCH_HOME", r"D:\ai3d\cache\torch")
sys.path.insert(0, str(SF3D_DIR))

import torch  # noqa: E402
from PIL import Image  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("objects", nargs="?", default=str(ROOT / "objects.json"))
    ap.add_argument("--only")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--tex", type=int, default=1024)
    ap.add_argument("--remesh", default="none", choices=["none", "triangle", "quad"])
    ap.add_argument("--fg-ratio", type=float, default=0.85)
    a = ap.parse_args()

    from sf3d.system import SF3D
    from sf3d.utils import resize_foreground

    device = a.device if (a.device != "cuda" or torch.cuda.is_available()) else "cpu"
    RAW.mkdir(parents=True, exist_ok=True)
    todo = [o for o in json.loads(Path(a.objects).read_text(encoding="utf-8"))
            if (not a.only or o["name"] == a.only)
            and (a.force or not (RAW / f"{o['name']}.glb").exists())]
    if not todo:
        print("nothing to do"); return 0

    print("device", device, flush=True)
    model = SF3D.from_pretrained("stabilityai/stable-fast-3d", config_name="config.yaml",
                                 weight_name="model.safetensors")
    model.to(device).eval()
    if device == "cuda":
        # texture_baker is built CPU-only (no CUDA Toolkit): bake on CPU, keep inference on GPU
        b = model.baker
        rasterize, interpolate = b.rasterize, b.interpolate
        b.rasterize = lambda uv, fi, res: rasterize(uv.cpu(), fi.cpu(), res).to(uv.device)
        b.interpolate = lambda attr, rast, fi: interpolate(attr.cpu(), rast.cpu(), fi.cpu()).to(attr.device)

    for o in todo:
        src = SRC / f"{o['name']}_nobg.png"
        img = resize_foreground(Image.open(src).convert("RGBA"), a.fg_ratio)
        t0 = time.time()
        with torch.no_grad():  # fp32: Pascal has no bf16
            mesh, _ = model.run_image([img], bake_resolution=a.tex, remesh=a.remesh,
                                      vertex_count=-1)
        out = RAW / f"{o['name']}.glb"
        mesh.export(str(out), include_normals=True)
        peak = torch.cuda.max_memory_allocated() / 2**20 if device == "cuda" else 0
        print(f"-> {out} {time.time() - t0:.0f}s peak_vram={peak:.0f}MB", flush=True)
        if device == "cuda":
            torch.cuda.empty_cache()
    return 0


if __name__ == "__main__":
    sys.exit(main())
