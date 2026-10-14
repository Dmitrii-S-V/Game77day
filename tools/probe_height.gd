extends SceneTree
## Печатает высоты и материал колонок вокруг точки (отладка стыков ландшафта).
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/probe_height.gd -- 1336 1464


func _initialize() -> void:
	var cx := 1336
	var cz := 1464
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2:
		cx = int(a[0])
		cz = int(a[1])
	var p := WorldParams.new()
	p.size = 2048
	p.seed_value = 1337
	var world := WorldMap.new()
	await world.generate(p)
	var gen := WorldGen.new(world)
	for dz in range(-14, 15, 2):
		var hs := ""
		var ms := ""
		for dx in range(-14, 15, 2):
			var x := cx + dx
			var z := cz + dz
			hs += "%6.2f" % gen.height_at(x, z)
			var ci := gen.column(floori(x / float(WorldGen.CHUNK)), floori(z / float(WorldGen.CHUNK)))
			ms += "%2d" % ci.mat[posmod(x, WorldGen.CHUNK) + WorldGen.CHUNK * posmod(z, WorldGen.CHUNK)]
		print("z%+3d " % dz, hs, "  |", ms)
	quit()
