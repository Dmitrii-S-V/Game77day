"""Blender: превью частей GLB оружия сбоку (каждая часть своим цветом) — понять, что затвор, что рамка.
Usage: blender -b -P pistol_preview.py -- <in.glb> <out_prefix>"""
import sys
import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.resolution_x = 900
sc.render.resolution_y = 600
meshes = [o for o in sc.objects if o.type == "MESH"]
cols = [(0.9, 0.2, 0.2, 1), (0.2, 0.5, 0.9, 1), (0.2, 0.8, 0.3, 1), (0.9, 0.8, 0.2, 1)]
for i, o in enumerate(meshes):
    o.color = cols[i % 4]
    ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
    print("PART", o.name, "min", tuple(round(min(v[k] for v in ws), 3) for k in range(3)), "max", tuple(round(max(v[k] for v in ws), 3) for k in range(3)))
allv = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
ctr = sum(allv, Vector()) / len(allv)
size = max(max(v[k] for v in allv) - min(v[k] for v in allv) for k in range(3))
cd = bpy.data.cameras.new("c")
cd.type = "ORTHO"
cd.ortho_scale = size * 1.15
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam
for mode in ("OBJECT", "TEXTURE"):
    sc.display.shading.color_type = mode
    for view, off, rot in (("side", Vector((0, -5, 0)), (1.5708, 0, 0)), ("top", Vector((0, 0, 5)), (0, 0, 0)), ("front", Vector((5, 0, 0)), (1.5708, 0, 1.5708))):
        cam.location = ctr + off * size
        cam.rotation_euler = rot
        sc.render.filepath = f"{a[1]}_{mode.lower()}_{view}.png"
        bpy.ops.render.render(write_still=True)
