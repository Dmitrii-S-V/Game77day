extends SceneTree
## Иконка приложения 77Days (exe, APK): assets/ui/app_icon.png 256x256 — тёмный фон, кровавая полоса, «77».


func _init() -> void:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.frequency = 0.03
	for y in n:
		for x in n:
			var c := Color(0.11, 0.1, 0.09).lerp(Color(0.2, 0.18, 0.15), 0.5 + 0.5 * nz.get_noise_2d(x, y))
			var d := absf((x - y) * 0.7071)
			if d < 22.0 + 6.0 * nz.get_noise_2d(x * 3.0, y):
				c = c.lerp(Color(0.45, 0.04, 0.03), 0.85)
			# скруглённые углы
			var cx := clampf(x, 36, n - 37)
			var cy := clampf(y, 36, n - 37)
			if Vector2(x, y).distance_to(Vector2(cx, cy)) > 36.0:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	# «77» блочными цифрами
	var seg := [[0, 0, 5, 1], [4, 1, 5, 3], [3, 3, 4, 5], [2, 5, 3, 8]]   # x0,y0,x1,y1 в клетках 5x8
	var cell := 14
	for k in 2:
		var ox := 38 + k * 100
		var oy := 72
		for s: Array in seg:
			for yy in range(oy + int(s[1]) * cell, oy + int(s[3]) * cell):
				for xx in range(ox + int(s[0]) * cell, ox + int(s[2]) * cell):
					img.set_pixel(xx, yy, Color(0.93, 0.88, 0.76))
	img.save_png("res://assets/ui/app_icon.png")
	print("icon saved")
	quit()
