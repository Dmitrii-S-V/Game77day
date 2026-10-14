extends SceneTree
## Тест игрока с блоками построек: проход сквозь ковёр и паутину, замедление, удар по мягким блокам,
## дверь по E, заколоченная дверь.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_player_blocks.gd

var fails := 0
var main: Node3D


func check(n: String, c: bool, info: String = "") -> void:
	print(("PASS  " if c else "FAIL  ") + n + ((" -- " + info) if info != "" else ""))
	if not c:
		fails += 1


func _initialize() -> void:
	_run()


func _phys(n: int) -> void:
	for i in n:
		await physics_frame


func _center(bb: BlockBuilding, c: Vector3i) -> Vector3:
	return bb.to_global(bb.origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * BlockGrid.B)


func _run() -> void:
	await process_frame
	BlockRegistry.ensure()
	main = Node3D.new()
	root.add_child(main)
	current_scene = main
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(200, 1, 200)
	fcs.shape = fsh
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	main.add_child(floor_body)
	var g := TestHouse.build()
	var bb := BlockBuilding.new()
	main.add_child(bb)
	bb.setup(g, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	var player := Player.new()
	main.add_child(player)
	player.inventory.select(0)
	for i in 300:
		await process_frame
		if bb.is_ready():
			break
	await _phys(10)

	# --- ходьба сквозь ковёр (x: ячейки 2..4 на z=5) ---
	var start := _center(bb, Vector3i(1, 2, 5))
	player.global_position = Vector3(start.x, 1.02, start.z)
	player.velocity = Vector3.ZERO
	await _phys(20)
	var x0 := player.global_position.x
	player.debug_dir = Vector3(1, 0, 0)
	await _phys(50)
	var x1 := player.global_position.x
	player.debug_dir = Vector3.ZERO
	var carpet_end := _center(bb, Vector3i(4, 2, 5)).x + 0.5
	check("игрок идёт сквозь ковёр (прошёл дальше его края)", x1 > carpet_end and x1 - x0 > 1.5, "%.2f -> %.2f, край ковра %.2f" % [x0, x1, carpet_end])
	check("игрок не упёрся: ковёр на месте и цел", g.get_cell(3, 2, 5) == BlockRegistry.id_by_key("carpet"))

	# --- удар по ковру: ломается ---
	var cc := _center(bb, Vector3i(3, 2, 5))
	player.global_position = Vector3(cc.x - 1.2, 1.02, cc.z)
	await _phys(3)
	player.set_look(-PI * 0.5, -0.9)   # смотрим на ковёр сверху-вперёд (yaw -90° = +X)
	player.cam.global_position = Vector3(cc.x - 0.8, cc.y + 1.0, cc.z)
	player.cam.look_at(Vector3(cc.x, cc.y - 0.2, cc.z))
	player._melee()
	await _phys(2)
	check("удар по ковру (слой 8) ломает его", g.get_cell(3, 2, 5) == 0)

	# --- паутина: проход и замедление ---
	var g2 := BlockGrid.new(20, 10, 20)
	g2.ground_cells = 1
	TestHouse.wall(g2, 0, 0, 0, 20, 2, 20, 5)
	TestHouse.wall(g2, 17, 2, 0, 18, 8, 20, 5)       # стена, чтобы паутине было за что держаться
	for z in range(0, 20):
		TestHouse.put(g2, "web", Vector3i(13, 2, z))
		TestHouse.put(g2, "web", Vector3i(13, 3, z))
		TestHouse.put(g2, "web", Vector3i(12, 2, z))
		TestHouse.put(g2, "web", Vector3i(12, 3, z))
	var bb2 := BlockBuilding.new()
	main.add_child(bb2)
	bb2.position = Vector3(40, 0, 0)
	bb2.setup(g2, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material())
	for i in 200:
		await process_frame
		if bb2.is_ready():
			break
	await _phys(6)
	var w0 := _center(bb2, Vector3i(2, 2, 10))
	player.global_position = Vector3(w0.x, 1.02, w0.z)
	player.velocity = Vector3.ZERO
	await _phys(10)
	player.debug_dir = Vector3(1, 0, 0)
	await _phys(30)
	var free_speed := absf(player.velocity.x)
	var px_before := player.global_position.x
	# идём до паутины (x ячейка 12 = +? м)
	var web_x := _center(bb2, Vector3i(12, 2, 10)).x
	var guard := 0
	while player.global_position.x < web_x - 0.2 and guard < 300:
		await _phys(1)
		guard += 1
	await _phys(14)
	var in_web := player._slows.size() > 0
	var web_speed := absf(player.velocity.x)
	await _phys(40)
	var after_x := player.global_position.x
	player.debug_dir = Vector3.ZERO
	check("свободная скорость %.2f м/с" % free_speed, free_speed > 4.0)
	check("в паутине зона замедления активна", in_web)
	check("в паутине скорость ниже (%.2f < %.2f)" % [web_speed, free_speed * 0.8], web_speed < free_speed * 0.8 and web_speed > 1.0)
	check("игрок проходит сквозь паутину дальше её клеток", after_x > web_x + 1.0, "%.2f vs %.2f" % [after_x, web_x])
	check("после выхода замедление снято", player._slows.is_empty(), str(player._slows))

	# --- двери по E ---
	var wd := Vector3i(4, 2, 9)
	var dc := _center(bb, wd)
	player.global_position = Vector3(dc.x, 0.02, dc.z + 2.0)
	player.velocity = Vector3.ZERO
	await _phys(5)
	player.cam.global_position = Vector3(dc.x, 2.2, dc.z + 2.0)
	player.cam.look_at(Vector3(dc.x, 2.0, dc.z))
	var before := BlockRegistry.state_of(g.get_meta_at(4, 2, 9))
	var handled := player._use_block()
	var after := BlockRegistry.state_of(g.get_meta_at(4, 2, 9))
	check("E по двери: переключилась (закрыта -> открыта)", handled and before == 0 and after == 1)
	player._use_block()
	check("E ещё раз закрывает", BlockRegistry.state_of(g.get_meta_at(4, 2, 9)) == 0)
	# заколоченная дверь сзади (3,2,0)
	var bd := _center(bb, Vector3i(2, 2, 0))
	player.global_position = Vector3(bd.x, 0.02, bd.z - 2.0)
	await _phys(5)
	player.cam.global_position = Vector3(bd.x, 2.2, bd.z - 2.0)
	player.cam.look_at(Vector3(bd.x, 2.0, bd.z))
	var bs0 := BlockRegistry.state_of(g.get_meta_at(2, 2, 0))
	player._use_block()
	check("E по заколоченной двери: не открывается", BlockRegistry.state_of(g.get_meta_at(2, 2, 0)) == bs0 and bs0 == 0)
	# пройти сквозь заколоченную дверь нельзя
	player.debug_dir = Vector3(0, 0, 1)
	await _phys(40)
	player.debug_dir = Vector3.ZERO
	check("через заколоченную дверь пройти нельзя", player.global_position.z < bd.z + 0.3, "z=%.2f дверь z=%.2f" % [player.global_position.z, bd.z])

	print("RESULT fails=", fails)
	quit(fails)
