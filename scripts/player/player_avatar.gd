class_name PlayerAvatar
extends Node3D
## Модель игрока от третьего лица (простая, из примитивов): её видят другие игроки по сети; у своего игрока она
## только отбрасывает тень (от первого лица тела не видно). Лицом к -Z, как и игрок.
## Анимация кодом: ходьба/бег (ноги и руки маятником), присед, взгляд вверх-вниз (голова, рука с пистолетом),
## действия руки (удар оружием, кулаком, выстрел, бросок, еда/питьё, перезарядка), смерть — лежит на спине.

var _j := {}                  # имя -> сустав (Node3D)
var _phase := 0.0
var _act := ""
var _act_t := 0.0
var _act_len := 0.0
var _item_id := "-"
var _item: Node3D
var _shadow_only := false
var _dead_k := 0.0
var _crouch_k := 0.0
var _label: Label3D
var _pack: Node3D             # модель рюкзака на спине (скрыта, пока не надет)

const ACT_LEN := {"swing": 0.55, "punch": 0.35, "shoot": 0.18, "throw": 0.6, "eat": 1.3, "drink": 1.6, "reload": 1.1}


## tint — цвет куртки (разный у игроков).
func build(tint: Color, name_text: String = "") -> void:
	var skin := _mat(Color(0.8, 0.62, 0.5), 0.7)
	var jacket := _mat(tint, 0.85)
	var pants := _mat(Color(0.2, 0.22, 0.26), 0.9)
	var dark := _mat(Color(0.1, 0.09, 0.08), 0.6)
	var hair := _mat(Color(0.18, 0.12, 0.08), 0.9)
	var root := _joint(self, "root", Vector3.ZERO)
	var hips := _joint(root, "hips", Vector3(0, 0.92, 0))
	_box(hips, Vector3(0.36, 0.2, 0.22), Vector3(0, 0.0, 0), pants)
	var spine := _joint(hips, "spine", Vector3(0, 0.08, 0))
	_box(spine, Vector3(0.44, 0.55, 0.25), Vector3(0, 0.28, 0), jacket)
	_build_pack(spine)
	var neck := _joint(spine, "neck", Vector3(0, 0.56, 0))
	_caps(neck, 0.06, 0.14, Vector3(0, 0.04, 0), skin)
	var head := _joint(neck, "head", Vector3(0, 0.12, 0))
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.125
	sm.height = 0.27
	hm.mesh = sm
	hm.material_override = skin
	hm.position = Vector3(0, 0.1, 0)
	head.add_child(hm)
	_box(head, Vector3(0.25, 0.08, 0.25), Vector3(0, 0.2, 0.01), hair)
	for sx in [-0.045, 0.045]:
		_box(head, Vector3(0.035, 0.02, 0.02), Vector3(sx, 0.12, -0.115), dark)   # глаза (лицо — к -Z)
	for side in [-1.0, 1.0]:
		var nm := "l" if side < 0.0 else "r"
		var sh := _joint(spine, nm + "_shoulder", Vector3(0.27 * side, 0.5, 0))
		_caps(sh, 0.065, 0.34, Vector3(0, -0.14, 0), jacket)
		var el := _joint(sh, nm + "_elbow", Vector3(0, -0.29, 0))
		_caps(el, 0.055, 0.3, Vector3(0, -0.12, 0), jacket)
		_box(el, Vector3(0.08, 0.1, 0.08), Vector3(0, -0.29, 0), skin)           # кисть
		_joint(el, nm + "_grip", Vector3(0, -0.3, 0))
		var hp := _joint(hips, nm + "_hip", Vector3(0.11 * side, -0.05, 0))
		_caps(hp, 0.085, 0.48, Vector3(0, -0.21, 0), pants)
		var kn := _joint(hp, nm + "_knee", Vector3(0, -0.43, 0))
		_caps(kn, 0.07, 0.46, Vector3(0, -0.2, 0), pants)
		_box(kn, Vector3(0.11, 0.08, 0.25), Vector3(0, -0.43, -0.05), dark)        # ботинок носком вперёд
	if name_text != "":
		_label = Label3D.new()
		_label.text = name_text
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.pixel_size = 0.004
		_label.font_size = 48
		_label.outline_size = 10
		_label.modulate = Color(1, 1, 1, 0.92)
		_label.position = Vector3(0, 2.15, 0)
		_label.no_depth_test = false
		add_child(_label)
	for mi: VisualInstance3D in find_children("*", "VisualInstance3D", true, false):
		mi.layers = 2      # как у зомби: декали крови (cull_mask 1) на тело не ложатся


## Рюкзак на спине (виден, только когда надет): корпус, клапан, карман, лямки спереди, фляга сбоку. Спина — +Z.
func _build_pack(spine: Node3D) -> void:
	_pack = Node3D.new()
	_pack.name = "Pack"
	_pack.visible = false
	spine.add_child(_pack)
	var body := _mat(Color(0.30, 0.34, 0.16), 0.95)
	var flap := _mat(Color(0.25, 0.29, 0.13), 0.95)
	var strap := _mat(Color(0.34, 0.27, 0.14), 0.9)
	var metal := _mat(Color(0.12, 0.12, 0.12), 0.5)
	_box(_pack, Vector3(0.34, 0.44, 0.17), Vector3(0, 0.30, 0.21), body)
	_box(_pack, Vector3(0.35, 0.16, 0.19), Vector3(0, 0.46, 0.215), flap)
	_box(_pack, Vector3(0.26, 0.18, 0.07), Vector3(0, 0.16, 0.34), flap)
	_box(_pack, Vector3(0.04, 0.3, 0.015), Vector3(-0.09, 0.4, 0.31), strap)
	_box(_pack, Vector3(0.04, 0.3, 0.015), Vector3(0.09, 0.4, 0.31), strap)
	_box(_pack, Vector3(0.05, 0.04, 0.02), Vector3(-0.09, 0.36, 0.32), metal)
	_box(_pack, Vector3(0.05, 0.04, 0.02), Vector3(0.09, 0.36, 0.32), metal)
	_box(_pack, Vector3(0.07, 0.2, 0.07), Vector3(0.2, 0.2, 0.22), metal)
	for side in [-1.0, 1.0]:
		_box(_pack, Vector3(0.06, 0.38, 0.02), Vector3(0.12 * side, 0.34, -0.135), strap)   # лямки на груди


## Надет ли рюкзак (показывает/прячет модель на спине).
func set_backpack(on: bool) -> void:
	if _pack != null:
		_pack.visible = on


## Только тень (своя модель — от первого лица её не видно, но тень на земле есть).
func set_shadow_only(on: bool) -> void:
	_shadow_only = on
	_apply_shadow_mode(self)


func _apply_shadow_mode(n: Node) -> void:
	for mi: GeometryInstance3D in n.find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _shadow_only \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _label != null:
		_label.visible = not _shadow_only


## Предмет в правой руке (по id из ItemDB; "" — пустая рука).
func set_item(id: String) -> void:
	if id == _item_id:
		return
	_item_id = id
	if _item != null:
		_item.queue_free()
		_item = null
	var m: Node3D = null
	match id:
		"stone_axe":
			m = ItemModels.stone_axe()
		"wooden_club":
			m = ItemModels.club()
		"pistol":
			m = ItemModels.pistol()
		"water_bottle", "glass_bottle":
			m = ItemModels.bottle(id == "water_bottle")["root"]
		"canned_food", "berries", "candy_bar":
			m = ItemModels.food(id)
	if m == null:
		return
	_item = Node3D.new()
	_item.add_child(m)
	# предмет «из кулака» вперёд (модели предметов — рукоятью вниз, вдоль +Y)
	_item.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	(_j["r_grip"] as Node3D).add_child(_item)
	for mi: VisualInstance3D in _item.find_children("*", "VisualInstance3D", true, false):
		mi.layers = 2
	_apply_shadow_mode(_item)


func play_action(action: String) -> void:
	if not ACT_LEN.has(action):
		return
	_act = action
	_act_t = 0.0
	_act_len = float(ACT_LEN[action])


## Кадр анимации: speed — скорость по земле (м/с), pitch — наклон взгляда (рад, вверх +).
func animate(delta: float, speed: float, crouch: bool, pitch: float, dead: bool) -> void:
	_dead_k = move_toward(_dead_k, 1.0 if dead else 0.0, delta * 2.5)
	_crouch_k = move_toward(_crouch_k, 1.0 if crouch else 0.0, delta * 6.0)
	var k := clampf(speed / 5.0, 0.0, 1.6)
	_phase += delta * (2.0 + speed * 1.55)
	var s := sin(_phase)
	var c := _crouch_k
	var hips: Node3D = _j["hips"]
	hips.position.y = 0.92 - 0.32 * c - absf(cos(_phase)) * 0.04 * minf(k, 1.0)
	(_j["spine"] as Node3D).rotation.x = -0.08 * k - 0.35 * c       # наклон вперёд (вперёд = -Z = минус)
	(_j["l_hip"] as Node3D).rotation.x = s * 0.6 * k + 1.0 * c
	(_j["r_hip"] as Node3D).rotation.x = -s * 0.6 * k + 1.0 * c
	(_j["l_knee"] as Node3D).rotation.x = -(maxf(0.0, -s) * 0.9 * k + 1.7 * c)
	(_j["r_knee"] as Node3D).rotation.x = -(maxf(0.0, s) * 0.9 * k + 1.7 * c)
	(_j["neck"] as Node3D).rotation.x = clampf(pitch, -1.0, 1.0) * 0.6 + 0.35 * c
	# руки: маятник при ходьбе; правая — по действию / с пистолетом целится по взгляду
	var la := -s * 0.45 * k
	var ra := s * 0.45 * k
	var le := 0.25      # локти сгибаются вперёд (+)
	var re := 0.3
	if _item_id == "pistol":
		ra = PI * 0.5 + clampf(pitch, -1.2, 1.2)
		re = 0.0
	elif _item_id != "" and _item != null:
		ra = 0.35 + s * 0.2 * k
		re = 0.6
	if _act != "":
		_act_t += delta
		var t := clampf(_act_t / _act_len, 0.0, 1.0)
		match _act:
			"swing", "throw":
				# замах над головой, затем рубящий удар вниз-вперёд
				ra = lerpf(0.3, 2.9, t / 0.45) if t < 0.45 else lerpf(2.9, 0.6, (t - 0.45) / 0.55)
				re = 0.5 if t < 0.45 else 0.1
			"punch":
				ra = sin(t * PI) * 1.55
				re = lerpf(1.4, 0.0, sin(t * PI))
			"shoot":
				ra = PI * 0.5 + clampf(pitch, -1.2, 1.2) + sin(t * PI) * 0.25
				re = 0.0
			"eat", "drink":
				var u := sin(minf(t * 1.6, 1.0) * PI * 0.5) * (1.0 if t < 0.85 else (1.0 - t) / 0.15)
				ra = lerpf(ra, 1.1, u)
				re = lerpf(re, 2.2, u)
			"reload":
				ra = 1.0
				re = 0.9
				la = 1.1 + sin(t * TAU * 2.0) * 0.15
				le = 1.0
		if _act_t >= _act_len:
			_act = ""
	(_j["l_shoulder"] as Node3D).rotation.x = la
	(_j["r_shoulder"] as Node3D).rotation.x = ra
	(_j["l_elbow"] as Node3D).rotation.x = le
	(_j["r_elbow"] as Node3D).rotation.x = re
	# смерть: падает на спину
	var root: Node3D = _j["root"]
	root.rotation.x = _dead_k * PI * 0.5
	root.position = Vector3(0, _dead_k * 0.14, -_dead_k * 0.9)
	if _label != null:
		_label.visible = not _shadow_only and _dead_k < 0.5


func _mat(col: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _joint(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = nm
	j.position = pos
	parent.add_child(j)
	_j[nm] = j
	return j


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _caps(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


## Цвет куртки игрока по его id (у всех одинаковый для одного и того же игрока).
static func tint_for(peer: int) -> Color:
	var cols := [Color(0.3, 0.38, 0.24), Color(0.5, 0.28, 0.18), Color(0.22, 0.3, 0.45), Color(0.45, 0.4, 0.22),
		Color(0.4, 0.2, 0.3), Color(0.25, 0.42, 0.42), Color(0.35, 0.35, 0.36), Color(0.55, 0.45, 0.32)]
	return cols[absi(hash(peer)) % cols.size()]
