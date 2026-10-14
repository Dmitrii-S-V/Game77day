"""Blender: превью GLB с 4 сторон (Workbench, текстура) в одну картинку.
Usage: blender -b --gpu-backend vulkan -P preview_glb.py -- <file.glb> <out_prefix>"""
import sys
import math
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
path, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.light = "STUDIO"
sc.render.resolution_x = 640
sc.render.resolution_y = 640
sc.render.film_transparent = False
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.3
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
views = {"front": (0, -4, 0), "side": (4, 0, 0), "top": (0, 0, 4), "back": (0, 4, 0)}
for name, p in views.items():
    cam.location = Vector(p)
    d = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y" if name != "top" else "Y").to_euler()
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
