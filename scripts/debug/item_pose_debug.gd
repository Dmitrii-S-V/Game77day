class_name ItemPoseDebug
extends Node
## Отладка: подгонка положения предмета в руке и самой руки. F9 — включить/выключить; при выключении всё
## сохраняется в data/item_poses.json (и подхватывается игрой). Редактируется предмет в руке (выбранный слот).
##   Мышью (манипулятор, как в редакторе): стрелки X красная / Y зелёная / Z синяя — тянуть ЛКМ для сдвига,
##   кольца тех же цветов — поворот вокруг оси; колесо — масштаб предмета; ПКМ (держать) — осмотреться.
##   H — что двигать (предмет / рука), G — оси (родителя / собственные).
##   Клавишами:  стрелки ←/→ X, ↑/↓ Y, PgUp/PgDn Z;  J/L поворот Y, I/K поворот X, U/O поворот Z;  =/- масштаб
##   Рука (с зажатым Alt): те же клавиши двигают/поворачивают руку
##   Shift — точнее, Ctrl — грубее;  R — сброс к значениям по умолчанию;  ЛКМ — удар (проверить замах)
##   P — режим «Пальцы»: [ / ] — выбрать сустав, ←/→ — согнуть/разогнуть (сохраняется для предмета или пустой руки)

const JOINTS := [
	"указательный: основание", "указательный: средний сустав", "указательный: кончик",
	"средний: основание", "средний: средний сустав", "средний: кончик",
	"безымянный: основание", "безымянный: средний сустав", "безымянный: кончик",
	"мизинец: основание", "мизинец: средний сустав", "мизинец: кончик",
	"большой: подвод к ладони", "большой: разворот", "большой: сгиб 1", "большой: сгиб 2", "большой: наклон",
	"запястье: сгиб к ладони", "запястье: вбок", "запястье: поворот",
]

var hand: HandRig
var _fingers_mode := false
var _joint := 0
var active := false
var _label: Label
var _layer: CanvasLayer
var _item_pos := Vector3.ZERO
var _item_rot := Vector3.ZERO      # градусы
var _item_scale := 1.0
var _hand_pos := Vector3.ZERO
var _hand_rot := Vector3.ZERO      # градусы
var _id := ""

# --- манипулятор мышью ---
const AX_COL := [Color(0.95, 0.22, 0.2), Color(0.3, 0.88, 0.25), Color(0.25, 0.48, 1.0)]
const HOVER_COL := Color(1.0, 0.9, 0.15)
var _giz: Node3D
var _handles: Array = []      # {kind: "move"|"rot", axis: 0..2, mat}
var _hover := -1
var _drag := -1
var _drag_last := Vector2.ZERO
var _target_hand := false     # H: двигать руку, а не предмет
var _local_axes := false      # G: оси самого объекта, а не родителя
var _auto := ""


func _ready() -> void:
	_build_gizmo()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--posedbg="):   # отладка снимков: включить, когда в руке этот предмет
			_auto = a.substr(10)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(12, 90)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.visible = false
	_layer.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_F9:
			_toggle()
		elif active and k == KEY_R:
			_reset()
		elif active and k == KEY_P:
			_set_fingers(not _fingers_mode)
		elif active and k == KEY_H:
			_target_hand = not _target_hand
		elif active and k == KEY_G:
			_local_axes = not _local_axes
		elif active and _fingers_mode and k == KEY_BRACKETRIGHT:
			_joint = (_joint + 1) % JOINTS.size()
		elif active and _fingers_mode and k == KEY_BRACKETLEFT:
			_joint = (_joint - 1 + JOINTS.size()) % JOINTS.size()


func _toggle() -> void:
	if hand == null:
		return
	if not active:
		_id = hand.pose_key()   # пустая рука — своя поза (_empty): пальцы, запястье, положение руки
		_load_current()
		active = true
		_label.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # курсор — для манипулятора
		print("ItemPoseDebug: ВКЛ для '%s'" % _id)
	else:
		_close()


func _close() -> void:
	_set_fingers(false)
	active = false
	_label.visible = false
	_giz.visible = false
	_dots.visible = false
	_drag = -1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_save()


func _load_current() -> void:
	if hand._item != null:
		_item_pos = hand._item.position
		_item_rot = hand._item.rotation_degrees
		_item_scale = hand._item.scale.x
	_hand_pos = hand.base_pos
	_hand_rot = Vector3(rad_to_deg(hand.base_rot.x), rad_to_deg(hand.base_rot.y), rad_to_deg(hand.base_rot.z))


func _reset() -> void:
	hand.reset_pose_defaults()
	_load_current()
	print("ItemPoseDebug: сброс к значениям по умолчанию")


func _process(delta: float) -> void:
	if _auto != "" and hand != null and hand.pose_key() == _auto and not active:
		_auto = ""
		_toggle()
		_set_fingers(OS.get_cmdline_user_args().has("--posedbg_fingers=1"))
		if OS.get_cmdline_user_args().has("--posedbg_orbit=1"):   # отладка снимка: вид сбоку
			_orbit_yaw = 1.3
			_orbit_pitch = -0.3
	if not active:
		return
	if hand == null or hand.pose_key() != _id:
		# сменили предмет — сохраняем сделанное и выходим
		_close()
		return
	var has_item := hand._item != null
	var mult := 1.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		mult = 0.2
	elif Input.is_physical_key_pressed(KEY_CTRL):
		mult = 4.0
	var hand_mode := Input.is_physical_key_pressed(KEY_ALT) or _target_hand
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_RIGHT): mv.x += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT): mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_UP): mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_PAGEUP): mv.z -= 1.0
	if Input.is_physical_key_pressed(KEY_PAGEDOWN): mv.z += 1.0
	var rt := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_I): rt.x += 1.0
	if Input.is_physical_key_pressed(KEY_K): rt.x -= 1.0
	if Input.is_physical_key_pressed(KEY_L): rt.y += 1.0
	if Input.is_physical_key_pressed(KEY_J): rt.y -= 1.0
	if Input.is_physical_key_pressed(KEY_O): rt.z += 1.0
	if Input.is_physical_key_pressed(KEY_U): rt.z -= 1.0
	var sc := 0.0
	if Input.is_physical_key_pressed(KEY_EQUAL): sc += 1.0
	if Input.is_physical_key_pressed(KEY_MINUS): sc -= 1.0
	if _fingers_mode:
		_update_orbit()
		_update_finger_gizmo()
		# сгиб выбранного сустава: ←/→ (рад/с), значение сразу видно — рука плавно догоняет
		var dv := (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
		dv *= 0.8 * delta * mult
		var val := _joint_value()
		_set_joint_value(val + dv)
		_label.text = "ОТЛАДКА ПОЗЫ  [%s]   режим: ПАЛЬЦЫ\nсустав %d/%d: %s = %.2f\nМЫШЬ: клик по точке — выбрать сустав, тянуть кольцо — согнуть (красное) / повернуть (зелёное) / наклонить (синее)\nклавиши: [ / ] — выбрать сустав,  ←/→ — согнуть/разогнуть,  Shift точнее, Ctrl грубее\nКАМЕРА: ПКМ тянуть — облёт вокруг ладони, колесо — приближение, СКМ тянуть — сдвиг\nP — назад к предмету/руке,  R — сброс,  F9 — закрыть и сохранить\n%s" % [
			_id, _joint + 1, JOINTS.size(), JOINTS[_joint], _joint_value(), _all_joints()]
		return
	var dpos := mv * 0.12 * delta * mult
	var drot := rt * 60.0 * delta * mult
	if hand_mode or not has_item:
		_hand_pos += dpos
		_hand_rot += drot
	else:
		_item_pos += dpos
		_item_rot += drot
		_item_scale = maxf(_item_scale * (1.0 + sc * 0.6 * delta * mult), 0.01)
	if has_item:
		hand._item.position = _item_pos
		hand._item.rotation_degrees = _item_rot
		hand._item.scale = Vector3.ONE * _item_scale
	hand.base_pos = _hand_pos
	hand.base_rot = Vector3(deg_to_rad(_hand_rot.x), deg_to_rad(_hand_rot.y), deg_to_rad(_hand_rot.z))
	_update_gizmo()
	_label.text = "ОТЛАДКА ПОЗЫ  [%s]   двигаем: %s (H)   оси: %s (G)\nпредмет  pos %s  rot %s  scale %.3f\nрука     pos %s  rot %s\nМЫШЬ: тянуть стрелку — сдвиг, кольцо — поворот, колесо — масштаб, ПКМ держать — осмотреться\nклавиши: стрелки/PgUp/PgDn — сдвиг, I/K J/L U/O — поворот, =/- масштаб\nP — пальцы и запястье,  Shift точнее, Ctrl грубее, R — сброс, F9 — закрыть и сохранить" % [
		_id, "РУКА" if (hand_mode or not has_item) else "ПРЕДМЕТ", "собственные" if _local_axes else "родителя",
		_fmt(_item_pos), _fmt(_item_rot, 1), _item_scale, _fmt(_hand_pos), _fmt(_hand_rot, 1)]


func _joint_value() -> float:
	if _joint < hand._target.size():
		return hand._target[_joint]
	var w: Vector3 = hand.wrist
	var arr: Array = [w.x, w.y, w.z]
	return float(arr[_joint - hand._target.size()])


func _set_joint_value(v: float) -> void:
	v = clampf(v, -1.6, 2.2)
	if _joint < hand._target.size():
		hand._target[_joint] = v
		return
	match _joint - hand._target.size():
		0: hand.wrist.x = v
		1: hand.wrist.y = v
		_: hand.wrist.z = v


func _all_joints() -> String:
	var s := ""
	for i in JOINTS.size():
		var saved := _joint
		_joint = i
		s += ("> " if i == saved else "   ") + "%s %.2f\n" % [JOINTS[i], _joint_value()]
		_joint = saved
	return s


func _fmt(v: Vector3, d: int = 3) -> String:
	return "(%s, %s, %s)" % [String.num(v.x, d), String.num(v.y, d), String.num(v.z, d)]


func _save() -> void:
	var pose := {
		"hand_pos": [snappedf(_hand_pos.x, 0.0005), snappedf(_hand_pos.y, 0.0005), snappedf(_hand_pos.z, 0.0005)],
		"hand_rot": [snappedf(_hand_rot.x, 0.1), snappedf(_hand_rot.y, 0.1), snappedf(_hand_rot.z, 0.1)],
	}
	if _id != HandRig.EMPTY_ID:
		pose["item_pos"] = [snappedf(_item_pos.x, 0.0005), snappedf(_item_pos.y, 0.0005), snappedf(_item_pos.z, 0.0005)]
		pose["item_rot"] = [snappedf(_item_rot.x, 0.1), snappedf(_item_rot.y, 0.1), snappedf(_item_rot.z, 0.1)]
		pose["item_scale"] = snappedf(_item_scale, 0.0005)
	var fg: Array = []
	for v in hand._target:
		fg.append(snappedf(v, 0.01))
	pose["fingers"] = fg
	pose["wrist"] = [snappedf(hand.wrist.x, 0.01), snappedf(hand.wrist.y, 0.01), snappedf(hand.wrist.z, 0.01)]
	ItemPoses.set_pose(_id, pose)
	var ok := ItemPoses.save()
	print("ItemPoseDebug: сохранено '%s' -> %s (%s)" % [_id, ItemPoses.PATH, "ok" if ok else "ОШИБКА записи"])
	print(JSON.stringify(pose))


# --- манипулятор (стрелки сдвига и кольца поворота) ------------------------------------------

func _gizmo_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true          # всегда поверх руки и предмета
	m.render_priority = 20
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Единичный манипулятор (длина стрелки 1), масштабируется под расстояние до камеры.
func _build_gizmo() -> void:
	_giz = Node3D.new()
	_giz.visible = false
	add_child(_giz)
	var to_axis := [Basis(Vector3.BACK, -PI * 0.5), Basis.IDENTITY, Basis(Vector3.RIGHT, PI * 0.5)]   # +Y -> X / Y / Z
	for i in 3:
		var mat := _gizmo_mat(AX_COL[i])
		var arrow := Node3D.new()
		arrow.basis = to_axis[i]
		_giz.add_child(arrow)
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = 0.8
		cm.radial_segments = 8
		shaft.mesh = cm
		shaft.position.y = 0.4
		shaft.material_override = mat
		arrow.add_child(shaft)
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.0
		tm.bottom_radius = 0.06
		tm.height = 0.2
		tm.radial_segments = 12
		tip.mesh = tm
		tip.position.y = 0.9
		tip.material_override = mat
		arrow.add_child(tip)
		_handles.append({"kind": "move", "axis": i, "mat": mat, "node": arrow})
	for i in 3:
		var mat := _gizmo_mat(AX_COL[i])
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()      # лежит в плоскости XZ (ось Y)
		tor.inner_radius = 0.66
		tor.outer_radius = 0.70
		tor.rings = 48
		tor.ring_segments = 6
		ring.mesh = tor
		ring.basis = to_axis[i]
		ring.material_override = mat
		_giz.add_child(ring)
		_handles.append({"kind": "rot", "axis": i, "mat": mat, "node": ring})
	for mi in _giz.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# точки суставов (режим «Пальцы»): клик — выбрать сустав
	_dots = Node3D.new()
	_dots.visible = false
	add_child(_dots)
	_dot_mat = _gizmo_mat(Color(1, 1, 1))
	_dot_sel_mat = _gizmo_mat(HOVER_COL)
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 5
	for b in EDIT_BONES:
		var d := MeshInstance3D.new()
		d.mesh = sm
		d.material_override = _dot_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dots.add_child(d)


# --- суставы мышью (режим «Пальцы») ---
# кость -> параметры: [ось кольца (0 — сгиб X красное, 1 — поворот Y зелёное, 2 — наклон Z синее), номер в JOINTS, множитель]
const EDIT_BONES := ["index_1", "index_2", "index_3", "middle_1", "middle_2", "middle_3", "ring_1", "ring_2", "ring_3",
	"pinky_1", "pinky_2", "pinky_3", "thumb_1", "thumb_2", "thumb_3", "hand"]
const BONE_PARAMS := {
	"index_1": [[0, 0, 1.0]], "index_2": [[0, 1, 1.0]], "index_3": [[0, 2, 1.0]],
	"middle_1": [[0, 3, 1.0]], "middle_2": [[0, 4, 1.0]], "middle_3": [[0, 5, 1.0]],
	"ring_1": [[0, 6, 1.0]], "ring_2": [[0, 7, 1.0]], "ring_3": [[0, 8, 1.0]],
	"pinky_1": [[0, 9, 1.0]], "pinky_2": [[0, 10, 1.0]], "pinky_3": [[0, 11, 1.0]],
	"thumb_1": [[0, 12, 0.55], [1, 13, 1.0], [2, 16, 1.0]], "thumb_2": [[0, 14, 1.2]], "thumb_3": [[0, 15, 1.2]],
	"hand": [[0, 17, 1.0], [1, 19, 1.0], [2, 18, 1.0]],
}
var _dots: Node3D
var _orbit_cam: Camera3D      # камера облёта ладони (режим «Пальцы»)
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_dist := 0.28
var _orbit_pan := Vector3.ZERO
var _orbiting := false
var _panning := false
var _dot_mat: StandardMaterial3D
var _dot_sel_mat: StandardMaterial3D
var _hover_dot := -1


## Режим «Пальцы»: своя камера облёта вокруг ладони (ПКМ — вращать, колесо — ближе/дальше, СКМ — сдвиг).
func _set_fingers(on: bool) -> void:
	_drag = -1
	_orbiting = false
	_panning = false
	if on == _fingers_mode and (not on or (_orbit_cam != null and _orbit_cam.current)):
		return
	_fingers_mode = on
	var pcam: Camera3D = null
	if hand != null:
		pcam = hand.get_parent() as Camera3D
	if on:
		if _orbit_cam == null:
			_orbit_cam = Camera3D.new()
			_orbit_cam.fov = 45.0
			_orbit_cam.near = 0.005
			_orbit_cam.far = 200.0
			add_child(_orbit_cam)
		# начальный вид — как из глаз игрока, ладонь в центре
		_orbit_yaw = 0.0
		_orbit_pitch = 0.0
		_orbit_pan = Vector3.ZERO
		if pcam != null:
			_orbit_dist = clampf(pcam.global_position.distance_to(_palm()) * 0.8, 0.08, 0.6)
		_update_orbit()
		_orbit_cam.make_current()
	elif pcam != null:
		pcam.make_current()


## Центр ладони (между запястьем и основанием среднего пальца).
func _palm() -> Vector3:
	if hand._skel == null:
		return hand.global_position
	return _bone_xf("hand").origin.lerp(_bone_xf("middle_1").origin, 0.6)


func _update_orbit() -> void:
	if _orbit_cam == null or hand == null:
		return
	var pcam := hand.get_parent() as Node3D
	var base := pcam.global_basis.orthonormalized() if pcam != null else Basis()
	var rot := base * Basis.from_euler(Vector3(_orbit_pitch, _orbit_yaw, 0.0))
	var c := _palm() + _orbit_pan
	_orbit_cam.global_transform = Transform3D(rot, c + rot * Vector3(0.0, 0.0, _orbit_dist))


## Кость выбранного сустава.
func _sel_bone() -> String:
	for b: String in BONE_PARAMS:
		for p: Array in BONE_PARAMS[b]:
			if int(p[1]) == _joint:
				return b
	return "hand"


func _bone_xf(b: String) -> Transform3D:
	var bi := hand._skel.find_bone(b)
	if bi < 0:
		return Transform3D()
	var xf := hand._skel.global_transform * hand._skel.get_bone_global_pose(bi)
	return Transform3D(xf.basis.orthonormalized(), xf.origin)


## Параметр кости по оси кольца: [номер сустава, множитель] или [].
func _bone_param(b: String, axis: int) -> Array:
	for p: Array in BONE_PARAMS.get(b, []):
		if int(p[0]) == axis:
			return [int(p[1]), float(p[2])]
	return []


func _update_finger_gizmo() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or hand._skel == null:
		_giz.visible = false
		_dots.visible = false
		return
	var bone := _sel_bone()
	var xf := _bone_xf(bone)
	var L := cam.global_position.distance_to(xf.origin) * 0.09
	_giz.visible = true
	_giz.global_transform = Transform3D(xf.basis.scaled(Vector3.ONE * L), xf.origin)
	for i in _handles.size():
		var h: Dictionary = _handles[i]
		(h["node"] as Node3D).visible = h["kind"] == "rot" and not _bone_param(bone, int(h["axis"])).is_empty()
	_dots.visible = true
	var ds := cam.global_position.distance_to(xf.origin) * 0.012
	for i in EDIT_BONES.size():
		var d := _dots.get_child(i) as MeshInstance3D
		var bx := _bone_xf(EDIT_BONES[i])
		d.global_transform = Transform3D(Basis().scaled(Vector3.ONE * ds), bx.origin)
		d.material_override = _dot_sel_mat if (EDIT_BONES[i] == bone or i == _hover_dot) else _dot_mat
	if _drag < 0:
		_hover = -1
		_hover_dot = -1
		var mp := get_viewport().get_mouse_position()
		var bd := 12.0
		# кольца выбранной кости
		for i in _handles.size():
			var h: Dictionary = _handles[i]
			if not (h["node"] as Node3D).visible:
				continue
			var d2 := _ring_dist(mp, cam, xf.origin, xf.basis[int(h["axis"])], L)
			if d2 < bd:
				bd = d2
				_hover = i
		# точки суставов (если не над кольцом)
		if _hover < 0:
			var bd2 := 14.0
			for i in EDIT_BONES.size():
				var p := _bone_xf(EDIT_BONES[i]).origin
				if cam.is_position_behind(p):
					continue
				var d3 := mp.distance_to(cam.unproject_position(p))
				if d3 < bd2:
					bd2 = d3
					_hover_dot = i
	for i in _handles.size():
		var hl := i == (_drag if _drag >= 0 else _hover)
		(_handles[i]["mat"] as StandardMaterial3D).albedo_color = HOVER_COL if hl else AX_COL[int(_handles[i]["axis"])]


func _ring_dist(mp: Vector2, cam: Camera3D, o: Vector3, a: Vector3, L: float) -> float:
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u)
	var d := 1e9
	var prev := Vector3.ZERO
	for k in 49:
		var ang := TAU * k / 48.0
		var p := o + (u * cos(ang) + v * sin(ang)) * L * 0.68
		if k > 0:
			d = minf(d, _seg_dist(mp, cam, prev, p))
		prev = p
	return d


## Поворот кольца сустава: угол курсора вокруг центра -> изменение параметра позы.
func _finger_drag(mp: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var bone := _sel_bone()
	var h: Dictionary = _handles[_drag]
	var axis := int(h["axis"])
	var par := _bone_param(bone, axis)
	if par.is_empty():
		return
	var xf := _bone_xf(bone)
	var fine := 0.25 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var c := cam.unproject_position(xf.origin)
	var da := wrapf((mp - c).angle() - (_drag_last - c).angle(), -PI, PI) * fine
	_drag_last = mp
	var a: Vector3 = xf.basis[axis]
	var ang := -da if a.dot(cam.global_position - xf.origin) > 0.0 else da
	# сгиб в HandRig — поворот на -flex вокруг X; поворот и наклон — на +значение
	var dv := (-ang if axis == 0 else ang) / float(par[1])
	var saved := _joint
	_joint = int(par[0])
	_set_joint_value(_joint_value() + dv)
	_joint = saved


func _target() -> Node3D:
	if _target_hand or Input.is_physical_key_pressed(KEY_ALT) or hand._item == null:
		return hand
	return hand._item


## Оси манипулятора в мире: родителя (по ним заданы числа position) или собственные оси объекта.
func _axes() -> Basis:
	var t := _target()
	var b: Basis = t.global_basis if _local_axes else t.get_parent_node_3d().global_basis
	return b.orthonormalized()


func _gizmo_len(cam: Camera3D) -> float:
	return cam.global_position.distance_to(_target().global_position) * 0.22


func _update_gizmo() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_giz.visible = true
	_dots.visible = false
	for h: Dictionary in _handles:
		(h["node"] as Node3D).visible = true
	var L := _gizmo_len(cam)
	_giz.global_transform = Transform3D(_axes().scaled(Vector3.ONE * L), _target().global_position)
	if _drag < 0:
		_hover = _pick(get_viewport().get_mouse_position(), cam)
	for i in _handles.size():
		var hl := i == (_drag if _drag >= 0 else _hover)
		(_handles[i]["mat"] as StandardMaterial3D).albedo_color = HOVER_COL if hl else AX_COL[int(_handles[i]["axis"])]


## Ближайшая к курсору ручка (в пикселях экрана) или -1.
func _pick(mp: Vector2, cam: Camera3D) -> int:
	var o := _target().global_position
	var ax := _axes()
	var L := _gizmo_len(cam)
	var best := -1
	var bd := 12.0
	for i in _handles.size():
		var h: Dictionary = _handles[i]
		var a: Vector3 = ax[int(h["axis"])]
		var d := 1e9
		if h["kind"] == "move":
			d = _seg_dist(mp, cam, o + a * L * 0.15, o + a * L)
		else:
			# кольцо: ломаная из 48 точек окружности радиусом 0.68
			var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
			var v := a.cross(u)
			var prev := Vector3.ZERO
			for k in 49:
				var ang := TAU * k / 48.0
				var p := o + (u * cos(ang) + v * sin(ang)) * L * 0.68
				if k > 0:
					d = minf(d, _seg_dist(mp, cam, prev, p))
				prev = p
			d += 2.0     # при равенстве — стрелка важнее
		if d < bd:
			bd = d
			best = i
	return best


func _seg_dist(mp: Vector2, cam: Camera3D, a: Vector3, b: Vector3) -> float:
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return 1e9
	var sa := cam.unproject_position(a)
	var sb := cam.unproject_position(b)
	return mp.distance_to(Geometry2D.get_closest_point_to_segment(mp, sa, sb))


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed and _hover >= 0:
					_drag = _hover
					_drag_last = mb.position
				elif mb.pressed and _fingers_mode and _hover_dot >= 0:
					# выбрать сустав кликом по точке
					_joint = int((BONE_PARAMS[EDIT_BONES[_hover_dot]] as Array)[0][1])
				elif not mb.pressed:
					_drag = -1
			MOUSE_BUTTON_RIGHT:
				if _fingers_mode:
					_orbiting = mb.pressed      # облёт камеры вокруг ладони
				else:
					# ПКМ держать — осмотреться (мышь захватывается), отпустить — снова курсор
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed and _fingers_mode
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and _fingers_mode:
					_orbit_dist = clampf(_orbit_dist * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), 0.04, 1.2)
				elif mb.pressed and hand._item != null:
					var f := 1.03 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.03
					if Input.is_physical_key_pressed(KEY_SHIFT):
						f = pow(f, 0.25)
					_item_scale = maxf(_item_scale * f, 0.01)
		get_viewport().set_input_as_handled()   # не отдавать клики игроку (удар, захват мыши, смена слота)
	elif event is InputEventMouseMotion and (_orbiting or _panning):
		var rel := (event as InputEventMouseMotion).relative
		if _orbiting:
			_orbit_yaw -= rel.x * 0.008
			_orbit_pitch = clampf(_orbit_pitch - rel.y * 0.008, -1.5, 1.5)
		else:
			var b := _orbit_cam.global_basis
			_orbit_pan += (-b.x * rel.x + b.y * rel.y) * _orbit_dist * 0.002
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag >= 0:
		if _fingers_mode:
			_finger_drag((event as InputEventMouseMotion).position)
		else:
			_drag_apply((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()


func _drag_apply(mp: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var h: Dictionary = _handles[_drag]
	var axis_i := int(h["axis"])
	var t := _target()
	var o := t.global_position
	var a: Vector3 = _axes()[axis_i]
	var L := _gizmo_len(cam)
	var fine := 0.25 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var delta := (mp - _drag_last) * fine
	_drag_last = mp
	var parent_b := t.get_parent_node_3d().global_basis
	if h["kind"] == "move":
		# движение мыши вдоль экранной проекции оси -> сдвиг вдоль оси в мире
		var s0 := cam.unproject_position(o)
		var sd := cam.unproject_position(o + a * L) - s0
		if sd.length_squared() < 4.0:
			return
		var w := a * (delta.dot(sd) / sd.length_squared() * L)
		var local := parent_b.inverse() * w
		if t == hand:
			_hand_pos += local
		else:
			_item_pos += local
		return
	# поворот: угол курсора вокруг центра манипулятора на экране
	var c := cam.unproject_position(o)
	var a0 := (mp - delta - c).angle()
	var a1 := (mp - c).angle()
	var da := wrapf(a1 - a0, -PI, PI)
	# ось к камере: по часовой на экране — отрицательный поворот
	var ang := -da if a.dot(cam.global_position - o) > 0.0 else da
	var deg: Vector3 = _hand_rot if t == hand else _item_rot
	var b := Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
	if _local_axes:
		b = b * Basis(Vector3.RIGHT if axis_i == 0 else (Vector3.UP if axis_i == 1 else Vector3.BACK), ang)
	else:
		var pa := (parent_b.inverse() * a).normalized()
		b = Basis(pa, ang) * b
	var e := b.get_euler()
	var nd := Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	if t == hand:
		_hand_rot = nd
	else:
		_item_rot = nd
