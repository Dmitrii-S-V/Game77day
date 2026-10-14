class_name FarProps
extends Node3D
## Дальние упрощённые LOD объектов (деревья, камни, здания, столбы) на плитках 64 м.
## Плитки строятся в потоках по плану мира (без расчёта воксельных колонок), деревья — MultiMesh
## из простых мешей с цветом в вершинах. Ближе CUT рисуются обычные объекты (far_prop.gdshader
## отбрасывает фрагменты ближе CUT). Дальность: деревья RANGE, столбы POLE_RANGE.

const TILE := 64.0
const COLS := 4            # колонок 16 м на сторону плитки
const RANGE := 780.0
const POLE_RANGE := 360.0
const ROCK_RANGE := 300.0
## Дальние объекты начинают рисоваться раньше, чем обычные пропадают (нахлёст): пока обычный объект
## ещё не создан или не достроен, на его месте уже виден упрощённый, и пустоты не возникает.
## Упрощённые модели внутри обычных (меньше по размеру), поэтому в зоне нахлёста их не видно.
const CUT_TREE := 62.0     # деревья/камни: ближе — только обычные
const CUT_PROP := 52.0     # здания/столбы
const NEAR_END := 104.0     # дальше обычные деревья/камни не рисуются

const WALL_H := {"house": 3.4, "farmhouse": 3.4, "shop": 4.2, "gas_store": 3.5, "warehouse": 6.5, "silo": 13.0, "gas_canopy": 0.0}
const ROOF_H := {"house": 2.2, "farmhouse": 2.2, "shop": 0.6, "gas_store": 0.4, "warehouse": 1.2, "silo": 0.0, "gas_canopy": 0.4}

## Уровни LOD деревьев: обычное дерево (Vegetation) до NEAR_END; затем оригинальная модель (FULL), облегчённая модель
## с тем же видом (MID) и, дальше всего, простая (SIMPLE). Эстафета — по расстоянию до дерева (шейдеры tree/foliage: far_cut/far_end).
const FADE := 18.0              # ширина зоны плавного перехода между уровнями (дизеринг)
const FULL_FROM := NEAR_END - FADE   # оригинальная модель начинает проявляться, пока обычное дерево гаснет
const FULL_TO := 210.0
const MID_TO := 420.0

var gen: WorldGen
var veg: Vegetation                 # источник материалов ствола и листвы
var _tier_mats := {}                # "full"|"mid" -> {"bark": mat, "leaf": mat, "pine": mat, "dry": mat}
var _mesh_cache := {}               # "<имя>|<tier>" -> ArrayMesh с материалами поверхностей
var _mat_tree: ShaderMaterial
var _mat_prop: ShaderMaterial
var _meshes := {}                 # "pine" | "oak" | "rock" -> ArrayMesh
var _tiles := {}                  # Vector2i -> Node3D
var _pending: Array[Vector2i] = []
var _inflight := {}
var _results: Array = []
var _mutex := Mutex.new()
var _center := Vector2(1e9, 0)
var _timer := 0.0


func setup(g: WorldGen) -> void:
	gen = g
	shared = self
	var sh := load("res://shaders/far_prop.gdshader") as Shader
	_mat_tree = ShaderMaterial.new()
	_mat_tree.shader = sh
	_mat_tree.set_shader_parameter("cut", MID_TO - FADE)
	_mat_tree.set_shader_parameter("fade_w", FADE)   # простая модель только за пределами MID
	_mat_prop = ShaderMaterial.new()
	_mat_prop.shader = sh
	_mat_prop.set_shader_parameter("cut", CUT_PROP)
	_mat_prop.set_shader_parameter("uv_center", true)
	_meshes["pine"] = _make_pine()
	_meshes["oak"] = _make_oak()
	_meshes["rock"] = _make_rock()


func is_idle() -> bool:
	return _pending.is_empty() and _inflight.is_empty() and _results.is_empty()


func update_view(pos: Vector3, delta: float) -> void:
	_timer -= delta
	var p2 := Vector2(pos.x, pos.z)
	if _timer <= 0.0 and p2.distance_to(_center) > 20.0:
		_timer = 0.5
		_center = p2
		_rebuild(p2)
	while _inflight.size() < 3 and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if (_tiles.has(key) and not _refresh.has(key)) or _inflight.has(key):
			continue
		_refresh.erase(key)
		_inflight[key] = true
		# снимок срубленного (словарь меняется в основном потоке)
		WorkerThreadPool.add_task(_job.bind(key, Vegetation.removed.duplicate()))
	_apply()


static var shared: FarProps
var _refresh := {}


## Срубили дерево/разбили камень: плитку перестроить (старая видна, пока не готова новая).
func refresh_at(pos: Vector3) -> void:
	var key := Vector2i(floori(pos.x / TILE), floori(pos.z / TILE))
	if _tiles.has(key) and not _refresh.has(key):
		_refresh[key] = true
		_pending.push_front(key)


func _rebuild(p: Vector2) -> void:
	_pending.clear()
	var t0 := Vector2i(floori((p.x - RANGE) / TILE), floori((p.y - RANGE) / TILE))
	var t1 := Vector2i(floori((p.x + RANGE) / TILE), floori((p.y + RANGE) / TILE))
	var wanted := {}
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			var c := Vector2((tx + 0.5) * TILE, (tz + 0.5) * TILE)
			if c.distance_to(p) > RANGE + TILE * 0.7 or c.distance_to(p) < CUT_PROP - TILE * 0.7:
				continue
			if not gen.in_map(tx * COLS, tz * COLS) and not gen.in_map(tx * COLS + COLS - 1, tz * COLS + COLS - 1):
				continue
			var key := Vector2i(tx, tz)
			wanted[key] = true
			if not _tiles.has(key) and not _inflight.has(key):
				_pending.append(key)
	for key: Vector2i in _tiles.keys():
		if not wanted.has(key):
			_tiles[key].queue_free()
			_tiles.erase(key)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _tc(a).distance_squared_to(p) < _tc(b).distance_squared_to(p))


func _tc(k: Vector2i) -> Vector2:
	return Vector2((k.x + 0.5) * TILE, (k.y + 0.5) * TILE)


# --- поток: данные плитки ------------------------------------------------------

func _job(key: Vector2i, removed: Dictionary) -> void:
	var res := _build(key, removed)
	res["key"] = key
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _build(key: Vector2i, removed: Dictionary = {}) -> Dictionary:
	var roads := gen.world.roads
	var minx := key.x * TILE
	var minz := key.y * TILE
	var lots := roads.lots_in(minx - 10.0, minx + TILE + 10.0, minz - 10.0, minz + TILE + 10.0)
	var segs := roads.gather_segments(minx - 10.0, minx + TILE + 10.0, minz - 10.0, minz + TILE + 10.0)
	var fulls := {}    # имя модели -> трансформы (12 float на экземпляр) для оригинальных/облегчённых деревьев
	var bufs := {"pine": PackedFloat32Array(), "oak": PackedFloat32Array(), "rock": PackedFloat32Array()}
	var counts := {"pine": 0, "oak": 0, "rock": 0}
	var poles := MeshBuilder.new()
	for cz in range(key.y * COLS, key.y * COLS + COLS):
		for cx in range(key.x * COLS, key.x * COLS + COLS):
			if not gen.in_map(cx, cz):
				continue
			for p: Dictionary in gen.vegetation_plan(cx, cz, true):
				var kind: String = p["kind"]
				if kind != "pine" and kind != "oak" and kind != "rock":
					continue
				var x: float = p["x"]
				var z: float = p["z"]
				if _in_settlement(x, z, lots, segs, 3.5):
					continue
				# те же условия, что у обычных деревьев (Vegetation._spawn_plant): иначе вдали виден LOD,
				# а вблизи дерева нет («фантомы»)
				if removed.has(Vegetation.plant_key(x, z)):
					continue
				if gen.world.hydro.near(x, z, 2.0):
					continue
				if gen.far_slope(x, z) > (0.9 if kind == "rock" else 0.6):
					continue
				var d := Vector2(x, z).distance_to(_center)
				if kind == "rock" and d > ROCK_RANGE:
					continue
				var b := Basis(Vector3.UP, float(p["rot"])).scaled(Vector3.ONE * float(p["scale"]))
				var y: float = float(p["h"]) - 0.35
				var v := 0.8 + 0.3 * fmod(absf(x * 12.9898 + z * 78.233), 1.0)
				var tint := Color(v, v, v, 1.0)
				if String(p["mesh"]).begins_with("oak_dry"):
					tint = Color(2.4, 1.1, 0.55, 1.0)
				elif kind == "oak":
					tint = Color(v * 1.15, v * 1.15, v * 0.9, 1.0)
				var arr: PackedFloat32Array = bufs[kind]
				arr.append_array(PackedFloat32Array([
					b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, z,
					tint.r, tint.g, tint.b, tint.a]))
				bufs[kind] = arr
				counts[kind] = int(counts[kind]) + 1
				if kind != "rock":
					var mn := String(p["mesh"])
					var fa: PackedFloat32Array = fulls.get(mn, PackedFloat32Array())
					fa.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, z]))
					fulls[mn] = fa
			if gen.world.roads != null and Vector2((cx + 0.5) * 16.0, (cz + 0.5) * 16.0).distance_to(_center) < POLE_RANGE:
				for pl: Dictionary in roads.poles_in_column(cx, cz):
					if pl["kind"] == "fallen":
						continue
					var pp: Vector2 = pl["pos"]
					var ph := gen.world.far_height(pp.x, pp.y)
					var lamp := String(pl["kind"]).begins_with("lamp")
					var pb := MeshBuilder.new()
					if lamp:
						pb.box(Vector3(0, 3.2, 0), Vector3(0.22, 6.4, 0.22), Color(0.45, 0.47, 0.46))
						pb.box(Vector3(0.7, 6.4, 0), Vector3(1.5, 0.18, 0.3), Color(0.4, 0.42, 0.42))
					else:
						var hgt := 5.0 if pl["kind"] == "broken" else 8.0
						pb.box(Vector3(0, hgt * 0.5 - 0.3, 0), Vector3(0.28, hgt, 0.28), Color(0.22, 0.15, 0.09))
						if hgt > 6.0:
							pb.box(Vector3(0, hgt - 1.0, 0), Vector3(1.8, 0.14, 0.14), Color(0.22, 0.15, 0.09))
					for i in pb.uvs.size():
						pb.uvs[i] = pp
					poles.append(pb, Transform3D(Basis(Vector3.UP, float(pl["yaw"])), Vector3(pp.x, ph, pp.y)))
	var bld := MeshBuilder.new()
	for l: Dictionary in lots:
		var bt: String = l["btype"]
		if bt == "" or not WALL_H.has(bt) or not Settlement.keeps_lot(l):
			continue
		var c: Vector2 = l["pos"]
		if c.x < minx or c.x >= minx + TILE or c.y < minz or c.y >= minz + TILE:
			continue
		_add_building(bld, l)
	return {"bufs": bufs, "counts": counts, "fulls": fulls, "poles": poles, "bld": bld}


## Точка внутри участка/дороги (деревья в городе и на дорогах не рисуем).
func _in_settlement(x: float, z: float, lots: Array, segs: PackedFloat32Array, margin: float) -> bool:
	for l: Dictionary in lots:
		var c: Vector2 = l["pos"]
		var hx: float = l["hx"]
		var hz: float = l["hz"]
		var dx := x - c.x
		var dz := z - c.y
		if absf(dx) > hx + hz + margin + 2.0 or absf(dz) > hx + hz + margin + 2.0:
			continue
		var rot: float = l["rot"]
		var lx := dx * cos(rot) + dz * sin(rot)
		var lz := -dx * sin(rot) + dz * cos(rot)
		if int(l["shape"]) == 1:
			if sqrt(lx * lx + lz * lz) < hx + margin:
				return true
		elif absf(lx) < hx + margin and absf(lz) < hz + margin:
			return true
	var ss := RoadNet.SS
	for q in range(0, segs.size(), ss):
		var ax := segs[q]
		var az := segs[q + 1]
		var abx := segs[q + 3] - ax
		var abz := segs[q + 4] - az
		var l2 := abx * abx + abz * abz
		var t := 0.0
		if l2 > 1e-6:
			t = clampf(((x - ax) * abx + (z - az) * abz) / l2, 0.0, 1.0)
		var ex := ax + abx * t - x
		var ez := az + abz * t - z
		var lim := segs[q + RoadNet.F_HW] + segs[q + RoadNet.F_SIDE] + margin + 2.0
		if ex * ex + ez * ez < lim * lim:
			return true
	return false


func _add_building(bld: MeshBuilder, l: Dictionary) -> void:
	var bt: String = l["btype"]
	var hx: float = l["hx"]
	var hz: float = l["hz"]
	var c: Vector2 = l["pos"]
	var seed_v: int = int(l["seed"])
	var bw := maxf(4.0, roundf(2.0 * hx - 3.0))
	var bd := maxf(3.5, roundf(2.0 * hz - 3.0))
	if bt == "silo":
		bw = roundf(hx * 2.0)
		bd = bw
	elif bt == "gas_canopy":
		bw = roundf(2.0 * hx - 0.5)
		bd = roundf(2.0 * hz)
	bw = maxf(bw - 0.8, 2.0)    # чуть меньше настоящего здания, чтобы тот его закрывал
	bd = maxf(bd - 0.8, 2.0)
	var wh: float = WALL_H[bt]
	var rh: float = ROOF_H[bt]
	var walls := Color(0.58, 0.5, 0.38)
	match seed_v % 3:
		1: walls = Color(0.52, 0.28, 0.22)
		2: walls = Color(0.5, 0.52, 0.52)
	if bt == "silo" or bt == "warehouse":
		walls = Color(0.5, 0.52, 0.53)
	var roof := Color(0.32, 0.26, 0.24)
	var b := MeshBuilder.new()
	if wh > 0.0:
		b.box(Vector3(0, wh * 0.5 - 0.5, 0), Vector3(bw, wh + 1.0, bd), walls)
	if rh > 0.0:
		var narrow := 0.8 if bt == "house" or bt == "farmhouse" else 1.0
		b.box(Vector3(0, wh + rh * 0.5 - 0.5, 0), Vector3(bw * 1.02, rh, bd * narrow * 1.02), roof)
	if bt == "gas_canopy":
		b.box(Vector3(0, 4.3, 0), Vector3(bw, 0.5, bd), Color(0.7, 0.2, 0.18))
	for i in b.uvs.size():
		b.uvs[i] = c
	bld.append(b, Transform3D(Basis(Vector3.UP, -float(l["rot"])), Vector3(c.x, float(l["plateau"]) + 0.06, c.y)))


# --- главный поток: применение ---------------------------------------------------

func _apply() -> void:
	# одна плитка за кадр и только если в бюджете кадра осталось время (или накопился хвост)
	_mutex.lock()
	var take := 0
	if not _results.is_empty() and (FrameBudget.ok(2.5) or _results.size() > 6):
		take = 1
	take = mini(take, _results.size())
	var batch := _results.slice(0, take)
	_results = _results.slice(take)
	_mutex.unlock()
	for r: Dictionary in batch:
		var key: Vector2i = r["key"]
		_inflight.erase(key)
		if _tiles.has(key):
			_tiles[key].queue_free()
			_tiles.erase(key)
		var node := Node3D.new()
		_add_tree_tiers(node, r["fulls"])
		for k: String in ["pine", "oak", "rock"]:
			var n: int = r["counts"][k]
			if n == 0:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _meshes[k]
			mm.instance_count = n
			mm.buffer = r["bufs"][k]
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _mat_tree
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = ROCK_RANGE + TILE if k == "rock" else RANGE + TILE
			mmi.visibility_range_begin = 0.0 if k == "rock" else MID_TO - TILE
			node.add_child(mmi)
		for kk: String in ["poles", "bld"]:
			var mb: MeshBuilder = r[kk]
			if mb.verts.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mb.to_mesh()
			mi.material_override = _mat_prop
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kk == "bld" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = (POLE_RANGE + TILE) if kk == "poles" else RANGE + TILE
			node.add_child(mi)
		add_child(node)
		_tiles[key] = node


## Деревья оригинальной модели (FULL) и облегчённой (MID): MultiMesh на плитку, по одному на модель и уровень.
func _add_tree_tiers(node: Node3D, fulls: Dictionary) -> void:
	if veg == null:
		return
	_ensure_tier_mats()
	for mn: String in fulls:
		var buf: PackedFloat32Array = fulls[mn]
		var n := buf.size() / 12
		if n == 0:
			continue
		for tier in ["full", "mid"]:
			var mesh := _tier_mesh(mn, tier)
			if mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = n
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			# дальние деревья тоже отбрасывают тень (её дальность — настройки графики; дальше тени не считаются)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.visibility_range_begin = 0.0 if tier == "full" else FULL_TO - 50.0
			mmi.visibility_range_end = (FULL_TO if tier == "full" else MID_TO) + TILE * 0.8
			node.add_child(mmi)


var near_end := NEAR_END   # где кончаются обычные деревья (Vegetation) — зависит от настроек графики


## Граница эстафеты «обычное дерево -> оригинальная модель FULL» (при уменьшенном радиусе растительности).
func set_near_end(e: float) -> void:
	near_end = e
	if _tier_mats.has("full"):
		for m: ShaderMaterial in (_tier_mats["full"] as Dictionary).values():
			m.set_shader_parameter("far_cut", e - FADE)


func _ensure_tier_mats() -> void:
	if not _tier_mats.is_empty():
		return
	for tier in ["full", "mid"]:
		var cut := near_end - FADE if tier == "full" else FULL_TO - FADE
		var fend := FULL_TO if tier == "full" else MID_TO
		var d := {}
		for bn: String in veg._bark_mats:
			var bark := (veg._bark_mats[bn] as ShaderMaterial).duplicate() as ShaderMaterial
			bark.set_shader_parameter("far_cut", cut)
			bark.set_shader_parameter("far_end", fend)
			bark.set_shader_parameter("fade_w", FADE)
			d[bn] = bark
		var burnt := (veg._mat_burnt as ShaderMaterial).duplicate() as ShaderMaterial
		burnt.set_shader_parameter("far_cut", cut)
		burnt.set_shader_parameter("far_end", fend)
		burnt.set_shader_parameter("fade_w", FADE)
		d["burnt"] = burnt
		for lk in ["leaf", "pine", "dry"]:
			var lm := (veg._leaf_mats[lk] as ShaderMaterial).duplicate() as ShaderMaterial
			lm.set_shader_parameter("far_cut", cut)
			lm.set_shader_parameter("far_end", fend)
			lm.set_shader_parameter("fade_w", FADE)
			d[lk] = lm
		_tier_mats[tier] = d


func _tier_mesh(mn: String, tier: String) -> ArrayMesh:
	var key := "%s|%s" % [mn, tier]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var res_name := mn
	if tier == "mid":
		var us := mn.rfind("_")
		if mn.begins_with("dead_tree"):
			res_name = mn
		elif us > 0:
			res_name = mn.substr(0, us) + "_lod_" + mn.substr(us + 1)
	var path := "res://assets/models/%s.res" % res_name
	if not ResourceLoader.exists(path):
		path = "res://assets/models/%s.res" % mn
		if not ResourceLoader.exists(path):
			_mesh_cache[key] = null
			return null
	var m := (load(path) as ArrayMesh).duplicate() as ArrayMesh
	var mats: Dictionary = _tier_mats[tier]
	m.surface_set_material(0, mats["burnt"] if mn.begins_with("dead_tree") else mats[Vegetation.bark_of(mn)])
	if m.get_surface_count() > 1:
		var lk := "pine" if mn.begins_with("pine") else ("dry" if "dry" in mn else "leaf")
		m.surface_set_material(1, mats[lk])
	_mesh_cache[key] = m
	return m


# --- простые меши ------------------------------------------------------------------

func _make_pine() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mb := MeshBuilder.new()
	var trunk := Color(0.2, 0.13, 0.08, 0.0)
	var pts: Array[Vector3] = [Vector3(0, -0.3, 0), Vector3(0, 4.0, 0)]
	var rad: Array[float] = [0.42, 0.3]
	ModelGen._tube(mb, pts, rad, 5, trunk, trunk, rng)
	var g := Color(0.05, 0.17, 0.07, 1.0)
	ModelGen._cone(mb, Vector3(0, 2.4, 0), 2.4, 4.4, 8, g, rng)
	ModelGen._cone(mb, Vector3(0, 5.2, 0), 1.7, 4.0, 8, g.lightened(0.05), rng)
	ModelGen._cone(mb, Vector3(0, 7.8, 0), 1.05, 3.6, 8, g.lightened(0.1), rng)
	return mb.to_mesh()


func _make_oak() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var mb := MeshBuilder.new()
	var trunk := Color(0.22, 0.16, 0.1, 0.0)
	var pts: Array[Vector3] = [Vector3(0, -0.3, 0), Vector3(0, 3.6, 0)]
	var rad: Array[float] = [0.5, 0.3]
	ModelGen._tube(mb, pts, rad, 5, trunk, trunk, rng)
	var ico: Array = ModelGen._icosphere(1)
	var src: PackedVector3Array = ico[0]
	var tris: PackedInt32Array = ico[1]
	var blobs := [[Vector3(0, 5.6, 0), Vector3(3.2, 2.4, 3.2)], [Vector3(1.9, 4.8, 0.9), Vector3(2.4, 1.8, 2.4)], [Vector3(-1.7, 4.6, -1.0), Vector3(2.3, 1.7, 2.3)]]
	for bl: Array in blobs:
		var base := mb.verts.size()
		for v in src:
			var d := v.normalized()
			var col := Color(0.09, 0.15, 0.05).lerp(Color(0.22, 0.31, 0.09), clampf(d.y * 0.5 + 0.5, 0.0, 1.0))
			col.a = 1.0
			mb.vert((bl[0] as Vector3) + d * (bl[1] as Vector3), col)
		for i in range(0, tris.size(), 3):
			mb.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2])
	return mb.to_mesh()


func _make_rock() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var ico: Array = ModelGen._icosphere(1)
	var src: PackedVector3Array = ico[0]
	var tris: PackedInt32Array = ico[1]
	for v in src:
		var d := v.normalized()
		var s := 0.42 + 0.12 * sin(d.x * 5.0 + d.z * 3.0)
		mb.vert(Vector3(d.x * 1.3, maxf(d.y, -0.3) * 0.8 + 0.1, d.z * 1.1), Color(s, s * 0.98, s * 0.95, 0.0))
	for i in range(0, tris.size(), 3):
		mb.tri(tris[i], tris[i + 1], tris[i + 2])
	return mb.to_mesh()
