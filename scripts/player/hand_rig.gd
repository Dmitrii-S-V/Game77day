class_name HandRig
extends Node3D
## Правая рука от первого лица: предплечье с рукавом, ладонь, четыре пальца по три фаланги,
## большой палец, ногти и суставы (гладкие меши, не низкополигональные). Пальцы сгибаются
## по позам (расслаблена / хват топора / хват бутылки / открыта), рука анимируется:
## дыхание, шаг, удар, бросок, питьё.
## Система координат руки: начало — запястье, -Z вперёд (пальцы), +Z к локтю, ладонь смотрит на -X,
## большой палец вверх (+Y).

signal hit_moment
signal release_moment
signal drink_progress(fill: float)
signal drink_done
signal eat_done
signal reload_done
signal action_started(action: String)   # для модели от третьего лица (тень, другие игроки по сети)

const SKIN := Color(0.78, 0.58, 0.46)
const FINGER_Y := [0.032, 0.011, -0.011, -0.031]
const FINGER_LEN := [[0.040, 0.024, 0.020], [0.044, 0.027, 0.021], [0.040, 0.025, 0.020], [0.032, 0.019, 0.017]]
const FINGER_R := [0.0090, 0.0094, 0.0088, 0.0080]
const THUMB_LEN := [0.036, 0.031, 0.025]

# 17 значений: 4 пальца x (mcp, pip, dip) + большой (y, x, изгиб2, изгиб3, z)
# расслабленная кисть: пальцы слегка согнуты каскадом (к мизинцу сильнее), большой палец прижат
const POSE_RELAX := [0.34, 0.42, 0.22, 0.42, 0.52, 0.27, 0.50, 0.60, 0.30, 0.58, 0.66, 0.32, 0.45, -0.1, 0.22, 0.15, 0.10]
const POSE_OPEN := [0.06, 0.10, 0.05, 0.08, 0.12, 0.06, 0.10, 0.14, 0.07, 0.14, 0.16, 0.08, 0.15, -0.2, 0.05, 0.04, 0.0]
const POSE_AXE := [1.05, 1.45, 0.85, 1.12, 1.5, 0.9, 1.2, 1.55, 0.95, 1.28, 1.6, 1.0, 0.95, -0.35, 0.55, 0.45, 0.35]
const POSE_BOTTLE := [0.85, 1.2, 0.6, 0.92, 1.25, 0.65, 1.0, 1.3, 0.7, 1.08, 1.35, 0.75, 0.85, -0.3, 0.5, 0.4, 0.3]

const DEF_BASE_POS := Vector3(0.19, -0.20, -0.36)
const DEF_BASE_ROT := Vector3(0.10, 0.18, 0.0)
# положение руки по умолчанию для отдельных предметов (пистолет — выше и ближе к центру, ствол к прицелу)
const ITEM_BASE := {"pistol": [Vector3(0.1, -0.165, -0.31), Vector3(0.0, 0.06, 0.0)]}

var base_pos := DEF_BASE_POS
var base_rot := DEF_BASE_ROT
var _def_item_pos := Vector3.ZERO     # значения по умолчанию из кода (для сброса в отладке)
var _def_item_rot := Vector3.ZERO
var _def_item_scale := 1.0
var speed := 0.0          # 0..1, скорость ходьбы (качание)
var look_delta := Vector2.ZERO
var item_id := ""
var fill := 1.0

var _fingers: Array = []
var _thumb: Dictionary = {}
var _grip: Node3D
var _item: Node3D
var _liquid: BottleLiquid
var _pose := PackedFloat32Array()
var _target := PackedFloat32Array()
var _t := 0.0
var _bob := 0.0
var _action := ""
var _at := 0.0
var _fired := false
var _fill0 := 1.0
var _sway := Vector2.ZERO
var _seg_cache := {}

# модель руки со скелетом (assets/ready/arm_fp.glb, scripts/ai3d/arm_rig.py): та же система координат,
# пальцы сгибаются поворотом костей вокруг их локальной оси X (минус — к ладони)
const ARM_GLB := "res://assets/ready/arm_fp.glb"
const ARM_SCALE := 1.15            # модель чуть мельче реальной руки
const FINGER_BONES := ["index", "middle", "ring", "pinky"]   # порядок как у FINGER_Y (от большого пальца)
var _skel: Skeleton3D
var _bone := {}                    # имя кости -> индекс
var _rest := {}                    # индекс -> Quaternion покоя
var _spread := {}                  # палец -> угол сведения к среднему
var wrist := Vector3.ZERO          # сгиб запястья (кость hand): x — к ладони, y — вбок, z — поворот (рад)
var _def_target := PackedFloat32Array()   # поза пальцев по умолчанию для текущего предмета (сброс в F9)
const EMPTY_ID := "_empty"         # ключ позы пустой руки в data/item_poses.json


func _ready() -> void:
	_pose = PackedFloat32Array(POSE_RELAX)
	_target = PackedFloat32Array(POSE_RELAX)
	_build()
	position = base_pos
	rotation = base_rot


func busy() -> bool:
	return _action != ""


func play(action: String) -> void:
	if _action != "":
		return
	_action = action
	_at = 0.0
	_fired = false
	_fill0 = fill
	action_started.emit(action)


func set_item(id: String, f: float = 1.0) -> void:
	if id == item_id and absf(f - fill) < 0.001 and _item != null:
		return
	item_id = id
	fill = f
	if _item != null:
		_item.queue_free()
		_item = null
	_liquid = null
	match id:
		"stone_axe":
			_item = ItemModels.stone_axe()
			_item.position = Vector3(0, -0.01, 0)
			_item.rotation = Vector3(-0.32, 0.0, -0.12)
			_target = PackedFloat32Array(POSE_AXE)
		"water_bottle", "glass_bottle":
			var b := ItemModels.bottle(id == "water_bottle")
			_item = b["root"]
			_item.position = Vector3(0, -0.075, 0)
			if b["liquid_mat"] != null:
				_liquid = BottleLiquid.new(_item, b["liquid_mat"], f)
			_target = PackedFloat32Array(POSE_BOTTLE)
		"wooden_club":
			_item = ItemModels.club()
			_item.position = Vector3(0, -0.02, 0)
			_item.rotation = Vector3(-0.45, 0.0, -0.3)
			_item.scale = Vector3.ONE * 0.85
			_target = PackedFloat32Array(POSE_AXE)
		"pistol":
			_item = ItemModels.pistol()
			_item.position = Vector3(0.0, -0.042, 0.01)
			_item.scale = Vector3.ONE * 1.2
			_target = PackedFloat32Array(POSE_AXE)
		"canned_food", "berries", "candy_bar":
			_item = ItemModels.food(id)
			_item.position = Vector3(0, -0.01, 0)
			_target = PackedFloat32Array(POSE_BOTTLE)
		_:
			_target = PackedFloat32Array(POSE_RELAX)
	_def_target = _target.duplicate()
	_find_gun_parts()
	if _item != null:
		_grip.add_child(_item)
		_def_item_pos = _item.position
		_def_item_rot = _item.rotation
		_def_item_scale = _item.scale.x
	_apply_saved_pose()


## Позы из data/item_poses.json (подгонка отладчиком ItemPoseDebug).
func pose_key() -> String:
	return item_id if item_id != "" else EMPTY_ID


func _apply_saved_pose() -> void:
	var p := ItemPoses.get_pose(pose_key())
	var def_pos: Vector3 = ITEM_BASE.get(item_id, [DEF_BASE_POS, DEF_BASE_ROT])[0]
	var def_rot: Vector3 = ITEM_BASE.get(item_id, [DEF_BASE_POS, DEF_BASE_ROT])[1]
	base_pos = ItemPoses.vec(p.get("hand_pos"), def_pos)
	var hr := ItemPoses.vec(p.get("hand_rot"), Vector3(rad_to_deg(def_rot.x), rad_to_deg(def_rot.y), rad_to_deg(def_rot.z)))
	base_rot = Vector3(deg_to_rad(hr.x), deg_to_rad(hr.y), deg_to_rad(hr.z))
	# сгибы пальцев и запястья (подгонка в F9, режим «Пальцы»)
	var fg: Variant = p.get("fingers")
	if fg is Array and (fg as Array).size() == _target.size():
		for i in _target.size():
			_target[i] = float(fg[i])
	wrist = ItemPoses.vec(p.get("wrist"), Vector3.ZERO)
	if _item == null:
		return
	if p.has("item_pos"):
		_item.position = ItemPoses.vec(p.get("item_pos"), _def_item_pos)
	if p.has("item_rot"):
		_item.rotation_degrees = ItemPoses.vec(p.get("item_rot"), Vector3.ZERO)
	if p.has("item_scale"):
		_item.scale = Vector3.ONE * float(p["item_scale"])


## Дуло пистолета в мировых координатах (для вспышки).
func muzzle_global() -> Vector3:
	if _item == null:
		return global_position
	var mz := _item.get_node_or_null("muzzle") as Node3D
	return mz.global_position if mz != null else global_position


## Детали пистолета: затвор откатывается при выстреле (и встаёт на задержку, когда патроны кончились),
## магазин при перезарядке выпадает вниз и вставляется новый.
var slide_locked := false
var _gun_parts := {}     # имя -> [Node3D, позиция покоя]
var _slide_k := 0.0
const SLIDE_TRAVEL := 0.024
const MAG_DIR := Vector3(0.0, -1.0, 0.22)


func _find_gun_parts() -> void:
	_gun_parts.clear()
	if _item == null:
		return
	for nm in ["slide", "mag", "bullet", "hammer", "trigger"]:
		var n := _item.find_child(nm, true, false) as Node3D
		if n != null:
			_gun_parts[nm] = [n, n.position]


func _gun_part(nm: String, off: Vector3) -> void:
	if _gun_parts.has(nm):
		var e: Array = _gun_parts[nm]
		(e[0] as Node3D).position = (e[1] as Vector3) + off


func _animate_gun(delta: float) -> void:
	if _gun_parts.is_empty():
		return
	# затвор: при выстреле — рывок назад и возврат; на задержке — остаётся сзади
	var want := 1.0 if slide_locked else 0.0
	if _action == "shoot":
		if _at < 0.025:
			want = _at / 0.025
		elif not slide_locked:
			want = maxf(0.0, 1.0 - (_at - 0.025) / 0.07)
		_slide_k = want
	else:
		_slide_k = move_toward(_slide_k, want, delta * 25.0)
	_gun_part("slide", Vector3(0.0, 0.0, SLIDE_TRAVEL * _slide_k))
	_gun_part("hammer", Vector3(0.0, 0.0, 0.004 * _slide_k))
	_gun_part("trigger", Vector3(0.0, 0.0, 0.004 if _action == "shoot" and _at < 0.06 else 0.0))
	# магазин: 0.15–0.35 с выпадает, 0.55–0.8 с вставляется новый
	var drop := 0.0
	if _action == "reload":
		if _at > 0.15 and _at < 0.55:
			drop = smoothstep(0.15, 0.35, _at)
		elif _at >= 0.55 and _at < 0.8:
			drop = 1.0 - smoothstep(0.55, 0.8, _at)
	var mo := MAG_DIR.normalized() * 0.16 * drop
	_gun_part("mag", mo)
	_gun_part("bullet", mo)
	if _gun_parts.has("mag"):
		(_gun_parts["mag"][0] as Node3D).visible = drop < 0.95
	if _gun_parts.has("bullet"):
		(_gun_parts["bullet"][0] as Node3D).visible = drop < 0.95 and not (slide_locked and _action != "reload")


func reset_pose_defaults() -> void:
	base_pos = ITEM_BASE.get(item_id, [DEF_BASE_POS, DEF_BASE_ROT])[0]
	base_rot = ITEM_BASE.get(item_id, [DEF_BASE_POS, DEF_BASE_ROT])[1]
	wrist = Vector3.ZERO
	if not _def_target.is_empty():
		_target = _def_target.duplicate()
	if _item != null:
		_item.position = _def_item_pos
		_item.rotation = _def_item_rot
		_item.scale = Vector3.ONE * _def_item_scale


func _process(delta: float) -> void:
	_t += delta
	# хват: плавное приближение к целевой позе
	var k := 1.0 - exp(-14.0 * delta)
	for i in _pose.size():
		_pose[i] = lerpf(_pose[i], _target[i], k)
	_apply_pose()
	# качание от шага и дыхания, инерция взгляда
	_bob += delta * (4.0 + speed * 6.0)
	_sway = _sway.lerp(look_delta, 1.0 - exp(-10.0 * delta)) * (1.0 - 0.05)
	look_delta = Vector2.ZERO
	var p := base_pos + Vector3(sin(_t * 1.3) * 0.002, sin(_t * 1.9) * 0.0025, 0.0)
	p += Vector3(sin(_bob * 0.5) * 0.008 * speed, absf(sin(_bob)) * -0.012 * speed, 0.0)
	var r := base_rot + Vector3(-_sway.y * 0.004, -_sway.x * 0.004, 0.0)
	if _action != "":
		_at += delta
		var pr := _action_pose(_action, _at)
		p += pr[0]
		r += pr[1]
	position = p
	rotation = r
	_animate_gun(delta)
	if _liquid != null:
		_liquid.fill = fill
		_liquid.update(delta)


func _key(keys: Array, t: float) -> Array:
	# keys: [[time, pos, rot], ...] — гладкая интерполяция
	if t <= keys[0][0]:
		return [keys[0][1], keys[0][2]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var u := smoothstep(0.0, 1.0, (t - float(a[0])) / (float(b[0]) - float(a[0])))
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u)]
	var last: Array = keys[keys.size() - 1]
	return [last[1], last[2]]


func _action_pose(action: String, t: float) -> Array:
	var z := Vector3.ZERO
	match action:
		"punch":
			# удар кулаком: замах к себе, прямой выпад вперёд, возврат; пальцы — в кулак (поза хвата без предмета)
			if t < 0.05:
				_target = PackedFloat32Array(POSE_AXE)
			if t >= 0.2 and not _fired:
				_fired = true
				hit_moment.emit()
			if t >= 0.44:
				_action = ""
				_target = _def_target.duplicate()
			return _key([
				[0.0, z, z], [0.1, Vector3(0.02, -0.02, 0.07), Vector3(0.12, 0.05, 0.1)],
				[0.2, Vector3(-0.03, 0.04, -0.3), Vector3(-0.08, 0.02, -0.06)],
				[0.27, Vector3(-0.025, 0.035, -0.26), Vector3(-0.06, 0.02, -0.05)], [0.44, z, z]], t)
		"swing":
			if t >= 0.30 and not _fired:
				_fired = true
				hit_moment.emit()
			if t >= 0.62:
				_action = ""
			return _key([
				[0.0, z, z], [0.20, Vector3(0.06, 0.11, 0.14), Vector3(0.9, -0.15, -0.5)],
				[0.32, Vector3(-0.07, -0.13, -0.24), Vector3(-0.6, 0.12, 0.4)],
				[0.44, Vector3(-0.06, -0.11, -0.2), Vector3(-0.5, 0.12, 0.35)], [0.62, z, z]], t)
		"throw":
			if t >= 0.31 and not _fired:
				_fired = true
				_target = PackedFloat32Array(POSE_OPEN)
				release_moment.emit()
			if t >= 0.58:
				_action = ""
			return _key([
				[0.0, z, z], [0.20, Vector3(0.07, 0.09, 0.2), Vector3(0.75, -0.1, -0.3)],
				[0.32, Vector3(-0.05, -0.03, -0.32), Vector3(-0.3, 0.05, 0.2)], [0.58, z, z]], t)
		"drink":
			var d := 0.0
			if t > 0.95 and t < 2.05:
				d = (t - 0.95) / 1.1
				fill = maxf(_fill0 * (1.0 - d), 0.0)
				drink_progress.emit(fill)
			elif t >= 2.05:
				fill = 0.0
			if t >= 2.7:
				_action = ""
				drink_done.emit()
			return _key([
				[0.0, z, z], [0.55, Vector3(-0.10, 0.02, 0.02), Vector3(0.85, 0.0, 0.15)],
				[1.0, Vector3(-0.12, 0.04, 0.04), Vector3(1.2, 0.0, 0.2)],
				[2.05, Vector3(-0.12, 0.04, 0.04), Vector3(1.28, 0.0, 0.2)], [2.7, z, z]], t)
		"shoot":
			# отдача: рывок назад-вверх и быстрый возврат
			if t >= 0.2:
				_action = ""
			return _key([[0.0, z, z], [0.03, Vector3(0.0, 0.012, 0.05), Vector3(0.22, 0.0, 0.0)], [0.2, z, z]], t)
		"reload":
			# опустить и повернуть, сменить магазин, вернуть
			if t >= 1.05 and not _fired:
				_fired = true
				reload_done.emit()
			if t >= 1.3:
				_action = ""
			return _key([
				[0.0, z, z], [0.25, Vector3(-0.03, -0.08, 0.04), Vector3(-0.35, 0.2, 0.6)],
				[0.6, Vector3(-0.03, -0.1, 0.04), Vector3(-0.4, 0.2, 0.65)], [0.75, Vector3(-0.03, -0.07, 0.04), Vector3(-0.3, 0.2, 0.6)],
				[1.3, z, z]], t)
		"eat":
			# поднести ко рту, три «укуса», опустить
			if t >= 1.05 and not _fired:
				_fired = true
				eat_done.emit()
			if t >= 1.45:
				_action = ""
			var bite := sin(clampf((t - 0.45) / 0.6, 0.0, 1.0) * PI * 3.0) * 0.012
			var kp: Array = _key([
				[0.0, z, z], [0.4, Vector3(-0.11, 0.07, 0.1), Vector3(0.6, 0.0, 0.35)],
				[1.05, Vector3(-0.11, 0.07, 0.1), Vector3(0.62, 0.0, 0.35)], [1.45, z, z]], t)
			return [(kp[0] as Vector3) + Vector3(0.0, bite, 0.0), kp[1]]
	_action = ""
	return [z, z]


func _bone_rot(nm: String, flex: float, twist: float = 0.0, side: float = 0.0) -> void:
	var bi: int = _bone.get(nm, -1)
	if bi < 0:
		return
	# сначала разведение/сведение (вокруг оси к тылу кисти), потом сгиб в уже повёрнутой кости
	var q: Quaternion = _rest[bi] * Quaternion(Vector3.BACK, side) * Quaternion(Vector3.UP, twist) * Quaternion(Vector3.RIGHT, -flex)
	_skel.set_bone_pose_rotation(bi, q)


## Угол, на который нужно повернуть основание пальца вокруг его оси Z, чтобы он смотрел параллельно среднему
## (в модели пальцы растопырены).
func _spread_of(fn: String) -> float:
	var b1: int = _bone.get(fn + "_1", -1)
	var b2: int = _bone.get(fn + "_2", -1)
	var m1: int = _bone.get("middle_1", -1)
	var m2: int = _bone.get("middle_2", -1)
	if b1 < 0 or b2 < 0 or m1 < 0 or m2 < 0 or fn == "middle":
		return 0.0
	var g1 := _skel.get_bone_global_rest(b1)
	var ref := _skel.get_bone_global_rest(m2).origin - _skel.get_bone_global_rest(m1).origin
	var l := g1.basis.inverse() * ref
	return atan2(-l.x, l.y)


func _apply_pose() -> void:
	if _skel != null:
		# чем сильнее сжат кулак, тем плотнее сведены пальцы
		var close := clampf(_pose[3] / 1.1, 0.0, 1.0)
		for i in 4:
			var fn: String = FINGER_BONES[i]
			_bone_rot(fn + "_1", _pose[i * 3], 0.0, float(_spread.get(fn, 0.0)) * lerpf(0.7, 0.95, close))
			_bone_rot(fn + "_2", _pose[i * 3 + 1])
			_bone_rot(fn + "_3", _pose[i * 3 + 2])
		# большой палец: [12] — подвод к ладони, [13] — разворот, [14]/[15] — сгиб фаланг, [16] — наклон
		_bone_rot("thumb_1", _pose[12] * 0.55, _pose[13], _pose[16])
		_bone_rot("thumb_2", _pose[14] * 1.2)
		_bone_rot("thumb_3", _pose[15] * 1.2)
		_bone_rot("hand", wrist.x, wrist.z, wrist.y)
		return
	for i in 4:
		var f: Dictionary = _fingers[i]
		(f["root"] as Node3D).rotation = Vector3(0, _pose[i * 3], 0)
		(f["j2"] as Node3D).rotation = Vector3(0, _pose[i * 3 + 1], 0)
		(f["j3"] as Node3D).rotation = Vector3(0, _pose[i * 3 + 2], 0)
	(_thumb["root"] as Node3D).rotation = Vector3(_pose[13], _pose[12], _pose[16])
	(_thumb["j2"] as Node3D).rotation = Vector3(0, _pose[14], 0)
	(_thumb["j3"] as Node3D).rotation = Vector3(0, _pose[15], 0)


# --- построение ---------------------------------------------------------------------

func _segment(length: float, r0: float, r1: float) -> ArrayMesh:
	var key := "%f_%f_%f" % [length, r0, r1]
	if _seg_cache.has(key):
		return _seg_cache[key]
	var prof: Array = [
		Vector2(r0, 0.0), Vector2(lerpf(r0, r1, 0.33), length * 0.33), Vector2(lerpf(r0, r1, 0.66), length * 0.66), Vector2(r1, length),
		Vector2(r1 * 0.94, length + r1 * 0.38), Vector2(r1 * 0.74, length + r1 * 0.72), Vector2(r1 * 0.4, length + r1 * 0.93), Vector2(0.0, length + r1),
	]
	var m := ItemModels.lathe(prof, 16, Color.WHITE)
	_seg_cache[key] = m
	return m


func _mi(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	return s


func _chain(parent: Node3D, lens: Array, r: float, skin: Material, nail: Material) -> Array:
	var nodes: Array = []
	var cur := parent
	var rr := r
	for s in lens.size():
		var l: float = lens[s]
		var seg := _mi(_segment(l, rr, rr * 0.88), skin, cur)
		seg.rotation.x = -PI * 0.5
		_mi(_sphere(rr * 0.98), skin, cur)
		nodes.append(cur)
		if s < lens.size() - 1:
			var nxt := Node3D.new()
			nxt.position = Vector3(0, 0, -l)
			cur.add_child(nxt)
			cur = nxt
		rr *= 0.88
	# ноготь на последней фаланге (тыльная сторона +X)
	var nl: float = lens[lens.size() - 1]
	var nm := _mi(_sphere(0.5), nail, cur)
	nm.scale = Vector3(0.0075, 0.0145, 0.016)
	nm.position = Vector3(rr * 1.08, 0.0, -nl * 0.66)
	return nodes


## Модель руки со скелетом. true, если загружена (тогда процедурная рука не строится).
func _build_model() -> bool:
	if not ResourceLoader.exists(ARM_GLB):
		return false
	var scene := load(ARM_GLB) as PackedScene
	if scene == null:
		return false
	var root := scene.instantiate() as Node3D
	root.scale = Vector3.ONE * ARM_SCALE
	add_child(root)
	var sk := root.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		root.queue_free()
		return false
	_skel = sk[0] as Skeleton3D
	for bi in _skel.get_bone_count():
		_bone[_skel.get_bone_name(bi)] = bi
		_rest[bi] = _skel.get_bone_rest(bi).basis.get_rotation_quaternion()
	for fn in FINGER_BONES:
		_spread[fn] = _spread_of(fn)
	print("ARM spread ", _spread)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grip = Node3D.new()
	_grip.position = GRIP_POS
	add_child(_grip)
	return true


const GRIP_POS := Vector3(-0.022, 0.0, -0.092)   # точка хвата предмета (в кольце согнутых пальцев)


func _build() -> void:
	if _build_model():
		return
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.62
	skin.rim_enabled = true
	skin.rim = 0.18
	skin.rim_tint = 0.65
	var nail := StandardMaterial3D.new()
	nail.albedo_color = Color(0.93, 0.8, 0.74)
	nail.roughness = 0.28
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.27, 0.22)
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cuff := StandardMaterial3D.new()
	cuff.albedo_color = Color(0.15, 0.2, 0.17)
	cuff.roughness = 0.9
	cuff.cull_mode = BaseMaterial3D.CULL_DISABLED

	# ладонь и основание большого пальца
	var palm := _mi(_sphere(0.5), skin, self)
	palm.scale = Vector3(0.036, 0.088, 0.108)
	palm.position = Vector3(0.0, 0.0, -0.052)
	var heel := _mi(_sphere(0.5), skin, self)
	heel.scale = Vector3(0.034, 0.075, 0.06)
	heel.position = Vector3(-0.004, 0.006, -0.022)
	var thenar := _mi(_sphere(0.5), skin, self)
	thenar.scale = Vector3(0.03, 0.036, 0.06)
	thenar.position = Vector3(-0.008, 0.034, -0.03)
	thenar.rotation = Vector3(0.0, 0.0, 0.0)
	# запястье и предплечье (к локтю — +Z)
	_mi(_sphere(0.034), skin, self)
	var fore := _mi(ItemModels.lathe([Vector2(0.034, 0.0), Vector2(0.040, 0.18), Vector2(0.046, 0.36), Vector2(0.05, 0.6), Vector2(0.0, 0.6)], 18, Color.WHITE), skin, self)
	fore.rotation.x = PI * 0.5
	# рукав
	var sleeve := _mi(ItemModels.lathe([Vector2(0.050, 0.11), Vector2(0.056, 0.2), Vector2(0.066, 0.4), Vector2(0.074, 0.62)], 20, Color.WHITE), cloth, self)
	sleeve.rotation.x = PI * 0.5
	var cuff_m := _mi(ItemModels.lathe([Vector2(0.047, 0.095), Vector2(0.058, 0.095), Vector2(0.058, 0.125), Vector2(0.050, 0.125)], 20, Color.WHITE), cuff, self)
	cuff_m.rotation.x = PI * 0.5

	# пальцы
	for i in 4:
		var root := Node3D.new()
		root.position = Vector3(-0.002, FINGER_Y[i], -0.093)
		add_child(root)
		var nodes := _chain(root, FINGER_LEN[i], FINGER_R[i], skin, nail)
		_fingers.append({"root": nodes[0], "j2": nodes[1], "j3": nodes[2]})
	# большой палец
	var troot := Node3D.new()
	troot.position = Vector3(-0.012, 0.040, -0.036)
	add_child(troot)
	var tn := _chain(troot, THUMB_LEN, 0.0108, skin, nail)
	_thumb = {"root": tn[0], "j2": tn[1], "j3": tn[2]}

	# точка хвата предмета
	_grip = Node3D.new()
	_grip.position = Vector3(-0.022, 0.0, -0.092)
	add_child(_grip)
