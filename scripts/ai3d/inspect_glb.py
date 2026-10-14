"""Blender: печатает состав GLB (объекты, арматуры, полигоны, габариты, материалы).
Usage: blender -b -P inspect_glb.py -- <file.glb>"""
import sys
import bpy
from mathutils import Vector

path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
for o in bpy.context.scene.objects:
    line = f"OBJ {o.name} type={o.type} parent={o.parent.name if o.parent else None}"
    if o.type == "MESH":
        me = o.data
        ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = Vector((min(v.x for v in ws), min(v.y for v in ws), min(v.z for v in ws)))
        mx = Vector((max(v.x for v in ws), max(v.y for v in ws), max(v.z for v in ws)))
        line += f" verts={len(me.vertices)} faces={len(me.polygons)} bbox_min={tuple(round(x, 3) for x in mn)} bbox_max={tuple(round(x, 3) for x in mx)}"
        line += f" vgroups={[g.name for g in o.vertex_groups][:10]} mats={[m.name for m in me.materials if m]}"
        line += f" uv={len(me.uv_layers)}"
    if o.type == "ARMATURE":
        line += f" bones={[b.name for b in o.data.bones][:40]}"
    print(line)
for img in bpy.data.images:
    print("IMG", img.name, tuple(img.size))
