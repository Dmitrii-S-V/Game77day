class_name Terrain
extends Node3D
## Стриминг чанков: генерация данных и меширинг в потоках, сборка мешей и коллизии
## в основном потоке, правка ландшафта (копать / насыпать).

signal edited(center: Vector3, radius: float)

const CHUNK := WorldGen.CHUNK
const PAD := CHUNK + 2
const MIN_CY := -3
const MAX_CY := 7
const MESH_APPLY_PER_FRAME := 4
const ISLAND_MAX := 90   # оторванные куски твёрдого размером до N узлов удаляются

var view_radius := 6
var max_jobs := 6
var gen: WorldGen
var material: Material
var keep_arrays := false           # для тестов: хранить массивы мешей
var debug_meshes := {}             # Vector3i -> {verts, idx}

var _data := {}        # Vector3i -> ChunkData
var _data_mutex := Mutex.new()
var _nodes := {}       # Vector3i -> MeshInstance3D (только непустые чанки)
var _done := {}        # Vector3i -> true (чанк построен, возможно пустой)
var _wanted := {}      # Vector3i -> true
var _inflight := {}    # Vector3i -> true
var _dirty := {}       # Vector3i -> true (изменён во время построения)
var _queue: Array[Vector3i] = []
var _priority: Array[Vector3i] = []
var _results: Array = []
var _results_mutex := Mutex.new()
var _center := Vector3i(1 << 30, 0, 0)
var built_total := 0   # счётчик построенных чанков (замер скорости стриминга)
var _col_queue: Array = []   # [cc, shape] — отложенное подключение коллизии дальних чанков
var _edited_cc := {}         # чанки, перестроенные из-за правки ландшафта: коллизия нужна сразу


func _priority_set_contains(cc: Vector3i) -> bool:
	if _edited_cc.has(cc):
		_edited_cc.erase(cc)
		return true
	return false


func update_view(pos: Vector3) -> void:
	var cx := floori(pos.x / CHUNK)
	var cz := floori(pos.z / CHUNK)
	if cx != _center.x or cz != _center.z:
		_center = Vector3i(cx, 0, cz)
		var tr := Time.get_ticks_usec()
		_rebuild_wanted()
		# игрок перешёл в новый чанк: всё, что теперь рядом (до 2 чанков), получает коллизию немедленно
		var i := 0
		while i < _col_queue.size():
			var qc: Vector3i = _col_queue[i][0]
			if (qc.x - cx) * (qc.x - cx) + (qc.z - cz) * (qc.z - cz) <= 4:
				_attach_col(_col_queue[i])
				_col_queue.remove_at(i)
			else:
				i += 1
		Prof.add("t_rebuild", Time.get_ticks_usec() - tr)
	var ta := Time.get_ticks_usec()
	_apply_results()
	Prof.add("t_apply", Time.get_ticks_usec() - ta)
	var tl := Time.get_ticks_usec()
	_launch_jobs()
	Prof.add("t_launch", Time.get_ticks_usec() - tl)


## Радиус ближнего ландшафта (в чанках) — из настроек графики; перестройка набора чанков на следующем кадре.
func set_view_radius(r: int) -> void:
	if r == view_radius:
		return
	view_radius = r
	_center = Vector3i(1 << 30, 0, 0)


## Радиус вокруг pos (м), в котором все нужные чанки уже построены.
func safe_radius(pos: Vector3) -> float:
	var best := 1e9
	var px := pos.x
	var pz := pos.z
	for lst in [_queue, _priority]:
		for cc: Vector3i in lst:
			if _done.has(cc):
				continue
			best = minf(best, _chunk_dist(cc, px, pz))
	for cc: Vector3i in _inflight.keys():
		best = minf(best, _chunk_dist(cc, px, pz))
	for cc: Vector3i in _wanted.keys():
		if not _done.has(cc):
			best = minf(best, _chunk_dist(cc, px, pz))
	return best


func _chunk_dist(cc: Vector3i, px: float, pz: float) -> float:
	var x0 := cc.x * CHUNK
	var z0 := cc.z * CHUNK
	var dx := maxf(maxf(x0 - px, px - (x0 + CHUNK)), 0.0)
	var dz := maxf(maxf(z0 - pz, pz - (z0 + CHUNK)), 0.0)
	return sqrt(dx * dx + dz * dz)


func is_idle() -> bool:
	return _queue.is_empty() and _priority.is_empty() and _inflight.is_empty()


## Построены ли все нужные чанки колонки (cx, cz).
func is_column_done(cx: int, cz: int) -> bool:
	var rng := gen.column_range(cx, cz)
	for cy in range(MIN_CY, MAX_CY + 1):
		if cy * CHUNK > rng.y or (cy + 1) * CHUNK < rng.x:
			continue
		if not _done.has(Vector3i(cx, cy, cz)):
			return false
	return true


## Готовы ли все нужные чанки в колонках вокруг позиции (для безопасного спавна игрока).
func is_ready_around(pos: Vector3, rad: int = 1) -> bool:
	var cx := floori(pos.x / CHUNK)
	var cz := floori(pos.z / CHUNK)
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if not is_column_done(cx + dx, cz + dz):
				return false
	return true


func stats() -> String:
	return "chunks %d  meshes %d  queue %d  jobs %d" % [_done.size(), _nodes.size(), _queue.size() + _priority.size(), _inflight.size()]


# --- данные -----------------------------------------------------------------

func get_chunk(cc: Vector3i) -> ChunkData:
	_data_mutex.lock()
	var cd: ChunkData = _data.get(cc)
	_data_mutex.unlock()
	if cd != null:
		return cd
	var fresh := gen.generate_chunk(cc)
	_data_mutex.lock()
	cd = _data.get(cc)
	if cd == null:
		_data[cc] = fresh
		cd = fresh
	_data_mutex.unlock()
	return cd


func density(ix: int, iy: int, iz: int) -> float:
	var cc := Vector3i(floori(ix / float(CHUNK)), floori(iy / float(CHUNK)), floori(iz / float(CHUNK)))
	return get_chunk(cc).dens[posmod(ix, CHUNK) + CHUNK * (posmod(iy, CHUNK) + CHUNK * posmod(iz, CHUNK))]


## Высота поверхности (по реальным данным, с учётом правок) возле hint. NAN, если не найдена.
func surface_y(x: float, z: float, hint: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	var y00 := _column_surface(ix, iz, hint)
	var y10 := _column_surface(ix + 1, iz, hint)
	var y01 := _column_surface(ix, iz + 1, hint)
	var y11 := _column_surface(ix + 1, iz + 1, hint)
	if is_nan(y00) or is_nan(y10) or is_nan(y01) or is_nan(y11):
		return NAN
	return lerpf(lerpf(y00, y10, fx), lerpf(y01, y11, fx), fz)


func column_surface(ix: int, iz: int, hint: float) -> float:
	return _column_surface(ix, iz, hint)


func _column_surface(ix: int, iz: int, hint: float) -> float:
	var y := ceili(hint) + 5
	var prev := density(ix, y, iz)
	if prev > 0.0:
		return NAN
	for i in 15:
		y -= 1
		var d := density(ix, y, iz)
		if d > 0.0:
			return y + d / (d - prev)
		prev = d
	return NAN


## Материал воксельной «ячейки» ландшафта под точкой попадания p (n — нормаль поверхности). {cell, mat} или {} если твёрдого нет.
func block_at(p: Vector3, n: Vector3) -> Dictionary:
	var q := p - n * 0.5
	var base := Vector3i(q.floor())
	var best := {}
	var bd := 1e9
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := base + Vector3i(dx, dy, dz)
				if density(c.x, c.y, c.z) <= 0.0:
					continue
				var d := (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(q)
				if d < bd:
					bd = d
					var cc := Vector3i(floori(c.x / float(CHUNK)), floori(c.y / float(CHUNK)), floori(c.z / float(CHUNK)))
					best = {"cell": c, "mat": get_chunk(cc).mat[posmod(c.x, CHUNK) + CHUNK * (posmod(c.y, CHUNK) + CHUNK * posmod(c.z, CHUNK))]}
	return best


## Прочность блока ландшафта по материалу (трава — верхний слой 125, земля и прочее под ней 75).
static func block_max_hp(mat: int) -> float:
	match mat:
		WorldGen.MAT_GRASS: return 125.0
		WorldGen.MAT_STONE: return 300.0
		WorldGen.MAT_ASPHALT, WorldGen.MAT_CONCRETE: return 300.0
	return 75.0


## Копать (add=false) или насыпать (add=true) сферу. radius в метрах.
func edit_sphere(center: Vector3, radius: float, add: bool, mat_id: int = WorldGen.MAT_DIRT) -> void:
	var reach := radius + 1.5
	var lo := Vector3i((center - Vector3.ONE * reach).floor())
	var hi := Vector3i((center + Vector3.ONE * reach).ceil())
	var last_cc := Vector3i(1 << 30, 0, 0)
	var cd: ChunkData = null
	var changed := false
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var dist := Vector3(x, y, z).distance_to(center)
				if dist > reach:
					continue
				var cc := Vector3i(floori(x / float(CHUNK)), floori(y / float(CHUNK)), floori(z / float(CHUNK)))
				if cc != last_cc:
					cd = get_chunk(cc)
					last_cc = cc
				var li := posmod(x, CHUNK) + CHUNK * (posmod(y, CHUNK) + CHUNK * posmod(z, CHUNK))
				var old := cd.dens[li]
				var nv := old
				if add:
					nv = maxf(old, radius - dist)
					if radius - dist > 0.0:
						cd.mat[li] = mat_id
				else:
					nv = minf(old, dist - radius)
				nv = clampf(nv, -4.0, 4.0)
				if nv != old:
					cd.dens[li] = nv
					cd.edited = true
					changed = true
	if not changed:
		return
	var margin := Vector3i.ONE * 3
	_remove_islands(lo - margin, hi + margin)
	var rlo := Vector3i(floori((lo.x - 5) / float(CHUNK)), floori((lo.y - 5) / float(CHUNK)), floori((lo.z - 5) / float(CHUNK)))
	var rhi := Vector3i(floori((hi.x + 5) / float(CHUNK)), floori((hi.y + 5) / float(CHUNK)), floori((hi.z + 5) / float(CHUNK)))
	for cz in range(rlo.z, rhi.z + 1):
		for cy in range(rlo.y, rhi.y + 1):
			for cx in range(rlo.x, rhi.x + 1):
				_request_remesh(Vector3i(cx, cy, cz))
	edited.emit(center, radius)


## Удаляет мелкие оторванные куски твёрдого (плавающие обломки) внутри бокса.
func _remove_islands(lo: Vector3i, hi: Vector3i) -> void:
	var sx := hi.x - lo.x + 1
	var sy := hi.y - lo.y + 1
	var sz := hi.z - lo.z + 1
	var n := sx * sy * sz
	var dens := PackedFloat32Array()
	dens.resize(n)
	var last_cc := Vector3i(1 << 30, 0, 0)
	var cd: ChunkData = null
	for z in sz:
		for y in sy:
			for x in sx:
				var wx := lo.x + x
				var wy := lo.y + y
				var wz := lo.z + z
				var cc := Vector3i(floori(wx / float(CHUNK)), floori(wy / float(CHUNK)), floori(wz / float(CHUNK)))
				if cc != last_cc:
					cd = get_chunk(cc)
					last_cc = cc
				dens[x + sx * (y + sy * z)] = cd.dens[posmod(wx, CHUNK) + CHUNK * (posmod(wy, CHUNK) + CHUNK * posmod(wz, CHUNK))]

	var seen := PackedByteArray()
	seen.resize(n)
	var stack := PackedInt32Array()
	var comp := PackedInt32Array()
	var layer := sx * sy
	for start in n:
		if seen[start] != 0 or dens[start] <= 0.0:
			continue
		stack.clear()
		comp.clear()
		stack.append(start)
		seen[start] = 1
		var touches := false
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append(i)
			var x := i % sx
			var y := (i / sx) % sy
			var z := i / layer
			if x == 0 or y == 0 or z == 0 or x == sx - 1 or y == sy - 1 or z == sz - 1:
				touches = true
			if x > 0 and seen[i - 1] == 0 and dens[i - 1] > 0.0:
				seen[i - 1] = 1
				stack.append(i - 1)
			if x < sx - 1 and seen[i + 1] == 0 and dens[i + 1] > 0.0:
				seen[i + 1] = 1
				stack.append(i + 1)
			if y > 0 and seen[i - sx] == 0 and dens[i - sx] > 0.0:
				seen[i - sx] = 1
				stack.append(i - sx)
			if y < sy - 1 and seen[i + sx] == 0 and dens[i + sx] > 0.0:
				seen[i + sx] = 1
				stack.append(i + sx)
			if z > 0 and seen[i - layer] == 0 and dens[i - layer] > 0.0:
				seen[i - layer] = 1
				stack.append(i - layer)
			if z < sz - 1 and seen[i + layer] == 0 and dens[i + layer] > 0.0:
				seen[i + layer] = 1
				stack.append(i + layer)
		if touches or comp.size() > ISLAND_MAX:
			continue
		for i in comp:
			var wx := lo.x + i % sx
			var wy := lo.y + (i / sx) % sy
			var wz := lo.z + i / layer
			var cc := Vector3i(floori(wx / float(CHUNK)), floori(wy / float(CHUNK)), floori(wz / float(CHUNK)))
			var c2 := get_chunk(cc)
			c2.dens[posmod(wx, CHUNK) + CHUNK * (posmod(wy, CHUNK) + CHUNK * posmod(wz, CHUNK))] = -0.6
			c2.edited = true


func _in_view(cc: Vector3i) -> bool:
	var dx := cc.x - _center.x
	var dz := cc.z - _center.z
	return dx * dx + dz * dz <= view_radius * view_radius and cc.y >= MIN_CY and cc.y <= MAX_CY


func _request_remesh(cc: Vector3i) -> void:
	_edited_cc[cc] = true
	if _inflight.has(cc):
		_dirty[cc] = true
	elif _done.has(cc):
		if not _priority.has(cc):
			_priority.append(cc)
	elif _in_view(cc) and not _priority.has(cc):
		# чанк вне "ожидаемых" (например, небо), но правка добавила в него поверхность
		_wanted[cc] = true
		_priority.append(cc)


# --- стриминг ---------------------------------------------------------------

func _rebuild_wanted() -> void:
	_wanted.clear()
	_queue.clear()
	var r := view_radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var cx := _center.x + dx
			var cz := _center.z + dz
			if not gen.in_map(cx, cz):
				continue
			var rng := gen.column_range(cx, cz)
			for cy in range(MIN_CY, MAX_CY + 1):
				# чанки целиком выше поверхности или глубоко под ней (с запасом на реки/озёра) не строим: поверхности
				# в них нет. Раньше генерировались 3-4 подземных чанка на колонку (с 3D-шумом пещер на каждый воксель) —
				# стриминг при полёте был в 2-3 раза медленнее. Понадобятся при копании — правка добавит их сама.
				if cy * CHUNK > rng.y or (cy + 1) * CHUNK < rng.x:
					continue
				var cc := Vector3i(cx, cy, cz)
				_wanted[cc] = true
				if not _done.has(cc) and not _inflight.has(cc):
					_queue.append(cc)
	# изменённые игроком чанки всегда остаются в мире
	_data_mutex.lock()
	for cc: Vector3i in _data.keys():
		var cd: ChunkData = _data[cc]
		if cd.edited and _in_view(cc) and not _wanted.has(cc):
			_wanted[cc] = true
			if not _done.has(cc) and not _inflight.has(cc):
				_queue.append(cc)
	_data_mutex.unlock()
	for cc: Vector3i in _done.keys():
		if not _wanted.has(cc):
			_unload(cc)
	_purge_data()
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _dist2(a) < _dist2(b))


func _dist2(cc: Vector3i) -> int:
	var dx := cc.x - _center.x
	var dz := cc.z - _center.z
	return dx * dx + dz * dz


func _unload(cc: Vector3i) -> void:
	_done.erase(cc)
	debug_meshes.erase(cc)
	var node: MeshInstance3D = _nodes.get(cc)
	if node != null:
		FrameBudget.free_later(node)
		_nodes.erase(cc)


func _purge_data() -> void:
	var lim := view_radius + 2
	_data_mutex.lock()
	for cc: Vector3i in _data.keys():
		var cd: ChunkData = _data[cc]
		if not cd.edited and (absi(cc.x - _center.x) > lim or absi(cc.z - _center.z) > lim):
			_data.erase(cc)
	_data_mutex.unlock()


func _launch_jobs() -> void:
	while _inflight.size() < max_jobs:
		var cc: Vector3i
		if not _priority.is_empty():
			cc = _priority.pop_front()
		elif not _queue.is_empty():
			cc = _queue.pop_front()
		else:
			break
		if _inflight.has(cc):
			_dirty[cc] = true
			continue
		_inflight[cc] = true
		WorkerThreadPool.add_task(_job.bind(cc))


func _job(cc: Vector3i) -> void:
	var res := _build_chunk(cc)
	_results_mutex.lock()
	_results.append(res)
	_results_mutex.unlock()


func _build_chunk(cc: Vector3i) -> Dictionary:
	var nb: Array[ChunkData] = []
	nb.resize(27)
	for dz in 3:
		for dy in 3:
			for dx in 3:
				nb[dx + 3 * (dy + 3 * dz)] = get_chunk(cc + Vector3i(dx - 1, dy - 1, dz - 1))

	var d := PackedFloat32Array()
	d.resize(PAD * PAD * PAD)
	var m := PackedByteArray()
	m.resize(PAD * PAD * PAD)
	for pz in PAD:
		var oz := 0 if pz == 0 else (2 if pz == PAD - 1 else 1)
		var lz := posmod(pz - 1, CHUNK)
		for py in PAD:
			var oy := 0 if py == 0 else (2 if py == PAD - 1 else 1)
			var ly := posmod(py - 1, CHUNK)
			for px in PAD:
				var ox := 0 if px == 0 else (2 if px == PAD - 1 else 1)
				var lx := posmod(px - 1, CHUNK)
				var cd := nb[ox + 3 * (oy + 3 * oz)]
				var li := lx + CHUNK * (ly + CHUNK * lz)
				var pi := px + PAD * (py + PAD * pz)
				d[pi] = cd.dens[li]
				m[pi] = cd.mat[li]

	var sn := SurfaceNets.new()
	var res := {"cc": cc, "ok": false}
	if sn.build(d, m):
		var faces := PackedVector3Array()
		faces.resize(sn.indices.size())
		for i in sn.indices.size():
			faces[i] = sn.verts[sn.indices[i]]
		res["ok"] = true
		res["verts"] = sn.verts
		res["norms"] = sn.norms
		res["cols"] = sn.cols
		res["custom0"] = sn.custom0
		res["uvs"] = sn.uvs
		res["idx"] = sn.indices
		res["faces"] = faces
		# коллизионная фигура строится здесь, в рабочем потоке (BVH дорого считать в главном)
		var shp := ConcavePolygonShape3D.new()
		shp.backface_collision = true
		shp.set_faces(faces)
		res["shape"] = shp
	return res


func _apply_results() -> void:
	# общий бюджет кадра (FrameBudget): минимум один кусок, дальше — пока не потрачено ~2 мс от начала подгрузки
	var applied := 0
	while applied < 8 and (applied == 0 or FrameBudget.ok(2.0)):
		_results_mutex.lock()
		if _results.is_empty():
			_results_mutex.unlock()
			break
		var r: Dictionary = _results.pop_front()
		_results_mutex.unlock()
		applied += 1
		built_total += 1
		var cc: Vector3i = r["cc"]
		_inflight.erase(cc)
		if _wanted.has(cc):
			_done[cc] = true
			_set_mesh(cc, r)
			if _dirty.has(cc):
				_dirty.erase(cc)
				_priority.append(cc)
	# отложенная коллизия дальних чанков — по одной, если в кадре осталось время (или очередь длинная)
	# (подключение коллизии стоит ~2 мс — только в «лёгком» кадре; очередь копится, пока игрок далеко от этих чанков;
	# чанки, к которым игрок подошёл ближе ~48 м, подключаются в любом случае)
	if not _col_queue.is_empty() and (FrameBudget.ok(1.0) or _col_queue.size() > 80):
		var it: Array = _col_queue.pop_front()
		_attach_col(it)
	elif not _col_queue.is_empty():
		for i in mini(_col_queue.size(), 12):
			var cc: Vector3i = _col_queue[i][0]
			if (cc.x - _center.x) * (cc.x - _center.x) + (cc.z - _center.z) * (cc.z - _center.z) <= 9:
				_attach_col(_col_queue[i])
				_col_queue.remove_at(i)
				break


func _attach_col(it: Array) -> void:
	var n: MeshInstance3D = _nodes.get(it[0])
	if n != null and is_instance_valid(n) and n.mesh == it[2]:   # чанк не перестраивался с тех пор
		(n.get_node("Body/Shape") as CollisionShape3D).shape = it[1]


func _set_mesh(cc: Vector3i, r: Dictionary) -> void:
	var node: MeshInstance3D = _nodes.get(cc)
	if keep_arrays:
		if r["ok"]:
			debug_meshes[cc] = {"verts": r["verts"], "idx": r["idx"]}
		else:
			debug_meshes.erase(cc)
	if not r["ok"]:
		if node != null:
			node.queue_free()
			_nodes.erase(cc)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_NORMAL] = r["norms"]
	arrays[Mesh.ARRAY_COLOR] = r["cols"]
	arrays[Mesh.ARRAY_CUSTOM0] = r["custom0"]
	arrays[Mesh.ARRAY_TEX_UV] = r["uvs"]
	arrays[Mesh.ARRAY_INDEX] = r["idx"]
	var tm := Time.get_ticks_usec()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	Prof.add("t_mesh", Time.get_ticks_usec() - tm)
	var ts := Time.get_ticks_usec()

	var shape: ConcavePolygonShape3D = r.get("shape")
	if shape == null:
		shape = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(r["faces"])

	if node == null:
		node = MeshInstance3D.new()
		node.position = Vector3(cc * CHUNK)
		node.material_override = material
		var body := StaticBody3D.new()
		body.name = "Body"
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		body.add_child(cs)
		node.add_child(body)
		add_child(node)
		_nodes[cc] = node
	node.mesh = mesh
	# коллизия: вблизи игрока (и при правке ландшафта) — сразу; дальше ~32 м — в очередь (подключится за кадр-другой)
	var dx := cc.x - _center.x
	var dz := cc.z - _center.z
	if dx * dx + dz * dz <= 4 or _priority_set_contains(cc):
		(node.get_node("Body/Shape") as CollisionShape3D).shape = shape
	else:
		_col_queue.append([cc, shape, mesh])
	Prof.add("t_node", Time.get_ticks_usec() - ts)
