"""Blender: пистолет со Sketchfab (pistol 9mm, DJMaesen, CC-BY 4.0) -> оружие от первого лица для Godot.
Запекает позу скелета в геометрию, оставляет один экземпляр (детали без суффикса _2), переводит в оси игры:
ствол вдоль -Z Godot (= +Y Blender), верх +Z Blender, начало координат — середина рукояти (место хвата), длина 0.2 м.
Детали остаются отдельными объектами: base, slide, mag, bullet, trigger, hammer (затвор и магазин анимируются в игре).
Usage: blender -b -P pistol_prep.py -- <in.glb> <out.glb> [preview_prefix]"""
import sys
import math
import bpy
import numpy as np
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
prev = a[2] if len(a) > 2 else ""
LENGTH = 0.2

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
dg = bpy.context.evaluated_depsgraph_get()

# новые объекты из деформированной геометрии (поза скелета + все трансформации), исходные — удалить
parts = {}
for o in [o for o in sc.objects if o.type == "MESH"]:
    nm = o.name.split("_HIpistol")[0]
    if nm.endswith("_2"):
        continue
    eo = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(eo, preserve_all_data_layers=True, depsgraph=dg)
    me.transform(o.matrix_world)
    no = bpy.data.objects.new(nm, me)
    parts[nm] = no
for o in list(sc.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for no in parts.values():
    sc.collection.objects.link(no)


def bbox(objs):
    v = np.concatenate([np.array([x.co[:] for x in o.data.vertices]) for o in objs])
    return v.min(axis=0), v.max(axis=0)


for nm, o in parts.items():
    mn, mx = bbox([o])
    print("PART", nm, "min", np.round(mn, 2), "max", np.round(mx, 2))

# ось ствола — самая длинная ось затвора; дуло — конец затвора, дальний от рукояти (магазина)
smn, smx = bbox([parts["slide"]])
ax = int(np.argmax(smx - smn))
mmn, mmx = bbox([parts["mag"]])
mag_c = (mmn + mmx) * 0.5
s_c = (smn + smx) * 0.5
fwd = Vector((0, 0, 0))
fwd[ax] = 1.0 if (s_c[ax] - mag_c[ax]) > 0 else -1.0     # от рукояти к дулу
# вверх: от магазина к затвору (перпендикулярно стволу)
up = Vector((s_c - mag_c))
up[ax] = 0.0
up.normalize()
print("AXES fwd", tuple(fwd), "up", tuple(up))
# базис: fwd -> +Y Blender, up -> +Z Blender
right = fwd.cross(up)
R = Matrix((right, fwd, up))           # строки: проекции на новые оси
allmn, allmx = bbox(list(parts.values()))
length = float(smx[ax] - smn[ax])
k = LENGTH / length
# центр хвата — середина рукояти: по высоте между низом затвора и низом рамки, по стволу — центр магазина
bmn, bmx = bbox([parts["base"]])
grip = Vector(mag_c)
grip_h = (float(np.dot(np.array(up), smn)) if False else None)
M = Matrix.Scale(k, 4) @ R.to_4x4()
for o in parts.values():
    o.data.transform(M)
# начало координат: по стволу — центр магазина (в верхней части рукояти), по высоте — чуть ниже затвора
mn2, mx2 = bbox([parts["mag"]])
smn2, smx2 = bbox([parts["slide"]])
origin = Vector(((mn2[0] + mx2[0]) * 0.5, (mn2[1] + mx2[1]) * 0.5, smn2[2] - 0.035))
for o in parts.values():
    o.data.transform(Matrix.Translation(-origin))
    o.data.update()
smn3, smx3 = bbox([parts["slide"]])
print("SLIDE after", np.round(smn3, 3), np.round(smx3, 3))
print("MUZZLE", (0.0, round(float(smx3[1]), 4), round(float((smn3[2] + smx3[2]) * 0.5), 4)))
for nm, o in parts.items():
    mn, mx = bbox([o])
    print("FINAL", nm, np.round(mn, 3), np.round(mx, 3), "verts", len(o.data.vertices))

if prev:
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 600
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = 0.3
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for view, loc, rot in (("side", (0.6, 0.03, 0.0), (math.pi / 2, 0, math.pi / 2)), ("back", (0.0, -0.6, 0.02), (math.pi / 2, 0, 0))):
        cam.location = loc
        cam.rotation_euler = rot
        sc.render.filepath = f"{prev}_{view}.png"
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED", out)
