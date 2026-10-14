extends SceneTree
## Проверка звуков: сколько вариантов у каждого и из каких файлов (запись или синтез), петли фона.


func _init() -> void:
	var names := ["step_grass", "step_gravel", "step_hard", "step_wood", "hit_wood", "hit_stone", "hit_dirt", "hit_flesh", "swing",
		"eat", "drink", "rustle", "door_open", "door_close", "zombie_groan", "zombie_attack", "zombie_hurt", "zombie_death",
		"player_hurt", "crow"]
	var fails := 0
	for n in names:
		var l := Sfx.streams(n)
		var kinds := {}
		for s: AudioStream in l:
			kinds[s.resource_path.get_extension()] = int(kinds.get(s.resource_path.get_extension(), 0)) + 1
		print("SND %-14s %2d  %s" % [n, l.size(), kinds])
		if l.is_empty():
			fails += 1
	for n in ["wind_loop", "crickets_loop", "birds_loop"]:
		var s := Sfx.loop_stream(n)
		print("LOOP %-14s %s %.1f s" % [n, "ok" if s != null else "НЕТ", s.get_length() if s != null else 0.0])
		if s == null:
			fails += 1
	print("RESULT fails=%d" % fails)
	quit()
