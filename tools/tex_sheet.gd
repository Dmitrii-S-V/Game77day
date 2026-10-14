extends SceneTree
func _init():
	BlockRegistry.ensure()
	var names := BlockRegistry._layer_names
	var cols := 8
	var rows := ceili(names.size() / float(cols))
	var sheet := Image.create(cols * 130, rows * 130, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.3, 0.45))
	for i in names.size():
		var im := BlockRegistry.texture_image(names[i])
		sheet.blend_rect(im, Rect2i(0, 0, 128, 128), Vector2i((i % cols) * 130 + 1, (i / cols) * 130 + 1))
	sheet.save_png("res://shots/block_tex_sheet.png")
	print(names)
	quit()
