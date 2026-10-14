extends SceneTree
## Время построения превью мира: godot --headless --path . --script res://tools/bench_preview.gd
func _init() -> void:
	var p := WorldParams.new()
	p.seed_value = 1337
	var w := WorldMap.new()
	await w.generate(p, null, func(_f: float, _t: String) -> void: pass)
	for px in [1024, 2048]:
		var t := Time.get_ticks_msec()
		var img: Image = await w.render_preview(px)
		print("preview ", px, ": ", Time.get_ticks_msec() - t, " ms, ", img.get_width())
	print("roads: ", w.roads.link_paths.size(), " paths, points ", _pts(w))
	quit()

func _pts(w: WorldMap) -> int:
	var n := 0
	for lp: Dictionary in w.roads.link_paths:
		n += (lp["pts"] as PackedVector2Array).size()
	var r := 0
	for rv: Dictionary in w.hydro.rivers:
		r += (rv["pts"] as PackedVector2Array).size()
	return n + r
