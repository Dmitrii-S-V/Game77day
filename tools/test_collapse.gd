extends SceneTree
## Регрессия: слом одного блока не должен обрушать дом (префабы из редактора и сгенерированные здания),
## двери префаба открываются. Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_collapse.gd

var fails := 0


func check(n: String, c: bool, info: String = "") -> void:
	print(("PASS  " if c else "FAIL  ") + n + ((" -- " + info) if info != "" else ""))
	if not c:
		fails += 1


func _initialize() -> void:
	_run()


func _count(g: BlockGrid) -> int:
	var n := 0
	for i in g.cells.size():
		if g.cells[i] != 0:
			n += 1
	return n


func _find_wall_cell(g: BlockGrid) -> Vector3i:
	# блок на периметре на высоте 1-2 слоя над землёй
	for y in range(g.ground_cells, g.ground_cells + 3):
		for z in g.nz:
			for x in g.nx:
				if g.get_cell(x, y, z) != 0 and not BlockRegistry.is_part(g.get_meta_at(x, y, z)):
					var id := g.get_cell(x, y, z)
					if id < BlockRegistry.FIRST_ID or BlockRegistry.is_cube(id):
						if (x == 0 or z == 0 or g.get_cell(x - 1, y, z) == 0) and g.get_cell(x, y + 1, z) != 0:
							return Vector3i(x, y, z)
	return Vector3i(-1, -1, -1)


func _run() -> void:
	await process_frame
	BlockRegistry.ensure()
	PrefabRegistry.reload()
	var main := Node3D.new()
	root.add_child(main)
	current_scene = main
	var items := PrefabRegistry.all()
	check("есть префабы (%d)" % items.size(), items.size() >= 2)
	for it: Dictionary in items:
		var nm := String(it["data"]["name"])
		if String(it["data"].get("category", "")) in ["other", "_test"]:
			continue   # демо-префабы (формы) без стен
		var g := PrefabRegistry.grid_of(it)
		var bb := BlockBuilding.new()
		main.add_child(bb)
		bb.setup(g, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
		for i in 200:
			await process_frame
			if bb.is_ready():
				break
		var before := _count(g)
		var c := _find_wall_cell(g)
		check("[%s] найден блок стены для слома" % nm, c.x >= 0)
		if c.x >= 0:
			bb.break_block(c, true)
			var after := _count(g)
			check("[%s] после слома одного блока дом цел (%d -> %d)" % [nm, before, after], before - after <= 12 and after > before * 0.95)
		# все двери префаба должны переключаться
		var door_id := BlockRegistry.id_by_key("door_wood")
		var doors := 0
		var toggled := 0
		for i in g.cells.size():
			if g.cells[i] == door_id and not BlockRegistry.is_part(g.meta[i]):
				doors += 1
				var a := g.cell_of(i)
				var s0 := BlockRegistry.state_of(g.meta[i])
				if bb.toggle_door(a) and BlockRegistry.state_of(g.get_meta_at(a.x, a.y, a.z)) != s0:
					toggled += 1
		check("[%s] двери открываются: %d из %d" % [nm, toggled, doors], toggled == doors)
		bb.queue_free()

	# сгенерированные здания тоже не должны рушиться целиком
	for bt in ["house", "farmhouse", "shop", "gas_store", "warehouse", "barn", "office", "apartment", "cabin", "shed", "silo", "gas_canopy"]:
		var g2 := BlockGen.generate(bt, 14.0, 12.0, 77)
		var bb2 := BlockBuilding.new()
		main.add_child(bb2)
		bb2.setup(g2, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
		for i in 300:
			await process_frame
			if bb2.is_ready():
				break
		var before2 := _count(g2)
		var c2 := _find_wall_cell(g2)
		if c2.x >= 0:
			bb2.break_block(c2, true)
		var after2 := _count(g2)
		check("[%s] генератор: слом блока не обрушает здание (%d -> %d)" % [bt, before2, after2], c2.x < 0 or (before2 - after2 <= 40 and after2 > before2 * 0.9), "блок %s" % str(c2))
		bb2.queue_free()
		await process_frame

	print("RESULT fails=", fails)
	quit(fails)
