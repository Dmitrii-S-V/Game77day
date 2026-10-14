class_name WorldGen
extends RefCounted
## Воксельный генератор по готовой карте мира (WorldMap): рельеф, пещеры, материалы,
## план растительности. Детерминирован по seed карты.

const CHUNK := 16
const MAT_GRASS := 0
const MAT_DIRT := 1
const MAT_STONE := 2
const MAT_SAND := 3
const MAT_ASPHALT := 4
const MAT_CONCRETE := 5
const MAT_GRAVEL := 6
const MAT_ROADSAND := 7
const MAT_BASE := 8   # щебёночная подушка под дорогой (не считается дорогой)
const WATER_LEVEL := 13.5
const FLOOR_Y := -44.0
const COLUMN_CACHE_MAX := 6000
const ROADSIDE_TREE_MIN := 6.0     # деревья вдоль дорог: полоса от края дороги, м
const ROADSIDE_TREE_MAX := 14.0
const ROADSIDE_TREE_P := 0.28      # шанс дерева на точку сетки 4 м в этой полосе (в лесу — до 0.3)

var world: WorldMap
var cols := 0   # размер карты в колонках 16 м

var _caves := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _col_cache := {}   # Vector2i -> ColumnInfo
var _col_mutex := Mutex.new()


func _init(world_map: WorldMap) -> void:
	world = world_map
	cols = world.size / CHUNK
	var s := world.params.seed_value
	_caves.seed = s + 4
	_caves.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_caves.frequency = 0.035
	_caves.fractal_octaves = 2
	_forest.seed = s + 5
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.006
	_forest.fractal_octaves = 2


## Итоговая высота (с реками, городами и дорогами), билинейно по сетке колонок.
func height_at(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	var a := lerpf(_grid_h(ix, iz), _grid_h(ix + 1, iz), fx)
	var b := lerpf(_grid_h(ix, iz + 1), _grid_h(ix + 1, iz + 1), fx)
	return lerpf(a, b, fz)


func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return sqrt(dx * dx + dz * dz) * 0.5


## Склон по дальней высоте (без колонок): по нему решают и обычные деревья, и их дальние LOD (FarProps) —
## одинаковое решение «есть дерево / нет», без фантомных LOD.
func far_slope(x: float, z: float) -> float:
	var dx := world.far_height(x + 1.0, z) - world.far_height(x - 1.0, z)
	var dz := world.far_height(x, z + 1.0) - world.far_height(x, z - 1.0)
	return sqrt(dx * dx + dz * dz) * 0.5


func _grid_h(ix: int, iz: int) -> float:
	var ci := column(floori(ix / float(CHUNK)), floori(iz / float(CHUNK)))
	return ci.h[posmod(ix, CHUNK) + CHUNK * posmod(iz, CHUNK)]


func column(cx: int, cz: int) -> ColumnInfo:
	var key := Vector2i(cx, cz)
	_col_mutex.lock()
	var ci: ColumnInfo = _col_cache.get(key)
	_col_mutex.unlock()
	if ci != null:
		return ci
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var hin := PackedFloat32Array()
	hin.resize(CHUNK * CHUNK)
	for j in CHUNK:
		for i in CHUNK:
			# холмики у загородных дорог — до дорог: дорога прорезает их выемкой (тот же рельеф у дальнего ландшафта)
			hin[i + CHUNK * j] = world.base_height(x0 + i, z0 + j) + world.roadside_bump(x0 + i, z0 + j)
	var water := PackedByteArray()
	water.resize(CHUNK * CHUNK)
	world.hydro.apply(x0, z0, CHUNK, hin, water)
	var res := world.roads.compute_area(x0, z0, CHUNK, hin)
	ci = ColumnInfo.new()
	ci.h = res["h"]
	ci.mat = res["mat"]
	var blocked: PackedByteArray = res["blocked"]
	for k in blocked.size():
		if water[k] != 0:
			blocked[k] = 1
	ci.blocked = blocked
	_col_mutex.lock()
	if _col_cache.size() > COLUMN_CACHE_MAX:
		_col_cache.clear()
	_col_cache[key] = ci
	_col_mutex.unlock()
	return ci


## Минимальная и максимальная высота поверхности над колонкой чанков (x=min, y=max).
## Приблизительно (по естественному рельефу, с запасом на реки, дороги и города).
var _range_cache := {}
var _range_mutex := Mutex.new()


func column_range(cx: int, cz: int) -> Vector2:
	var rk := Vector2i(cx, cz)
	_range_mutex.lock()
	var cached: Variant = _range_cache.get(rk)
	_range_mutex.unlock()
	if cached != null:
		return cached
	var v := _column_range_calc(cx, cz)
	_range_mutex.lock()
	if _range_cache.size() > 20000:
		_range_cache.clear()
	_range_cache[rk] = v
	_range_mutex.unlock()
	return v


func _column_range_calc(cx: int, cz: int) -> Vector2:
	var lo := INF
	var hi := -INF
	for iz in 5:
		for ix in 5:
			var h := world.base_height(cx * CHUNK + ix * CHUNK / 4.0, cz * CHUNK + iz * CHUNK / 4.0)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo - 12.0, hi + 10.0)


func in_map(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < cols and cz < cols


func spawn_point() -> Vector3:
	return world.spawn


func generate_chunk(cc: Vector3i) -> ChunkData:
	var cd := ChunkData.new()
	var n := CHUNK
	cd.dens.resize(n * n * n)
	cd.mat.resize(n * n * n)
	var col := column(cc.x, cc.z)
	var ox := cc.x * n
	var oy := cc.y * n
	var oz := cc.z * n
	for z in n:
		for x in n:
			var wx := ox + x
			var wz := oz + z
			var k := x + n * z
			var h := col.h[k]
			var rm: int = col.mat[k]
			var sandy := h < WATER_LEVEL + 2.0
			for y in n:
				var wy := oy + y
				var depth := h - wy
				var d := clampf(depth, -4.0, 4.0)
				if depth > 5.0:
					var c := (absf(_caves.get_noise_3d(wx, wy, wz)) - 0.08) * 14.0
					d = minf(d, maxf(c, 6.0 - depth))
				d = minf(d, wy - FLOOR_Y)
				var i := x + n * (y + n * z)
				cd.dens[i] = d
				var m := MAT_STONE
				if rm != 0 and depth < 3.4:
					# тонкое покрытие -> щебёночная подушка (асфальт/бетон) или земля -> грунт
					if depth < 0.999:
						m = rm
					elif rm == MAT_ROADSAND or rm == MAT_GRAVEL:
						m = MAT_DIRT
					else:
						m = MAT_BASE if depth < 2.4 else MAT_DIRT
				elif depth < 1.6:
					m = MAT_SAND if sandy else MAT_GRASS
				elif depth < 4.0 and sandy:
					m = MAT_SAND
				elif depth < 6.0:
					m = MAT_DIRT
				cd.mat[i] = m
	return cd


## Колонка с наибольшим числом деревьев рядом с точкой (для скриншотов и отладки).
func find_forest_spot(center: Vector2, ncols: int) -> Vector3:
	var best := Vector3(center.x, height_at(center.x, center.y) + 2.0, center.y)
	var best_n := -1
	var c0 := Vector2i(floori(center.x / CHUNK), floori(center.y / CHUNK))
	for dz in range(-ncols, ncols + 1):
		for dx in range(-ncols, ncols + 1):
			if not in_map(c0.x + dx, c0.y + dz):
				continue
			var n := 0
			for p: Dictionary in vegetation_plan(c0.x + dx, c0.y + dz):
				if p["res"] == "wood":
					n += 1
			if n > best_n:
				best_n = n
				var x := (c0.x + dx) * CHUNK + 8.0
				var z := (c0.y + dz) * CHUNK + 8.0
				best = Vector3(x, height_at(x, z) + 2.0, z)
	return best


## Растительность колонки: массив словарей {kind, mesh, res, x, z, h, rot, scale}.
## Детерминирована; позиции по высоте уточняет Vegetation по реальным данным ландшафта.
## far=true: без расчёта колонки (дальние LOD): высота по far_height, дорог и воды не знаем.
func vegetation_plan(cx: int, cz: int, far: bool = false) -> Array:
	var col: ColumnInfo = null if far else column(cx, cz)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.params.seed_value, cx, cz, 77])
	var out := []
	var cell := 4
	for gz in 4:
		for gx in 4:
			var lx := gx * cell + rng.randf_range(0.5, cell - 0.5)
			var lz := gz * cell + rng.randf_range(0.5, cell - 0.5)
			var roll := rng.randf()
			var pick := rng.randf()
			var variant := rng.randi() % 3
			var rot := rng.randf() * TAU
			var sc := rng.randf_range(0.8, 1.25)
			var k := int(lx) + CHUNK * int(lz)
			var wx := cx * CHUNK + lx
			var wz := cz * CHUNK + lz
			var h: float
			if far:
				h = world.far_height(wx, wz)
			else:
				if col.blocked[k] != 0 or col.mat[k] != 0:
					continue
				h = col.h[k]
			if h < WATER_LEVEL + 0.8:
				continue
			var tree_p := clampf((_forest.get_noise_2d(wx, wz) + 0.1) * 0.55, 0.0, 0.3)
			# обочины загородных дорог: деревья чаще (полоса 6–14 м от края; ближе — дальние LOD их не рисуют)
			var rd := world.road_dist(wx, wz)
			if rd >= ROADSIDE_TREE_MIN and rd <= ROADSIDE_TREE_MAX:
				tree_p = maxf(tree_p, ROADSIDE_TREE_P)
			var kind := ""
			var mesh := ""
			var res := ""
			var burnt := world.biome.burn_at(wx, wz)
			if burnt > 0.45:
				tree_p *= 0.45      # в выжженном биоме деревьев мало, и все они мёртвые
			if roll < tree_p:
				res = "wood"
				if burnt > 0.45:
					kind = "dead_tree"
				elif h > 34.0:
					kind = "pine" if pick < 0.8 else "dead_tree"
				elif h < WATER_LEVEL + 4.0:
					kind = "oak" if pick < 0.85 else "dead_tree"
				else:
					kind = "pine" if pick < 0.35 else ("oak" if pick < 0.9 else "dead_tree")
				mesh = "dead_tree_0" if kind == "dead_tree" else "%s_%d" % [kind, variant]
				if kind == "oak" and fmod(pick * 37.0, 1.0) < 0.16:
					mesh = "oak_dry_%d" % (variant % 2)
			elif roll < tree_p + 0.06:
				if burnt > 0.45:
					continue
				kind = "bush"
				res = "fiber"
				mesh = "bush_%d" % variant
				sc *= 0.9
			elif roll < tree_p + 0.09:
				kind = "rock"
				res = "stone"
				mesh = "rock_%d" % variant
				sc = rng.randf_range(0.7, 1.5)
			else:
				continue
			out.append({"kind": kind, "mesh": mesh, "res": res, "x": wx, "z": wz, "h": h, "rot": rot, "scale": sc})
	return out
