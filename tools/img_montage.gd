extends SceneTree
## Склейка картинок в ряд (отладка): -- <out.png> <h> <img1> <img2> ...  (абсолютные пути)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var h := int(a[1])
	var imgs: Array[Image] = []
	var w := 0
	for i in range(2, a.size()):
		var im := Image.load_from_file(a[i])
		if im == null:
			continue
		im.convert(Image.FORMAT_RGB8)
		im.resize(int(im.get_width() * float(h) / im.get_height()), h)
		imgs.append(im)
		w += im.get_width()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var x := 0
	for im in imgs:
		out.blit_rect(im, Rect2i(0, 0, im.get_width(), h), Vector2i(x, 0))
		x += im.get_width()
	out.save_png(a[0])
	quit()
