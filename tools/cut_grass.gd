extends SceneTree
## Атлас кустов травы для GrassField (основная трава): assets/src/flora/grass_sheet.webp (прозрачный фон, 3x2 куста)
## -> assets/textures/grass_tufts.png (3x2 ячейки CELL x CELL, куст по центру, корнем к нижнему краю).
## В ячейке берётся самый большой связный кусок и отдельные куски внутри; обрывки соседей у краёв отбрасываются.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/cut_grass.gd

const SRC := "res://assets/src/flora/grass_sheet.webp"
const OUT := "res://assets/textures/grass_tufts.png"
const COLS := 3
const ROWS := 2
const CELL := 384
const ALPHA_MIN := 0.25


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var at := Image.create(COLS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	at.fill(Color(0, 0, 0, 0))
	var cw := float(w) / COLS
	var ch := float(h) / ROWS
	for r in ROWS:
		for c in COLS:
			var x0 := int(c * cw)
			var y0 := int(r * ch)
			var keep := _components(src, x0, y0, int((c + 1) * cw), int((r + 1) * ch))
			var bx0 := w
			var bx1 := 0
			var by0 := h
			var by1 := 0
			for p: Vector2i in keep:
				bx0 = mini(bx0, p.x)
				bx1 = maxi(bx1, p.x + 1)
				by0 = mini(by0, p.y)
				by1 = maxi(by1, p.y + 1)
			var img := Image.create(bx1 - bx0, by1 - by0, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for p: Vector2i in keep:
				img.set_pixel(p.x - bx0, p.y - by0, src.get_pixelv(p))
			var k := minf(float(CELL - 8) / img.get_width(), float(CELL - 4) / img.get_height())
			var sw := roundi(img.get_width() * k)
			var sh := roundi(img.get_height() * k)
			img.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
			at.blend_rect(img, Rect2i(0, 0, sw, sh), Vector2i(c * CELL + (CELL - sw) / 2, r * CELL + CELL - sh))
			print("куст %d: %dx%d -> %dx%d" % [r * COLS + c, bx1 - bx0, by1 - by0, sw, sh])
	_bleed(at)
	at.save_png(OUT)
	print("атлас ", OUT, " ", at.get_size())
	quit()


func _components(src: Image, x0: int, y0: int, x1: int, y1: int) -> Array:
	var cw := x1 - x0
	var chh := y1 - y0
	var lab := PackedInt32Array()
	lab.resize(cw * chh)
	var comps: Array = []
	for ly in chh:
		for lx in cw:
			if lab[ly * cw + lx] != 0 or src.get_pixel(x0 + lx, y0 + ly).a < ALPHA_MIN:
				continue
			var id := comps.size() + 1
			var px: Array = []
			var edge := false
			var st: Array[Vector2i] = [Vector2i(lx, ly)]
			lab[ly * cw + lx] = id
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				px.append(Vector2i(x0 + q.x, y0 + q.y))
				if q.x == 0 or q.y == 0 or q.x == cw - 1 or q.y == chh - 1:
					edge = true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := q + Vector2i(dx, dy)
						if n.x < 0 or n.y < 0 or n.x >= cw or n.y >= chh or lab[n.y * cw + n.x] != 0:
							continue
						if src.get_pixel(x0 + n.x, y0 + n.y).a >= ALPHA_MIN:
							lab[n.y * cw + n.x] = id
							st.append(n)
			comps.append({"px": px, "edge": edge})
	var big := 0
	for i in comps.size():
		if (comps[i]["px"] as Array).size() > (comps[big]["px"] as Array).size():
			big = i
	var out: Array = []
	for i in comps.size():
		if i == big or (not bool(comps[i]["edge"]) and (comps[i]["px"] as Array).size() >= 8):
			out.append_array(comps[i]["px"])
	# полупрозрачная кайма вокруг (сглаженные края травинок) — тоже нужна
	var have := {}
	for p: Vector2i in out:
		have[p] = true
	var halo: Array = []
	for p: Vector2i in out:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if not have.has(n) and n.x >= x0 and n.y >= y0 and n.x < x1 and n.y < y1 and src.get_pixelv(n).a > 0.02:
				have[n] = true
				halo.append(n)
	return out + halo


## Цвет прозрачных пикселей — от соседних (без тёмной каймы в мипмапах).
func _bleed(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for pass_i in 6:
		var src := img.duplicate() as Image
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a > 0.05:
					continue
				var acc := Color(0, 0, 0, 0)
				var n := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var px := x + d.x
					var py := y + d.y
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var q := src.get_pixel(px, py)
					if q.a > 0.05:
						acc += Color(q.r, q.g, q.b, 0)
						n += 1
				if n > 0:
					img.set_pixel(x, y, Color(acc.r / n, acc.g / n, acc.b / n, src.get_pixel(x, y).a))
