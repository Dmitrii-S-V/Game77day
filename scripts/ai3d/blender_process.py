"""Run: blender -b -P blender_process.py -- in.glb out.glb KIND CX CY CZ PREVIEW_PREFIX
Cells are in Godot axes (x, y-up, z). 1 unit = 1 m = 1 block.
Imports GLB, cleans, decimates (Collapse) to the kind's budget, fixes normals,
fits to the cell box, puts origin at bottom center, exports GLB, renders previews."""
import math
import sys

import bmesh
import bpy
from mathutils import Vector

BUDGETS = {"prop_small": 2000, "prop_medium": 5000, "prop_large": 12000}
MARGIN = 0.05  # per side, in cells

import os

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, kind = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
cells = [float(v) for v in argv[3:6]]
preview = os.path.abspath(argv[6]) if len(argv) > 6 else None


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("EMPTY: no mesh in " + src)

bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
obj.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# remove loose bits (stray vertices/edges, tiny floating islands)
bm = bmesh.new()
bm.from_mesh(obj.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(obj.data)
bm.free()

tris_in = tri_count(obj)
budget = BUDGETS.get(kind, 5000)
if tris_in > budget:  # Collapse keeps UVs; do it in Blender, not trimesh
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = budget / tris_in
    bpy.ops.object.modifier_apply(modifier=mod.name)

# normals outward
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth()

# Blender (x, y, z-up) <-> Godot (x, y-up, z): Godot size = (dx, dz, dy)
bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
dim = mx - mn
target = Vector((cells[0] - 2 * MARGIN, cells[2] - 2 * MARGIN, cells[1] - 2 * MARGIN))  # Blender xyz
target = Vector((max(target.x, 0.05), max(target.y, 0.05), max(target.z, 0.05)))
s = min(target.x / dim.x if dim.x > 1e-6 else 1e9,
        target.y / dim.y if dim.y > 1e-6 else 1e9,
        target.z / dim.z if dim.z > 1e-6 else 1e9)
obj.scale = (s, s, s)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
obj.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)  # origin = bottom center
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

tris_out = tri_count(obj)
size_godot = (mx.x - mn.x, mx.z - mn.z, mx.y - mn.y)
print(f"RESULT tris_in={tris_in} tris_out={tris_out} scale={s:.4f} "
      f"size_godot={size_godot[0]:.3f},{size_godot[1]:.3f},{size_godot[2]:.3f}")

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True,
                          export_apply=True, use_selection=False)

if preview:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = sc.render.resolution_y = 512
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_shadows = False
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.5, 0.5, 0.55)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    h = size_godot[1]
    center = Vector((0, 0, h / 2))
    cam_data.ortho_scale = max(h, size_godot[0], size_godot[2]) * 1.25
    dist = 20
    for name, yaw in (("front", 0), ("side", 90), ("persp", 35)):
        a = math.radians(yaw)
        elev = math.radians(20 if name == "persp" else 0)
        # camera looks from -Y (front) in Blender, which is +Z in Godot
        cam.location = center + Vector((math.sin(a) * math.cos(elev), -math.cos(a) * math.cos(elev),
                                        math.sin(elev))) * dist
        direction = center - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{preview}_{name}.png"
        bpy.ops.render.render(write_still=True)
    print("PREVIEWS", preview)
