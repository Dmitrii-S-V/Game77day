extends SceneTree
## Атлас кустов травы под текстуры земли: assets/src/flora/tufts_v2/<main|pine|meadow>_N.png (по кусту на картинку,
## прозрачный фон) -> assets/textures/grass_tufts_v2.png (4x4 ячейки CELL, куст корнем к нижнему краю) +
## data/blocks/tufts.json: [{cell, pool, hf, wf}] (pool — на какой земле растёт: main — основная трава grass_a,
## pine — хвойная подстилка grass_b, meadow — луг grass_c; hf/wf — доля ячейки, занятая кустом).
## Белый ореол от генератора (полупрозрачные светлые пиксели вокруг) убирается, край травинок — цвета травинки.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/cut_tufts.gd

const SRC := "res://assets/src/flora/tufts_v2/"
const OUT := "res://assets/textures/grass_tufts_v2.png"
const JSON_OUT := "res://data/blocks/tufts.json"
const COLS := 4
const ROWS := 4
const CELL := 768
const ALPHA_MIN := 0.1
const PAD_TOP := 24
const PAD_BOTTOM := 24


func _init() -> void:
	var list: Array = []
	for pool in ["main", "pine", "meadow"]:
		for i in range(1, 32):
			var p := ProjectSettings.globalize_path(SRC + "%s_%d.png" % [pool, i])
			if not FileAccess.file_exists(p):
				break
			var im := Image.load_from_file(p)
			im.convert(Image.FORMAT_RGBA8)
			_dehalo(im)
			list.append({"img": _crop(im), "pool": pool})
	var at := Image.create(COLS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	at.fill(Color(0, 0, 0, 0))
	var items: Array = []
	for n in mini(list.size(), COLS * ROWS):
		var img: Image = list[n]["img"]
		# зазор сверху и снизу ячейки: вдали (мелкие мипмапы) тёмные корни не протекают в карточку куста под ними
		var k := minf(float(CELL - 8) / img.get_width(), float(CELL - PAD_TOP - PAD_BOTTOM) / img.get_height())
		var sw := roundi(img.get_width() * k)
		var sh := roundi(img.get_height() * k)
		img.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
		at.blend_rect(img, Rect2i(0, 0, sw, sh), Vector2i((n % COLS) * CELL + (CELL - sw) / 2, (n / COLS) * CELL + CELL - PAD_BOTTOM - sh))
		items.append({"cell": n, "pool": list[n]["pool"], "hf": float(sh) / CELL, "wf": float(sw) / CELL})
		print("ячейка %d %s %dx%d" % [n, list[n]["pool"], sw, sh])
	_bleed(at)
	at.save_png(OUT)
	var f := FileAccess.open(JSON_OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_comment": "tools/cut_tufts.gd: кусты травы в атласе grass_tufts_v2.png (4x4)", "items": items}, "  "))
	f.close()
	print("атлас ", OUT, " кустов ", items.size())
	quit()


## Ореол: светлые малонасыщенные полупрозрачные пиксели (свечение от белого фона генератора) — прозрачные.
func _dehalo(im: Image) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var d := im.get_data()
	for i in w * h:
		var a := d[i * 4 + 3]
		if a == 0:
			continue
		var r := d[i * 4]
		var g := d[i * 4 + 1]
		var b := d[i * 4 + 2]
		var mn := mini(r, mini(g, b))
		var mx := maxi(r, maxi(g, b))
		if (a <= 235 and mn > 150 and mx - mn < 40) or (mn > 185 and mx - mn < 28):   # и непрозрачная белая заливка
			d[i * 4 + 3] = 0
	im.set_data(w, h, false, Image.FORMAT_RGBA8, d)


func _crop(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var x0 := w
	var x1 := 0
	var y0 := h
	var y1 := 0
	for y in h:
		for x in w:
			if im.get_pixel(x, y).a >= ALPHA_MIN:
				x0 = mini(x0, x)
				x1 = maxi(x1, x + 1)
				y0 = mini(y0, y)
				y1 = maxi(y1, y + 1)
	var out := im.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a < ALPHA_MIN:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	_decontaminate(out)
	return out


## Цвет полупрозрачной каймы — от ближайших плотных пикселей (вдали без тёмного/белого контура). Альфа сохраняется.
func _decontaminate(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 if data[i * 4 + 3] >= 230 else 0
	for pass_i in 6:
		var grow := solid.duplicate()
		var src := data.duplicate()
		for y in h:
			for x in w:
				var i := y * w + x
				if solid[i] != 0:
					continue
				var r := 0
				var g := 0
				var b := 0
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var px := x + dx
						var py := y + dy
						if px < 0 or py < 0 or px >= w or py >= h:
							continue
						var j := py * w + px
						if solid[j] != 0:
							r += src[j * 4]
							g += src[j * 4 + 1]
							b += src[j * 4 + 2]
							n += 1
				if n > 0:
					data[i * 4] = r / n
					data[i * 4 + 1] = g / n
					data[i * 4 + 2] = b / n
					grow[i] = 1
		solid = grow
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


## Цвет полностью прозрачных пикселей — от соседних (мипмапы без тёмной каймы).
func _bleed(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for pass_i in 8:
		var src := data.duplicate()
		for y in h:
			for x in w:
				var i := (y * w + x) * 4
				if src[i + 3] > 12 or (src[i] + src[i + 1] + src[i + 2]) > 0:
					continue
				var r := 0
				var g := 0
				var b := 0
				var n := 0
				for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var px := x + dd.x
					var py := y + dd.y
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var j := (py * w + px) * 4
					if src[j + 3] > 12 or (src[j] + src[j + 1] + src[j + 2]) > 0:
						r += src[j]
						g += src[j + 1]
						b += src[j + 2]
						n += 1
				if n > 0:
					data[i] = r / n
					data[i + 1] = g / n
					data[i + 2] = b / n
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
