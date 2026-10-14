"""Blender: печать положения костей (.blend или .glb). Usage: blender -b [file.blend] -P dump_bones.py -- [file.glb]"""
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if args:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args[0])
for o in bpy.context.scene.objects:
    if o.type == "ARMATURE":
        for b in o.data.bones:
            h = o.matrix_world @ b.head_local
            t = o.matrix_world @ b.tail_local
            print("BONE %-10s head %7.4f %7.4f %7.4f  tail %7.4f %7.4f %7.4f" % (b.name, h.x, h.y, h.z, t.x, t.y, t.z))
