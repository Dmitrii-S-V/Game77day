"""Blender: зомби-гуманоид из модели Meshy -> упрощение, рост 1.82 м, скелет (19 костей), веса, анимации
(idle, walk, run, attack, hit, death), экспорт GLB для Godot (assets/ready/zombie_friend.glb).
Суставы ищутся по геометрии (срезы по высоте, крайние точки рук), остальное — по пропорциям тела.
Анимации задаются поворотами в осях покоя скелета (Blender: Z вверх, лицо к -Y): q = B^-1 * R * B.
Usage: blender -b -P zombie_rig.py -- <in.glb> <out.glb> [preview_prefix] [save.blend] [height=..] [style=..] [walk=<мокап.fbx>]"""
import os
import sys
import math
import bpy
import numpy as np
from mathutils import Vector, Matrix, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
opts = dict(a.split("=", 1) for a in args if "=" in a and not a.startswith(("C:", "D:")))   # height=1.68 style=leaper
args = [a for a in args if a.split("=", 1)[0] not in opts]
src, out = args[0], args[1]
prev = args[2] if len(args) > 2 else ""
save_blend = args[3] if len(args) > 3 else ""
HEIGHT = float(opts.get("height", 1.82))
STYLE = opts.get("style", "walker")     # walker — «друг» (шатается, руки вперёд); leaper — прыгун (низкая стойка, присед, прыжок)
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=src)
ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0004)
bpy.ops.object.mode_set(mode="OBJECT")
dec = ob.modifiers.new("dec", "DECIMATE")
dec.ratio = 26000.0 / max(len(ob.data.polygons), 1)
bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

V = np.array([v.co[:] for v in ob.data.vertices])
zmin, zmax = V[:, 2].min(), V[:, 2].max()
s = HEIGHT / (zmax - zmin)
cx = (V[:, 0].min() + V[:, 0].max()) * 0.5
cy = np.median(V[:, 1])
ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -zmin))))
ob.data.update()
V = np.array([v.co[:] for v in ob.data.vertices])
H = HEIGHT


def slice_x(z0, z1):
    m = (V[:, 2] >= z0) & (V[:, 2] < z1)
    return V[m]


# --- суставы -------------------------------------------------------------------------
# кисти: самые низкие точки на внешних краях рук (A-поза: руки опущены и отведены)
hands = {}
for side, sg in (("l", 1.0), ("r", -1.0)):
    band = V[(V[:, 2] > 0.40 * H) & (V[:, 2] < 0.62 * H) & (V[:, 0] * sg > 0.16 * H)]
    if len(band) == 0:
        band = V[(V[:, 2] > 0.4 * H) & (V[:, 2] < 0.62 * H) & (V[:, 0] * sg > 0.1 * H)]
    lowest = band[band[:, 2] < band[:, 2].min() + 0.06]
    hands[side] = lowest.mean(axis=0)
# ноги: центр сечения на высоте колена и щиколотки, по сторонам
legs = {}
for side, sg in (("l", 1.0), ("r", -1.0)):
    k = slice_x(0.26 * H, 0.30 * H)
    k = k[k[:, 0] * sg > 0.0]
    a = slice_x(0.04 * H, 0.07 * H)
    a = a[a[:, 0] * sg > 0.0]
    legs[side] = (k.mean(axis=0), a.mean(axis=0))
shoulder_z = 0.815 * H
torso = slice_x(0.70 * H, 0.74 * H)
torso = torso[np.abs(torso[:, 0]) < 0.17 * H]
sh_x = np.percentile(np.abs(torso[:, 0]), 92) * 0.85
fy = np.median(slice_x(0.6 * H, 0.75 * H)[:, 1])   # середина туловища по глубине
if STYLE == "leaper":
    # у прыгуна рюкзак: середину по глубине берём по тазу (там рюкзака нет)
    pel = slice_x(0.47 * H, 0.53 * H)
    fy = np.median(pel[np.abs(pel[:, 0]) < 0.15 * H][:, 1])
print("FY", round(float(fy), 3))

J = {}
J["hips"] = Vector((0, fy, 0.53 * H))
J["spine"] = Vector((0, fy, 0.60 * H))
J["chest"] = Vector((0, fy, 0.69 * H))
J["neck"] = Vector((0, fy + 0.01, 0.835 * H))
J["head"] = Vector((0, fy - 0.005, 0.875 * H))
J["head_end"] = Vector((0, fy - 0.01, 1.0 * H))
for side, sg in (("l", 1.0), ("r", -1.0)):
    shoulder = Vector((sg * sh_x, fy + 0.01, shoulder_z))
    hand = Vector(hands[side])
    wrist = shoulder.lerp(hand, 0.88)
    elbow = shoulder.lerp(wrist, 0.5) + Vector((0, 0.03, 0))   # локоть чуть назад
    J["clav_" + side] = Vector((sg * 0.03 * H, fy, 0.80 * H))
    J["shoulder_" + side] = shoulder
    J["elbow_" + side] = elbow
    J["wrist_" + side] = wrist
    J["hand_end_" + side] = hand + (hand - wrist).normalized() * 0.04
    knee = Vector(legs[side][0])
    ankle = Vector(legs[side][1])
    hip = Vector((sg * 0.085 * H, fy, 0.50 * H))
    knee = Vector((knee.x, knee.y - 0.01, knee.z))        # колено чуть вперёд
    J["hip_" + side] = hip
    J["knee_" + side] = knee
    J["ankle_" + side] = ankle
    J["toe_" + side] = Vector((ankle.x, ankle.y - 0.13, 0.015))

# кости: имя -> (голова, хвост, родитель)
BONES = {
    "hips": (J["hips"], J["spine"], None),
    "spine": (J["spine"], J["chest"], "hips"),
    "chest": (J["chest"], J["neck"], "spine"),
    "neck": (J["neck"], J["head"], "chest"),
    "head": (J["head"], J["head_end"], "neck"),
}
for sd in ("l", "r"):
    BONES["clavicle_" + sd] = (J["clav_" + sd], J["shoulder_" + sd], "chest")
    BONES["upper_arm_" + sd] = (J["shoulder_" + sd], J["elbow_" + sd], "clavicle_" + sd)
    BONES["forearm_" + sd] = (J["elbow_" + sd], J["wrist_" + sd], "upper_arm_" + sd)
    BONES["hand_" + sd] = (J["wrist_" + sd], J["hand_end_" + sd], "forearm_" + sd)
    BONES["thigh_" + sd] = (J["hip_" + sd], J["knee_" + sd], "hips")
    BONES["shin_" + sd] = (J["knee_" + sd], J["ankle_" + sd], "thigh_" + sd)
    BONES["foot_" + sd] = (J["ankle_" + sd], J["toe_" + sd], "shin_" + sd)

arm = bpy.data.armatures.new("ZombieRig")
rig = bpy.data.objects.new("ZombieRig", arm)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for nm, (h, t, par) in BONES.items():
    b = arm.edit_bones.new(nm)
    b.head = h
    b.tail = t
    b.align_roll(Vector((0, -1, 0)))
    eb[nm] = b
for nm, (h, t, par) in BONES.items():
    if par:
        eb[nm].parent = eb[par]
bpy.ops.object.mode_set(mode="OBJECT")

# --- веса: ближайшая кость + плавное смешение с соседями по цепочке; ноги/руки — только своей стороны ----------
names = list(BONES.keys())
heads = np.array([BONES[n][0][:] for n in names])
tails = np.array([BONES[n][1][:] for n in names])


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab[None, :]), axis=1)


D = np.stack([seg_dist(V, heads[i], tails[i]) for i in range(len(names))], axis=1)
thick = {"hips": 0.55, "spine": 0.5, "chest": 0.5, "neck": 0.8, "head": 0.7, "clavicle_l": 1.6, "clavicle_r": 1.6}
for n, k in thick.items():
    D[:, names.index(n)] *= k
side_of = {n: (1.0 if n.endswith("_l") else (-1.0 if n.endswith("_r") else 0.0)) for n in names}
for i, n in enumerate(names):
    sg = side_of[n]
    if sg != 0.0 and ("thigh" in n or "shin" in n or "foot" in n):
        D[V[:, 0] * sg < -0.01, i] = 1e9      # левая нога не тянет вершины правой
    if sg != 0.0 and ("arm" in n or "hand" in n):
        D[V[:, 0] * sg < 0.05 * H, i] = 1e9    # руки — только своей стороны и не середина туловища
near = np.argmin(D, axis=1)
neigh = {n: {n} for n in names}
for n, (h, t, p) in BONES.items():
    if p:
        neigh[n].add(p)
        neigh[p].add(n)
idx = {n: i for i, n in enumerate(names)}
groups = {n: ob.vertex_groups.new(name=n) for n in names}
for vi in range(len(V)):
    b0 = names[near[vi]]
    ws = {}
    for c in neigh[b0]:
        d = D[vi, idx[c]]
        if d < 1e8:
            ws[c] = 1.0 / (d + 0.01) ** 4
    tot = sum(ws.values())
    for c, w in ws.items():
        w /= tot
        if w > 0.02:
            groups[c].add([vi], w, "REPLACE")
ob.parent = rig
mod = ob.modifiers.new("Armature", "ARMATURE")
mod.object = rig

# --- анимации --------------------------------------------------------------------------------
B = {pb.name: rig.data.bones[pb.name].matrix_local.to_quaternion() for pb in rig.pose.bones}
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def rot(name, axis, deg):
    """Поворот кости вокруг оси покоя (в осях скелета), с учётом её ориентации."""
    R = Quaternion(axis, math.radians(deg))
    b = B[name]
    return b.inverted() @ R @ b


def key(action_name, frames, pose_fn, loop=True):
    """pose_fn(t 0..1) -> {кость: [(ось, градусы), ...], '_loc': Vector} ; ключи по кадрам."""
    act = bpy.data.actions.new(action_name)
    rig.animation_data_create()
    rig.animation_data.action = act
    n = frames
    for f in range(n + 1):
        t = f / n
        pose = pose_fn(t)
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            q = Quaternion()
            for ax, deg in pose.get(pb.name, []):
                q = rot(pb.name, ax, deg) @ q
            pb.rotation_quaternion = q
            pb.location = (0, 0, 0)
            if pb.name == "hips" and "_loc" in pose:
                pb.location = B["hips"].inverted() @ pose["_loc"]
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            pb.keyframe_insert("location", frame=f + 1)
    act.use_fake_user = True
    trk = rig.animation_data.nla_tracks.new()
    trk.name = action_name
    st = trk.strips.new(action_name, 1, act)
    rig.animation_data.action = None
    return act


S = math.sin
TAU = math.tau


def base_hunch():
    # сутулость, голова свешена, руки вперёд (классическая поза зомби)
    return {"spine": [(X, 10)], "chest": [(X, 8)], "neck": [(X, -6)], "head": [(X, 12), (Y, 10)],
            "upper_arm_l": [(X, -55), (Y, -8)], "upper_arm_r": [(X, -48), (Y, 8)],
            "forearm_l": [(X, -15)], "forearm_r": [(X, -25)]}


def merge(a, b):
    out = {k: (v.copy() if k == "_loc" else list(v)) for k, v in a.items()}
    for k, v in b.items():
        if k == "_loc":
            out[k] = v
        else:
            out.setdefault(k, []).extend(v)
    return out


def idle(t):
    p = base_hunch()
    br = S(t * TAU)
    return merge(p, {"chest": [(X, 2 * br)], "head": [(Z, 6 * S(t * TAU + 1.0)), (Y, 4 * br)],
                     "upper_arm_l": [(X, -4 * br)], "upper_arm_r": [(X, 3 * br)], "_loc": Vector((0, 0, -0.008 * (1 + br)))})


def walk(t, amp=1.0, lean=0.0):
    p = base_hunch()
    ph = t * TAU
    sw = 28 * amp
    q = {
        "thigh_l": [(X, -sw * S(ph))], "thigh_r": [(X, sw * S(ph))],
        "shin_l": [(X, 35 * amp * max(0.0, S(ph + 1.6)))], "shin_r": [(X, 35 * amp * max(0.0, S(ph + 1.6 + math.pi)))],
        "foot_l": [(X, 10 * amp * S(ph + 0.5))], "foot_r": [(X, -10 * amp * S(ph + 0.5))],
        "hips": [(Z, 8 * amp * S(ph)), (Y, 4 * amp * S(ph))],
        "spine": [(X, lean), (Z, -6 * amp * S(ph))],
        "upper_arm_l": [(X, 10 * amp * S(ph))], "upper_arm_r": [(X, -10 * amp * S(ph))],
        "head": [(Y, 8 * S(ph * 0.5)), (X, 4 * S(ph * 2))],
        "_loc": Vector((0.012 * amp * S(ph), 0, -0.035 * amp * abs(S(ph)))),
    }
    return merge(p, q)


def attack(t):
    p = base_hunch()
    # замах (руки вверх) 0-0.4, удар вниз 0.4-0.6, возврат
    if t < 0.4:
        a = t / 0.4
        up = -55 - 95 * a
        lean = -8 * a
    elif t < 0.6:
        a = (t - 0.4) / 0.2
        up = -150 + 140 * a
        lean = -8 + 30 * a
    else:
        a = (t - 0.6) / 0.4
        up = -10 - 45 * a
        lean = 22 - 22 * a
    return merge({k: v for k, v in p.items() if not k.startswith("upper_arm")},
                 {"upper_arm_l": [(X, up)], "upper_arm_r": [(X, up + 5)], "spine": [(X, lean)],
                  "chest": [(X, lean * 0.5)], "forearm_l": [(X, -20)], "forearm_r": [(X, -20)]})


def hit(t):
    p = base_hunch()
    a = S(min(t / 0.35, 1.0) * math.pi) if t < 0.35 else S(math.pi) * 0 + max(0.0, 1.0 - (t - 0.35) / 0.65) * 0.0
    a = S(t * math.pi)
    return merge(p, {"spine": [(X, -18 * a)], "chest": [(X, -10 * a)], "head": [(X, -20 * a), (Z, 10 * a)],
                     "upper_arm_l": [(X, 20 * a)], "upper_arm_r": [(X, 25 * a)]})


DEATH_DROP = [0.0]   # доп. опускание тела в конце падения: подбирается по низшей точке меша (тело ложится на землю)


def death(t):
    p = base_hunch()
    e = min(1.0, t / 0.75)
    e = e * e * (3 - 2 * e)
    knee = min(1.0, t / 0.4)
    return merge(p, {
        "hips": [(X, -90 * e)],
        "_loc": Vector((0, 0.45 * e, -(0.47 + DEATH_DROP[0]) * e - 0.05 * knee * (1 - e))),
        "thigh_l": [(X, -25 * knee * (1 - e) + 10 * e)], "thigh_r": [(X, -15 * knee * (1 - e) + 5 * e)],
        "shin_l": [(X, 50 * knee * (1 - e) + 5 * e)], "shin_r": [(X, 40 * knee * (1 - e))],
        "spine": [(X, -10 * e)], "head": [(X, -25 * e), (Z, 30 * e)],
        "upper_arm_l": [(X, 40 * e), (Y, -40 * e)], "upper_arm_r": [(X, 30 * e), (Y, 35 * e)],
    })


# --- прыгун (style=leaper): низкая «звериная» стойка, хромает, присед на корточки и прыжок ---------------------
CROUCH_DROP = [0.0]   # опускание таза в приседе: подбирается так, чтобы ступни стояли на земле


def L(a, b, s):
    return a + (b - a) * s


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def leaper_base():
    return {"spine": [(X, 22)], "chest": [(X, 12)], "neck": [(X, -15)], "head": [(X, 5)],
            "upper_arm_l": [(X, 8), (Y, -12)], "upper_arm_r": [(X, 8), (Y, 12)],
            "forearm_l": [(X, -30)], "forearm_r": [(X, -35)],
            "thigh_l": [(X, -12)], "thigh_r": [(X, -12)], "shin_l": [(X, 22)], "shin_r": [(X, 22)],
            "_loc": Vector((0, 0, -0.03))}


def l_idle(t):
    br = S(t * TAU)
    jerk = S(t * TAU * 3) ** 9        # редкие резкие подёргивания головы
    return merge(leaper_base(), {"chest": [(X, 2 * br)], "head": [(Z, 18 * jerk), (Y, 6 * br)],
                                 "upper_arm_l": [(X, 4 * br)], "upper_arm_r": [(X, -3 * br)],
                                 "_loc": Vector((0, 0, -0.03 - 0.01 * (1 + br)))})


def l_walk(t):
    # хромает: левая нога почти не сгибается, на правую «проваливается», тело раскачивается
    ph = t * TAU
    return merge(leaper_base(), {
        "thigh_l": [(X, -22 * S(ph))], "shin_l": [(X, 8 + 12 * max(0.0, S(ph + 1.6)))],
        "thigh_r": [(X, 26 * S(ph))], "shin_r": [(X, 40 * max(0.0, S(ph + 1.6 + math.pi)))],
        "foot_l": [(X, 6 * S(ph))], "foot_r": [(X, -10 * S(ph + 0.5))],
        "hips": [(Z, 12 * S(ph)), (Y, 6 * S(ph))], "spine": [(Z, -10 * S(ph))],
        "upper_arm_l": [(X, 18 * S(ph + 0.8))], "upper_arm_r": [(X, -18 * S(ph + 0.8))],
        "head": [(Z, 10 * S(ph))],
        "_loc": Vector((0.02 * S(ph), 0, -0.04 - 0.05 * max(0.0, S(ph + math.pi)))),
    })


def l_run(t):
    # низкий быстрый бег: сильный наклон, руки работают, колени высоко
    ph = t * TAU
    return merge(leaper_base(), {
        "spine": [(X, 18)], "chest": [(X, 6)], "neck": [(X, -18)],
        "thigh_l": [(X, -40 * S(ph) - 10)], "thigh_r": [(X, 40 * S(ph) - 10)],
        "shin_l": [(X, 70 * max(0.0, S(ph + 1.6)) + 10)], "shin_r": [(X, 70 * max(0.0, S(ph + 1.6 + math.pi)) + 10)],
        "upper_arm_l": [(X, 45 * S(ph))], "upper_arm_r": [(X, -45 * S(ph))],
        "forearm_l": [(X, -70)], "forearm_r": [(X, -70)],
        "_loc": Vector((0, 0, -0.06 - 0.04 * abs(S(ph)))),
    })


def crouch_pose(s=1.0, br=0.0):
    """Присед на корточки: s=1 — полный присед, 0 — стойка прыгуна."""
    return merge(leaper_base(), {
        "thigh_l": [(X, L(0, -100, s))], "thigh_r": [(X, L(0, -95, s))],
        "shin_l": [(X, L(0, 120, s))], "shin_r": [(X, L(0, 115, s))],
        "foot_l": [(X, L(0, -20, s))], "foot_r": [(X, L(0, -20, s))],
        "spine": [(X, L(0, 18, s))], "chest": [(X, 3 * br)], "neck": [(X, L(0, -15, s))],
        "upper_arm_l": [(X, L(0, -48, s))], "upper_arm_r": [(X, L(0, -44, s))],
        "_loc": Vector((0, L(0, 0.22, s), L(0, -0.5 - CROUCH_DROP[0], s))),
    })


def l_crouch(t):
    return crouch_pose(1.0, S(t * TAU))


def leap_pose(s):
    """Прыжок: s=0 — присед, s=1 — вытянут в полёте (руки вперёд, ноги назад)."""
    c = 1.0 - s
    return merge(leaper_base(), {
        "thigh_l": [(X, L(-100, 28, s))], "thigh_r": [(X, L(-95, 20, s))],
        "shin_l": [(X, L(120, 35, s))], "shin_r": [(X, L(115, 45, s))],
        "foot_l": [(X, L(-20, 35, s))], "foot_r": [(X, L(-20, 30, s))],
        "spine": [(X, L(18, 45, s))], "chest": [(X, L(0, 12, s))], "neck": [(X, L(-15, -40, s))],
        "upper_arm_l": [(X, L(-48, -150, s)), (Y, -10 * s)], "upper_arm_r": [(X, L(-44, -145, s)), (Y, 10 * s)],
        "forearm_l": [(X, L(0, 20, s))], "forearm_r": [(X, L(0, 20, s))],
        "_loc": Vector((0, 0.22 * c, (-0.5 - CROUCH_DROP[0]) * c - 0.05 * s)),
    })


def l_leap(t):
    if t < 0.15:
        s = smooth(t / 0.15)            # толчок
    elif t < 0.6:
        s = 1.0                         # полёт
    else:
        s = 1.0 - smooth((t - 0.6) / 0.4) * 0.8    # приземление в полуприсед
    return leap_pose(s)


def l_attack(t):
    # бросок с захватом двумя руками и рывком вперёд
    if t < 0.35:
        a = t / 0.35
        up, lean, fwd = L(8, 20, a), L(22, 15, a), 0.0
    elif t < 0.55:
        a = (t - 0.35) / 0.2
        up, lean, fwd = L(20, -100, a), L(15, 45, a), -0.18 * a
    else:
        a = (t - 0.55) / 0.45
        up, lean, fwd = L(-100, 8, a), L(45, 22, a), -0.18 * (1 - a)
    b = leaper_base()
    return merge({k: v for k, v in b.items() if not k.startswith(("upper_arm", "spine"))},
                 {"upper_arm_l": [(X, up), (Y, -15)], "upper_arm_r": [(X, up), (Y, 15)], "spine": [(X, lean)],
                  "forearm_l": [(X, -25)], "forearm_r": [(X, -25)], "head": [(X, 10)],
                  "_loc": Vector((0, fwd, -0.03))})


def l_hit(t):
    a = S(t * math.pi)
    return merge(leaper_base(), {"spine": [(X, -22 * a)], "chest": [(X, -12 * a)], "head": [(X, -25 * a), (Z, -12 * a)],
                                 "upper_arm_l": [(X, 25 * a)], "upper_arm_r": [(X, 20 * a)]})


if STYLE == "leaper":
    key("idle", 60, l_idle)
    key("walk", 40, l_walk)
    key("run", 18, l_run)
    key("attack", 24, l_attack, False)
    key("hit", 10, l_hit, False)
elif opts.get("walk"):
    # ходьба из мокапа (FBX Mixamo): scripts/ai3d/mocap_walk.py
    key("idle", 60, idle)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mocap_walk
    print("WALK_SPEED %.3f" % mocap_walk.apply(rig, ob, opts["walk"]))
    key("run", 20, lambda t: walk(t, 1.6, 18.0))
    key("attack", 26, attack, False)
    key("hit", 10, hit, False)
else:
    key("idle", 60, idle)
    key("walk", 36, lambda t: walk(t, 1.0, 6.0))
    key("run", 20, lambda t: walk(t, 1.6, 18.0))
    key("attack", 26, attack, False)
    key("hit", 10, hit, False)


def lowest_z(track_name, frame):
    """Низшая точка деформированного меша в кадре анимации (остальные дорожки NLA заглушены)."""
    for tr in rig.animation_data.nla_tracks:
        tr.mute = tr.name != track_name
    bpy.context.scene.frame_set(frame)
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


def l_death(t):
    # прыгун падает ничком (вперёд), руки вперёд
    e = smooth(t / 0.7)
    knee = min(1.0, t / 0.3)
    return merge(leaper_base(), {
        "hips": [(X, 88 * e)],
        "_loc": Vector((0, -0.45 * e, -(0.47 + DEATH_DROP[0]) * e - 0.08 * knee * (1 - e))),
        "thigh_l": [(X, -30 * knee * (1 - e))], "thigh_r": [(X, -20 * knee * (1 - e))],
        "shin_l": [(X, 60 * knee * (1 - e) + 8 * e)], "shin_r": [(X, 45 * knee * (1 - e))],
        "spine": [(X, -10 * e)], "neck": [(X, -20 * e)], "head": [(Z, 35 * e)],
        "upper_arm_l": [(X, -120 * e), (Y, -25 * e)], "upper_arm_r": [(X, -100 * e), (Y, 30 * e)],
    })


death_fn = l_death if STYLE == "leaper" else death


def refit(name, frames, fn, loop, drop, frame, target):
    """Анимация, у которой низшая точка тела в кадре frame должна быть на высоте target: пробный проход,
    затем drop[0] = поправка и анимация пересоздаётся."""
    act = key(name, frames, fn, loop)
    low = lowest_z(name, frame)
    drop[0] = low - target
    rig.animation_data.nla_tracks.remove(rig.animation_data.nla_tracks[name])
    bpy.data.actions.remove(act)
    key(name, frames, fn, loop)
    print("%s lowest before %.3f after %.3f" % (name.upper(), low, lowest_z(name, frame)))


# смерть: тело ложится на землю (раньше висело на ~0.35 м)
refit("death", 36, death_fn, False, DEATH_DROP, 37, 0.02)
if STYLE == "leaper":
    # присед: ступни на земле (низшая точка как в стойке); прыжок строится от той же позы
    rest_low = lowest_z("idle", 1)
    refit("crouch", 30, l_crouch, True, CROUCH_DROP, 1, rest_low)
    key("leap", 24, l_leap, False)

if prev:
    sc = bpy.context.scene
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
    shots = (("walk", 10), ("walk", 28), ("attack", 12), ("death", 37))
    if STYLE == "leaper":
        shots = (("idle", 1), ("walk", 12), ("run", 5), ("crouch", 1), ("leap", 8), ("attack", 13), ("death", 37))
    for nm, fr in shots:
        trk = rig.animation_data.nla_tracks
        for tr in trk:
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
print("JOINTS", {k: tuple(round(x, 3) for x in v) for k, v in J.items() if k in ("shoulder_l", "wrist_l", "knee_l", "ankle_l", "hips")})
print("EXPORTED", out, "verts", len(V))
