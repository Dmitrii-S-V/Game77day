extends SceneTree
## Автотест блоков построек (этапы 1, 2, 5): таблица прочности, коллизии мягких блоков, двери, окна,
## крепления (свеча), свет, инструменты улучшения/текстуры, загрузка префаба.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_blocks.gd

var fails := 0
var main: Node3D


func check(name_: String, cond: bool, info: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name_ + ((" -- " + info) if info != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _phys(n: int) -> void:
	for i in n:
		await physics_frame


func _cell_center(bb: BlockBuilding, c: Vector3i) -> Vector3:
	return bb.to_global(bb.origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * BlockGrid.B)


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	return root.get_world_3d().direct_space_state.intersect_ray(q)


func _capsule_hits(pos: Vector3, mask: int) -> int:
	var sh := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.9, 0))
	q.collision_mask = mask
	return root.get_world_3d().direct_space_state.intersect_shape(q, 8).size()


func _run() -> void:
	await process_frame
	BlockRegistry.ensure()
	# --- таблица прочности (этап 1) ---
	var expect := {
		"frame": 20, "planks_fresh": 150, "planks_worn": 100, "planks_rotten": 60, "planks_dying": 30,
		"concrete_smooth": 800, "concrete_cracked": 500, "concrete_reinforced": 1200, "concrete_dirty": 600,
		"door_wood": 200, "door_boarded": 300, "window_ok": 40, "window_broken": 15, "window_boarded": 120,
		"web": 5, "chandelier": 25, "candle": 5, "carpet": 30,
	}
	var bad := []
	for k: String in expect:
		if int(BlockRegistry.material_by_key(k).get("hp", -1)) != int(expect[k]):
			bad.append(k)
	check("таблица hp в данных совпадает с заданием (%d материалов)" % expect.size(), bad.is_empty(), str(bad))
	# и то же через блоки/tier'ы
	var wall := BlockRegistry.id_by_key("wall")
	var tier_hp := [20, 150, 100, 60, 30, 800, 500, 1200, 600]
	var ok_t := true
	for t in tier_hp.size():
		if int(BlockRegistry.hp(wall, t)) != tier_hp[t]:
			ok_t = false
	check("hp по tier'ам блока wall", ok_t)
	check("hp дверей/окон/декора через блоки", int(BlockRegistry.hp(BlockRegistry.id_by_key("door_boarded"))) == 300 and int(BlockRegistry.hp(BlockRegistry.id_by_key("window_broken"))) == 15 and int(BlockRegistry.hp(BlockRegistry.id_by_key("candle"))) == 5)
	check("множители инструментов есть для всех типов", BlockRegistry.tool_mult("axe", wall, 1) == 1.0 and BlockRegistry.tool_mult("pickaxe", wall, 5) > BlockRegistry.tool_mult("axe", wall, 5))
	check("текстурный массив: слоёв >= 39", BlockRegistry.texture_array().get_layers() >= 39, str(BlockRegistry.texture_array().get_layers()))

	# --- загрузка префаба через реестр (этап 4/5) ---
	PrefabRegistry.reload()
	var item := PrefabRegistry.find("test_house")
	check("префаб test_house найден в реестре", not item.is_empty())
	var g := PrefabRegistry.grid_of(item)
	var ref := TestHouse.build()
	var diff := 0
	for z in ref.nz:
		for y in ref.ny:
			for x in ref.nx:
				if g.get_cell(x, y, z) != ref.get_cell(x, y, z) or g.get_meta_at(x, y, z) != ref.get_meta_at(x, y, z):
					diff += 1
	check("префаб из JSON совпадает со сборкой кода (ячейки)", diff == 0, "различий %d" % diff)
	var picked := PrefabRegistry.pick("house", 20.0, 20.0, 0.0)
	check("pick(house) возвращает test_house при rnd=0", not picked.is_empty() and String(picked["item"]["data"]["name"]) == "test_house")
	check("pick не берёт префаб для слишком маленького участка", PrefabRegistry.pick("house", 3.0, 3.0, 0.0).is_empty())

	# --- сцена ---
	main = Node3D.new()
	root.add_child(main)
	current_scene = main
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.make_current()
	var bb := BlockBuilding.new()
	main.add_child(bb)
	bb.setup(g, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	for i in 300:
		await process_frame
		if bb.is_ready():
			break
	await _phys(4)
	check("здание построено (меши куски готовы)", bb.is_ready())

	# ковёр (3,2,5): проходим, но выбирается
	var carpet_c := Vector3i(3, 2, 5)
	var cc := _cell_center(bb, carpet_c)
	var floor_y := bb.to_global(bb.origin + Vector3(0, 2 * BlockGrid.B, 0)).y
	check("ковёр: игрок (капсула) проходит", _capsule_hits(Vector3(cc.x, floor_y + 0.03, cc.z), 3) == 0)
	var r := _ray(Vector3(cc.x, cc.y + 1.5, cc.z), Vector3(cc.x, cc.y - 0.5, cc.z), 8)
	check("ковёр: луч удара/выделения (слой 8) попадает", not r.is_empty() and r["collider"].has_meta("anchor"))
	if not r.is_empty():
		var broke := bb.hit(r["position"], r["normal"], 16.0, "axe", r["collider"])
		check("ковёр ломается ударом (hp 30, ткань x3)", broke and g.get_cell(3, 2, 5) == 0)

	# паутина (1,7,1)
	var web_c := Vector3i(1, 4, 1)
	var wc := _cell_center(bb, web_c)
	var ent := bb.custom_entry(web_c)
	var has_area := false
	for n: Node in ent.get("nodes", []):
		if n is Area3D:
			has_area = true
	check("паутина: есть зона замедления (Area3D)", has_area)
	var wr := _ray(Vector3(wc.x + 0.6, wc.y, wc.z), Vector3(wc.x - 0.1, wc.y, wc.z), 8)
	check("паутина: выбирается слоем 8", not wr.is_empty())
	if not wr.is_empty():
		bb.hit(wr["position"], wr["normal"], 16.0, "axe", wr["collider"])
		check("паутина ломается с одного удара (hp 5)", g.get_cell(1, 4, 1) == 0)

	# заколоченная дверь (3,2,0)
	var bd := Vector3i(2, 2, 0)
	check("заколоченная дверь не открывается", not bb.toggle_door(bd))
	var bdc := _cell_center(bb, bd)
	check("заколоченная дверь твёрдая", _ray(Vector3(bdc.x, bdc.y + 0.5, bdc.z - 1.0), Vector3(bdc.x, bdc.y + 0.5, bdc.z + 1.0), 2).size() > 0)
	# рабочая дверь (6,2,13)
	var wd := Vector3i(4, 2, 9)
	var wdc := _cell_center(bb, wd)
	var pass_pos := Vector3(wdc.x, bb.to_global(bb.origin + Vector3(0, 2 * BlockGrid.B, 0)).y + 0.03, wdc.z)
	check("рабочая дверь закрыта: капсула блокируется", _capsule_hits(pass_pos, 3) > 0)
	check("рабочая дверь открывается", bb.toggle_door(wd))
	await _phys(3)
	check("рабочая дверь открыта: проход свободен", _capsule_hits(pass_pos, 3) == 0)
	check("дверь закрывается обратно", bb.toggle_door(wd))

	# окна
	var wi := _cell_center(bb, Vector3i(2, 3, 9))
	var wb := _cell_center(bb, Vector3i(8, 3, 9))
	check("целое окно: стекло твёрдое", _ray(Vector3(wi.x + 0.25, wi.y + 0.25, wi.z + 1.0), Vector3(wi.x + 0.25, wi.y + 0.25, wi.z - 1.0), 2).size() > 0 or _ray(Vector3(wi.x - 0.25, wi.y - 0.25, wi.z + 1.0), Vector3(wi.x - 0.25, wi.y - 0.25, wi.z - 1.0), 2).size() > 0)
	var open_hits := 0
	for off in [Vector2(-0.25, -0.25), Vector2(0.25, 0.25), Vector2(0.0, 0.0), Vector2(0.25, -0.25)]:
		open_hits += _ray(Vector3(wb.x + off.x, wb.y + off.y, wb.z + 1.5), Vector3(wb.x + off.x, wb.y + off.y, wb.z - 1.5), 2).size()
	check("разбитое окно: стекла нет, лучи через проём свободны", open_hits == 0, str(open_hits))

	# hp по факту ударов: свежие доски (tier 1) hp 150, топор x1, удар 16 -> 10 ударов
	var plank_c := Vector3i(5, 3, 9)   # стена фасада, свежие доски
	var pw := _cell_center(bb, plank_c)
	check("ячейка фасада — свежие доски", g.get_cell(5, 3, 9) == wall and BlockRegistry.tier_of(g.get_meta_at(5, 3, 9)) == 1)
	var hits := 0
	while g.get_cell(5, 3, 9) != 0 and hits < 40:
		bb.hit(pw + Vector3(0, 0, 0.3), Vector3(0, 0, 1), 16.0, "axe")
		hits += 1
	check("свежие доски (hp 150) ломаются за 10 ударов по 16", hits == 10, str(hits))

	# свеча: опора — стол; убираем опору -> свеча падает
	var candle_c := Vector3i(8, 3, 3)
	check("свеча стоит на столе", g.get_cell(8, 3, 3) == BlockRegistry.id_by_key("candle"))
	var light_ent := bb.custom_entry(candle_c)
	check("свеча: есть свет без теней, с затуханием по дальности", light_ent.get("light") != null and not (light_ent["light"] as OmniLight3D).shadow_enabled and (light_ent["light"] as OmniLight3D).distance_fade_enabled)
	bb.break_block(Vector3i(8, 2, 3), true)
	await _frames(2)
	var fell := false
	for n in main.get_children():
		if n is RigidBody3D and n.has_meta("falling_block"):
			fell = true
	check("свеча падает без опоры (ячейка очищена, упал объект)", g.get_cell(8, 3, 3) == 0 and fell)
	check("свет свечи удалён вместе с блоком", bb.custom_entry(candle_c).is_empty())

	# люстра: опора сверху
	var ch := Vector3i(3, 4, 5)
	check("люстра висит под потолком и светит", g.get_cell(3, 4, 5) == BlockRegistry.id_by_key("chandelier") and bb.custom_entry(ch).get("light") != null)
	bb.break_block(Vector3i(3, 5, 5), true)
	check("люстра отваливается без опоры сверху", g.get_cell(3, 4, 5) == 0)

	# инструменты этап 2
	var fr := Vector3i(11, 3, 3)   # каркас в правой стене
	check("каркас: tier 0, hp 20", BlockRegistry.tier_of(g.get_meta_at(11, 3, 3)) == 0 and BlockOps.inspect(g, fr)["hp_max"] == 20.0)
	var _unused := 0
	check("улучшить: каркас -> доски свежие", BlockOps.upgrade(bb, fr, 1) and BlockRegistry.tier_of(g.get_meta_at(11, 3, 3)) == 1)
	check("улучшить: hp стал 150", BlockOps.inspect(g, fr)["hp_max"] == 150.0 and BlockOps.inspect(g, fr)["hp"] == 150.0)
	g.hp[g.idx(11, 3, 3)] = 77.0
	var v0 := BlockRegistry.variant_of(g.get_meta_at(11, 3, 3))
	check("текстура: вариант меняется", BlockOps.cycle_variant(bb, fr, 1) and BlockRegistry.variant_of(g.get_meta_at(11, 3, 3)) != v0)
	check("текстура: материал и hp не меняются", BlockOps.inspect(g, fr)["material"] == "planks_fresh" and BlockOps.inspect(g, fr)["hp"] == 77.0)
	check("в игре нельзя «понизить» материал", not BlockOps.upgrade(bb, fr, 0, false))

	# свет: лимит активных источников
	var bb2 := BlockBuilding.new()
	main.add_child(bb2)
	var g2 := BlockGrid.new(40, 8, 8)
	TestHouse.wall(g2, 0, 0, 0, 40, 1, 8, 5)
	for i in 14:
		TestHouse.put(g2, "candle", Vector3i(2 + i * 2, 1, 3))
	bb2.setup(g2, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	await _frames(60)
	await create_timer(1.0).timeout
	var vis := 0
	var total := 0
	for l in BlockBuilding.registered_lights():
		if is_instance_valid(l):
			total += 1
			if (l as Light3D).visible:
				vis += 1
	check("свет: источников %d, активных не больше 8" % total, total >= 14 and vis <= 8, "активно %d" % vis)

	# --- формы: колонны, клин, кол, скругления; декали; износ
	var gs := BlockGrid.new(12, 6, 6)
	gs.ground_cells = 1
	TestHouse.wall(gs, 0, 0, 0, 12, 1, 6, 5)
	var shape_keys := ["pillar_thick", "pillar_thin", "round_1", "round_4", "wedge", "wedge_low", "stake"]
	for si in shape_keys.size():
		TestHouse.put(gs, shape_keys[si], Vector3i(1 + si, 1, 2))
	var bbs := BlockBuilding.new()
	main.add_child(bbs)
	bbs.position = Vector3(120, 0, 0)
	bbs.setup(gs, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	for i in 200:
		await process_frame
		if bbs.is_ready():
			break
	await _phys(4)
	var solid_ok := true
	for si in shape_keys.size():
		var cs := _cell_center(bbs, Vector3i(1 + si, 1, 2))
		var hit_s := _ray(Vector3(cs.x, cs.y + 2.0, cs.z), Vector3(cs.x, cs.y - 2.0, cs.z), 2)
		if hit_s.is_empty():
			solid_ok = false
	check("формы (7 шт.) имеют твёрдую коллизию", solid_ok)
	var wcn := _cell_center(bbs, Vector3i(5, 1, 2))
	var wr2 := _ray(Vector3(wcn.x, wcn.y + 3.0, wcn.z + 0.45), Vector3(wcn.x, wcn.y - 3.0, wcn.z + 0.45), 2)
	var wt := _ray(Vector3(wcn.x, wcn.y + 3.0, wcn.z - 0.45), Vector3(wcn.x, wcn.y - 3.0, wcn.z - 0.45), 2)
	check("клин: у высокой стороны выше, чем у низкой", not wr2.is_empty() and not wt.is_empty() and wr2["position"].y > wt["position"].y + 0.5, "hi %s lo %s" % [str(wr2.get("position")), str(wt.get("position"))])
	check("формы ломаются по hp материала (колонна: 150)", BlockRegistry.hp(BlockRegistry.id_by_key("pillar_thick"), 0) == 150.0)
	check("декали: таблица загружена (%d слоёв стен)" % BlockDecals.count(), BlockDecals.count() > 60)
	var gw := TestHouse.build()
	var wn := BlockWeather.apply(gw, 99, 0.3)
	check("износ ставит декали (%d шт.)" % wn, wn > 10 and not gw.decals.is_empty())
	var any_cell := -1
	for kd in gw.decals.keys():
		any_cell = int(kd) / 8
		break
	var cc2 := gw.cell_of(any_cell)
	gw.set_cell(cc2.x, cc2.y, cc2.z, 0, 0)
	var left := false
	for f in 6:
		if gw.decals.has(any_cell * 8 + f):
			left = true
	check("декали пропадают вместе с блоком", not left)

	print("RESULT fails=", fails)
	quit(fails)
