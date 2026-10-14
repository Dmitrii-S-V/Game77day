"""Blender: пересчёт весов руки по ТЕКУЩЕМУ положению костей в assets/src/arm_rig.blend (после ручной правки суставов),
сохранение .blend и экспорт в игру.
Вершина достаётся ближайшей кости и плавно смешивается только с соседями по своей цепочке (родитель/ребёнок),
у кисти — только с ближайшим пальцем: соседние пальцы не тянут друг друга.
Usage: blender -b D:/77Days/assets/src/arm_rig.blend -P arm_reweight.py"""
import bpy
import numpy as np

rig = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]

# позу — в покой, чтобы веса считались по исходной форме
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.scale = (1, 1, 1)

bones = rig.data.bones
names = [b.name for b in bones]
mw = rig.matrix_world
mi = ob.matrix_world.inverted()
heads = np.array([(mi @ (mw @ b.head_local))[:] for b in bones])
tails = np.array([(mi @ (mw @ b.tail_local))[:] for b in bones])
parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
V = np.array([v.co[:] for v in ob.data.vertices])


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
    q = a + t[:, None] * ab[None, :]
    return np.linalg.norm(P - q, axis=1)


D = np.stack([seg_dist(V, heads[i], tails[i]) for i in range(len(names))], axis=1)
if "hand" in names:
    D[:, names.index("hand")] *= 0.55
if "arm" in names:
    D[:, names.index("arm")] *= 0.6
near = np.argmin(D, axis=1)
neigh = {n: {n} for n in names}
for n, p in parent.items():
    if p:
        neigh[n].add(p)
        neigh[p].add(n)
idx = {n: i for i, n in enumerate(names)}
for g in list(ob.vertex_groups):
    ob.vertex_groups.remove(g)
groups = {n: ob.vertex_groups.new(name=n) for n in names}
for vi in range(len(V)):
    b0 = names[near[vi]]
    cand = set(neigh[b0])
    if b0 == "hand" or b0.endswith("_1"):
        f1 = [c for c in cand if c.endswith("_1")]
        if f1:
            best = min(f1, key=lambda c: D[vi, idx[c]])
            cand = {c for c in cand if not c.endswith("_1") or c == best}
    ws = {c: 1.0 / (D[vi, idx[c]] + 0.002) ** 4 for c in cand}
    s = sum(ws.values())
    for c, w in ws.items():
        w /= s
        if w > 0.02:
            groups[c].add([vi], w, "REPLACE")
print("REWEIGHT verts", len(V), "bones", len(names))
bpy.ops.wm.save_mainfile()
for o in bpy.context.scene.objects:
    o.select_set(o.type in ("MESH", "ARMATURE"))
bpy.ops.export_scene.gltf(filepath="D:/77Days/assets/ready/arm_fp.glb", export_format="GLB", use_selection=True,
                          export_skins=True, export_animations=False, export_yup=False,
                          export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED arm_fp.glb")
