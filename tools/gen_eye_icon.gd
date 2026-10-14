extends SceneTree
## Иконка «глаз» для шкалы заметности: assets/ui/icons/eye.png (в стиле остальных: светло-серая с тёмной обводкой).


func _init() -> void:
	var n := 52
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var light := Color8(213, 209, 206)
	var dark := Color8(38, 34, 32)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0      # -1..1
			var v := (y + 0.5) / n * 2.0 - 1.0
			# миндалевидный контур: |v| < 0.55 * (1 - u^2)
			var lid := 0.56 * (1.0 - u * u)
			var e := absf(v) - lid                   # <0 внутри глаза
			var r := Vector2(u, v).length()
			var c := Color(0, 0, 0, 0)
			if e < 0.0 and absf(u) < 0.98:
				c = light
				if r < 0.36:
					c = dark                         # радужка
					if r < 0.3:
						c = light.darkened(0.35)
					if r < 0.16:
						c = dark                     # зрачок
					if Vector2(u + 0.1, v + 0.1).length() < 0.07:
						c = Color(1, 1, 1)           # блик
			if (e >= -0.09 and e < 0.04 and absf(u) < 1.0) or (absf(u) >= 0.92 and absf(u) < 1.0 and absf(v) < 0.12):
				c = dark                             # обводка век
			img.set_pixel(x, y, c)
	img.save_png("res://assets/ui/icons/eye.png")
	print("eye icon saved")
	quit()
