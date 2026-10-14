"""Blender: модель со Sketchfab -> блок-модель для построек (BlockShapes «model»).
Сливает меши (материалы сохраняются), равномерно масштабирует под ширину footprint (ось X), ставит в систему
якоря блока: X 0..W, низ на 0, по глубине — по центру клетки(ок). Оси Godot: X вправо, Y вверх, Z — глубина
(= -Y Blender). Текстуры пережимаются в JPEG (max_tex — предельный размер).
Usage: blender -b -P prop_prep.py -- <in.glb> <out.glb> width=2 depth=1 [max_tex=1024] [rot=0] [preview_prefix=...]"""
import sys
import math
import bpy
import numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
opt = dict(a.split("=", 1) for a in args[2:] if "=" in a)
W = float(opt.get("width", 1))
D = float(opt.get("depth", 1))
MAX_TEX = int(opt.get("max_tex", 1024))
ROT = float(opt.get("rot", 0))            # поворот вокруг вертикали (градусы) до подгонки — если «перед» модели не туда
prev = opt.get("preview_prefix", "")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
meshes = [o for o in sc.objects if o.type == "MESH"]
# применить трансформации родителей и слить в один объект
for o in meshes:
    o.data = o.data.copy()
    o.data.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = opt.get("name", "model")
if ROT:
    ob.data.transform(Matrix.Rotation(math.radians(ROT), 4, "Z"))
V = np.array([v.co[:] for v in ob.data.vertices])
mn, mx = V.min(axis=0), V.max(axis=0)
k = W / (mx[0] - mn[0])
# в Blender: X 0..W, Z от 0, по Y центр в -D/2 (после экспорта Y-up это Z Godot = +D/2)
cy = (mn[1] + mx[1]) * 0.5
ob.data.transform(Matrix.Translation(Vector((-mn[0] * k, -cy * k - D * 0.5, -mn[2] * k))) @ Matrix.Scale(k, 4))
ob.data.update()
V = np.array([v.co[:] for v in ob.data.vertices])
mn, mx = V.min(axis=0), V.max(axis=0)
print("SCALE", round(k, 4), "faces", len(ob.data.polygons))
# габариты в осях Godot (x, y, z) = (x, z, -y)
print("GODOT_BOX min", (round(mn[0], 3), round(mn[2], 3), round(-mx[1], 3)), "max", (round(mx[0], 3), round(mx[2], 3), round(-mn[1], 3)))
# слои по высоте: глубина модели в нижней/верхней половине (для коробок столкновений)
for z0, z1 in ((0.0, 0.5), (0.5, 1.0), (1.0, 1.5), (1.5, 2.5)):
    m = (V[:, 2] >= z0) & (V[:, 2] < z1)
    if m.any():
        print("LAYER y %.1f-%.1f  z %.3f..%.3f" % (z0, z1, -V[m, 1].max(), -V[m, 1].min()))

for img in bpy.data.images:
    if img.size[0] > MAX_TEX:
        img.scale(MAX_TEX, MAX_TEX)

if prev:
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 700
    sc.render.resolution_y = 500
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = max(W, mx[2]) * 1.3
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    c = Vector(((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mx[2] / 2))
    for view, off, rot in (("front", Vector((0, -6, 0)), (1.5708, 0, 0)), ("side", Vector((6, 0, 0)), (1.5708, 0, 1.5708)),
                           ("persp", Vector((4, -5, 3)), None)):
        cam.location = c + off
        if rot:
            cam.rotation_euler = rot
        else:
            d = c - cam.location
            cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{prev}_{view}.png"
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)

bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=85)
print("EXPORTED", out)
