"""Blender: крупные ортопроекции кисти из выровненного .blend (для разметки суставов).
Usage: blender -b --gpu-backend vulkan <in.blend> -P arm_closeup.py -- <prefix> <center_z> <ortho>"""
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
prev, cz, ortho = args[0], float(args[1]), float(args[2])
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x = 1000
sc.render.resolution_y = 1000
cd = bpy.data.cameras.new("cam2")
cd.type = "ORTHO"
cd.ortho_scale = ortho
cam = bpy.data.objects.new("cam2", cd)
sc.collection.objects.link(cam)
sc.camera = cam
for name, loc, rot in [("x", (1.0, 0.0, cz), (0.0, 1.5708, 0.0)), ("y", (0.0, -1.0, cz), (1.5708, 0.0, 0.0)), ("mx", (-1.0, 0.0, cz), (0.0, -1.5708, 0.0))]:
    cam.location = loc
    cam.rotation_euler = rot
    sc.render.filepath = f"{prev}_{name}.png"
    bpy.ops.render.render(write_still=True)
