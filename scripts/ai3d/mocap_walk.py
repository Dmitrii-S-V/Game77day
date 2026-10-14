"""Blender: перенос ходьбы из мокапа (FBX со скелетом Mixamo, например экспорт Rokoko) на скелет зомби.
Вызывается из zombie_rig.py / mixamo_zombie.py (аргумент walk=<fbx>), делает дорожку NLA «walk».

- Перенос по мировой ориентации костей: поворот кости мокапа относительно её позы покоя переносится на кость цели;
  разница поз покоя (T-поза мокапа, A-поза цели) гасится поправкой «направление кости цели -> направление мокапа».
- Ходьба на месте: поступательное движение таза убирается, курс выпрямляется покадрово, остаются покачивания.
- Цикл — почти вся запись: самые похожие кадры у начала и у конца, конец плавно (FADE кадров) сводится к началу.
- Лёгкое сглаживание дрожания (мокап с видео) и подгонка высоты: ступни на уровне земли, как в позе покоя.
Возвращает естественную скорость шага в м/с (для скорости проигрывания в игре)."""
import math
import bpy
import numpy as np
from mathutils import Vector, Quaternion

MIXAMO = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]
for _s in ("Left", "Right"):
    MIXAMO += [_s + n for n in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase")]

# короткие кости своего скелета (zombie_rig.py) -> Mixamo; у своего скелета грудь одна — берём верхний позвонок
SHORT_MAP = {"hips": "Hips", "spine": "Spine", "chest": "Spine2", "neck": "Neck", "head": "Head"}
for _sd, _s in (("l", "Left"), ("r", "Right")):
    SHORT_MAP.update({"clavicle_" + _sd: _s + "Shoulder", "upper_arm_" + _sd: _s + "Arm", "forearm_" + _sd: _s + "ForeArm",
                      "hand_" + _sd: _s + "Hand", "thigh_" + _sd: _s + "UpLeg", "shin_" + _sd: _s + "Leg",
                      "foot_" + _sd: _s + "Foot", "toe_" + _sd: _s + "ToeBase"})

FADE = 20          # кадров плавного сведения конца цикла к началу
MIN_LEN = 28
SEARCH = 45        # начало цикла ищется в первых SEARCH кадрах (после FADE), конец — в последних SEARCH: берётся почти вся запись
HEAD_WIN = 27      # полуокно (кадры) для курса и скользящего среднего таза ≈ шаг
SMOOTH = 3         # проходов сглаживания (мокап с видео дрожит; 1 — заметные рывки при ускоренном проигрывании)


def _short(name):
    return name.split(":")[-1].replace("mixamorig_", "")


def auto_map(rig):
    """Кость цели -> имя Mixamo (свой скелет — по SHORT_MAP, скелет Mixamo — по имени)."""
    m = {}
    for b in rig.data.bones:
        s = _short(b.name)
        if s in SHORT_MAP:
            m[b.name] = SHORT_MAP[s]
        elif s in MIXAMO:
            m[b.name] = s
    return m


def _wq(mat):
    return mat.to_3x3().normalized().to_quaternion()


def _align(qs):
    """Последовательность кватернионов без скачков знака."""
    for i in range(1, len(qs)):
        if qs[i].dot(qs[i - 1]) < 0:
            qs[i] = -qs[i]
    return qs


def _smooth_q(qs):
    out = []
    w = (1, 4, 6, 4, 1)
    n = len(qs)
    for i in range(n):
        acc = np.zeros(4)
        for k, wk in enumerate(w):
            j = min(max(i + k - 2, 0), n - 1)
            acc += wk * np.array(qs[j][:])
        out.append(Quaternion(acc / np.linalg.norm(acc)))
    return out


def _smooth_v(vs):
    a = np.array([v[:] for v in vs])
    b = a.copy()
    for i in range(len(a)):
        lo, hi = max(i - 2, 0), min(i + 3, len(a))
        b[i] = a[lo:hi].mean(axis=0)
    return [Vector(x) for x in b]


def _ordered(rig):
    out = []

    def rec(b):
        out.append(b)
        for c in b.children:
            rec(c)
    for b in rig.data.bones:
        if b.parent is None:
            rec(b)
    return out


def _lowest(rig, ob, track, frames):
    """Низшая точка меша по кадрам дорожки (остальные заглушены)."""
    sc = bpy.context.scene
    for tr in rig.animation_data.nla_tracks:
        tr.mute = tr.name != track if track else True
    lows = []
    mw = np.array(ob.matrix_world)
    for f in frames:
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        eo = ob.evaluated_get(dg)
        me = eo.to_mesh()
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        eo.to_mesh_clear()
        z = co.reshape(-1, 3) @ mw[2, :3] + mw[2, 3]
        lows.append(float(np.percentile(z, 0.2)))
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    return lows


def apply(rig, ob, fbx_path, name="walk"):
    sc = bpy.context.scene
    fps = sc.render.fps
    # --- мокап: загрузить и снять мировые ориентации костей по кадрам ---------------------------------
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    sc.render.fps = fps
    new = [o for o in bpy.data.objects if o not in before]
    src = [o for o in new if o.type == "ARMATURE"][0]
    sb = {_short(b.name): b for b in src.data.bones}
    act = src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    names = [n for n in MIXAMO if n in sb]
    rest_q = {n: _wq(src.matrix_world @ sb[n].matrix_local) for n in names}
    rest_dir = {n: (src.matrix_world.to_3x3() @ (sb[n].tail_local - sb[n].head_local)).normalized() for n in names}
    rest_hip = (src.matrix_world @ sb["Hips"].head_local).z
    Q = {n: [] for n in names}
    LQ = {n: [] for n in names}
    P = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for n in names:
            pb = src.pose.bones[sb[n].name]
            Q[n].append(_wq(src.matrix_world @ pb.matrix))
            LQ[n].append(pb.matrix_basis.to_quaternion())
        P.append((src.matrix_world @ src.pose.bones[sb["Hips"].name].matrix).translation.copy())
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for n in names:
        for _ in range(SMOOTH):
            Q[n] = _smooth_q(_align(Q[n]))
        LQ[n] = _align(LQ[n])
    for _ in range(SMOOTH):
        P = _smooth_v(P)
    T = len(P)

    # --- цикл: два самых похожих кадра (локальные повороты без таза + высота таза) ---------------------
    def diff(i, j):
        d = 0.0
        for n in names:
            if n == "Hips":
                continue
            d += LQ[n][i].rotation_difference(LQ[n][j]).angle
        up_i = Q["Hips"][i] @ Vector((0, 0, 1))
        up_j = Q["Hips"][j] @ Vector((0, 0, 1))
        return d + up_i.angle(up_j, 0.0) * 3 + abs(P[i].z - P[j].z) * 20
    # почти вся запись: начало — в первых SEARCH кадрах после FADE (кадры до него нужны для склейки), конец — в последних
    best = None
    min_len = max(MIN_LEN, int((T - FADE) * 0.7))
    for i in range(FADE, min(FADE + SEARCH, T - min_len)):
        for j in range(max(i + min_len, T - 1 - SEARCH), T):
            c = diff(i, j)
            if best is None or c < best[0]:
                best = (c, i, j - i)
    _, i0, N = best
    print("MOCAP frames %d, loop %d..%d (%d кадров, %.2f с), err %.3f" % (T, i0, i0 + N, N, N / fps, diff(i0, i0 + N)))

    # курс по кадрам: на длинной записи человек сворачивает — каждый кадр поворачиваем так, чтобы средний ход
    # (за шаг вперёд и назад) шёл к -Y (лицо моделей — к -Y); покачивания таза — отклонение от скользящего среднего
    hw = HEAD_WIN
    yaws = []
    for k in range(T):
        h = P[min(k + hw, T - 1)] - P[max(k - hw, 0)]
        a = math.atan2(h.x, -h.y)
        if yaws:
            a = yaws[-1] + (a - yaws[-1] + math.pi) % math.tau - math.pi
        yaws.append(a)
    for _ in range(3):
        yaws = [sum(yaws[max(k - 8, 0):k + 9]) / len(yaws[max(k - 8, 0):k + 9]) for k in range(T)]
    Yk = [Quaternion((0, 0, 1), -a) for a in yaws]
    M = []
    for k in range(T):
        seg = P[max(k - hw, 0):min(k + hw + 1, T)]
        M.append(sum(seg, Vector()) / len(seg))
    QC = {n: _align([Yk[k] @ Q[n][k] for k in range(T)]) for n in names}
    PC = []
    for k in range(T):
        r = Yk[k] @ Vector((P[k].x - M[k].x, P[k].y - M[k].y, 0.0))
        PC.append(Vector((r.x, r.y, P[k].z)))
    # путь таза — ломаная по шагам (покачивания внутри шага не считаются)
    ks = list(range(i0, i0 + N, hw)) + [i0 + N]
    path = sum(((P[ks[q + 1]] - P[ks[q]]).to_2d().length for q in range(len(ks) - 1)), 0.0)
    speed_src = path / (N / fps)

    def _w(t):
        w = (t - (N - FADE)) / FADE
        return w * w * (3 - 2 * w)

    def blend_q(n, t):
        a = QC[n][i0 + t]
        if t <= N - FADE:
            return a
        b = QC[n][i0 + t - N]
        if a.dot(b) < 0:
            b = -b
        return a.slerp(b, _w(t))

    def blend_p(t):
        a = PC[i0 + t]
        if t <= N - FADE:
            return a
        return a.lerp(PC[i0 + t - N], _w(t))

    # --- цель ------------------------------------------------------------------------------------------
    m = auto_map(rig)
    A = _wq(rig.matrix_world)
    Ainv = A.inverted()
    tb = {b.name: b for b in rig.data.bones}
    order = _ordered(rig)
    tgt_rest_q = {b.name: A @ b.matrix_local.to_quaternion() for b in order}
    off = {}
    for bn, sn in m.items():
        b = tb[bn]
        tdir = (rig.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()
        off[bn] = tdir.rotation_difference(rest_dir[sn])
    root = [b for b in order if _short(b.name) in ("hips", "Hips")][0]
    k_h = (rig.matrix_world @ root.head_local).z / rest_hip       # масштаб смещений таза по высоте таза
    speed = speed_src * k_h
    print("MOCAP map %d костей, масштаб %.3f, скорость %.2f м/с (мокап %.2f)" % (len(m), k_h, speed, speed_src))

    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def build(dz):
        a_ = bpy.data.actions.new(name)
        rig.animation_data_create()
        rig.animation_data.action = a_
        mwi = rig.matrix_world.inverted().to_3x3()
        prev = {}
        for t in range(N + 1):
            tt = t % N if t == N else t           # последний кадр = первый (бесшовный цикл)
            posed = {}
            for b in order:
                pb = rig.pose.bones[b.name]
                rel = (b.parent.matrix_local.inverted() @ b.matrix_local).to_quaternion() if b.parent else b.matrix_local.to_quaternion()
                par = posed[b.parent.name] if b.parent else Quaternion()
                if b.name in m:
                    sn = m[b.name]
                    D = blend_q(sn, tt) @ rest_q[sn].inverted()
                    W = D @ off[b.name] @ tgt_rest_q[b.name]
                    arm_q = Ainv @ W
                    basis = rel.inverted() @ par.inverted() @ arm_q
                else:
                    basis = Quaternion()
                    arm_q = par @ rel
                posed[b.name] = arm_q
                if b.name in prev and basis.dot(prev[b.name]) < 0:
                    basis = -basis              # без скачков знака между ключами
                prev[b.name] = basis
                pb.rotation_quaternion = basis
                pb.location = (0, 0, 0)
                if b == root:
                    r = blend_p(tt)       # высота таза мокапа относительно покоя (приседание мокапа сохраняется)
                    w_off = Vector((r.x * k_h, r.y * k_h, (r.z - rest_hip) * k_h + dz))
                    pb.location = b.matrix_local.to_3x3().inverted() @ (mwi @ w_off)
                pb.keyframe_insert("rotation_quaternion", frame=t + 1)
                pb.keyframe_insert("location", frame=t + 1)
        a_.use_fake_user = True
        trk = rig.animation_data.nla_tracks.new()
        trk.name = name
        trk.strips.new(name, 1, a_)
        rig.animation_data.action = None
        return a_

    rig.animation_data_create()
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)
    rest_low = min(_lowest(rig, ob, None, [1]))
    a1 = build(0.0)
    lows = _lowest(rig, ob, name, range(1, N + 2, 3))
    dz = rest_low - min(lows)
    rig.animation_data.nla_tracks.remove(rig.animation_data.nla_tracks[name])
    bpy.data.actions.remove(a1)
    build(dz)
    print("MOCAP ступни: покой %.3f, ходьба мин %.3f -> поправка %.3f" % (rest_low, min(lows), dz))
    return speed
