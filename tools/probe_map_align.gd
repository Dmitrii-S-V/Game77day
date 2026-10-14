extends SceneTree
## Сверка карты с миром: превью (WorldMap.macro) против реальной высоты (WorldGen.height_at), города рядом с точкой.
## godot --headless --path . --script res://tools/probe_map_align.gd -- --seed=1

func _init() -> void:
	var p := WorldParams.new()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2 and kv[0] == "seed":
			p.seed_value = int(kv[1])
	var w := WorldMap.new()
	await w.generate(p, null, func(_f: float, _t: String) -> void: pass)
	var gen := WorldGen.new(w)
	print("world size ", w.size, " spawn ", w.spawn)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 400
	var a := PackedFloat64Array()
	var b := PackedFloat64Array()
	for i in n:
		var x := rng.randf_range(100.0, w.size - 100.0)
		var z := rng.randf_range(100.0, w.size - 100.0)
		a.append(w.macro(x, z))
		b.append(gen.height_at(x, z))
	print("corr macro vs real height: ", _corr(a, b))
	# транспонированный вариант (если бы x/z были перепутаны)
	var c := PackedFloat64Array()
	rng.seed = 7
	for i in n:
		var x := rng.randf_range(100.0, w.size - 100.0)
		var z := rng.randf_range(100.0, w.size - 100.0)
		c.append(w.macro(z, x))
	print("corr transposed: ", _corr(c, b))
	var sp := Vector2(w.spawn.x, w.spawn.z)
	for t: Dictionary in w.roads.towns:
		var d := (t["center"] as Vector2).distance_to(sp)
		print("town tier %d at (%.0f, %.0f) dist to spawn %.0f" % [t["tier"], t["center"].x, t["center"].y, d])
	quit()


func _corr(x: PackedFloat64Array, y: PackedFloat64Array) -> float:
	var n := x.size()
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += x[i]
		my += y[i]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		sxy += (x[i] - mx) * (y[i] - my)
		sxx += (x[i] - mx) * (x[i] - mx)
		syy += (y[i] - my) * (y[i] - my)
	return sxy / sqrt(sxx * syy + 0.000001)
