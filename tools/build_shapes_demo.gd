extends SceneTree
## Демо-префаб всех новых форм (колонны, скругления, клинья, кол) в нескольких материалах. Категория other — в генерацию не попадает.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/build_shapes_demo.gd
func _init() -> void:
	await process_frame
	BlockRegistry.ensure()
	var g := BlockGrid.new(18, 5, 9)
	g.ground_cells = 1
	TestHouse.wall(g, 0, 0, 0, 18, 2, 9, 5)
	var keys := ["pillar_thick", "pillar_thin", "round_1", "round_4", "wedge", "wedge_low", "stake"]
	var tiers := [0, 4, 5]   # доски свежие, доски гнилые, бетон гладкий (индексы tier'ов формы)
	for r in tiers.size():
		for i in keys.size():
			TestHouse.put(g, keys[i], Vector3i(1 + i * 2, 2, 1 + r * 3), (i + r) % 4 if i >= 2 and i <= 5 else 0, tiers[r], 0)
	var d := PrefabIO.to_dict(g, {"name": "shapes_demo", "category": "other", "tags": ["demo"], "weight": 0.0, "margin": 1, "sink": 1})
	PrefabIO.save_dict(d, PrefabIO.DIR_RES + "shapes_demo.json")
	print("shapes_demo blocks ", d["blocks"].size())
	quit()
