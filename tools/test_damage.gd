extends SceneTree
var fails := 0
func check(n: String, c: bool, i: String = "") -> void:
	print(("PASS  " if c else "FAIL  ") + n + ((" -- " + i) if i != "" else ""))
	if not c: fails += 1
func _initialize() -> void:
	_run()
func _tree(sc: float) -> Node3D:
	var n := Node3D.new()
	n.scale = Vector3.ONE * sc
	n.set_meta("resource", "wood")
	n.set_meta("kind", "oak")
	return n
func _run() -> void:
	await process_frame
	var main := Node3D.new(); root.add_child(main); current_scene = main
	var p := Player.new(); main.add_child(p)
	await process_frame
	check("топор: дерево 39, земля 25", ItemDB.damage("stone_axe", "tree") == 39.0 and ItemDB.damage("stone_axe", "ground") == 25.0)
	check("блоки ландшафта: трава 125, земля 75", Terrain.block_max_hp(WorldGen.MAT_GRASS) == 125.0 and Terrain.block_max_hp(WorldGen.MAT_DIRT) == 75.0)
	print("slots: ", p.inventory.slots.size())
	for sc in [0.8, 1.25]:
		var t := _tree(sc); main.add_child(t)
		var hits := 0
		var before: int = p.inventory.count_of("planks") if p.inventory.has_method("count_of") else 0
		while is_instance_valid(t) and not t.is_queued_for_deletion() and hits < 40:
			p._hit_plant(t, Vector3.ZERO)
			hits += 1
		var mx := float(t.get_meta("hp_max", 0.0)) if is_instance_valid(t) else 0.0
		print("scale ", sc, " hp_max ", mx, " hits ", hits)
		var expect_hp := 200.0 if sc < 1.0 else 500.0
		check("дерево масштаба %.2f: прочность %d" % [sc, int(expect_hp)], mx == expect_hp)
		check("ударов топором (39): %d" % ceili(expect_hp / 39.0), hits == ceili(expect_hp / 39.0), str(hits))
	var total := 0
	for i in 8:
		var s: Variant = p.inventory.slots[i] if "slots" in p.inventory else null
		if s != null and s["id"] == "planks":
			total += int(s["n"])
	print("planks in inventory: ", total)
	check("доски: 47 + 118 = 165", total == 165, str(total))
	print("RESULT fails=", fails)
	quit(fails)
