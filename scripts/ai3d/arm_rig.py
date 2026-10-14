"""Blender, шаг 2: скелет руки (предплечье, кисть, 4 пальца x 3 фаланги, большой палец x 3) и веса для руки Meshy.
Вход — выровненный arm_align.py .blend (пальцы +Z, тыл кисти +X, большой палец -Y). На выходе GLB в системе HandRig:
начало — запястье, пальцы -Z, ладонь -X, большой палец +Y, метры.
Веса: вершина достаётся ближайшей кости и плавно смешивается только с соседями по своей цепочке
(иначе соседние пальцы тянут друг друга).
Usage: blender -b <aligned.blend> -P arm_rig.py -- <out.glb>"""
import sys
import bpy
import numpy as np
from mathutils import Vector, Matrix

out = sys.argv[sys.argv.index("--") + 1]

# суставы в выровненном пространстве (сняты с ортопроекций, 5000 px/м), x — к тылу кисти
W = (-0.005, -0.002, 0.135)          # запястье
E = (0.0, 0.0, -0.17)                # локоть (край манжеты)
FINGERS = {
    "index": [(0.006, -0.008, 0.204), (0.014, -0.009, 0.234), (0.019, -0.013, 0.258), (0.022, -0.014, 0.276)],
    "middle": [(0.006, 0.009, 0.204), (0.011, 0.015, 0.240), (0.013, 0.015, 0.260), (0.013, 0.015, 0.281)],
    "ring": [(0.006, 0.023, 0.206), (0.004, 0.032, 0.234), (0.001, 0.036, 0.254), (0.000, 0.037, 0.274)],
    "pinky": [(0.004, 0.034, 0.206), (-0.004, 0.038, 0.222), (-0.011, 0.042, 0.236), (-0.018, 0.044, 0.250)],
}
THUMB = [(-0.008, -0.028, 0.156), (0.000, -0.040, 0.180), (0.006, -0.054, 0.202), (0.007, -0.061, 0.221)]


def tr(p):
    # поворот на 180° вокруг X и перенос: запястье в начало координат
    return Vector((p[0] - W[0], -(p[1] - W[1]), -(p[2] - W[2])))


ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
# сетку — в систему HandRig
ob.data.transform(Matrix.Translation(Vector((-W[0], -W[1], -W[2]))))
ob.data.transform(Matrix.Rotation(np.pi, 4, "X"))
ob.data.update()

# кости: имя -> (голова, хвост, родитель)
bones = {"arm": (tr(E), tr(W), None), "hand": (tr(W), tr(FINGERS["middle"][0]), "arm")}
chains = {"arm": ["arm", "hand"]}
for fn, pts in FINGERS.items():
    names = []
    for k in range(3):
        nm = "%s_%d" % (fn, k + 1)
        bones[nm] = (tr(pts[k]), tr(pts[k + 1]), "hand" if k == 0 else "%s_%d" % (fn, k))
        names.append(nm)
    chains[fn] = names
names = []
for k in range(3):
    nm = "thumb_%d" % (k + 1)
    bones[nm] = (tr(THUMB[k]), tr(THUMB[k + 1]), "hand" if k == 0 else "thumb_%d" % k)
    names.append(nm)
chains["thumb"] = names

arm_data = bpy.data.armatures.new("ArmRig")
rig = bpy.data.objects.new("ArmRig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for nm, (h, t, par) in bones.items():
    b = arm_data.edit_bones.new(nm)
    b.head = h
    b.tail = t
    # ролл: ось Z кости — к тылу кисти (+X), чтобы сгиб был поворотом вокруг одной оси
    b.align_roll(Vector((1, 0, 0)))
    eb[nm] = b
for nm, (h, t, par) in bones.items():
    if par:
        eb[nm].parent = eb[par]
        eb[nm].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# --- веса ---
names = list(bones.keys())
heads = np.array([bones[n][0][:] for n in names])
tails = np.array([bones[n][1][:] for n in names])
V = np.array([v.co[:] for v in ob.data.vertices])


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
    q = a + t[:, None] * ab[None, :]
    return np.linalg.norm(P - q, axis=1)


D = np.stack([seg_dist(V, heads[i], tails[i]) for i in range(len(names))], axis=1)
# кисть шире своей кости: ладонь/тыл — до 4 см от оси; предплечье — толстое
D[:, names.index("hand")] *= 0.55
D[:, names.index("arm")] *= 0.6
near = np.argmin(D, axis=1)
neigh = {n: {n} for n in names}
for n, (h, t, par) in bones.items():
    if par:
        neigh[n].add(par)
        neigh[par].add(n)
idx = {n: i for i, n in enumerate(names)}
for g in list(ob.vertex_groups):
    ob.vertex_groups.remove(g)
groups = {n: ob.vertex_groups.new(name=n) for n in names}
for vi in range(len(V)):
    b0 = names[near[vi]]
    cand = set(neigh[b0])
    # у кисти соседи — все пальцы: берём только ближайший палец, чтобы ладонь не тянулась за всеми сразу
    if b0 == "hand" or names[near[vi]] in ("index_1", "middle_1", "ring_1", "pinky_1", "thumb_1"):
        fingers1 = [c for c in cand if c.endswith("_1")]
        if fingers1:
            best = min(fingers1, key=lambda c: D[vi, idx[c]])
            cand = {c for c in cand if not c.endswith("_1") or c == best}
    ws = {c: 1.0 / (D[vi, idx[c]] + 0.002) ** 4 for c in cand}
    s = sum(ws.values())
    for c, w in ws.items():
        w /= s
        if w > 0.02:
            groups[c].add([vi], w, "REPLACE")
ob.parent = rig
mod = ob.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print("RIG bones", len(names), "verts", len(V))
for n in names:
    print("BONE", n, tuple(round(x, 4) for x in bones[n][0]), "->", tuple(round(x, 4) for x in bones[n][1]))

bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_skins=True,
                          export_animations=False, export_yup=False, export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED", out)

# исходник для ручной правки (кости, веса) в Blender
if "--save" in sys.argv:
    save_path = sys.argv[sys.argv.index("--save") + 1]
    for o in list(bpy.context.scene.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o)
    bpy.ops.wm.save_as_mainfile(filepath=save_path)
    print("SAVED", save_path)

# проверка весов: кулак (сгиб всех фаланг к ладони) — превью с тыла и с ладони
if "--posetest" in sys.argv:
    prefix = sys.argv[sys.argv.index("--posetest") + 1]
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        if pb.name.startswith(("index", "middle", "ring", "pinky")):
            pb.rotation_euler = (float(sys.argv[sys.argv.index("--posetest") + 2]), 0, 0)
        elif pb.name.startswith("thumb"):
            pb.rotation_euler = (float(sys.argv[sys.argv.index("--posetest") + 2]) * 0.6, 0, 0)
    bpy.ops.object.mode_set(mode="OBJECT")
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 700
    sc.render.resolution_y = 700
    cd = bpy.data.cameras.new("pc")
    cd.type = "ORTHO"
    cd.ortho_scale = 0.24
    cam = bpy.data.objects.new("pc", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, loc, rot in [("dorsal", (1.0, 0.0, -0.07), (0.0, 1.5708, 0.0)), ("side", (0.0, 1.0, -0.07), (-1.5708, 0.0, 0.0))]:
        cam.location = loc
        cam.rotation_euler = rot
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)
