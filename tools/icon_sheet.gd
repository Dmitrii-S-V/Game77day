extends SceneTree
## Лист всех иконок (проверка): assets/icons/*.png на сером фоне -> -- <out.png>


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var ids: Array = ItemDB.ITEMS.keys()
	var cols := 8
	var s := 128
	var sheet := Image.create(cols * s, ceili(ids.size() / float(cols)) * s, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.13, 0.15))
	for i in ids.size():
		var p := ProjectSettings.globalize_path("res://assets/icons/%s.png" % ids[i])
		var img := Image.load_from_file(p)
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(0, 0, s, s), Vector2i((i % cols) * s, (i / cols) * s))
	sheet.save_png(out)
	quit()
