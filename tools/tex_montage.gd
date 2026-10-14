extends SceneTree
## Склейка превью текстур в одну картинку (отладка): -- <out.png> <tex1> <tex2> ...  (имена из assets/textures без .png)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var cell := 256
	var out := Image.create(cell * (a.size() - 1), cell, false, Image.FORMAT_RGB8)
	for i in range(1, a.size()):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/%s.png" % a[i]))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i - 1) * cell, 0))
	out.save_png(a[0])
	quit()
