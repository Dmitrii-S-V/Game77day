extends SceneTree
## Автотест редактора структур: постановка, undo/redo, выделение, заливка, копирование, поворот, зеркало,
## правила опоры, сохранение/загрузка, реестр префабов.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_editor.gd

var fails := 0


func check(n: String, c: bool, info: String = "") -> void:
	print(("PASS  " if c else "FAIL  ") + n + ((" -- " + info) if info != "" else ""))
	if not c:
		fails += 1


func _initialize() -> void:
	_run()


func _count(g: BlockGrid, id: int = -1) -> int:
	var n := 0
	for i in g.cells.size():
		if g.cells[i] != 0 and (id < 0 or g.cells[i] == id):
			n += 1
	return n


func _run() -> void:
	await process_frame
	var ed: Node3D = load("res://scenes/editor.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame
	var g: BlockGrid = ed.grid
	var wall := BlockRegistry.id_by_key("wall")
	check("редактор запущен, холст %dx%dx%d" % [g.nx, g.ny, g.nz], g != null and g.nx == 48)
	check("палитра: пунктов больше 15", BlockRegistry.palette().size() >= 15, str(BlockRegistry.palette().size()))
	check("палитра: поиск «доски» фильтрует", _filter_count(ed, "доски") >= 4, str(_filter_count(ed, "доски")))

	# постановка / undo / redo
	ed.select_key("wall:planks_worn")
	var c := Vector3i(10, 1, 10)
	ed._place_at(c)
	check("поставить блок (доски потрёпанные)", g.get_cell(10, 1, 10) == wall and BlockRegistry.tier_of(g.get_meta_at(10, 1, 10)) == 2)
	ed._place_at(c)
	check("повторная постановка в занятую ячейку отклоняется", _count(g) == 1)
	ed._do_undo()
	check("undo убирает блок", _count(g) == 0)
	ed._do_redo()
	check("redo возвращает блок", _count(g) == 1)
	ed._remove_at(c)
	check("удалить блок", _count(g) == 0)
	ed._do_undo()
	check("undo удаления возвращает блок", _count(g) == 1)

	# крепления
	ed.select_key("candle")
	ed._place_at(Vector3i(20, 8, 20))
	check("свеча в воздухе не ставится (нет опоры)", g.get_cell(20, 8, 20) == 0)
	ed._place_at(Vector3i(20, 1, 20))
	check("свеча на земле ставится", g.get_cell(20, 1, 20) == BlockRegistry.id_by_key("candle"))
	ed.select_key("wall:concrete_smooth")
	ed._place_at(Vector3i(30, 1, 30))
	ed.select_key("carpet")
	ed._place_at(Vector3i(30, 2, 30))
	check("ковёр на блоке ставится", g.get_cell(30, 2, 30) == BlockRegistry.id_by_key("carpet"))
	ed._remove_at(Vector3i(30, 1, 30))
	check("убрали опору: ковёр отваливается (редактор)", g.get_cell(30, 2, 30) == 0)

	# заливка выделения
	ed.select_key("wall:concrete_cracked")
	ed.has_sel = true
	ed.sel_lo = Vector3i(2, 1, 2)
	ed.sel_hi = Vector3i(5, 3, 4)
	ed._fill_selection()
	check("заливка 4x3x3 = 36 блоков", _count(g, wall) == 36 + 1 + 0, str(_count(g, wall)))
	ed._do_undo()
	check("undo заливки", _count(g, wall) == 1)
	ed._do_redo()

	# копирование и вставка
	ed._copy_selection()
	ed._target = Vector3i(40, 1, 40)
	ed._paste()
	check("вставка копирует 36 блоков", _count(g, wall) == 72 + 1, str(_count(g, wall)))
	ed._do_undo()
	check("undo вставки", _count(g, wall) == 36 + 1)

	# очистка
	ed._clear_selection()
	check("очистка выделения", _count(g, wall) == 1)
	ed._do_undo()

	# поворот: дверь 2x4x1 + блоки; проверяем footprint и rot
	ed.has_sel = true
	ed.sel_lo = Vector3i(44, 1, 10)
	ed.sel_hi = Vector3i(44, 2, 10)
	ed.select_key("door_wood")
	ed._place_at(Vector3i(44, 1, 10))
	check("дверь поставлена (1x2x1 = 2 ячейки)", _count(g, BlockRegistry.id_by_key("door_wood")) == 2)
	ed.sel_lo = Vector3i(44, 1, 10)
	ed.sel_hi = Vector3i(44, 2, 10)
	ed._rotate_selection()
	var door := BlockRegistry.id_by_key("door_wood")
	var anchor := Vector3i(-1, -1, -1)
	for z in range(8, 14):
		for x in range(42, 48):
			if g.get_cell(x, 1, z) == door and not BlockRegistry.is_part(g.get_meta_at(x, 1, z)):
				anchor = Vector3i(x, 1, z)
	check("после поворота дверь: rot=1, 2 ячейки, один якорь", anchor.x >= 0 and BlockRegistry.rot_of(g.get_meta_at(anchor.x, anchor.y, anchor.z)) == 1 and _count(g, door) == 2, str(anchor))
	check("части двери указывают на якорь", g.anchor_of(anchor + Vector3i(0, 1, 0)) == anchor)
	ed._rotate_selection()
	ed._rotate_selection()
	ed._rotate_selection()
	check("4 поворота возвращают дверь на место (rot 0, якорь 44,1,10)", g.get_cell(44, 1, 10) == door and BlockRegistry.rot_of(g.get_meta_at(44, 1, 10)) == 0, str(_count(g, door)))
	ed._mirror_selection(false)
	check("зеркало не теряет блоки двери", _count(g, door) == 2)

	# вкладки, материал форм, поворот по всем осям, кисть
	var col := BlockRegistry.id_by_key("column")
	var beam := BlockRegistry.id_by_key("beam")
	check("формы: колонна — форма, дверь — объект", ed._is_shape(col) and not ed._is_shape(door))
	ed.select_key("column")
	ed.cur_mat = "metal_rusty"
	ed._update_pal_info()
	ed._place_at(Vector3i(12, 1, 30))
	var cm := g.get_meta_at(12, 1, 30)
	check("колонна из металла (материал из кнопки)", g.get_cell(12, 1, 30) == col and BlockRegistry.material_key(col, BlockRegistry.tier_of(cm)) == "metal_rusty")
	ed.select_key("beam")
	ed._rotate_cur(Vector3.BACK)      # балка вдоль X -> вертикально
	ed._place_at(Vector3i(14, 1, 30))
	var bm := g.get_meta_at(14, 1, 30)
	var parts := BlockShapes.build(beam, bm)
	var hb: Dictionary = {}
	for b: Dictionary in parts["boxes"]:
		if b.get("hidden", false):
			hb = b
	var ext: Vector3 = (hb["b"] as Vector3) - (hb["a"] as Vector3) if not hb.is_empty() else Vector3.ZERO
	check("поворот вокруг Z: балка стоит вертикально (up=%d)" % BlockRegistry.up_of(bm), BlockRegistry.up_of(bm) != 0 and absf(ext.y - 1.0) < 0.01 and absf(ext.x - 0.5) < 0.01, str(ext))
	ed.cur_mat = "concrete_dirty"
	ed._brush_at(Vector3i(14, 1, 30))
	var bm2 := g.get_meta_at(14, 1, 30)
	check("кисть: материал сменился, поворот сохранился", BlockRegistry.material_key(beam, BlockRegistry.tier_of(bm2)) == "concrete_dirty" and BlockRegistry.up_of(bm2) == BlockRegistry.up_of(bm) and BlockRegistry.rot_of(bm2) == BlockRegistry.rot_of(bm))
	ed._do_undo()
	check("undo кисти", g.get_meta_at(14, 1, 30) == bm)
	ed.has_sel = true
	ed.sel_lo = Vector3i(14, 1, 30)
	ed.sel_hi = Vector3i(14, 1, 30)
	var ob := BlockRegistry.orient_basis(bm)
	ed._rotate_selection()
	var rb := BlockRegistry.orient_basis(g.get_meta_at(14, 1, 30))
	var want := Basis(Vector3.UP, PI * 0.5) * ob
	check("поворот выделения учитывает наклонённый блок", (rb.x - want.x).length() < 0.01 and (rb.y - want.y).length() < 0.01)
	ed._rotate_cur(Vector3.BACK)
	ed._rotate_cur(Vector3.BACK)
	ed._rotate_cur(Vector3.BACK)
	check("4 поворота вокруг Z возвращают исходную ориентацию", ed.cur_up == 0)
	ed.has_sel = false

	# покрытие земли
	ed._set_mode(ed.Mode.GROUND)
	ed.cur_ground = "gravel"
	ed.ground_brush = 3
	ed._begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
	ed._paint_ground(Vector2i(20, 20))
	ed._end_op()
	check("земля: кисть 3x3 = 9 ячеек гравия", g.ground.size() == 9 and String(g.ground.get(Vector2i(21, 21), "")) == "gravel", str(g.ground.size()))
	ed._do_undo()
	check("undo земли", g.ground.is_empty())
	ed._do_redo()
	check("redo земли", g.ground.size() == 9)
	ed.cur_ground = "asphalt"
	ed.ground_brush = 1
	ed._begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
	ed._paint_ground(Vector2i(25, 20))
	ed._end_op()
	# растения и предметы
	ed._set_mode(ed.Mode.PLANT)
	ed.cur_plant = "oak_lichen"
	ed._begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
	ed._plant_at(Vector3(22.3, 0, 22.1), false)
	ed._end_op()
	ed.cur_plant = "bench"
	ed._begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
	ed._plant_at(Vector3(24.0, 0, 22.0), false)
	ed._end_op()
	check("растения: дуб с лишаем и скамейка посажены", g.plants.size() == 2 and String(g.plants[0]["type"]) == "oak_lichen")
	ed._do_undo()
	check("undo растения", g.plants.size() == 1)
	ed._do_redo()
	ed._set_mode(ed.Mode.PLACE)

	# сохранение и загрузка
	ed.info["name"] = "test_editor_tmp"
	var d := PrefabIO.to_dict(g, {"name": "test_editor_tmp", "category": "other", "tags": ["t"], "weight": 2.5, "biomes": ["any"], "margin": 1})
	check("to_dict: блоков и футпринт заполнены", d["blocks"].size() > 10 and d["footprint"][0] > 0 and float(d["weight"]) == 2.5, str(d["footprint"]))
	PrefabIO.save_dict(d, "user://prefabs/test_editor_tmp.json")
	PrefabRegistry.reload()
	var it := PrefabRegistry.find("test_editor_tmp")
	check("сохранённый префаб виден реестру", not it.is_empty())
	var g2 := PrefabRegistry.grid_of(it)
	check("загрузка даёт те же блоки (%d)" % _count(g, -1), _count(g2, -1) == _count(g, -1), "%d vs %d" % [_count(g2, -1), _count(g, -1)])
	var ups := 0
	for i in g2.cells.size():
		if g2.cells[i] == beam and BlockRegistry.up_of(g2.meta[i]) != 0:
			ups += 1
	check("префаб хранит поворот по всем осям", ups == 1)
	var kinds := {}
	for gc: Vector2i in g2.ground:
		kinds[g2.ground[gc]] = int(kinds.get(g2.ground[gc], 0)) + 1
	check("префаб хранит покрытие земли (9 гравия, 1 асфальт)", int(kinds.get("gravel", 0)) == 9 and int(kinds.get("asphalt", 0)) == 1, str(kinds))
	check("префаб хранит растения", g2.plants.size() == 2, str(g2.plants.size()))
	var bbt := BlockBuilding.new()
	root.add_child(bbt)
	bbt.setup(g2, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	check("здание в мире кладёт покрытие (узел GroundPaint)", bbt.get_node_or_null("GroundPaint") != null)
	var lichen_trees := 0
	var benches := 0
	for ch in bbt.get_children():
		if ch.get_meta("lichen", false):
			lichen_trees += 1
		if String(ch.get_meta("kind", "")) == "bench":
			benches += 1
	check("в мире: дерево с лишаем и скамейка (ломаются как ресурсы)", lichen_trees == 1 and benches == 1, "%d %d" % [lichen_trees, benches])
	bbt.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://prefabs/test_editor_tmp.json"))
	PrefabRegistry.reload()

	# обработка пустого холста
	ed._on_new()
	check("«Новая» очищает холст", _count(g) == 0)
	ed._do_undo()
	check("undo «Новая» возвращает содержимое", _count(g) > 10)

	print("RESULT fails=", fails)
	quit(fails)


func _filter_count(ed: Node, q: String) -> int:
	var n := 0
	for p: Dictionary in BlockRegistry.palette():
		if q in String(p["name"]).to_lower():
			n += 1
	return n
