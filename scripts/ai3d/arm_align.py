"""Blender, шаг 1: рука Meshy -> упрощение, выравнивание по главным осям (PCA), масштаб в метры,
превью-проекции с известным масштабом для снятия координат суставов.
Usage: blender -b --gpu-backend vulkan -P arm_align.py -- <in.glb> <out.blend> <preview_prefix> [flipz] [flipx]"""
import sys
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out_blend, prev = args[0], args[1], args[2]
flipz = "flipz" in args
flipx = "flipx" in args
LENGTH = 0.46   # от локтевого края манжеты до кончика среднего пальца, м

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
# упрощение: ~22k треугольников (для руки от первого лица достаточно)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode="OBJECT")
dec = ob.modifiers.new("dec", "DECIMATE")
dec.ratio = 22000.0 / max(len(ob.data.polygons), 1)
bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

v = np.array([vv.co[:] for vv in ob.data.vertices])
c = v.mean(axis=0)
cov = np.cov((v - c).T)
w, e = np.linalg.eigh(cov)          # по возрастанию
ax_main = e[:, 2]                   # длина руки
ax_thin = e[:, 0]                   # нормаль ладони/толщина
ax_mid = np.cross(ax_main, ax_thin)
# новая система: X = толщина, Y = ширина, Z = длина
R = np.array([ax_thin, ax_mid, ax_main])
if flipz:
    R[2] *= -1; R[0] *= -1
if flipx:
    R[0] *= -1; R[1] *= -1
p = (v - c) @ R.T
L = p[:, 2].max() - p[:, 2].min()
s = LENGTH / L
M = Matrix([[R[0][0], R[0][1], R[0][2], 0], [R[1][0], R[1][1], R[1][2], 0], [R[2][0], R[2][1], R[2][2], 0], [0, 0, 0, 1]])
ob.matrix_world = Matrix.Scale(s, 4) @ M @ Matrix.Translation(Vector((-c[0], -c[1], -c[2])))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
v2 = np.array([vv.co[:] for vv in ob.data.vertices])
print("ALIGN eig", w, "scale", s)
print("ALIGN bbox min", v2.min(axis=0), "max", v2.max(axis=0))
# толщина по срезам вдоль Z: где манжета (толсто и кругло), где пальцы
zs = np.linspace(v2[:, 2].min(), v2[:, 2].max(), 24)
for i in range(len(zs) - 1):
    m = (v2[:, 2] >= zs[i]) & (v2[:, 2] < zs[i + 1])
    if m.sum() > 0:
        print("SLICE z=%.3f n=%d xr=%.3f..%.3f yr=%.3f..%.3f" % (zs[i], m.sum(), v2[m, 0].min(), v2[m, 0].max(), v2[m, 1].min(), v2[m, 1].max()))
bpy.ops.wm.save_as_mainfile(filepath=out_blend)

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x = 900
sc.render.resolution_y = 900
cd = bpy.data.cameras.new("cam")
cd.type = "ORTHO"
cd.ortho_scale = 0.5
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cz = (v2[:, 2].min() + v2[:, 2].max()) * 0.5
# вид вдоль -X (смотрим на ладонь/тыл): по горизонтали Z, по вертикали Y
for name, loc, rot in [("x", (1.0, 0.0, cz), (0.0, 1.5708, 0.0)), ("y", (0.0, -1.0, cz), (1.5708, 0.0, 0.0))]:
    cam.location = loc
    cam.rotation_euler = rot
    sc.render.filepath = f"{prev}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("CAM center z", cz, "ortho 0.5 m / 900 px")
