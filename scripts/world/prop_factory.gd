class_name PropFactory
extends RefCounted
## Мелкие объекты на территории построек и в парках: скамейка (оттенок от синего до зелёного, ломается на дерево),
## рюкзак и куча мусора (обыск E, Loot), камешек (подобрать E — камень), кустик низкой травы.

const BENCH_GLB := "res://assets/ready/props/bench_wooden.glb"   # «Bench Wooden 01», randombug, CC BY 4.0
const PILE_GLB := "res://assets/ready/street_trash.glb"
const BENCH_SIZE := Vector3(1.15, 0.5, 0.42)

static var _bench_scene: PackedScene
static var _bench_mat: ShaderMaterial
static var _pile_scene: PackedScene
static var _pack_meshes: Array = []
static var _pack_mat: StandardMaterial3D
static var _tuft_mat: ShaderMaterial
static var _tuft_mesh: ArrayMesh


## Скамейка с центром в начале координат (вдоль X), hue — 0.33 зелёная … 0.6 синяя.
static func bench(hue: float) -> Node3D:
	var node := Node3D.new()
	node.set_meta("resource", "wood")
	node.set_meta("kind", "bench")
	if _bench_scene == null and ResourceLoader.exists(BENCH_GLB):
		_bench_scene = load(BENCH_GLB) as PackedScene
	if _bench_scene != null:
		var m := _bench_scene.instantiate() as Node3D
		m.position = Vector3(-BENCH_SIZE.x * 0.5, 0.0, -BENCH_SIZE.z * 0.5)
		node.add_child(m)
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _bench_material(mi)
			mi.set_instance_shader_parameter("hue", hue)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = BENCH_SIZE
	cs.shape = sh
	cs.position.y = BENCH_SIZE.y * 0.5
	body.add_child(cs)
	node.add_child(body)
	return node


static func _bench_material(mi: MeshInstance3D) -> ShaderMaterial:
	if _bench_mat != null:
		return _bench_mat
	_bench_mat = ShaderMaterial.new()
	_bench_mat.shader = load("res://shaders/painted_hue.gdshader")
	var src := mi.get_active_material(0) as StandardMaterial3D
	if src != null:
		_bench_mat.set_shader_parameter("tex_albedo", src.albedo_texture)
		if src.normal_texture != null:
			_bench_mat.set_shader_parameter("tex_normal", src.normal_texture)
			_bench_mat.set_shader_parameter("has_normal", true)
	return _bench_mat


## Куча мусора с обыском (как на улицах).
static func trash_pile() -> Node3D:
	if _pile_scene == null:
		_pile_scene = load(PILE_GLB) as PackedScene
	var inst := _pile_scene.instantiate() as Node3D
	inst.set_meta("litter", true)
	inst.set_meta("loot", "trash_pile")
	Breakables.mark(inst, "pile")
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 120.0
	var bag := inst.find_child("trash_bag*", true, false)
	if bag != null:
		for mi in bag.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).get_active_material(0)
			if m is StandardMaterial3D:
				var bm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				bm.albedo_color = Color(0.3, 0.3, 0.32)
				bm.roughness = 0.35
				(mi as MeshInstance3D).material_override = bm
	inst.add_child(_box_body(Vector3(0.6, 0.55, 0.6), 0.27))
	return inst


## Брошенный рюкзак (обыск E, таблица «backpack»): лежит на спине, цвет — по variant.
static func backpack(variant: int) -> Node3D:
	if _pack_meshes.is_empty():
		_pack_mat = ItemModels.vertex_color_material()
		for col: Color in [Color(0.28, 0.32, 0.2), Color(0.16, 0.2, 0.32), Color(0.42, 0.13, 0.1), Color(0.12, 0.12, 0.13), Color(0.36, 0.33, 0.28)]:
			var mb := MeshBuilder.new()
			var dark := col.darkened(0.45)
			mb.box(Vector3(0, 0.19, 0), Vector3(0.3, 0.38, 0.16), col)                   # корпус
			mb.box(Vector3(0, 0.37, 0.01), Vector3(0.31, 0.06, 0.18), col.darkened(0.12)) # клапан
			mb.box(Vector3(0, 0.12, 0.1), Vector3(0.22, 0.15, 0.05), col.lightened(0.06)) # передний карман
			mb.box(Vector3(0, 0.2, 0.126), Vector3(0.2, 0.008, 0.008), dark)              # молния кармана
			for sx in [-0.08, 0.08]:
				mb.box(Vector3(sx, 0.2, -0.09), Vector3(0.04, 0.34, 0.02), dark)           # лямки
			mb.box(Vector3(0, 0.42, -0.03), Vector3(0.06, 0.03, 0.03), dark)              # ручка
			_pack_meshes.append(mb.to_mesh())
	var node := Node3D.new()
	node.set_meta("loot", "backpack")
	Breakables.mark(node, "backpack")
	var mi := MeshInstance3D.new()
	mi.mesh = _pack_meshes[posmod(variant, _pack_meshes.size())]
	mi.material_override = _pack_mat
	mi.rotation.x = -PI * 0.5      # лежит на спине (лямками вниз)
	mi.position = Vector3(0, 0.1, 0.19)
	node.add_child(mi)
	node.add_child(_box_body(Vector3(0.34, 0.2, 0.44), 0.1))
	return node


## Камешек: подбирается E (+1 камень), не появляется снова (Vegetation.removed).
static func pebble(scale: float) -> Node3D:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/models/rock_%d.res" % (randi() % 3)) if ResourceLoader.exists("res://assets/models/rock_0.res") else SphereMesh.new()
	mi.scale = Vector3.ONE * scale
	if Vegetation.shared != null and not Vegetation.shared._rock_mats.is_empty():
		mi.set_surface_override_material(0, Vegetation.shared._rock_mats[0])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	node.add_to_group("pickups")
	node.set_meta("item", {"id": "stone", "n": 1})
	node.set_meta("decor", true)
	return node


## Кустик низкой травы (те же карточки осоки, что у травы ландшафта); seed — разный вид/размер.
static func tuft(seed_v: int, count: int = 4) -> Node3D:
	_ensure_tuft()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _tuft_mesh
	mm.instance_count = count
	for i in count:
		var s := rng.randf_range(0.28, 0.5)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.2, s, s * 1.2)),
			Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, Color(rng.randf_range(0.6, 1.0), 0, 0, float(rng.randi() % 8) / 255.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _tuft_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GrassField.register_mmi(mmi)   # срезается ударом (трава в инвентарь)
	return mmi


## Кустики травы на ячейках «трава» покрытия земли (cells: Vector2i -> ключ), в системе узла покрытия.
static func tufts_for(cells: Dictionary, cell: float, seed_v: int) -> Node3D:
	_ensure_tuft()
	var pts: Array = []
	for c: Vector2i in cells:
		if String(cells[c]) != "grass":
			continue
		var h := absi(hash([c, seed_v]))
		for k in h % 4:   # 0–3 кустика на ячейку
			var hk := absi(hash([c, seed_v, k]))
			pts.append([Vector3((c.x + float(hk % 97) / 97.0) * cell, 0.0, (c.y + float(hk / 97 % 89) / 89.0) * cell), hk])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _tuft_mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		var hk: int = pts[i][1]
		var s := 0.25 + float(hk % 23) / 23.0 * 0.25
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(hk % 360)).scaled(Vector3(s * 1.2, s, s * 1.2)), pts[i][0]))
		mm.set_instance_custom_data(i, Color(0.55 + float(hk % 17) / 17.0 * 0.45, 0, 0, float(hk % 8) / 255.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tufts"
	mmi.multimesh = mm
	mmi.material_override = _tuft_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GrassField.register_mmi(mmi)
	return mmi


static func _ensure_tuft() -> void:
	if _tuft_mat != null:
		return
	_tuft_mat = ShaderMaterial.new()
	_tuft_mat.shader = load("res://shaders/grass.gdshader")
	_tuft_mat.set_shader_parameter("bright", 0.62)
	var st := TexCache.texture("res://assets/textures/sedge.png", true, 0, false)
	if st != null:
		_tuft_mat.set_shader_parameter("tex_sedge", st)
	for pair in [["tex_g1", "grass_a"], ["tex_g2", "grass_b"], ["tex_g3", "grass_c"]]:
		var gt := TexCache.texture("res://assets/textures/%s.png" % pair[1], true, 0, true)
		if gt != null:
			_tuft_mat.set_shader_parameter(pair[0], gt)
	var mb := MeshBuilder.new()
	var up := Vector3.UP
	var w := Color.WHITE
	var a0 := mb.vert_full(Vector3(-0.5, 0, 0), w, Vector2(0, 1), up)
	var a1 := mb.vert_full(Vector3(0.5, 0, 0), w, Vector2(1, 1), up)
	var a2 := mb.vert_full(Vector3(0.5, 1, 0), w, Vector2(1, 0), up)
	var a3 := mb.vert_full(Vector3(-0.5, 1, 0), w, Vector2(0, 0), up)
	mb.quad(a0, a1, a2, a3)
	var b0 := mb.vert_full(Vector3(0, 0, -0.5), w, Vector2(0, 1), up)
	var b1 := mb.vert_full(Vector3(0, 0, 0.5), w, Vector2(1, 1), up)
	var b2 := mb.vert_full(Vector3(0, 1, 0.5), w, Vector2(1, 0), up)
	var b3 := mb.vert_full(Vector3(0, 1, -0.5), w, Vector2(0, 0), up)
	mb.quad(b0, b1, b2, b3)
	_tuft_mesh = mb.to_mesh()


static func _box_body(size: Vector3, y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = Vector3(0, y, 0)
	body.add_child(cs)
	return body
