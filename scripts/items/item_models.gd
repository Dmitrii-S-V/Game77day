class_name ItemModels
extends RefCounted
## Модели предметов в руке и в мире: каменный топор, стеклянная бутылка (+ жидкость).
## Начало координат — точка хвата; рукоятка/бутылка вдоль +Y.

const BODY_TOP := 0.14      # верх цилиндрической части бутылки
const LIQ_BOTTOM := 0.012
const LIQ_HEIGHT := 0.128   # высота полной жидкости

static var _vc_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D


static func vertex_color_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.85
	return _vc_mat


static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.7, 0.88, 0.82, 0.28)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.roughness = 0.04
		_glass_mat.metallic_specular = 1.0
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass_mat.rim_enabled = true
		_glass_mat.rim = 0.4
		_glass_mat.rim_tint = 0.3
	return _glass_mat


static func _pts(list: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in list:
		out.append(p)
	return out


static func _radii(list: Array) -> Array[float]:
	var out: Array[float] = []
	for r: float in list:
		out.append(r)
	return out


const AXE_GLB := "res://assets/ready/stone_axe_meshy.glb"
const AXE_SCALE := 0.32
const AXE_TWIST := 2.57                      # поворот вокруг рукояти: камень боком к камере, лезвие вперёд-влево                      # модель 1.9 м в длину -> рукоять около 0.55 м
const AXE_GRIP := Vector3(0.45, 0.0, 0.0)    # точка хвата в координатах модели (на рукояти)
static var _axe_scene: PackedScene


## Каменный топор: детализированная модель (Meshy). Начало координат — хват, рукоять вдоль +Y, лезвие смотрит вперёд (-Z).
## Нет файла — запасной процедурный топор.
static func stone_axe() -> Node3D:
	if _axe_scene == null and ResourceLoader.exists(AXE_GLB):
		_axe_scene = load(AXE_GLB) as PackedScene
	if _axe_scene == null:
		return stone_axe_procedural()
	var node := Node3D.new()
	var m := _axe_scene.instantiate() as Node3D
	# рукоять: +X модели -> -Y (голова вверх); лезвие (модельный -Y) -> -Z
	var b := Basis(Vector3.UP, PI * 0.5 - AXE_TWIST) * Basis(Vector3.BACK, -PI * 0.5) * Basis.from_scale(Vector3.ONE * AXE_SCALE)
	m.transform = Transform3D(b, -(b * AXE_GRIP))
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(m)
	return node


## Запасной процедурный каменный топор: рукоять, каменное навершие, обмотка.
static func stone_axe_procedural() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mb := MeshBuilder.new()
	var wood_a := Color(0.38, 0.26, 0.16)
	var wood_b := Color(0.5, 0.36, 0.22)
	ModelGen._tube(mb, _pts([Vector3(0, -0.15, 0), Vector3(0.0, 0.05, 0.004), Vector3(0, 0.25, 0), Vector3(0, 0.42, -0.003)]),
		_radii([0.019, 0.016, 0.015, 0.017]), 12, wood_a, wood_b, rng)
	# каменное навершие: вытянутый булыжник с заострённым передним краем
	var ico := ModelGen._icosphere(3)
	var src: PackedVector3Array = ico[0]
	var head := MeshBuilder.new()
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 3.0
	for v in src:
		var d := v.normalized()
		var r := 1.0 + noise.get_noise_3d(d.x * 2.0, d.y * 2.0, d.z * 2.0) * 0.12
		var p := Vector3(d.x * 0.024, d.y * 0.045, d.z * 0.075) * r
		if p.z < -0.02:
			p.x *= 0.45 + 0.55 * (p.z + 0.075) / 0.055   # лезвие тоньше к краю
		var shade := 0.5 + noise.get_noise_3d(d.x * 4.0 + 5.0, d.y * 4.0, d.z * 4.0) * 0.4
		var c := Color(0.42, 0.42, 0.4).lerp(Color(0.62, 0.6, 0.56), shade)
		head.vert(p, c)
	var tris: PackedInt32Array = ico[1]
	for i in range(0, tris.size(), 3):
		head.tri(tris[i], tris[i + 1], tris[i + 2])
	mb.append(head, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.385, -0.04)))
	# обмотка шнуром
	var cord := Color(0.72, 0.6, 0.4)
	for k in 5:
		var y := 0.345 + k * 0.012
		ModelGen._tube(mb, _pts([Vector3(0, y, 0), Vector3(0, y + 0.008, 0)]), _radii([0.0225, 0.0225]), 10, cord, cord.darkened(0.2), rng)
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	mi.material_override = vertex_color_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return node


static var _club_mat: StandardMaterial3D


## Дубина: сучковатое бревно, расширяющееся к ударной части, с вбитыми гвоздями и обмоткой тряпьём на рукояти.
## Начало координат — хват, вдоль +Y. Кора — фототекстура (трипланарно), цвет вершин её подкрашивает.
static func club() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var mb := MeshBuilder.new()
	var w_a := Color(0.62, 0.5, 0.38)
	var w_b := Color(0.78, 0.66, 0.5)
	# ствол: рукоять 3.2 см -> ударная часть 9 см, слегка изогнут
	ModelGen._tube(mb, _pts([Vector3(0, -0.16, 0), Vector3(0.002, 0.05, 0.003), Vector3(-0.004, 0.25, 0.0), Vector3(0.003, 0.45, -0.006),
		Vector3(0.0, 0.6, -0.004), Vector3(0.0, 0.66, 0.0)]),
		_radii([0.017, 0.018, 0.026, 0.04, 0.045, 0.03]), 14, w_a, w_b, rng)
	# сучки
	for k in 4:
		var y := rng.randf_range(0.3, 0.58)
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.35, sin(a)).normalized()
		var base := Vector3(cos(a) * 0.03, y, sin(a) * 0.03)
		ModelGen._tube(mb, _pts([base, base + dir * 0.03]), _radii([0.012, 0.004]), 6, w_a.darkened(0.2), w_a, rng)
	# гвозди: торчат из ударной части
	var nail := Color(0.35, 0.33, 0.3)
	for k in 9:
		var y2 := rng.randf_range(0.44, 0.62)
		var a2 := rng.randf() * TAU
		var d2 := Vector3(cos(a2), rng.randf_range(-0.2, 0.3), sin(a2)).normalized()
		var p0 := Vector3(cos(a2) * 0.035, y2, sin(a2) * 0.035)
		ModelGen._tube(mb, _pts([p0, p0 + d2 * rng.randf_range(0.035, 0.055)]), _radii([0.0028, 0.0012]), 5, nail, nail.lightened(0.2), rng)
	# обмотка тряпьём
	var cloth := Color(0.36, 0.32, 0.27)
	for k in 7:
		var yc := -0.1 + k * 0.022
		ModelGen._tube(mb, _pts([Vector3(0, yc, 0), Vector3(0, yc + 0.016, 0)]), _radii([0.0205, 0.021]), 10, cloth, cloth.darkened(0.25), rng)
	if _club_mat == null:
		_club_mat = StandardMaterial3D.new()
		_club_mat.vertex_color_use_as_albedo = true
		_club_mat.vertex_color_is_srgb = true
		_club_mat.albedo_texture = TexCache.texture("res://assets/textures/bark_1.png", true, 1024)
		_club_mat.uv1_triplanar = true
		_club_mat.uv1_scale = Vector3.ONE * 4.0
		_club_mat.roughness = 0.9
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	mi.material_override = _club_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return node


## Пистолет: модель assets/ready/pistol_9mm.glb («pistol 9mm», DJMaesen, CC-BY 4.0; подготовка — scripts/ai3d/pistol_prep.py)
## с отдельными деталями slide / mag / bullet / trigger / hammer. Ствол вдоль -Z, начало координат — хват.
## У узла есть дочерний Marker3D «muzzle» (дуло). Без файла — простая модель из коробок.
const PISTOL_GLB := "res://assets/ready/pistol_9mm.glb"
static var _pistol_scene: PackedScene


static func pistol() -> Node3D:
	if _pistol_scene == null and ResourceLoader.exists(PISTOL_GLB):
		_pistol_scene = load(PISTOL_GLB) as PackedScene
	if _pistol_scene != null:
		var n := _pistol_scene.instantiate() as Node3D
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mz := Marker3D.new()
		mz.name = "muzzle"
		mz.position = Vector3(0.0, 0.0557, -0.172)
		n.add_child(mz)
		return n
	return pistol_simple()


const PISTOL_MUZZLE := Vector3(0.0, 0.062, -0.158)


static func pistol_simple() -> Node3D:
	var mb := MeshBuilder.new()
	var poly := Color(0.07, 0.07, 0.075)
	var steel := Color(0.16, 0.16, 0.17)
	var dark := Color(0.03, 0.03, 0.03)
	# рукоять (наклонена: низ дальше назад) с насечками
	var grip := MeshBuilder.new()
	grip.box(Vector3(0, -0.01, 0), Vector3(0.028, 0.105, 0.033), poly)
	grip.box(Vector3(0, -0.01, 0.0168), Vector3(0.024, 0.08, 0.002), poly.lightened(0.06))
	grip.box(Vector3(0, -0.064, 0), Vector3(0.03, 0.008, 0.036), dark)   # пятка магазина
	mb.append(grip, Transform3D(Basis(Vector3.RIGHT, -0.32), Vector3(0, 0, 0.004)))
	# рамка и затвор
	mb.box(Vector3(0, 0.042, -0.045), Vector3(0.026, 0.016, 0.15), poly)
	mb.box(Vector3(0, 0.062, -0.052), Vector3(0.024, 0.026, 0.19), steel)
	for k in 6:   # насечки затвора сзади
		mb.box(Vector3(0, 0.062, 0.03 - k * 0.006), Vector3(0.0255, 0.02, 0.0018), steel.darkened(0.4))
	mb.box(PISTOL_MUZZLE + Vector3(0, 0, 0.002), Vector3(0.011, 0.011, 0.004), dark)   # дуло
	# прицел
	mb.box(Vector3(0, 0.078, -0.14), Vector3(0.004, 0.006, 0.006), steel)
	mb.box(Vector3(0, 0.078, 0.03), Vector3(0.016, 0.006, 0.006), steel)
	# спусковая скоба и крючок
	mb.box(Vector3(0, 0.012, -0.052), Vector3(0.007, 0.005, 0.05), poly)
	mb.box(Vector3(0, 0.024, -0.076), Vector3(0.007, 0.03, 0.005), poly)
	mb.box(Vector3(0, 0.024, -0.04), Vector3(0.005, 0.02, 0.005), steel)
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	var m := vertex_color_material().duplicate() as StandardMaterial3D
	m.roughness = 0.45
	m.metallic = 0.35
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var mz := Marker3D.new()
	mz.name = "muzzle"
	mz.position = PISTOL_MUZZLE
	node.add_child(mz)
	return node


## Еда в руке/в мире: консервная банка, горсть ягод, шоколадный батончик. Начало координат — хват.
static func food(id: String) -> Node3D:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	match id:
		"canned_food":
			mb.append_mesh(lathe([Vector2(0.0, -0.05), Vector2(0.036, -0.05), Vector2(0.037, -0.046), Vector2(0.037, 0.046), Vector2(0.036, 0.05), Vector2(0.0, 0.05)], 16, Color(0.72, 0.72, 0.7)))
			mb.append_mesh(lathe([Vector2(0.0375, -0.036), Vector2(0.0375, 0.036)], 16, Color(0.62, 0.22, 0.12)))   # этикетка
		"berries":
			for k in 9:
				var s := ModelGen._icosphere(1)
				var bm := MeshBuilder.new()
				var r := rng.randf_range(0.007, 0.01)
				var c := Color(0.25, 0.04, 0.12).lerp(Color(0.45, 0.08, 0.15), rng.randf())
				for v: Vector3 in s[0]:
					bm.vert(v.normalized() * r, c)
				var tr: PackedInt32Array = s[1]
				for i in range(0, tr.size(), 3):
					bm.tri(tr[i], tr[i + 1], tr[i + 2])
				mb.append(bm, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.02, 0.02), rng.randf_range(0.0, 0.025), rng.randf_range(-0.02, 0.02))))
		_:
			mb.box(Vector3(0, 0.0, 0), Vector3(0.03, 0.11, 0.012), Color(0.55, 0.15, 0.1))
			mb.box(Vector3(0, 0.0, 0), Vector3(0.031, 0.045, 0.013), Color(0.85, 0.8, 0.7))
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	mi.material_override = vertex_color_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return node


## Поверхность вращения: профиль (радиус, высота) от нижней точки к верхней.
static func lathe(profile: Array, sides: int, col: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rings: Array = []
	for pr: Vector2 in profile:
		var ring: Array[int] = []
		for j in sides:
			var a := TAU * j / sides
			ring.append(mb.vert(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x), col))
		rings.append(ring)
	for i in rings.size() - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			mb.quad(rings[i][j], rings[i + 1][j], rings[i + 1][j2], rings[i][j2])
	return mb.to_mesh()


## Стеклянная бутылка. Возвращает {root, liquid_mat (или null)}; root имеет метаданные модели.
static func bottle(with_water: bool) -> Dictionary:
	var root := Node3D.new()
	var glass_profile: Array = [
		Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.031, 0.008), Vector2(0.0335, 0.02), Vector2(0.0335, 0.11),
		Vector2(0.031, 0.145), Vector2(0.022, 0.172), Vector2(0.0135, 0.195), Vector2(0.0125, 0.225),
		Vector2(0.015, 0.232), Vector2(0.015, 0.24), Vector2(0.0105, 0.24), Vector2(0.0105, 0.2),
	]
	var gm := MeshInstance3D.new()
	gm.mesh = lathe(glass_profile, 20, Color.WHITE)
	gm.material_override = glass_material()
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gm.name = "Glass"
	root.add_child(gm)
	# пробка
	var cork := MeshInstance3D.new()
	cork.mesh = lathe([Vector2(0.0, 0.236), Vector2(0.0125, 0.236), Vector2(0.0125, 0.262), Vector2(0.0, 0.262)], 12, Color(0.62, 0.48, 0.3))
	cork.material_override = vertex_color_material()
	cork.name = "Cork"
	cork.visible = with_water
	root.add_child(cork)
	var lm: ShaderMaterial = null
	if with_water:
		var liquid := MeshInstance3D.new()
		liquid.mesh = lathe([Vector2(0.0, LIQ_BOTTOM), Vector2(0.0295, LIQ_BOTTOM), Vector2(0.0305, LIQ_BOTTOM + 0.01), Vector2(0.0305, BODY_TOP),
			Vector2(0.0, BODY_TOP)], 20, Color.WHITE)
		lm = ShaderMaterial.new()
		lm.shader = load("res://shaders/liquid.gdshader")
		liquid.material_override = lm
		liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		liquid.name = "Liquid"
		root.add_child(liquid)
	return {"root": root, "liquid_mat": lm}
