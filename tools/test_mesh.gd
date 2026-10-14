extends SceneTree
## Тест целостности ландшафта после правок: открытые границы (дыры, висящие треугольники)
## и мелкие оторванные компоненты. Запуск:
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_mesh.gd

var terrain: Terrain
var phase := 0
var frames := 0
var spawn := Vector3.ZERO


func _initialize() -> void:
	var p := WorldParams.new()
	p.size = 1024
	var world := WorldMap.new()
	await world.generate(p)
	terrain = Terrain.new()
	terrain.gen = WorldGen.new(world)
	terrain.keep_arrays = true
	terrain.view_radius = 3
	root.add_child(terrain)
	spawn = terrain.gen.spawn_point()
	terrain.update_view(spawn)


func _process(_delta: float) -> bool:
	frames += 1
	terrain.update_view(spawn)
	if not terrain.is_idle():
		return false
	if phase == 0:
		print("loaded, %s" % terrain.stats())
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 60:
			var p := Vector3(spawn.x + rng.randf_range(-22, 22), 0, spawn.z + rng.randf_range(-22, 22))
			p.y = terrain.gen.height_at(p.x, p.z) + rng.randf_range(-6.0, 1.0)
			var r := rng.randf_range(1.2, 3.0)
			terrain.edit_sphere(p, r, rng.randf() < 0.7, WorldGen.MAT_DIRT)
		phase = 1
		return false
	if phase == 1:
		_analyze()
		return true
	return false


func _analyze() -> void:
	var cx0 := spawn.x
	var cz0 := spawn.z
	var weld := {}
	var wv: Array[Vector3] = []
	var tris: Array[Vector3i] = []
	for cc: Vector3i in terrain.debug_meshes.keys():
		var m: Dictionary = terrain.debug_meshes[cc]
		var verts: PackedVector3Array = m["verts"]
		var idx: PackedInt32Array = m["idx"]
		var map := PackedInt32Array()
		map.resize(verts.size())
		for i in verts.size():
			var wp := verts[i] + Vector3(cc * WorldGen.CHUNK)
			var key := Vector3i((wp * 1000.0).round())
			if not weld.has(key):
				weld[key] = wv.size()
				wv.append(wp)
			map[i] = weld[key]
		for t in range(0, idx.size(), 3):
			tris.append(Vector3i(map[idx[t]], map[idx[t + 1]], map[idx[t + 2]]))
	var edges := {}
	var parent := PackedInt32Array()
	parent.resize(wv.size())
	for i in parent.size():
		parent[i] = i
	for t in tris:
		for e in [Vector2i(t.x, t.y), Vector2i(t.y, t.z), Vector2i(t.z, t.x)]:
			var key := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
			edges[key] = int(edges.get(key, 0)) + 1
		_union(parent, t.x, t.y)
		_union(parent, t.y, t.z)
	var open := 0
	var open_inner := 0
	for key: Vector2i in edges.keys():
		if edges[key] == 1:
			open += 1
			var a := wv[key.x]
			var inner := absf(a.x - cx0) < 30.0 and absf(a.z - cz0) < 30.0
			if inner:
				open_inner += 1
				if open_inner <= 5:
					print("  open edge near ", a)
	var comp := {}
	for t in tris:
		var r := _find(parent, t.x)
		comp[r] = int(comp.get(r, 0)) + 1
	var small := 0
	var small_inner := 0
	var cpos := {}
	for t in tris:
		var r := _find(parent, t.x)
		if not cpos.has(r):
			cpos[r] = wv[t.x]
	for r in comp.keys():
		if comp[r] <= 40:
			small += 1
			var p: Vector3 = cpos[r]
			if absf(p.x - cx0) < 30.0 and absf(p.z - cz0) < 30.0:
				small_inner += 1
				print("  small component (%d tris) at %s" % [comp[r], p])
	print("RESULT triangles %d  open edges %d (inner %d)  components %d  small %d (inner %d)" % [tris.size(), open, open_inner, comp.size(), small, small_inner])


func _find(p: PackedInt32Array, a: int) -> int:
	while p[a] != a:
		p[a] = p[p[a]]
		a = p[a]
	return a


func _union(p: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(p, a)
	var rb := _find(p, b)
	if ra != rb:
		p[ra] = rb
