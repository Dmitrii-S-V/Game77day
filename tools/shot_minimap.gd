extends SceneTree
## Снимок большой и маленькой карты с метками (нужно окно, не headless).
## godot --path . --script res://tools/shot_minimap.gd -- out_prefix

func _init() -> void:
	var prefix := "res://shots/minimap"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.3, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var mm := Minimap.new()
	root.add_child(mm)
	await process_frame
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	for y in 512:
		for x in 512:
			img.set_pixel(x, y, Color(0.25 + 0.3 * float((x / 32 + y / 32) % 2), 0.45, 0.25))
	mm.map_texture = ImageTexture.create_from_image(img)
	mm.world_size = 2048.0
	Minimap.marks = [
		{"pos": Vector2(1000, 1000), "color": Color(1.0, 0.25, 0.2), "n": 1},
		{"pos": Vector2(1150, 950), "color": Color(1.0, 0.8, 0.1), "n": 2},
		{"pos": Vector2(1900, 300), "color": Color(0.2, 0.7, 1.0), "n": 3},
	]
	mm._center_m = Vector2(1000, 1000)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(prefix + "_small.png")
	mm.expanded = true
	mm._follow = false
	mm._view_m = 500.0
	mm._apply_layout()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(prefix + "_big.png")
	print("saved ", prefix)
	Minimap.marks.clear()
	quit()
