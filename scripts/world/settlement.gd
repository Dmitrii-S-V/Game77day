class_name Settlement
extends Node3D
## Столбы, здания и мусор вокруг игрока. Колонки 16x16 м создаются при приближении.
## Сами дороги — часть ландшафта (см. RoadAtlas и шейдер terrain.gdshader).

const CHUNK := WorldGen.CHUNK

var terrain: Terrain
var roads: RoadNet
var radius := 5
var prop_material: StandardMaterial3D
var pole_wood: StandardMaterial3D
var pole_metal: StandardMaterial3D
var pole_rust: StandardMaterial3D
var block_material: ShaderMaterial
var glass_material: StandardMaterial3D

var _cols := {}        # Vector2i -> Node3D
var _center := Vector2i(1 << 30, 0)
var _pending: Array[Vector2i] = []
var _meshes := {}
var _bq: Array = []   # очередь зданий: {node, lot}
var _tmpl_jobs := {}
var _tmpl_done := {}
var _tmpl_mutex := Mutex.new()
var _pile_scene: PackedScene
static var prefab_count := 0


func _ready() -> void:
	prop_material = StandardMaterial3D.new()
	prop_material.vertex_color_use_as_albedo = true
	prop_material.vertex_color_is_srgb = true
	prop_material.roughness = 0.9
	pole_wood = _tex_material("wood_planks", 0.7, 0.9)
	pole_metal = _tex_material("metal_clean", 0.8, 0.55)
	pole_rust = _tex_material("metal_rust", 0.8, 0.75)
	block_material = ShaderMaterial.new()
	block_material.shader = load("res://shaders/block.gdshader")
	BlockRegistry.apply_to_material(block_material)
	glass_material = StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.55, 0.75, 0.85, 0.28)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.05
	glass_material.metallic_specular = 0.9
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Материал с трипланарной текстурой; цвет вершин затемняет/подкрашивает.
func _tex_material(tex_name: String, scale: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = TexCache.texture("res://assets/textures/%s.png" % tex_name, true, 1024)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	return m


func setup(t: Terrain) -> void:
	terrain = t
	roads = t.gen.world.roads
	shared = self
	PrefabRegistry.ensure()     # до потоков FarProps (keeps_lot из рабочего потока только читает)
	_live.clear()
	_deferred.clear()
	_warm_up()


## Прогрев кэшей при загрузке мира (вместо подвисаний при первом появлении): модели столбов и мусора, куча мусора (glb),
## сетки префабов.
func _warm_up() -> void:
	for kind in ["wood", "lamp", "lamp_rust", "broken", "fallen", "metal_rust"]:
		for v in 4:
			_pole(kind, v)
	for kind in ["tire", "barrel", "planks", "bag", "box", "cans"]:
		for v in 3:
			_litter(kind, v)
	_pile_scene = load("res://assets/ready/street_trash.glb") as PackedScene
	BlockBuilding.warm_up()
	for it: Dictionary in PrefabRegistry.all():
		PrefabRegistry.grid_of(it)


## Радиус построек (колонки) — не больше радиуса ближнего ландшафта (настройки графики).
func set_radius(r: int) -> void:
	if r == radius:
		return
	radius = r
	_center = Vector2i(1 << 30, 0)


func is_idle() -> bool:
	return _pending.is_empty() and _bq.is_empty()


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
				if dx * dx + dz * dz <= radius * radius and not _cols.has(key) and terrain.gen.in_map(key.x, key.y):
					_pending.append(key)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - c).length_squared() < (b - c).length_squared())
		for key: Vector2i in _cols.keys():
			if (key - c).length_squared() > (radius + 1) * (radius + 1):
				FrameBudget.free_later(_cols[key])
				_cols.erase(key)
	var spawned := 0
	var i := 0
	while i < _pending.size() and i < 10 and spawned < 1:
		var key := _pending[i]
		if terrain.is_column_done(key.x, key.y):
			_spawn_column(key)
			_pending.remove_at(i)
			spawned += 1
		else:
			i += 1
	var tries := _bq.size()
	while tries > 0 and not _bq.is_empty():
		tries -= 1
		var q: Dictionary = _bq.pop_front()
		if is_instance_valid(q["node"]) and not (q["node"] as Node).is_queued_for_deletion() and (q["node"] as Node3D).visible:
			if _spawn_building(q["node"], q["lot"]):
				break
			_bq.append(q)   # шаблон ещё генерируется — вернём в очередь


func _spawn_column(key: Vector2i) -> void:
	var node := Node3D.new()
	node.name = "Set_%d_%d" % [key.x, key.y]
	add_child(node)
	_cols[key] = node
	_spawn_props(key, node)


func _pole(kind: String, variant: int) -> Dictionary:
	var k := "%s_%d" % [kind, variant]
	if not _meshes.has(k):
		_meshes[k] = PoleGen.make(kind, 1000 + variant * 7919 + kind.hash() % 1000)
	return _meshes[k]


func _litter(kind: String, variant: int) -> Dictionary:
	var k := "L_%s_%d" % [kind, variant]
	if not _meshes.has(k):
		_meshes[k] = LitterGen.make(kind, 500 + variant * 313 + kind.hash() % 800)
	return _meshes[k]


## Мешок с разбросанным мусором (assets/ready/street_trash.glb).
func _spawn_pile(node: Node3D, pos: Vector3, yaw: float) -> void:
	if Breakables.is_broken(pos):
		return
	if _pile_scene == null:
		_pile_scene = load("res://assets/ready/street_trash.glb") as PackedScene
		if _pile_scene == null:
			return
	var inst := _pile_scene.instantiate() as Node3D
	inst.position = pos
	inst.rotation.y = yaw
	inst.set_meta("litter", true)
	inst.set_meta("loot", "trash_pile")   # E — обыскать (Loot)
	Breakables.mark(inst, "pile")
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 120.0
	# мешок на текстуре выцвел: затемняем до чёрного пластика
	var bag := inst.find_child("trash_bag*", true, false)
	if bag != null:
		for mi in bag.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).get_active_material(0)
			if m is StandardMaterial3D:
				var bm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				bm.albedo_color = Color(0.3, 0.3, 0.32)
				bm.roughness = 0.35
				(mi as MeshInstance3D).material_override = bm
	node.add_child(inst)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.28
	sh.height = 0.55
	cs.shape = sh
	cs.position = Vector3(0, 0.27, 0)
	body.add_child(cs)
	inst.add_child(body)


func _block_template(btype: String, w: float, d: float, variant: int) -> BlockGrid:
	var k := "%s_%d_%d_%d" % [btype, int(w), int(d), variant]
	if not _meshes.has(k):
		_meshes[k] = BlockGen.generate(btype, w, d, variant * 104729 + btype.hash() % 5000)
	return _meshes[k]


## Шаблон здания в рабочем потоке: true, когда готов (иначе запущена генерация, здание ждёт в очереди).
func _template_ready(btype: String, w: float, d: float, variant: int) -> bool:
	var k := "%s_%d_%d_%d" % [btype, int(w), int(d), variant]
	if _meshes.has(k):
		return true
	if not _tmpl_jobs.has(k):
		_tmpl_jobs[k] = true
		WorkerThreadPool.add_task(func() -> void:
			var g := BlockGen.generate(btype, w, d, variant * 104729 + btype.hash() % 5000)
			_tmpl_mutex.lock()
			_tmpl_done[k] = g
			_tmpl_mutex.unlock())
	_tmpl_mutex.lock()
	var g2: BlockGrid = _tmpl_done.get(k)
	_tmpl_mutex.unlock()
	if g2 != null:
		_meshes[k] = g2
		return true
	return false


func _add_boxes(inst: Node3D, boxes: Array) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[1]
		cs.shape = sh
		cs.position = b[0]
		body.add_child(cs)
	inst.add_child(body)


func _spawn_props(key: Vector2i, node: Node3D) -> void:
	var gen := terrain.gen
	for p: Dictionary in roads.poles_in_column(key.x, key.y):
		var pos: Vector2 = p["pos"]
		var y := terrain.surface_y(pos.x, pos.y, gen.height_at(pos.x, pos.y))
		if is_nan(y):
			continue
		var kind: String = p["kind"]
		if Breakables.is_broken(Vector3(pos.x, y, pos.y)):
			continue
		var data := _pole(kind, int(p["seed"]) % 4)
		var inst := Node3D.new()
		inst.position = Vector3(pos.x, y - 0.05 + (0.12 if p["across"] else 0.0), pos.y)
		inst.rotation.y = p["yaw"]
		inst.set_meta("pole", true)
		Breakables.mark(inst, "pole_metal" if kind in ["lamp", "lamp_rust", "metal_rust"] else "pole_wood")
		var mi := MeshInstance3D.new()
		mi.mesh = data["mesh"]
		match kind:
			"lamp":
				mi.material_override = pole_metal
			"lamp_rust", "metal_rust":
				mi.material_override = pole_rust
			_:
				mi.material_override = pole_wood
		mi.visibility_range_end = 200.0
		inst.add_child(mi)
		_add_boxes(inst, data["boxes"])
		node.add_child(inst)
	for lt: Dictionary in roads.litter_in_column(key.x, key.y):
		var lpos: Vector2 = lt["pos"]
		var ly := terrain.surface_y(lpos.x, lpos.y, gen.height_at(lpos.x, lpos.y))
		if is_nan(ly):
			continue
		var lkind: String = lt["kind"]
		if Breakables.is_broken(Vector3(lpos.x, ly, lpos.y)):
			continue
		if lkind == "pile":
			_spawn_pile(node, Vector3(lpos.x, ly - 0.02, lpos.y), float(lt["yaw"]))
			continue
		var ldata := _litter(lkind, int(lt["seed"]) % 3)
		var linst := Node3D.new()
		linst.position = Vector3(lpos.x, ly - 0.01, lpos.y)
		linst.rotation.y = lt["yaw"]
		if lkind == "tire" and float(lt["tilt"]) > 0.55:
			linst.rotation.x = 1.2 + float(lt["tilt"]) * 0.2   # покрышка стоит на ребре
		linst.set_meta("litter", true)
		if Breakables.DEFS.has(lkind):
			Breakables.mark(linst, lkind)
		if lkind == "bag":
			linst.set_meta("loot", "trash_bag")
		var lmi := MeshInstance3D.new()
		lmi.mesh = ldata["mesh"]
		match lkind:
			"barrel":
				lmi.material_override = pole_rust
			"planks":
				lmi.material_override = pole_wood
			_:
				lmi.material_override = prop_material
		lmi.visibility_range_end = 120.0
		linst.add_child(lmi)
		if not (ldata["boxes"] as Array).is_empty():
			_add_boxes(linst, ldata["boxes"])
		node.add_child(linst)
	# редкие кучи мусора вне дорог (поля, лес)
	var prng := RandomNumberGenerator.new()
	prng.seed = hash([key.x, key.y, 7331])
	if prng.randf() < 0.07:
		var px := key.x * 16.0 + prng.randf_range(1.0, 15.0)
		var pz := key.y * 16.0 + prng.randf_range(1.0, 15.0)
		var py := terrain.surface_y(px, pz, gen.height_at(px, pz))
		if not is_nan(py) and py > 0.5:
			_spawn_pile(node, Vector3(px, py - 0.02, pz), prng.randf() * TAU)
	for lot: Dictionary in roads.buildings_in_column(key.x, key.y):
		_bq.append({"node": node, "lot": lot})


## Здание участка: ставится из очереди по одному за кадр (генерация шаблона и меши дорогие — иначе подвисание).
func _spawn_building(node: Node3D, lot: Dictionary) -> bool:
	var c: Vector2 = lot["pos"]
	var bt: String = lot["btype"]
	var hx: float = lot["hx"]
	var hz: float = lot["hz"]
	var bw := maxf(4.0, roundf(2.0 * hx - 3.0))
	var bd := maxf(3.5, roundf(2.0 * hz - 3.0))
	if bt == "silo":
		bw = roundf(hx * 2.0)
		bd = bw
	elif bt == "gas_canopy":
		bw = roundf(2.0 * hx - 0.5)
		bd = roundf(2.0 * hz)
	# префабы из редактора структур: если подходит по размеру и победил по весу — ставим вместо кодового здания
	var key := building_key(c)
	var pf := PrefabRegistry.pick(bt, 2.0 * hx - 1.0, 2.0 * hz - 1.0, float(int(lot["seed"]) % 1000) / 1000.0)
	if not pf.is_empty():
		var pbb := BlockBuilding.new()
		# своя копия сетки (у префаба она общая: разрушение одного здания меняло все такие же)
		var pgrid: BlockGrid = edited_grids[key] if edited_grids.has(key) else PrefabRegistry.grid_of(pf["item"]).duplicate_grid()
		pbb.position = Vector3(c.x, float(lot["plateau"]) + 0.06 - pgrid.sink * BlockGrid.B, c.y)
		pbb.rotation.y = -float(lot["rot"]) + (PI * 0.5 if pf["rotated"] else 0.0)
		node.add_child(pbb)
		_flush_deferred(key, pgrid)
		pbb.setup(pgrid, block_material, glass_material)
		_track(pbb, key)
		prefab_count += 1
		return true
	if bt == "park":
		# парк без префаба (категория «park» в редакторе): сквер кодом — дорожки, деревья, скамейки, трава
		var park := BlockBuilding.new()
		var pg := _park_grid(roundi(2.0 * hx - 1.0), roundi(2.0 * hz - 1.0), int(lot["seed"]))
		park.position = Vector3(c.x, float(lot["plateau"]) + 0.06 - pg.sink * BlockGrid.B, c.y)
		park.rotation.y = -float(lot["rot"])
		node.add_child(park)
		park.setup(pg, block_material, glass_material)
		return true
	if not bool(lot.get("poi", false)):
		return true      # кодовые дома — только в POI; в городах — лишь свои префабы (участок без префаба пустой)
	if not _template_ready(bt, bw, bd, int(lot["seed"]) % 4):
		return false
	var tmpl := _block_template(bt, bw, bd, int(lot["seed"]) % 4)
	var bb := BlockBuilding.new()
	bb.position = Vector3(c.x, float(lot["plateau"]) + 0.06, c.y)
	bb.rotation.y = -float(lot["rot"])
	node.add_child(bb)
	var bgrid: BlockGrid = edited_grids[key] if edited_grids.has(key) else tmpl.duplicate_grid()
	_flush_deferred(key, bgrid)
	bb.setup(bgrid, block_material, glass_material)
	_track(bb, key)
	return true


## Сквер w x d м: гравийные дорожки крестом (или одна вдоль), трава, деревья по углам, скамейки у дорожек
## (оттенки от синего до зелёного), кусты. Та же сетка, что у префаба: территорию раскладывает BlockBuilding.
func _park_grid(w: int, d: int, seed_v: int) -> BlockGrid:
	w = maxi(w, 6)
	d = maxi(d, 6)
	var g := BlockGrid.new(w, 2, d)
	g.ground_cells = 1
	g.sink = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var cx := w / 2
	var cz := d / 2
	var cross := rng.randf() < 0.6
	var path := "gravel" if rng.randf() < 0.7 else "concrete"
	for z in d:
		for x in w:
			var on_path := absi(z - cz) <= 0 or (cross and absi(x - cx) <= 0)
			g.ground[Vector2i(x, z)] = path if on_path else "grass"
	# скамейки вдоль дорожки (лицом к ней), 2-4 шт.
	var nb := rng.randi_range(2, 4)
	for i in nb:
		var along := rng.randf_range(1.5, float(w) - 1.5)
		var side := -1.0 if i % 2 == 0 else 1.0
		g.plants.append({"type": "bench", "x": along, "z": cz + 0.5 + side * 1.1, "rot": 0.0 if side > 0 else PI, "scale": 1.0,
			"hue": rng.randf_range(0.33, 0.6)})
	# деревья по углам и кусты
	var trees := ["oak_0", "oak_1", "oak_2", "oak_dry_0", "pine_1"]
	for corner: Vector2 in [Vector2(1.5, 1.5), Vector2(w - 1.5, 1.5), Vector2(1.5, d - 1.5), Vector2(w - 1.5, d - 1.5)]:
		if rng.randf() < 0.8:
			g.plants.append({"type": trees[rng.randi() % trees.size()], "x": corner.x + rng.randf_range(-0.4, 0.4),
				"z": corner.y + rng.randf_range(-0.4, 0.4), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.8, 1.1), "hue": 0.0})
	for i in rng.randi_range(1, 3):
		var bx := rng.randf_range(1.0, w - 1.0)
		var bz := rng.randf_range(1.0, d - 1.0)
		if absf(bz - cz - 0.5) > 1.5 and (not cross or absf(bx - cx - 0.5) > 1.5):
			g.plants.append({"type": "bush_%d" % (rng.randi() % 3), "x": bx, "z": bz, "rot": rng.randf() * TAU, "scale": 0.9, "hue": 0.0})
	return g


## Изменённые игроком здания (разрушены блоки, открыты двери): сетка запоминается и при повторном появлении
## здания (и после загрузки сохранения) используется вместо исходной.
var edited_grids := {}   # ключ участка -> BlockGrid


## Стоит ли на участке здание: свой префаб из редактора (подходит по размеру), сквер или кодовое здание POI.
## Так же решают дальние модели (FarProps) и спящие зомби — без «фантомных» домов на пустых участках.
static func keeps_lot(l: Dictionary) -> bool:
	var bt := String(l["btype"])
	if bt == "":
		return false
	if bt == "park" or bool(l.get("poi", false)):
		return true
	return not PrefabRegistry.pick(bt, 2.0 * float(l["hx"]) - 1.0, 2.0 * float(l["hz"]) - 1.0,
		float(int(l["seed"]) % 1000) / 1000.0).is_empty()


static func building_key(c: Vector2) -> String:
	return "%d_%d" % [roundi(c.x * 4.0), roundi(c.y * 4.0)]


func _track(bb: BlockBuilding, key: String) -> void:
	var mark := func(_a: Variant = null) -> void: edited_grids[key] = bb.grid
	bb.block_changed.connect(mark)
	bb.edited.connect(mark)
	bb.set_meta("bkey", key)     # сетевые правки находят здание по ключу
	_live[key] = bb


## Сеть: здания на сцене по ключу участка и правки зданий, которых у этого игрока сейчас нет (применятся к сетке
## при появлении здания).
static var _live := {}
static var _deferred := {}      # ключ -> [[вид, ячейка, ...], ...]
static var shared: Settlement


static func live_building(key: String) -> BlockBuilding:
	var bb: Variant = _live.get(key)
	if bb != null and is_instance_valid(bb) and (bb as Node).is_inside_tree():
		return bb
	_live.erase(key)
	return null


## args — как у Net.op ("bb_hit": [ключ, ячейка, урон, инструмент], "door": [ключ, якорь]).
static func defer_op(key: String, args: Array) -> void:
	var kind := "bb_hit" if args.size() >= 4 else "door"
	if not _deferred.has(key):
		_deferred[key] = []
	(_deferred[key] as Array).append([kind] + args.slice(1))
	# здание уже было изменено (сетка в памяти) — применить сразу
	if shared != null and is_instance_valid(shared) and shared.edited_grids.has(key):
		_flush_deferred(key, shared.edited_grids[key])


static func _flush_deferred(key: String, g: BlockGrid) -> void:
	if not _deferred.has(key):
		return
	for op: Array in _deferred[key]:
		BlockBuilding.apply_to_grid(g, op)
	_deferred.erase(key)
	if shared != null and is_instance_valid(shared):
		shared.edited_grids[key] = g


## Ландшафт изменён: убираем столбы, у которых пропала земля.
func on_edited(center: Vector3, edit_radius: float) -> void:
	var reach := edit_radius + 6.0
	var lo := Vector2i(floori((center.x - reach) / CHUNK), floori((center.z - reach) / CHUNK))
	var hi := Vector2i(floori((center.x + reach) / CHUNK), floori((center.z + reach) / CHUNK))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cz)
			if _cols.has(key):
				for inst in (_cols[key] as Node3D).get_children():
					if inst.has_meta("pole") and not inst.is_queued_for_deletion():
						var p := (inst as Node3D).position
						var y := terrain.surface_y(p.x, p.z, p.y)
						if is_nan(y) or absf(y - p.y) > 0.6:
							inst.queue_free()
