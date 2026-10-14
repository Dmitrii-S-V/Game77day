class_name FarTerrain
extends Node3D
## Дальний ландшафт (LOD): кольца плиток с шагом сетки 8 / 16 / 32 / 64 м вокруг игрока.
## Плитки строятся в рабочих потоках по итоговой высоте карты, цвет — по высоте и уклону,
## по краям — юбки, скрывающие щели между уровнями. Внутри радиуса более детального
## уровня сетка проседает (см. terrain_far.gdshader), чтобы не пробивать его.

const GRID := 16   # ячеек на плитку по стороне

# cell: шаг сетки; inner/outer: радиус охвата (м); sink: радиус проседания; fade; amount
const LEVELS := [
	{"cell": 8.0, "inner": 80.0, "outer": 440.0, "sink": 86.0, "fade": 40.0, "amount": 1.1},
	{"cell": 16.0, "inner": 400.0, "outer": 1050.0, "sink": 380.0, "fade": 80.0, "amount": 2.2},
	{"cell": 32.0, "inner": 980.0, "outer": 2100.0, "sink": 920.0, "fade": 160.0, "amount": 3.5},
	{"cell": 64.0, "inner": 1950.0, "outer": 4300.0, "sink": 1850.0, "fade": 300.0, "amount": 6.0},
]

var world: WorldMap
var base_material: ShaderMaterial   # шаблон: текстуры уже заданы

var _materials: Array[ShaderMaterial] = []
var _tiles := {}        # Vector3i(level, tx, tz) -> MeshInstance3D
var _pending: Array[Vector3i] = []
var _inflight := {}
var _results: Array = []
var _results_mutex := Mutex.new()
var _center := Vector2(1e9, 0)
var _timer := 0.0


func setup(w: WorldMap, mat_template: ShaderMaterial) -> void:
	world = w
	for lv: Dictionary in LEVELS:
		var m := mat_template.duplicate() as ShaderMaterial
		m.set_shader_parameter("sink_radius", lv["sink"])
		m.set_shader_parameter("sink_fade", lv["fade"])
		m.set_shader_parameter("sink_amount", lv["amount"])
		_materials.append(m)


## Радиус, внутри которого ближний ландшафт готов (дальняя плитка скрывается только там; пока чанки грузятся — не оставляем дыр).
func set_near_radius(r: float) -> void:
	for m in _materials:
		m.set_shader_parameter("near_radius", r)


## Радиус проседания ближайшего уровня (под радиус ближнего ландшафта из настроек графики).
func set_level0_sink(r: float) -> void:
	if not _materials.is_empty():
		_materials[0].set_shader_parameter("sink_radius", r)


func is_idle() -> bool:
	return _pending.is_empty() and _inflight.is_empty()


func update_view(pos: Vector3, delta: float) -> void:
	_timer -= delta
	var p2 := Vector2(pos.x, pos.z)
	if _timer <= 0.0 and p2.distance_to(_center) > 24.0:
		_timer = 0.4
		_center = p2
		_rebuild(p2)
	while _inflight.size() < 4 and not _pending.is_empty():
		var key: Vector3i = _pending.pop_front()
		if _tiles.has(key) or _inflight.has(key):
			continue
		_inflight[key] = true
		WorkerThreadPool.add_task(_job.bind(key))
	_apply()


func _rebuild(p: Vector2) -> void:
	var wanted := {}
	var size := float(world.size)
	_pending.clear()
	for li in LEVELS.size():
		var lv: Dictionary = LEVELS[li]
		var tile: float = lv["cell"] * GRID
		var outer: float = lv["outer"]
		var tx0 := floori((p.x - outer) / tile)
		var tx1 := floori((p.x + outer) / tile)
		var tz0 := floori((p.y - outer) / tile)
		var tz1 := floori((p.y + outer) / tile)
		for tz in range(tz0, tz1 + 1):
			for tx in range(tx0, tx1 + 1):
				var c := Vector2((tx + 0.5) * tile, (tz + 0.5) * tile)
				# плитка нужна, если её квадрат пересекает кольцо [inner, outer]
				var half := tile * 0.5
				var dx := maxf(absf(c.x - p.x) - half, 0.0)
				var dz := maxf(absf(c.y - p.y) - half, 0.0)
				var dmin := sqrt(dx * dx + dz * dz)
				var dmax := Vector2(absf(c.x - p.x) + half, absf(c.y - p.y) + half).length()
				if dmin > outer or dmax < float(lv["inner"]):
					continue
				if (tx + 1) * tile < -300.0 or tx * tile > size + 300.0 or (tz + 1) * tile < -300.0 or tz * tile > size + 300.0:
					continue
				var key := Vector3i(li, tx, tz)
				wanted[key] = true
				if not _tiles.has(key) and not _inflight.has(key):
					_pending.append(key)
	for key: Vector3i in _tiles.keys():
		if not wanted.has(key):
			_tiles[key].queue_free()
			_tiles.erase(key)
	_pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _tile_dist(a, p) < _tile_dist(b, p))


func _tile_dist(k: Vector3i, p: Vector2) -> float:
	var tile: float = float(LEVELS[k.x]["cell"]) * GRID
	return Vector2((k.y + 0.5) * tile, (k.z + 0.5) * tile).distance_to(p)


func _job(key: Vector3i) -> void:
	var res := _build(key)
	res["key"] = key
	_results_mutex.lock()
	_results.append(res)
	_results_mutex.unlock()


func _build(key: Vector3i) -> Dictionary:
	var lv: Dictionary = LEVELS[key.x]
	var cell: float = lv["cell"]
	var tile := cell * GRID
	var ox := key.y * tile
	var oz := key.z * tile
	var n := GRID + 1
	var m := GRID + 3   # с запасом для нормалей
	var hs := PackedFloat32Array()
	hs.resize(m * m)
	for j in m:
		for i in m:
			hs[i + m * j] = world.far_height(ox + (i - 1) * cell, oz + (j - 1) * cell)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var h := hs[(i + 1) + m * (j + 1)]
			var gx := hs[(i + 2) + m * (j + 1)] - hs[i + m * (j + 1)]
			var gz := hs[(i + 1) + m * (j + 2)] - hs[(i + 1) + m * j]
			var nrm := Vector3(-gx, 2.0 * cell, -gz).normalized()
			verts.append(Vector3(i * cell, h, j * cell))
			norms.append(nrm)
			cols.append(_weights(h, nrm))
			uvs.append(Vector2(0.0, world.hydro.water_floor(ox + i * cell, oz + j * cell)))
	for j in GRID:
		for i in GRID:
			var a := i + n * j
			# по часовой сверху: (a, a+1, a+n+1) и (a, a+n+1, a+n)
			idx.append_array(PackedInt32Array([a, a + 1, a + n + 1, a, a + n + 1, a + n]))
	# юбки по краям плитки (uv.x = 1: не проседают вместе с плиткой)
	var skirt := cell * 0.9 + 4.0
	for side in 4:
		var first := verts.size()
		for k in n:
			var bi := 0
			match side:
				0: bi = k
				1: bi = k + n * GRID
				2: bi = n * k
				_: bi = GRID + n * k
			verts.append(verts[bi] + Vector3(0, -skirt, 0))
			norms.append(norms[bi])
			cols.append(cols[bi])
			uvs.append(Vector2(2.0, uvs[bi].y))   # x = 2: нижняя кромка юбки (не проседает; шейдер не накладывает на неё дороги/биом)
		for k in GRID:
			var t0 := 0
			var t1 := 0
			match side:
				0: t0 = k; t1 = k + 1
				1: t0 = k + n * GRID; t1 = k + 1 + n * GRID
				2: t0 = n * k; t1 = n * (k + 1)
				_: t0 = GRID + n * k; t1 = GRID + n * (k + 1)
			var b0 := first + k
			var b1 := first + k + 1
			if side == 0 or side == 3:
				idx.append_array(PackedInt32Array([t0, b0, b1, t0, b1, t1]))
			else:
				idx.append_array(PackedInt32Array([t0, t1, b1, t0, b1, b0]))
	return {"verts": verts, "norms": norms, "cols": cols, "uvs": uvs, "idx": idx, "origin": Vector3(ox, 0, oz)}


func _weights(h: float, nrm: Vector3) -> Color:
	var steep := 1.0 - smoothstep(0.62, 0.85, nrm.y)
	var rock := maxf(steep, smoothstep(62.0, 80.0, h))
	var sand := 1.0 - smoothstep(WorldMap.SEA + 0.5, WorldMap.SEA + 2.2, h)
	var grass := (1.0 - rock) * (1.0 - sand)
	var dirt := (1.0 - rock) * sand * 0.3
	return Color(grass, dirt, rock, sand * (1.0 - rock))


func _apply() -> void:
	_results_mutex.lock()
	var take := mini(2, _results.size())
	var batch := _results.slice(0, take)
	_results = _results.slice(take)
	_results_mutex.unlock()
	for r: Dictionary in batch:
		var key: Vector3i = r["key"]
		_inflight.erase(key)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = r["verts"]
		arrays[Mesh.ARRAY_NORMAL] = r["norms"]
		arrays[Mesh.ARRAY_COLOR] = r["cols"]
		arrays[Mesh.ARRAY_TEX_UV] = r["uvs"]
		arrays[Mesh.ARRAY_INDEX] = r["idx"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _materials[key.x]
		mi.position = r["origin"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 40.0
		add_child(mi)
		if _tiles.has(key):
			_tiles[key].queue_free()
		_tiles[key] = mi
