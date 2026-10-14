class_name BlockBuilding
extends Node3D
## Здание из блоков: куски меша 8x8x8 ячеек, коллизия по видимым граням, поблочное разрушение
## с обломками и обрушением оторванных от земли частей. Нестандартные блоки (двери, окна, декор)
## рисуются в меш куска, а коллизию, свет и зоны замедления получают отдельными узлами (_custom).

const B := BlockGrid.B
const CS := BlockGrid.CS
const SUPPORT_CAP := 9000
const LAYER_SOLID := 2
const LAYER_SOFT := 8       # «мягкие» блоки: игрок проходит, но их можно выбрать и ударить
const KIND_COLORS := {
	"wood": Color(0.5, 0.36, 0.22), "stone": Color(0.55, 0.55, 0.53), "glass": Color(0.6, 0.78, 0.88),
	"cloth": Color(0.6, 0.2, 0.2), "metal": Color(0.5, 0.52, 0.55), "wax": Color(0.9, 0.85, 0.7),
}

static var _break_snd_ms := 0

signal block_changed(cells: Array)
signal edited          # любое изменение игроком (в т.ч. дверь) — для сохранения

var grid: BlockGrid
var opaque_mat: Material
var glass_mat: Material
var origin := Vector3.ZERO     # смещение пространства сетки относительно узла
var edit_mode := false         # редактор: без обрушений и обломков

var _chunks := {}              # Vector3i -> {mi, gi, body}
var _results: Array = []
var _results_mutex := Mutex.new()
var _pending := 0
var _props: Array = []
var _custom_todo: Array = []     # индексы якорей, для которых ещё не созданы узлы (см. setup)
var _custom := {}              # idx якоря -> {nodes: Array, light: OmniLight3D}
static var _prop_scenes := {}


## Прогрев: загрузить модели предметов зданий (унитаз) заранее.
static func warm_up() -> void:
	for nm in ["toilet"]:
		var path := "res://assets/ready/%s.glb" % nm
		if _prop_scenes.get(nm) == null and ResourceLoader.exists(path):
			_prop_scenes[nm] = load(path)
static var _lights: Array = []
static var _light_node: Node


func setup(g: BlockGrid, opaque: Material, glass: Material, edit: bool = false, org: Variant = null) -> void:
	grid = g
	opaque_mat = opaque
	glass_mat = glass
	edit_mode = edit
	origin = org if org is Vector3 else Vector3(-g.nx * B * 0.5, -g.ground_cells * B, -g.nz * B * 0.5)
	set_meta("block_building", true)
	_spawn_props()
	if not edit:
		_populate_territory()
	if grid.has_new:
		if edit:
			_sync_all_custom()
		else:
			# в мире узлы коллизии/света нестандартных блоков создаются порциями по кадрам (без подвисаний)
			for i in grid.cells.size():
				var cid := grid.cells[i]
				if cid >= BlockRegistry.FIRST_ID and not BlockRegistry.is_cube(cid) and not BlockRegistry.is_part(grid.meta[i]):
					_custom_todo.append(i)
	WorkerThreadPool.add_task(_build_all)


## Территория префаба в мире: покрытие земли (с кустиками травы на «траве»), посаженное в редакторе (деревья, кусты,
## скамейки…), случайные камешки на свободной земле, иногда куча мусора и брошенный рюкзак с лутом.
## Всё детерминировано по месту здания; срубленное/подобранное не возвращается (Vegetation.removed).
func _populate_territory() -> void:
	if grid.ground.is_empty() and grid.plants.is_empty() and not grid.has_new:
		return     # кодовые здания без префабных данных — как раньше
	var top := grid.sink * B - 0.03          # локальная высота поверхности участка (пол — вровень с землёй)
	var seed_v := absi(hash(Vector2i(roundi(global_position.x * 2.0), roundi(global_position.z * 2.0))))
	if not grid.ground.is_empty():
		var gp := GroundTypes.make_node(grid.ground, B, seed_v)
		gp.position = Vector3(origin.x, top, origin.z)
		add_child(gp)
	for p: Dictionary in grid.plants:
		var lp := Vector3(origin.x + float(p["x"]), top, origin.z + float(p["z"]))
		var gpos := global_transform * lp
		if Vegetation.removed.has(Vegetation.plant_key(gpos.x, gpos.z)):
			continue
		var n := PlantTypes.make(p, lp, gpos)
		if n != null:
			add_child(n)
	# свободная земля участка: ячейки без пола и стен
	var free: Array[Vector2i] = []
	for z in grid.nz:
		for x in grid.nx:
			if grid.get_cell(x, grid.ground_cells, z) == 0 and (grid.ny <= grid.ground_cells + 1 or grid.get_cell(x, grid.ground_cells + 1, z) == 0):
				free.append(Vector2i(x, z))
	if free.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for c in free:
		if rng.randf() < 0.035:
			var lp := Vector3(origin.x + c.x + rng.randf_range(0.2, 0.8), top, origin.z + c.y + rng.randf_range(0.2, 0.8))
			var gpos := global_transform * lp
			if not Vegetation.removed.has(Vegetation.plant_key(gpos.x, gpos.z)):
				var pb := PropFactory.pebble(rng.randf_range(0.06, 0.12))
				pb.position = lp
				pb.rotation.y = rng.randf() * TAU
				add_child(pb)
	if rng.randf() < 0.3:
		var c := free[rng.randi() % free.size()]
		var ppos := Vector3(origin.x + c.x + 0.5, top, origin.z + c.y + 0.5)
		var prot := rng.randf() * TAU
		if not Breakables.is_broken(global_transform * ppos):
			var pile := PropFactory.trash_pile()
			pile.position = ppos
			pile.rotation.y = prot
			add_child(pile)
	if rng.randf() < 0.15:
		var c2 := free[rng.randi() % free.size()]
		var bpos := Vector3(origin.x + c2.x + 0.5, top, origin.z + c2.y + 0.5)
		var bvar := rng.randi()
		var brot := rng.randf() * TAU
		if not Breakables.is_broken(global_transform * bpos):
			var pack := PropFactory.backpack(bvar)
			pack.position = bpos
			pack.rotation.y = brot
			add_child(pack)


## Предметы внутри (унитазы): модели из assets/ready, коллизия-ящик; пропадают, если пол под ними разрушен.
func _spawn_props() -> void:
	for p: Dictionary in grid.props:
		if _prop_scenes.get(p["name"]) == null:
			var path := "res://assets/ready/%s.glb" % p["name"]
			if not ResourceLoader.exists(path):
				continue
			_prop_scenes[p["name"]] = load(path)
		var inst := (_prop_scenes[p["name"]] as PackedScene).instantiate() as Node3D
		inst.position = origin + (p["pos"] as Vector3)
		inst.rotation.y = p["yaw"]
		inst.set_meta("support", p["support"])
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_SOLID
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.74, 0.8, 0.48)
		cs.shape = sh
		cs.position = Vector3(0, 0.4, 0)
		body.add_child(cs)
		inst.add_child(body)
		add_child(inst)
		_props.append(inst)


func _update_props() -> void:
	for inst in _props.duplicate():
		if not is_instance_valid(inst) or inst.is_queued_for_deletion():
			_props.erase(inst)
			continue
		var c: Vector3i = inst.get_meta("support")
		if grid.get_cell(c.x, c.y, c.z) == 0:
			Debris.burst(get_tree().current_scene, inst.global_position + Vector3(0, 0.3, 0), Color(0.8, 0.8, 0.78), 5, 3.0, 0.1, 5.0, Debris.node_tex(inst))
			inst.queue_free()
			_props.erase(inst)


func is_ready() -> bool:
	return _pending == 0 and _results.is_empty()


func _build_all() -> void:
	var cd := grid.chunk_dims()
	_pending = cd.x * cd.y * cd.z
	for cz in cd.z:
		for cy in cd.y:
			for cx in cd.x:
				var res := BlockMesher.build_chunk(grid, cx, cy, cz)
				res["cc"] = Vector3i(cx, cy, cz)
				# коллизия строится здесь, в рабочем потоке (дерево треугольников дорого считать в главном)
				var fc: PackedVector3Array = res["faces"]
				if not fc.is_empty():
					var shp := ConcavePolygonShape3D.new()
					shp.set_faces(fc)
					res["shape"] = shp
				_results_mutex.lock()
				_results.append(res)
				_results_mutex.unlock()


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	# узлы нестандартных блоков и куски меша — в пределах общего бюджета кадра (здания в городе подгружаются пачкой)
	if not _custom_todo.is_empty() and (edit_mode or FrameBudget.ok(3.0)):
		for k in mini(10, _custom_todo.size()):
			var ci: int = _custom_todo.pop_back()
			if grid.cells[ci] != 0:
				_sync_custom(grid.cell_of(ci))
			if not edit_mode and not FrameBudget.ok(3.0):
				break
		Prof.add("bb_custom", Time.get_ticks_usec() - t0)
	if _results.is_empty():
		return
	if not edit_mode and not FrameBudget.ok(3.0) and _chunks.size() > 0:
		return
	var t1 := Time.get_ticks_usec()
	_results_mutex.lock()
	var take := mini(1 if not edit_mode else 3, _results.size())
	var batch := _results.slice(0, take)
	_results = _results.slice(take)
	_results_mutex.unlock()
	for r: Dictionary in batch:
		_pending -= 1
		_apply(r)
	Prof.add("bb_apply", Time.get_ticks_usec() - t1)


func _apply(r: Dictionary) -> void:
	var cc: Vector3i = r["cc"]
	var entry: Dictionary = _chunks.get(cc, {})
	for nm in ["mi", "gi", "body"]:
		if entry.has(nm) and is_instance_valid(entry[nm]):
			(entry[nm] as Node).queue_free()
	entry = {}
	var ov: PackedVector3Array = r["ov"]
	if not ov.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ov
		arrays[Mesh.ARRAY_NORMAL] = r["on"]
		arrays[Mesh.ARRAY_COLOR] = r["oc"]
		arrays[Mesh.ARRAY_TEX_UV] = r["ou"]
		arrays[Mesh.ARRAY_TEX_UV2] = r["ou2"]
		arrays[Mesh.ARRAY_INDEX] = r["oi"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = opaque_mat
		mi.position = origin
		add_child(mi)
		entry["mi"] = mi
	var gv: PackedVector3Array = r["gv"]
	if not gv.is_empty():
		var garr := []
		garr.resize(Mesh.ARRAY_MAX)
		garr[Mesh.ARRAY_VERTEX] = gv
		garr[Mesh.ARRAY_NORMAL] = r["gn"]
		garr[Mesh.ARRAY_COLOR] = r["gc"]
		garr[Mesh.ARRAY_INDEX] = r["gi"]
		var gmesh := ArrayMesh.new()
		gmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garr)
		var gi := MeshInstance3D.new()
		gi.mesh = gmesh
		gi.material_override = glass_mat
		gi.position = origin
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gi)
		entry["gi"] = gi
	var faces: PackedVector3Array = r["faces"]
	if not faces.is_empty():
		var shape: ConcavePolygonShape3D = r.get("shape")
		if shape == null:
			shape = ConcavePolygonShape3D.new()
			shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_SOLID
		body.collision_mask = 0
		body.position = origin
		body.set_meta("block_building", self)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		entry["body"] = body
	_chunks[cc] = entry


func _rebuild_chunk(cc: Vector3i) -> void:
	var cd := grid.chunk_dims()
	if cc.x < 0 or cc.y < 0 or cc.z < 0 or cc.x >= cd.x or cc.y >= cd.y or cc.z >= cd.z:
		return
	var res := BlockMesher.build_chunk(grid, cc.x, cc.y, cc.z)
	res["cc"] = cc
	_apply(res)


## Пересобрать меши всех кусков и узлы нестандартных блоков (после загрузки структуры в редакторе).
func rebuild_all() -> void:
	var cd := grid.chunk_dims()
	for cz in cd.z:
		for cy in cd.y:
			for cx in cd.x:
				_rebuild_chunk(Vector3i(cx, cy, cz))
	_sync_all_custom()


## Пересобрать меши и узлы в прямоугольнике ячеек [lo, hi] (включительно) и вокруг него.
func refresh_region(lo: Vector3i, hi: Vector3i) -> void:
	lo = Vector3i(maxi(lo.x, 0), maxi(lo.y, 0), maxi(lo.z, 0))
	hi = Vector3i(mini(hi.x, grid.nx - 1), mini(hi.y, grid.ny - 1), mini(hi.z, grid.nz - 1))
	var c0 := Vector3i(floori((lo.x - 1) / float(CS)), floori((lo.y - 1) / float(CS)), floori((lo.z - 1) / float(CS)))
	var c1 := Vector3i(floori((hi.x + 1) / float(CS)), floori((hi.y + 1) / float(CS)), floori((hi.z + 1) / float(CS)))
	for cz in range(c0.z, c1.z + 1):
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				_rebuild_chunk(Vector3i(cx, cy, cz))
	# узлы нестандартных блоков: якоря в области, расширенной на размер footprint
	var a_lo := Vector3i(maxi(lo.x - 4, 0), maxi(lo.y - 4, 0), maxi(lo.z - 4, 0))
	var a_hi := hi
	for k in _custom.keys():
		var a := grid.cell_of(k)
		if a.x >= a_lo.x and a.y >= a_lo.y and a.z >= a_lo.z and a.x <= a_hi.x and a.y <= a_hi.y and a.z <= a_hi.z:
			_clear_custom(k)
	for z in range(a_lo.z, a_hi.z + 1):
		for y in range(a_lo.y, a_hi.y + 1):
			for x in range(a_lo.x, a_hi.x + 1):
				var id := grid.cells[grid.idx(x, y, z)]
				if id >= BlockRegistry.FIRST_ID:
					_sync_custom(Vector3i(x, y, z))


## Пересобрать меши и узлы вокруг изменённых ячеек.
func refresh_cells(cs: Array) -> void:
	if cs.size() > 24:
		var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
		var hi := Vector3i(-1, -1, -1)
		for c: Vector3i in cs:
			lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
			hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
		refresh_region(lo, hi)
		return
	var todo := {}
	for c: Vector3i in cs:
		for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			todo[Vector3i(floori(n.x / float(CS)), floori(n.y / float(CS)), floori(n.z / float(CS)))] = true
	for k: Vector3i in todo.keys():
		_rebuild_chunk(k)
	# узлы нестандартных блоков: перепроверяем якоря поблизости (footprint до 4 ячеек)
	var anchors := {}
	for c: Vector3i in cs:
		for dz in range(-4, 1):
			for dy in range(-4, 1):
				for dx in range(-4, 1):
					var a := c + Vector3i(dx, dy, dz)
					if grid.inside(a.x, a.y, a.z):
						anchors[grid.idx(a.x, a.y, a.z)] = a
	for k in _custom.keys():
		if anchors.has(k):
			_clear_custom(k)
	for k in anchors:
		var a: Vector3i = anchors[k]
		_sync_custom(a)


## Отладка: убрать крышу (для осмотра интерьера сверху).
func debug_open_roof() -> void:
	# верхнее сплошное перекрытие (потолок) и всё выше него
	var ceiling := grid.ny
	for y in range(grid.ny - 1, 0, -1):
		var cnt := 0
		for z in grid.nz:
			for x in grid.nx:
				if grid.get_cell(x, y, z) != 0:
					cnt += 1
		if cnt > grid.nx * grid.nz * 4 / 10:
			ceiling = y
			break
	for z in grid.nz:
		for y in range(ceiling, grid.ny):
			for x in grid.nx:
				grid.set_cell(x, y, z, 0)
	var cd := grid.chunk_dims()
	for cz in cd.z:
		for cy in cd.y:
			for cx in cd.x:
				_rebuild_chunk(Vector3i(cx, cy, cz))


# --- удар и разрушение ------------------------------------------------------------------

## Ячейка под мировой точкой попадания (или якорь блока, если коллайдер нестандартного блока).
func cell_at_hit(world_pos: Vector3, normal: Vector3, collider: Object = null) -> Vector3i:
	if collider != null and collider is Node and (collider as Node).has_meta("anchor"):
		return (collider as Node).get_meta("anchor")
	var lp := to_local(world_pos - normal * 0.03) - origin
	return Vector3i(floori(lp.x / B), floori(lp.y / B), floori(lp.z / B))


## Удар по зданию в мировой точке: урон блоку. true, если блок найден. tool_name: axe | pickaxe | hand.
func hit(world_pos: Vector3, normal: Vector3, dmg: float, tool_name: String = "axe", collider: Object = null) -> bool:
	return hit_cell(cell_at_hit(world_pos, normal, collider), dmg, tool_name, world_pos)


## Удар по ячейке c (сеть применяет удары других игроков и зомби хоста этим же путём — урон детерминирован).
func hit_cell(c: Vector3i, dmg: float, tool_name: String, world_pos: Vector3 = Vector3.INF) -> bool:
	var id := grid.get_cell(c.x, c.y, c.z)
	if id == 0:
		return false
	if has_meta("bkey"):
		Net.op("bb_hit", [String(get_meta("bkey")), c, dmg, tool_name])
	if world_pos == Vector3.INF:
		world_pos = _cell_world(c)
	var a := grid.anchor_of(c)
	id = grid.get_cell(a.x, a.y, a.z)
	var m := grid.get_meta_at(a.x, a.y, a.z)
	var key := grid.idx(a.x, a.y, a.z)
	var max_hp := 0.0
	var mult := 1.0
	if BlockRegistry.is_new(id):
		var tier := BlockRegistry.tier_of(m)
		max_hp = BlockRegistry.hp(id, tier)
		mult = BlockRegistry.tool_mult(tool_name, id, tier)
	else:
		max_hp = float(BlockDefs.hp(id))
		mult = float(BlockDefs.AXE[id])
	var left: float = grid.hp.get(key, max_hp) - dmg * mult
	edited.emit()
	if left > 0.0:
		grid.hp[key] = left
		_burst(world_pos, id, m, 2, 1.5, 0.05, 2.0)
		return true
	grid.hp.erase(key)
	break_block(a, true)
	return true


## Прочность блока под точкой попадания: [осталось, максимум] или пусто.
func hp_at_hit(world_pos: Vector3, normal: Vector3, collider: Object = null) -> Array:
	var c := cell_at_hit(world_pos, normal, collider)
	var id := grid.get_cell(c.x, c.y, c.z)
	if id == 0:
		return []
	var a := grid.anchor_of(c)
	id = grid.get_cell(a.x, a.y, a.z)
	var m := grid.get_meta_at(a.x, a.y, a.z)
	var mx := BlockRegistry.hp(id, BlockRegistry.tier_of(m)) if BlockRegistry.is_new(id) else float(BlockDefs.hp(id))
	return [float(grid.hp.get(grid.idx(a.x, a.y, a.z), mx)), mx]


## Материал блока под точкой попадания (для звука удара): wood/stone/metal/glass/cloth/wax или "".
func kind_at_hit(world_pos: Vector3, normal: Vector3, collider: Object = null) -> String:
	var c := cell_at_hit(world_pos, normal, collider)
	if grid.get_cell(c.x, c.y, c.z) == 0:
		return ""
	var a := grid.anchor_of(c)
	var id := grid.get_cell(a.x, a.y, a.z)
	if BlockRegistry.is_new(id):
		return BlockRegistry.kind(id, BlockRegistry.tier_of(grid.get_meta_at(a.x, a.y, a.z)))
	match id:
		BlockDefs.BRICK, BlockDefs.CONCRETE, BlockDefs.STONE:
			return "stone"
		BlockDefs.METAL:
			return "metal"
		BlockDefs.GLASS:
			return "glass"
	return "wood"


## Текстура осколков блока — та же, что на самом блоке (стекло и старые блоки — без текстуры, цветом).
func debris_tex(id: int, m: int) -> Texture2D:
	if not BlockRegistry.is_new(id):
		return null
	var tier := BlockRegistry.tier_of(m)
	if BlockRegistry.kind(id, tier) == "glass":
		return null
	return Debris.block_layer_tex(BlockRegistry.tex_layer(id, tier, BlockRegistry.variant_of(m)))


## Осколки блока: текстурой материала; стекло и ткань — плоские.
func _burst(pos: Vector3, id: int, m: int, count: int, speed: float, size: float, life: float) -> void:
	var k := BlockRegistry.kind(id, BlockRegistry.tier_of(m)) if BlockRegistry.is_new(id) else ""
	var flat := 0.25 if k in ["glass", "cloth"] else (0.55 if k == "wood" else 1.0)
	Debris.burst(get_tree().current_scene, pos, block_color(id, m), count, speed, size, life, debris_tex(id, m), flat)


func block_color(id: int, m: int) -> Color:
	if BlockRegistry.is_new(id):
		return KIND_COLORS.get(BlockRegistry.kind(id, BlockRegistry.tier_of(m)), Color(0.5, 0.5, 0.5))
	return BlockDefs.color(id)


func _cell_world(c: Vector3i) -> Vector3:
	return to_global(origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * B)


## Ломает блок целиком (с частями) и проверяет крепления и опоры вокруг.
func break_block(c: Vector3i, check_support: bool) -> void:
	var id := grid.get_cell(c.x, c.y, c.z)
	if id == 0:
		return
	var rec := grid.remove_block(c)
	if rec.is_empty():
		return
	var cs: Array = rec["cells"]
	var wp := _cell_world(rec["anchor"])
	var count := 6 if (id == BlockDefs.GLASS or BlockRegistry.kind(id, BlockRegistry.tier_of(int(rec["meta"]))) == "glass") else 4
	if not edit_mode:
		_burst(wp, int(rec["id"]), int(rec["meta"]), count, 3.0, 0.14, 6.0)
		Debris.dust(get_tree().current_scene, wp, block_color(int(rec["id"]), int(rec["meta"])), 1.0)
		# звук разрушения; при обрушении многих блоков разом — не чаще раза в 0.12 с
		var now := Time.get_ticks_msec()
		if now - _break_snd_ms > 120:
			_break_snd_ms = now
			Sfx.play_at(self, "block_break", wp, 0.0, 40.0)
	refresh_cells(cs)
	if check_support and not edit_mode:
		_check_attachments(cs)
		for q: Vector3i in cs:
			_check_support(q)
	_update_props()
	block_changed.emit(cs)


## Крепящиеся блоки рядом с убранными ячейками: если опоры нет — отваливаются.
func _check_attachments(removed: Array) -> void:
	var seen := {}
	for c: Vector3i in removed:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			var id := grid.get_cell(n.x, n.y, n.z)
			if id == 0 or not BlockRegistry.is_new(id):
				continue
			var a := grid.anchor_of(n)
			if seen.has(a):
				continue
			seen[a] = true
			var m := grid.get_meta_at(a.x, a.y, a.z)
			if BlockRegistry.support_mode(id) != "" and not grid.is_supported(a, id, m):
				_drop_block(a)


func _drop_block(a: Vector3i) -> void:
	var id := grid.get_cell(a.x, a.y, a.z)
	var m := grid.get_meta_at(a.x, a.y, a.z)
	var wp := _cell_world(a)
	if edit_mode:
		var rec0 := grid.remove_block(a)
		if not rec0.is_empty():
			refresh_cells(rec0["cells"])
			_check_attachments(rec0["cells"])
		return
	if BlockRegistry.shape_of(id) == "candle":
		_spawn_falling_piece(wp, Color(0.92, 0.88, 0.72), Vector3(0.1, 0.16, 0.1))
	elif BlockRegistry.shape_of(id) == "chandelier":
		_spawn_falling_piece(wp, Color(0.7, 0.55, 0.25), Vector3(0.4, 0.2, 0.4))
	grid.hp.erase(grid.idx(a.x, a.y, a.z))
	var rec := grid.remove_block(a)
	if rec.is_empty():
		return
	_burst(wp, id, m, 3, 2.0, 0.1, 4.0)
	refresh_cells(rec["cells"])
	_check_attachments(rec["cells"])
	block_changed.emit(rec["cells"])


func _spawn_falling_piece(wp: Vector3, color: Color, size: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = color
	mi.material_override = mt
	rb.add_child(mi)
	rb.set_meta("falling_block", true)
	get_tree().current_scene.add_child(rb)
	rb.global_position = wp
	var tmr := get_tree().create_timer(3.5)
	tmr.timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.queue_free())


func _break_cell(c: Vector3i, check_support: bool) -> void:
	break_block(c, check_support)


func _refresh_around(c: Vector3i) -> void:
	refresh_cells([c])


## Части здания, потерявшие связь с землёй, обрушиваются.
func _check_support(removed: Vector3i) -> void:
	var visited := {}
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var start: Vector3i = removed + d
		if grid.get_cell(start.x, start.y, start.z) == 0 or visited.has(start):
			continue
		var comp: Array[Vector3i] = []
		var stack: Array[Vector3i] = [start]
		visited[start] = true
		var grounded := false
		var capped := false
		while not stack.is_empty():
			var cur: Vector3i = stack.pop_back()
			comp.append(cur)
			if cur.y <= grid.ground_cells:   # слой на земле и всё под ней опираются на землю
				grounded = true
			if comp.size() > SUPPORT_CAP:
				capped = true
				break
			for d2 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var nb: Vector3i = cur + d2
				if not visited.has(nb) and grid.get_cell(nb.x, nb.y, nb.z) != 0:
					visited[nb] = true
					stack.append(nb)
		if grounded or capped:
			continue
		# обрушение: убираем всю оторванную часть
		var stride := maxi(1, comp.size() / 24)
		var touched := {}
		for i in comp.size():
			var cc: Vector3i = comp[i]
			var cid := grid.get_cell(cc.x, cc.y, cc.z)
			var cmeta := grid.get_meta_at(cc.x, cc.y, cc.z)
			grid.set_cell(cc.x, cc.y, cc.z, 0, 0)
			if i % stride == 0:
				_burst(_cell_world(cc), cid, cmeta, 1, 2.0, 0.16, 6.0)
				if i % (stride * 4) == 0:
					Debris.dust(get_tree().current_scene, _cell_world(cc), block_color(cid, cmeta), 1.3)
			touched[Vector3i(floori(cc.x / float(CS)), floori(cc.y / float(CS)), floori(cc.z / float(CS)))] = true
		for k: Vector3i in touched.keys():
			for dz in range(-1, 2):
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						touched[k + Vector3i(dx, dy, dz)] = touched.get(k + Vector3i(dx, dy, dz), false)
		for k: Vector3i in touched.keys():
			_rebuild_chunk(k)
		if grid.has_new:
			_sync_all_custom()


# --- нестандартные блоки: коллизия, свет, замедление ---------------------------------------

func _sync_all_custom() -> void:
	for k in _custom.keys():
		_clear_custom(k)
	for i in grid.cells.size():
		var id := grid.cells[i]
		if id >= BlockRegistry.FIRST_ID and not BlockRegistry.is_cube(id) and not BlockRegistry.is_part(grid.meta[i]):
			_sync_custom(grid.cell_of(i))


func _clear_custom(key: int) -> void:
	var e: Dictionary = _custom.get(key, {})
	for n: Node in e.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	var l: Variant = e.get("light")
	if l != null and is_instance_valid(l):
		_lights.erase(l)
		(l as Node).queue_free()
	_custom.erase(key)


func _sync_custom(a: Vector3i) -> void:
	var key := grid.idx(a.x, a.y, a.z)
	var id := grid.get_cell(a.x, a.y, a.z)
	if id < BlockRegistry.FIRST_ID or BlockRegistry.is_cube(id) or BlockRegistry.is_part(grid.get_meta_at(a.x, a.y, a.z)):
		return
	if _custom.has(key):
		_clear_custom(key)
	var m := grid.get_meta_at(a.x, a.y, a.z)
	if BlockRegistry.shape_of(id) == "marker":
		_custom[key] = _sync_marker(a, id, m)
		return
	var parts := BlockShapes.build(id, m)
	var entry := {"nodes": [], "light": null}
	var base := origin + Vector3(a) * B
	var bodies := {}
	for b: Dictionary in parts["boxes"]:
		var coll: String = b["coll"]
		if coll == "none":
			continue
		var layer := LAYER_SOFT if coll == "soft" else LAYER_SOLID
		var body: StaticBody3D = bodies.get(layer)
		if body == null:
			body = StaticBody3D.new()
			body.collision_layer = layer
			body.collision_mask = 0
			body.position = base
			body.set_meta("block_building", self)
			body.set_meta("anchor", a)
			add_child(body)
			bodies[layer] = body
			entry["nodes"].append(body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var lo: Vector3 = b["a"]
		var hi: Vector3 = b["b"]
		sh.size = (hi - lo).max(Vector3(0.02, 0.02, 0.02))
		cs.shape = sh
		cs.position = (lo + hi) * 0.5
		body.add_child(cs)
	for h: Dictionary in parts.get("hulls", []):
		var hbody: StaticBody3D = bodies.get(LAYER_SOLID)
		if hbody == null:
			hbody = StaticBody3D.new()
			hbody.collision_layer = LAYER_SOLID
			hbody.collision_mask = 0
			hbody.position = base
			hbody.set_meta("block_building", self)
			hbody.set_meta("anchor", a)
			add_child(hbody)
			bodies[LAYER_SOLID] = hbody
			entry["nodes"].append(hbody)
		var hcs := CollisionShape3D.new()
		var hsh := ConvexPolygonShape3D.new()
		var hv := PackedVector3Array()
		for p: Vector3 in h["pts"]:
			hv.append(p)
		hsh.points = hv
		hcs.shape = hsh
		hbody.add_child(hcs)
	if BlockRegistry.shape_of(id) == "model":
		var mn := _model_node(id)
		if mn != null:
			# модель стоит в системе якоря при повороте 0; поворот footprint — как у BlockShapes._rot_point
			var rot := BlockRegistry.rot_of(m)
			var dims0 := Vector3(BlockRegistry.footprint(id, 0)) * B
			mn.transform = Transform3D(Basis(Vector3.UP, rot * PI * 0.5), base + BlockShapes._rot_point(Vector3.ZERO, dims0, rot))
			add_child(mn)
			entry["nodes"].append(mn)
	var cfg := BlockRegistry.light_cfg(id)
	if not cfg.is_empty():
		var lt := OmniLight3D.new()
		lt.light_color = Color.html(String(cfg.get("color", "#ffcc88")))
		lt.omni_range = float(cfg.get("range", 5.0))
		lt.light_energy = float(cfg.get("energy", 1.0))
		lt.shadow_enabled = false
		lt.distance_fade_enabled = true
		var lc := BlockRegistry.lights_cfg()
		lt.distance_fade_begin = float(lc.get("fade_begin", 16.0))
		lt.distance_fade_length = float(lc.get("fade_length", 6.0))
		var off: Array = cfg.get("offset", [0.25, 0.25, 0.25])
		var dims := Vector3(BlockRegistry.footprint(id, 0)) * B
		var lp := BlockShapes._rot_point(Vector3(off[0], off[1], off[2]), dims, BlockRegistry.rot_of(m))
		lt.position = base + lp
		lt.set_meta("base_energy", lt.light_energy)
		lt.set_meta("flicker", float(cfg.get("flicker", 0.0)))
		lt.set_meta("phase", float(key % 997))
		add_child(lt)
		entry["light"] = lt
		_register_light(lt)
	var slow := float(BlockRegistry.block(id).get("slow", 0.0))
	if slow > 0.0:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4
		area.position = base + (parts["size"] as Vector3) * 0.5
		var acs := CollisionShape3D.new()
		var ash := BoxShape3D.new()
		ash.size = parts["size"]
		acs.shape = ash
		area.add_child(acs)
		area.body_entered.connect(func(body: Node) -> void:
			if body.has_method("add_slow"):
				body.add_slow(slow))
		area.body_exited.connect(func(body: Node) -> void:
			if body.has_method("remove_slow"):
				body.remove_slow(slow))
		add_child(area)
		entry["nodes"].append(area)
	_custom[key] = entry


# --- зоны спящих зомби ----------------------------------------------------------------------
## Блоки-зоны (blocks.json, shape «marker»): «спавн спящего» — там появляется спящий зомби случайного типа,
## «триггер» — наступил игрок, и спящие этого цвета в этом здании просыпаются. Цвет — tier блока.
## В редакторе зоны видны полупрозрачными цветными коробками, в игре — невидимы и без столкновений.

## Цвет зоны (ключ tier: red, blue…) и её цвет для показа.
static func marker_color_key(id: int, meta: int) -> String:
	return String(BlockRegistry.tier_def(id, BlockRegistry.tier_of(meta)).get("key", ""))


static func marker_kind(id: int) -> String:
	return String(BlockRegistry.block(id).get("marker", ""))


func _sync_marker(a: Vector3i, id: int, m: int) -> Dictionary:
	var entry := {"nodes": [], "light": null}
	var base := origin + Vector3(a) * B
	var kind := marker_kind(id)
	var ck := marker_color_key(id, m)
	if edit_mode:
		var col := Color.html(String(BlockRegistry.tier_def(id, BlockRegistry.tier_of(m)).get("color", "#ffffff")))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := 0.8 if kind == "spawn" else 0.15
		bm.size = Vector3(0.8, h, 0.8) * B
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(col, 0.55 if kind == "spawn" else 0.75)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = base + Vector3(0.5, h * 0.5, 0.5) * B
		add_child(mi)
		entry["nodes"].append(mi)
		var lb := Label3D.new()
		lb.text = "Z" if kind == "spawn" else "T"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 64
		lb.pixel_size = 0.005
		lb.outline_size = 12
		lb.no_depth_test = true
		lb.position = base + Vector3(0.5, h + 0.25, 0.5) * B
		add_child(lb)
		entry["nodes"].append(lb)
	elif kind == "trigger":
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4          # игроки (свой и по сети)
		area.position = base + Vector3(0.5, 1.0, 0.5) * B
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.0, 2.0, 1.0) * B
		cs.shape = sh
		area.add_child(cs)
		area.body_entered.connect(func(body: Node) -> void:
			if body.is_in_group("survivors") and has_meta("bkey"):
				ZombieDirector.trigger(String(get_meta("bkey")), ck, body as Node3D))
		add_child(area)
		entry["nodes"].append(area)
	return entry


## Зоны вида kind ("spawn" | "trigger"): [{pos — мировая точка на полу ячейки, color, cell}].
func marker_spots(kind: String) -> Array:
	var out: Array = []
	for i in grid.cells.size():
		var id := int(grid.cells[i])
		if id < BlockRegistry.FIRST_ID or BlockRegistry.shape_of(id) != "marker" or marker_kind(id) != kind:
			continue
		var c := grid.cell_of(i)
		out.append({"pos": to_global(origin + (Vector3(c) + Vector3(0.5, 0.02, 0.5)) * B), "color": marker_color_key(id, grid.meta[i]), "cell": c})
	return out


static var _model_scenes := {}   # путь -> PackedScene (модели блоков грузятся один раз)


## Экземпляр 3D-модели блока (shape «model», путь в blocks.json «model») или null.
static func _model_node(id: int) -> Node3D:
	var path := String(BlockRegistry.block(id).get("model", ""))
	if path == "":
		return null
	if not _model_scenes.has(path):
		_model_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _model_scenes[path]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


## Узлы нестандартных блоков для проверки и тестов: якорь -> {nodes, light}.
func custom_entry(a: Vector3i) -> Dictionary:
	return _custom.get(grid.idx(a.x, a.y, a.z), {})


# --- взаимодействие ----------------------------------------------------------------------

## Открыть/закрыть дверь, которой принадлежит ячейка. Возвращает true, если дверь переключена.
func toggle_door(c: Vector3i) -> bool:
	var a := grid.anchor_of(c)
	var id := grid.get_cell(a.x, a.y, a.z)
	if id == 0 or not BlockRegistry.is_new(id) or BlockRegistry.shape_of(id) != "door":
		return false
	if not bool(BlockRegistry.block(id).get("openable", false)):
		return false
	var m := grid.get_meta_at(a.x, a.y, a.z)
	grid.set_cell(a.x, a.y, a.z, id, m ^ (1 << 10))
	refresh_cells(grid.footprint_cells(a, id, BlockRegistry.rot_of(m)))
	edited.emit()
	if has_meta("bkey"):
		Net.op("door", [String(get_meta("bkey")), a])
	return true


## Сетевая правка здания, которого у этого игрока сейчас нет на сцене (далеко): прямо в сетке, до постройки.
## op: ["bb_hit", ячейка, урон, инструмент] — как hit_cell (разрушенный блок убирается без проверки опор) |
## ["door", якорь] — переключить.
static func apply_to_grid(g: BlockGrid, op: Array) -> void:
	var c: Vector3i = op[1]
	var id := g.get_cell(c.x, c.y, c.z)
	if id == 0:
		return
	var a := g.anchor_of(c)
	id = g.get_cell(a.x, a.y, a.z)
	var m := g.get_meta_at(a.x, a.y, a.z)
	if String(op[0]) == "door":
		if BlockRegistry.is_new(id) and BlockRegistry.shape_of(id) == "door":
			g.set_cell(a.x, a.y, a.z, id, m ^ (1 << 10))
		return
	var max_hp := 0.0
	var mult := 1.0
	if BlockRegistry.is_new(id):
		var tier := BlockRegistry.tier_of(m)
		max_hp = BlockRegistry.hp(id, tier)
		mult = BlockRegistry.tool_mult(String(op[3]), id, tier)
	else:
		max_hp = float(BlockDefs.hp(id))
		mult = float(BlockDefs.AXE[id])
	var key := g.idx(a.x, a.y, a.z)
	var left: float = g.hp.get(key, max_hp) - float(op[2]) * mult
	if left > 0.0:
		g.hp[key] = left
	else:
		g.hp.erase(key)
		g.remove_block(a)


# --- свет: ограничение числа активных источников ----------------------------------------

func _register_light(lt: OmniLight3D) -> void:
	_lights.append(lt)
	if _light_node == null or not is_instance_valid(_light_node):
		var n := Node.new()
		n.name = "BlockLightBudget"
		n.set_script(load("res://scripts/blocks/block_light_budget.gd"))
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(n)
		_light_node = n


static func registered_lights() -> Array:
	return _lights
