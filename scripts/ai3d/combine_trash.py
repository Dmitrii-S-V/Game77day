"""Blender: 4 trash props from assets/ready -> one street_trash.glb (objects side by side, realistic sizes).
Usage: blender -b --gpu-backend vulkan -P combine_trash.py"""
import bpy, math
from mathutils import Vector

R = r"D:\77Days\assets\ready"
# name, target longest horizontal/vertical size (m), x position, yaw
ITEMS = [("trash_bag", 0.60, 0.0, 0.0, 0.0), ("trash_bottle", 0.30, 0.46, 0.22, 0.9),
         ("trash_rag", 0.38, -0.42, 0.30, -2.2), ("trash_ketchup", 0.22, 0.12, -0.44, 2.4)]
bpy.ops.wm.read_factory_settings(use_empty=True)
for name, size, x, y, yaw in ITEMS:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f"{R}\{name}.glb")
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    dims = [max(p[i] for p in pts) - min(p[i] for p in pts) for i in range(3)]
    s = size / max(dims)
    cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2
    cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2
    zmin = min(p.z for p in pts)
    root.scale = (s, s, s)
    root.rotation_euler = (0, 0, yaw)
    root.location = (x - cx * s, y - cy * s, -zmin * s)
    bpy.context.view_layer.update()
    print("PLACED", name, [round(d * s, 3) for d in dims])
bpy.ops.export_scene.gltf(filepath=r"D:\77Days\assets\ready\street_trash.glb", export_format="GLB",
                          export_apply=True, export_image_format="AUTO")
print("EXPORTED")
