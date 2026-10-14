extends SceneTree
## Предпросмотр карты мира (как в меню). Запуск:
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_map_preview.gd -- --size=2048 --seed=1337 --towns=8 --pois=12 --rivers=3 --lakes=4
## Выход: D:/77Days/shots/world_map.png (512x512)

func _init() -> void:
	var p := WorldParams.new()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"size": p.size = int(kv[1])
			"seed": p.seed_value = int(kv[1])
			"towns": p.towns = int(kv[1])
			"pois": p.pois = int(kv[1])
			"rivers": p.rivers = int(kv[1])
			"lakes": p.lakes = int(kv[1])
			"mountain": p.pct_mountain = int(kv[1])
			"hill": p.pct_hill = int(kv[1])
			"plain": p.pct_plain = int(kv[1])
	var sw := Time.get_ticks_msec()
	var w := WorldMap.new()
	await w.generate(p, null, func(f: float, t: String) -> void: print('[%.2f] %s' % [f, t]))
	print(p.summary())
	print(w.info, "  (", Time.get_ticks_msec() - sw, " ms)")
	for t: Dictionary in w.roads.towns:
		print("  town tier %d %s at (%.0f, %.0f) R %.0f lots %d" % [t["tier"], RoadNet.Pattern.keys()[t["pattern"]], t["center"].x, t["center"].y, t["radius"], t["lots"].size()])
	for t: Dictionary in w.roads.pois:
		print("  poi %s at (%.0f, %.0f)" % [t["poi_type"], t["center"].x, t["center"].y])
	var img: Image = await w.render_preview(512)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	print("saved err ", img.save_png(ProjectSettings.globalize_path("res://shots/world_map.png")))
	quit()
