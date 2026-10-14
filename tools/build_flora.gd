extends SceneTree
## Собирает атлас флоры из спрайтов декалей природы (kind plant / rock / ground в data/blocks/decals.json):
## assets/textures/flora.png (8x4 ячейки по 256) и data/blocks/flora.json. Растения и камни выровнены корнем к низу ячейки,
## напочвенные пятна — по центру. Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/build_flora.gd

const CELL := 256
const COLS := 8
const ROWS := 4


func _init() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://data/blocks/decals.json"), FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var atlas := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.3, 0.3, 0.2, 0.0))
	var out: Array = []
	for e: Dictionary in d["decals"]:
		var kind := String(e["kind"])
		if not (kind in ["plant", "rock", "ground"]):
			continue
		if out.size() >= COLS * ROWS:
			break
		var im := Image.load_from_file(ProjectSettings.globalize_path(String(e["file"])))
		im.convert(Image.FORMAT_RGBA8)
		var bb := _alpha_bbox(im)
		if bb.size.x < 4 or bb.size.y < 4:
			continue
		var crop := im.get_region(bb)
		var aspect := float(bb.size.x) / float(bb.size.y)
		var sc := minf(float(CELL - 6) / bb.size.x, float(CELL - 6) / bb.size.y)
		crop.resize(maxi(int(bb.size.x * sc), 1), maxi(int(bb.size.y * sc), 1), Image.INTERPOLATE_LANCZOS)
		var idx := out.size()
		var cell := Vector2i((idx % COLS) * CELL, (idx / COLS) * CELL)
		var off := Vector2i((CELL - crop.get_width()) / 2, (CELL - crop.get_height()) if kind != "ground" else (CELL - crop.get_height()) / 2)
		atlas.blit_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()), cell + off)
		# размер: растения — высота (м) по ширине кадра, камни — высота, пятна — ширина
		var size := 0.8
		match kind:
			"plant":
				size = clampf(0.45 + 0.5 * float(bb.size.y) / 300.0, 0.4, 1.0)
			"rock":
				size = clampf(0.25 + 0.5 * float(bb.size.y) / 300.0, 0.25, 0.75)
			"ground":
				size = clampf(1.0 + 1.6 * float(bb.size.x) / 300.0, 1.2, 3.2)
		out.append({"key": e["key"], "cell": idx, "kind": kind, "aspect": snappedf(aspect, 0.01), "size": snappedf(size, 0.01),
			"weight": 1.0 if kind != "rock" else 0.7})
	atlas.save_png(ProjectSettings.globalize_path("res://assets/textures/flora.png"))
	var fo := FileAccess.open(ProjectSettings.globalize_path("res://data/blocks/flora.json"), FileAccess.WRITE)
	fo.store_string(JSON.stringify({"_comment": "Атлас флоры (assets/textures/flora.png, 8x4 ячейки): plant — вертикальные карточки, rock — камни-карточки, ground — плоские пятна на земле. size: высота (plant, rock) или ширина (ground) в метрах. Плотность — константы в scripts/world/grass_field.gd.", "cols": COLS, "rows": ROWS, "items": out}, "  "))
	print("flora atlas: ", out.size(), " cells")
	quit()


func _alpha_bbox(im: Image) -> Rect2i:
	var x0 := im.get_width()
	var y0 := im.get_height()
	var x1 := -1
	var y1 := -1
	for y in im.get_height():
		for x in im.get_width():
			if im.get_pixel(x, y).a > 0.15:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
