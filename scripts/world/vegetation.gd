class_name Vegetation
extends Node3D
## Растительность и камни вокруг игрока (в будущем — ресурсы: wood / fiber / stone).
## Каждый объект — Node3D с метой "resource" и "kind", статичным коллайдером на слое 2
## (слой 1 занят ландшафтом). Если ландшафт под объектом выкопан/засыпан — объект исчезает.

const CHUNK := WorldGen.CHUNK

var terrain: Terrain
var radius := 6
var _meshes := {}
var _mat: ShaderMaterial
var _mat_burnt: ShaderMaterial
var _leaf_mats := {}   # "leaf" | "pine" | "dry" -> ShaderMaterial
var _cols := {}     # Vector2i -> Node3D
var _center := Vector2i(1 << 30, 0)
var _pending: Array[Vector2i] = []


## Кора по модели (одинаково у ближнего дерева и его дальних LOD в FarProps).
static func bark_of(mesh_name: String) -> String:
	if mesh_name.begins_with("pine"):
		return "bark_2"            # красно-бурая сосновая
	if mesh_name.begins_with("dead_tree") or mesh_name.begins_with("oak_dry"):
		return "bark_3"            # глубокие борозды, серая
	if mesh_name.begins_with("oak"):
		return ["bark", "bark_1", "bark_3"][absi(mesh_name.hash()) % 3]
	return "bark"


var _bark_mats := {}   # имя текстуры коры -> ShaderMaterial
var _rock_mats: Array[ShaderMaterial] = []


var _near_end := FarProps.NEAR_END

## Срубленные деревья, разбитые камни, сорванные кусты (и растения на выкопанной земле): не появляются снова
## при подгрузке колонки; сохраняются в сейв. Ключ — позиция с точностью 25 см.
static var removed := {}


static func plant_key(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x * 4.0), roundi(z * 4.0))


static func mark_removed(pos: Vector3) -> void:
	removed[plant_key(pos.x, pos.z)] = true
	if FarProps.shared != null and is_instance_valid(FarProps.shared):
		FarProps.shared.refresh_at(pos)   # дальняя модель срубленного дерева тоже пропадёт


## Радиус растительности (колонки) и граница её растворения (настройки графики); дальше — модели FarProps.
func set_range(r: int, near_end: float) -> void:
	radius = r
	_near_end = near_end
	_center = Vector2i(1 << 30, 0)
	var mats: Array = _bark_mats.values() + _rock_mats + _leaf_mats.values()
	mats.append(_mat_burnt)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("far_end", near_end)


func bark_material(mesh_name: String) -> ShaderMaterial:
	return _bark_mats.get(bark_of(mesh_name), _mat)


func _ready() -> void:
	shared = self
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/tree.gdshader")
	_mat.set_shader_parameter("far_end", FarProps.NEAR_END)
	_mat.set_shader_parameter("fade_w", FarProps.FADE)
	for bn in ["bark", "bark_1", "bark_2", "bark_3", "bark_lichen"]:
		var bm := _mat.duplicate() as ShaderMaterial
		var t := _load_tex("res://assets/textures/%s.png" % bn)
		if t != null:
			bm.set_shader_parameter("tex_bark", t)
		var tn := _load_tex("res://assets/textures/%s_n.png" % bn)
		if tn != null:
			bm.set_shader_parameter("tex_bark_n", tn)
			bm.set_shader_parameter("has_bark_n", true)
		if bn == "bark_1" or bn == "bark_3":
			bm.set_shader_parameter("tint", Vector3(0.74, 0.72, 0.7))   # светлые серые коры приглушаем под мрачную гамму
		_bark_mats[bn] = bm
	_mat = _bark_mats["bark"]
	_mat_burnt = (_bark_mats["bark_3"] as ShaderMaterial).duplicate() as ShaderMaterial
	_mat_burnt.set_shader_parameter("tint", Vector3(0.22, 0.2, 0.19))
	# валуны: фотопороды (гранит, слоистый мшистый, скальная из ландшафта)
	var rsh := load("res://shaders/rock.gdshader") as Shader
	for rn in ["rock_a", "rock_c", "terrain_stone"]:
		var rm := ShaderMaterial.new()
		rm.shader = rsh
		rm.set_shader_parameter("tex_rock", _load_tex("res://assets/textures/%s.png" % rn))
		rm.set_shader_parameter("tex_rock_n", _load_tex("res://assets/textures/%s_n.png" % rn))
		rm.set_shader_parameter("tex_moss", _load_tex("res://assets/textures/grass_c.png"))
		rm.set_shader_parameter("far_end", FarProps.NEAR_END)
		rm.set_shader_parameter("fade_w", FarProps.FADE)
		_rock_mats.append(rm)
	for n in ["leaf", "pine", "dry"]:
		var fm := ShaderMaterial.new()
		fm.shader = load("res://shaders/foliage.gdshader")
		# листва с вырезом по альфе — без сжатия (края не «крошатся»), но из кэша
		var ft := TexCache.texture("res://assets/textures/foliage_%s.png" % n, true, 0, false)
		if ft != null:
			fm.set_shader_parameter("tex_leaf", ft)
		fm.set_shader_parameter("far_end", FarProps.NEAR_END)
		fm.set_shader_parameter("fade_w", FarProps.FADE)
		_leaf_mats[n] = fm


## Текстура с мипмапами из PNG (Image.load: файлы фототекстур не проходят импорт Godot).
static var _tex_cache := {}


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t := TexCache.texture(path, not path.ends_with("_n.png"), 1024)
	_tex_cache[path] = t
	return t


func is_idle() -> bool:
	return _pending.is_empty() and _jobs.is_empty()


func count() -> int:
	var n := 0
	for c: Node3D in _cols.values():
		n += c.get_child_count()
	return n


func update_view(pos: Vector3) -> void:
	var c := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	if c != _center:
		_center = c
		_pending.clear()
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var key := Vector2i(c.x + dx, c.y + dz)
				if dx * dx + dz * dz <= radius * radius and not _cols.has(key):
					_pending.append(key)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - c).length_squared() < (b - c).length_squared())
		for key: Vector2i in _cols.keys():
			if (key - c).length_squared() > (radius + 1) * (radius + 1):
				FrameBudget.free_later(_cols[key])
				_cols.erase(key)
	# растения ставятся порциями в пределах бюджета кадра (колонка — до ~16 деревьев с коллизией: целиком за кадр
	# это давало пики 3-9 мс); новая колонка начинается, только когда предыдущие доставлены
	var done_any := false
	while not _jobs.is_empty() and (not done_any or FrameBudget.ok(3.0)):
		var job: Dictionary = _jobs[0]
		var node: Node3D = job["node"]
		var plan: Array = job["plan"]
		var k: int = job["i"]
		if not is_instance_valid(node) or node.is_queued_for_deletion() or k >= plan.size():
			_jobs.pop_front()
			continue
		_spawn_plant(node, plan[k])
		job["i"] = k + 1
		done_any = true
	if _jobs.is_empty() or FrameBudget.ok(2.5):
		var i := 0
		while i < _pending.size() and i < 10:
			var key := _pending[i]
			if terrain.is_column_done(key.x, key.y):
				_spawn_column(key)
				_pending.remove_at(i)
				break
			i += 1


func _mesh(mesh_name: String) -> Mesh:
	if not _meshes.has(mesh_name):
		var path := "res://assets/models/%s.res" % mesh_name
		_meshes[mesh_name] = load(path) if ResourceLoader.exists(path) else null
	return _meshes[mesh_name]


var _jobs: Array = []   # {node, plan, i} — колонки, растения которых ещё ставятся
static var _sh_rock: SphereShape3D
static var _sh_trunk: CylinderShape3D
static var _sh_bush: SphereShape3D


func _spawn_column(key: Vector2i) -> void:
	var node := Node3D.new()
	node.name = "Col_%d_%d" % [key.x, key.y]
	add_child(node)
	_cols[key] = node
	_jobs.append({"node": node, "plan": terrain.gen.vegetation_plan(key.x, key.y), "i": 0})


func _spawn_plant(node: Node3D, p: Dictionary) -> void:
	var x: float = p["x"]
	var z: float = p["z"]
	if removed.has(plant_key(x, z)):
		return
	var kind: String = p["kind"]
	var y := terrain.surface_y(x, z, p["h"])
	if is_nan(y):
		return
	var max_slope := 0.9 if kind == "rock" else (0.75 if kind == "bush" else 0.6)
	# склон — та же функция, что у дальних LOD (FarProps): решение совпадает, фантомов нет
	if terrain.gen.far_slope(x, z) > max_slope or (kind != "bush" and terrain.gen.world.hydro.near(x, z, 2.0)):
		return
	var inst := make_plant(String(p["mesh"]), kind, String(p["res"]), Vector3(x, y - 0.12, z), float(p["rot"]), float(p["scale"]))
	if inst != null:
		node.add_child(inst)


static var shared: Vegetation   # для парков, префабов и редактора (материалы коры и листвы общие)
const LICHEN_P := 15            # % лиственных и мёртвых деревьев с лишаем (с них иногда пенициллин)


## Дерево/куст/валун — узел с метой resource/kind, мешем и коллизией (общая для леса, парков, префабов и редактора).
## Позиция и поворот — мировые (или в системе родителя, если узел добавят не в корень). lichen: -1 — по месту (LICHEN_P).
func make_plant(mesh_name: String, kind: String, res: String, pos: Vector3, rot: float, scale: float, lichen: int = -1) -> Node3D:
	var mesh := _mesh(mesh_name)
	if mesh == null:
		return null
	var x := pos.x
	var z := pos.z
	var inst := Node3D.new()
	inst.position = pos
	inst.rotation.y = rot
	inst.scale = Vector3.ONE * scale
	inst.set_meta("resource", res)
	inst.set_meta("kind", kind)
	if true:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var has_lichen := false
		if kind == "oak" or kind == "dead_tree":
			has_lichen = lichen == 1 or (lichen < 0 and absi(hash([plant_key(x, z), 911])) % 100 < LICHEN_P)
		if has_lichen:
			inst.set_meta("lichen", true)
		if kind == "rock":
			mi.set_surface_override_material(0, _rock_mats[absi(hash(Vector2i(roundi(x * 4.0), roundi(z * 4.0)))) % _rock_mats.size()])
		elif has_lichen:
			mi.set_surface_override_material(0, _bark_mats["bark_lichen"])
		else:
			mi.set_surface_override_material(0, _mat_burnt if kind == "dead_tree" else bark_material(mesh_name))
		if mesh.get_surface_count() > 1:
			var lk := "pine" if mesh_name.begins_with("pine") else ("dry" if "dry" in mesh_name else "leaf")
			mi.set_surface_override_material(1, _leaf_mats[lk])
		mi.visibility_range_end = _near_end + 6.0   # дальше — упрощённые LOD (FarProps); растворение — дизерингом в шейдерах
		inst.add_child(mi)
		if kind == "rock":
			ContactShadow.add(inst, 0.9 * scale, 0.7)   # камень «лежит» на земле
		if kind == "bush":
			# куст: «мягкое» тело (слой 8) — по нему бьют, но сквозь него ходят игрок и зомби
			var sb := StaticBody3D.new()
			sb.collision_layer = 8
			sb.collision_mask = 0
			var scs := CollisionShape3D.new()
			if _sh_bush == null:
				_sh_bush = SphereShape3D.new()
				_sh_bush.radius = 0.55
			scs.shape = _sh_bush
			scs.position.y = 0.5
			sb.add_child(scs)
			inst.add_child(sb)
		else:
			var body := StaticBody3D.new()
			body.collision_layer = 2
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			# общие формы для всех экземпляров (масштаб узла их растягивает как раньше)
			if kind == "rock":
				if _sh_rock == null:
					_sh_rock = SphereShape3D.new()
					_sh_rock.radius = 0.8
				cs.shape = _sh_rock
				cs.position.y = 0.4
			else:
				if _sh_trunk == null:
					_sh_trunk = CylinderShape3D.new()
					_sh_trunk.radius = 0.4
					_sh_trunk.height = 5.0
				cs.shape = _sh_trunk
				cs.position.y = 2.5
			body.add_child(cs)
			inst.add_child(body)
	return inst


## Ландшафт изменён: убираем растения, у которых пропала или сместилась земля.
func on_edited(center: Vector3, edit_radius: float) -> void:
	var reach := edit_radius + 4.0
	var lo := Vector2i(floori((center.x - reach) / CHUNK), floori((center.z - reach) / CHUNK))
	var hi := Vector2i(floori((center.x + reach) / CHUNK), floori((center.z + reach) / CHUNK))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var col: Node3D = _cols.get(Vector2i(cx, cz))
			if col == null:
				continue
			for inst: Node3D in col.get_children():
				if inst.is_queued_for_deletion():
					continue
				var p := inst.position
				if Vector2(p.x - center.x, p.z - center.z).length() > reach:
					continue
				var y := terrain.surface_y(p.x, p.z, p.y)
				if is_nan(y) or absf(y - (p.y + 0.12)) > 0.6:
					mark_removed(p)
					inst.queue_free()
