extends SceneTree
## Замер стоимости построения чанка ландшафта по этапам (колонка, данные, сборка поля, Surface Nets, коллизия).
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/bench_chunks.gd


func _initialize() -> void:
	var p := WorldParams.new()
	p.size = 2048
	p.seed_value = 1337
	var world := WorldMap.new()
	await world.generate(p)
	var terrain := Terrain.new()
	terrain.gen = WorldGen.new(world)
	var gen := terrain.gen
	var c0 := Vector2i(1300 / 16, 1450 / 16)   # город
	var cols: Array[Vector2i] = []
	for dz in 6:
		for dx in 6:
			cols.append(c0 + Vector2i(dx, dz))
	var t := Time.get_ticks_usec()
	for c in cols:
		gen.column(c.x, c.y)
	var t_col := Time.get_ticks_usec() - t
	# чанки с поверхностью
	var surf: Array[Vector3i] = []
	for c in cols:
		var rng := gen.column_range(c.x, c.y)
		for cy in range(Terrain.MIN_CY, Terrain.MAX_CY + 1):
			if cy * 16 > rng.y or (cy + 1) * 16 < rng.x:
				continue
			surf.append(Vector3i(c.x, cy, c.y))
	t = Time.get_ticks_usec()
	var ndata := 0
	for cc in surf:
		for dz in 3:
			for dy in 3:
				for dx in 3:
					terrain.get_chunk(cc + Vector3i(dx - 1, dy - 1, dz - 1))
	ndata = terrain._data.size()
	var t_data := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var tris := 0
	for cc in surf:
		var r := terrain._build_chunk(cc)
		if r["ok"]:
			tris += (r["idx"] as PackedInt32Array).size() / 3
	var t_build := Time.get_ticks_usec() - t
	print("BENCH columns %d: %.1f ms (%.2f ms each)" % [cols.size(), t_col / 1000.0, t_col / 1000.0 / cols.size()])
	print("BENCH chunk data %d: %.1f ms (%.2f ms each)" % [ndata, t_data / 1000.0, t_data / 1000.0 / ndata])
	print("BENCH build (copy+nets+shape) %d surface chunks: %.1f ms (%.2f ms each), tris %d" % [surf.size(), t_build / 1000.0, t_build / 1000.0 / surf.size(), tris])
	quit()
