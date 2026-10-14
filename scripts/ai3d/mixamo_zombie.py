"""Blender: зомби-прыгун на скелете Mixamo/Meshy (модель уже со скинингом) -> свои анимации -> GLB для Godot.
Модель: assets/src/mudworn_biped/... (Meshy «biped», кости mixamorig:*). Готовые анимации из файла удаляются,
вместо них — idle, walk (хромает), run, crouch (на корточках), leap (прыжок), attack, hit, death (ничком).
Повороты задаются в осях скелета (Blender: Z вверх, лицо к -Y): q = B^-1 * R * B — как в zombie_rig.py.
Usage: blender -b -P mixamo_zombie.py -- <in.glb> <out.glb> [preview_prefix] [save.blend] [walk=<мокап.fbx>]"""
import os
import sys
import math
import bpy
import numpy as np
from mathutils import Vector, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
opts = dict(a.split("=", 1) for a in args if a.startswith("walk="))
args = [a for a in args if not a.startswith("walk=")]
src, out = args[0], args[1]
prev = args[2] if len(args) > 2 else ""
save_blend = args[3] if len(args) > 3 else ""
FPS = 30
TARGET_FACES = 26000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
rig = [o for o in sc.objects if o.type == "ARMATURE"][0]
ob = [o for o in sc.objects if o.type == "MESH" and o.parent == rig][0]
# лишнее (вспомогательные объекты из правки в Blender)
for o in list(sc.objects):
    if o not in (rig, ob):
        bpy.data.objects.remove(o, do_unlink=True)
# готовые анимации — убрать
if rig.animation_data:
    rig.animation_data.action = None
    for tr in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(tr)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion()
    pb.location = (0, 0, 0)
    pb.scale = (1, 1, 1)

# упрощение сетки (веса костей сохраняются): прореживание должно идти до модификатора скелета
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
nf = len(ob.data.polygons)
if nf > TARGET_FACES:
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = TARGET_FACES / nf
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("FACES", nf, "->", len(ob.data.polygons))

# --- имена костей: короткие -> mixamo ---------------------------------------------------------
MAP = {"hips": "Hips", "spine": "Spine", "chest": "Spine1", "chest2": "Spine2", "neck": "Neck", "head": "Head"}
for sd, side in (("l", "Left"), ("r", "Right")):
    MAP.update({"clavicle_" + sd: side + "Shoulder", "upper_arm_" + sd: side + "Arm", "forearm_" + sd: side + "ForeArm",
                "hand_" + sd: side + "Hand", "thigh_" + sd: side + "UpLeg", "shin_" + sd: side + "Leg",
                "foot_" + sd: side + "Foot", "toe_" + sd: side + "ToeBase"})
PB = {}
for short, mx in MAP.items():
    for pb in rig.pose.bones:
        if pb.name.split(":")[-1] == mx:
            PB[short] = pb
print("BONES", sorted(PB.keys()))
B = {k: (rig.matrix_world.to_quaternion() @ rig.data.bones[pb.name].matrix_local.to_quaternion()) for k, pb in PB.items()}
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
S = math.sin
TAU = math.tau


def rot(name, axis, deg):
    R = Quaternion(axis, math.radians(deg))
    b = B[name]
    return b.inverted() @ R @ b


def key(action_name, frames, pose_fn, loop=True):
    """pose_fn(t 0..1) -> {кость: [(ось, градусы), ...], '_loc': Vector}; ключи по кадрам, дорожка NLA с именем анимации."""
    act = bpy.data.actions.new(action_name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in range(frames + 1):
        pose = pose_fn(f / frames)
        for short, pb in PB.items():
            q = Quaternion()
            for ax, deg in pose.get(short, []):
                q = rot(short, ax, deg) @ q
            pb.rotation_quaternion = q
            pb.location = (0, 0, 0)
            if short == "hips" and "_loc" in pose:
                pb.location = B["hips"].inverted() @ pose["_loc"]
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            pb.keyframe_insert("location", frame=f + 1)
    act.use_fake_user = True
    trk = rig.animation_data.nla_tracks.new()
    trk.name = action_name
    trk.strips.new(action_name, 1, act)
    rig.animation_data.action = None
    return act


def merge(a, b):
    out_ = {k: (v.copy() if k == "_loc" else list(v)) for k, v in a.items()}
    for k, v in b.items():
        if k == "_loc":
            out_[k] = v
        else:
            out_.setdefault(k, []).extend(v)
    return out_


def L(a, b, s):
    return a + (b - a) * s


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


CROUCH_DROP = [0.0]
DEATH_DROP = [0.0]


# --- позы прыгуна (как style=leaper в zombie_rig.py; «грудь» делится на два позвонка) ------------------------
def base():
    return {"spine": [(X, 14)], "chest": [(X, 8)], "chest2": [(X, 8)], "neck": [(X, -12)], "head": [(X, 2)],
            "upper_arm_l": [(X, 8), (Y, -12)], "upper_arm_r": [(X, 8), (Y, 12)],
            "forearm_l": [(X, -30)], "forearm_r": [(X, -35)],
            "thigh_l": [(X, -12)], "thigh_r": [(X, -12)], "shin_l": [(X, 22)], "shin_r": [(X, 22)],
            "_loc": Vector((0, 0, -0.03))}


def idle(t):
    br = S(t * TAU)
    jerk = S(t * TAU * 3) ** 9        # редкие резкие подёргивания головы
    return merge(base(), {"chest": [(X, 2 * br)], "head": [(Z, 18 * jerk), (Y, 6 * br)],
                          "upper_arm_l": [(X, 4 * br)], "upper_arm_r": [(X, -3 * br)],
                          "_loc": Vector((0, 0, -0.03 - 0.01 * (1 + br)))})


def walk(t):
    ph = t * TAU
    return merge(base(), {
        "thigh_l": [(X, -22 * S(ph))], "shin_l": [(X, 8 + 12 * max(0.0, S(ph + 1.6)))],
        "thigh_r": [(X, 26 * S(ph))], "shin_r": [(X, 40 * max(0.0, S(ph + 1.6 + math.pi)))],
        "foot_l": [(X, 6 * S(ph))], "foot_r": [(X, -10 * S(ph + 0.5))],
        "hips": [(Z, 12 * S(ph)), (Y, 6 * S(ph))], "spine": [(Z, -10 * S(ph))],
        "upper_arm_l": [(X, 18 * S(ph + 0.8))], "upper_arm_r": [(X, -18 * S(ph + 0.8))],
        "head": [(Z, 10 * S(ph))],
        "_loc": Vector((0.02 * S(ph), 0, -0.04 - 0.05 * max(0.0, S(ph + math.pi)))),
    })


def run(t):
    ph = t * TAU
    return merge(base(), {
        "spine": [(X, 14)], "chest": [(X, 4)], "neck": [(X, -18)],
        "thigh_l": [(X, -40 * S(ph) - 10)], "thigh_r": [(X, 40 * S(ph) - 10)],
        "shin_l": [(X, 70 * max(0.0, S(ph + 1.6)) + 10)], "shin_r": [(X, 70 * max(0.0, S(ph + 1.6 + math.pi)) + 10)],
        "upper_arm_l": [(X, 45 * S(ph))], "upper_arm_r": [(X, -45 * S(ph))],
        "forearm_l": [(X, -70)], "forearm_r": [(X, -70)],
        "_loc": Vector((0, 0, -0.06 - 0.04 * abs(S(ph)))),
    })


def crouch_pose(s=1.0, br=0.0):
    return merge(base(), {
        "thigh_l": [(X, L(0, -100, s))], "thigh_r": [(X, L(0, -95, s))],
        "shin_l": [(X, L(0, 120, s))], "shin_r": [(X, L(0, 115, s))],
        "foot_l": [(X, L(0, -20, s))], "foot_r": [(X, L(0, -20, s))],
        "spine": [(X, L(0, 14, s))], "chest": [(X, 3 * br)], "neck": [(X, L(0, -15, s))],
        "upper_arm_l": [(X, L(0, -48, s))], "upper_arm_r": [(X, L(0, -44, s))],
        "_loc": Vector((0, L(0, 0.22, s), L(0, -0.5 - CROUCH_DROP[0], s))),
    })


def crouch(t):
    return crouch_pose(1.0, S(t * TAU))


def leap_pose(s):
    c = 1.0 - s
    return merge(base(), {
        "thigh_l": [(X, L(-100, 28, s))], "thigh_r": [(X, L(-95, 20, s))],
        "shin_l": [(X, L(120, 35, s))], "shin_r": [(X, L(115, 45, s))],
        "foot_l": [(X, L(-20, 35, s))], "foot_r": [(X, L(-20, 30, s))],
        "spine": [(X, L(14, 35, s))], "chest": [(X, L(0, 10, s))], "neck": [(X, L(-15, -40, s))],
        "upper_arm_l": [(X, L(-48, -150, s)), (Y, -10 * s)], "upper_arm_r": [(X, L(-44, -145, s)), (Y, 10 * s)],
        "forearm_l": [(X, L(0, 20, s))], "forearm_r": [(X, L(0, 20, s))],
        "_loc": Vector((0, 0.22 * c, (-0.5 - CROUCH_DROP[0]) * c - 0.05 * s)),
    })


def leap(t):
    if t < 0.15:
        s = smooth(t / 0.15)
    elif t < 0.6:
        s = 1.0
    else:
        s = 1.0 - smooth((t - 0.6) / 0.4) * 0.8
    return leap_pose(s)


def attack(t):
    if t < 0.35:
        a = t / 0.35
        up, lean, fwd = L(8, 20, a), L(14, 10, a), 0.0
    elif t < 0.55:
        a = (t - 0.35) / 0.2
        up, lean, fwd = L(20, -100, a), L(10, 35, a), -0.18 * a
    else:
        a = (t - 0.55) / 0.45
        up, lean, fwd = L(-100, 8, a), L(35, 14, a), -0.18 * (1 - a)
    b = base()
    return merge({k: v for k, v in b.items() if not k.startswith(("upper_arm", "spine"))},
                 {"upper_arm_l": [(X, up), (Y, -15)], "upper_arm_r": [(X, up), (Y, 15)], "spine": [(X, lean)],
                  "forearm_l": [(X, -25)], "forearm_r": [(X, -25)], "head": [(X, 10)],
                  "_loc": Vector((0, fwd, -0.03))})


def hit(t):
    a = S(t * math.pi)
    return merge(base(), {"spine": [(X, -18 * a)], "chest": [(X, -10 * a)], "head": [(X, -25 * a), (Z, -12 * a)],
                          "upper_arm_l": [(X, 25 * a)], "upper_arm_r": [(X, 20 * a)]})


def death(t):
    # падает навзничь (на спину, на рюкзак): колени подгибаются, затем назад; руки вдоль тела, чуть в стороны
    e = smooth(t / 0.7)
    knee = min(1.0, t / 0.3)
    b = base()
    return merge({k: v for k, v in b.items() if not k.startswith(("upper_arm", "forearm", "spine", "chest", "neck"))}, {
        "hips": [(X, -90 * e)],
        "_loc": Vector((0, 0.45 * e, -(0.47 + DEATH_DROP[0]) * e - 0.08 * knee * (1 - e))),
        "thigh_l": [(X, -30 * knee * (1 - e) + 24 * e)], "thigh_r": [(X, -20 * knee * (1 - e) - 15 * e)],
        "shin_l": [(X, 60 * knee * (1 - e) + 6 * e)], "shin_r": [(X, 45 * knee * (1 - e) + 45 * e)],
        "spine": [(X, L(14, -8, e))], "chest": [(X, L(8, 0, e))], "neck": [(X, L(-12, 10, e))], "head": [(Z, 35 * e)],
        # руки назад (к земле — он на спине, туловище приподнято рюкзаком) и чуть в стороны
        "upper_arm_l": [(X, L(8, 40, e)), (Y, L(-12, -35, e))], "upper_arm_r": [(X, L(8, 35, e)), (Y, L(12, 28, e))],
        "forearm_l": [(X, L(-30, -3, e))], "forearm_r": [(X, L(-35, -8, e))],
    })


def lowest_z(track_name, frame):
    for tr in rig.animation_data.nla_tracks:
        tr.mute = tr.name != track_name
    sc.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    eo = ob.evaluated_get(dg)
    me = eo.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    eo.to_mesh_clear()
    co = co.reshape(-1, 3)
    mw = np.array(ob.matrix_world)
    z = co @ mw[2, :3] + mw[2, 3]
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    return float(np.percentile(z, 0.2))


def refit(name, frames, fn, loop, drop, frame, target):
    act = key(name, frames, fn, loop)
    low = lowest_z(name, frame)
    drop[0] = low - target
    rig.animation_data.nla_tracks.remove(rig.animation_data.nla_tracks[name])
    bpy.data.actions.remove(act)
    key(name, frames, fn, loop)
    print("%s lowest before %.3f after %.3f" % (name.upper(), low, lowest_z(name, frame)))


key("idle", 60, idle)
if opts.get("walk"):
    # ходьба из мокапа (FBX Mixamo): scripts/ai3d/mocap_walk.py
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mocap_walk
    print("WALK_SPEED %.3f" % mocap_walk.apply(rig, ob, opts["walk"]))
else:
    key("walk", 40, walk)
key("run", 18, run)
key("attack", 24, attack, False)
key("hit", 10, hit, False)
refit("death", 36, death, False, DEATH_DROP, 37, 0.02)
rest_low = lowest_z("idle", 1)
refit("crouch", 30, crouch, True, CROUCH_DROP, 1, rest_low)
key("leap", 24, leap, False)
sc.frame_set(1)

if prev:
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 520
    sc.render.resolution_y = 640
    cd = bpy.data.cameras.new("pc")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.3
    cam = bpy.data.objects.new("pc", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for nm, fr in (("idle", 1), ("walk", 12), ("run", 5), ("crouch", 1), ("leap", 8), ("attack", 13), ("death", 37)):
        for tr in rig.animation_data.nla_tracks:
            tr.mute = tr.name != nm
        sc.frame_set(fr)
        for view, loc, r in (("side", (3.0, 0.0, 0.95), (1.5708, 0.0, 1.5708)), ("front", (0.0, -3.0, 0.95), (1.5708, 0.0, 0.0))):
            cam.location = loc
            cam.rotation_euler = r
            sc.render.filepath = f"{prev}_{nm}{fr}_{view}.png"
            bpy.ops.render.render(write_still=True)
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    bpy.data.objects.remove(cam)

if save_blend:
    bpy.ops.wm.save_as_mainfile(filepath=save_blend)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_skins=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS", export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", out, "faces", len(ob.data.polygons))
