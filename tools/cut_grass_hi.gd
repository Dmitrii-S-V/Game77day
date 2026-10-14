extends SceneTree
## Атлас основной травы высокого разрешения: assets/src/flora/grass_hi/tuft_N.webp (по кусту на картинку, прозрачный фон)
## -> assets/textures/grass_tufts_hi.png (4x2 ячейки CELL_W x CELL_H, куст по центру, корнем к нижнему краю).
## Лишние ячейки — зеркальные копии первых кустов. Кайма у краёв травинок: цвет — от соседних непрозрачных пикселей
## (без белого/тёмного ореола в мипмапах); светлая полупрозрачная кайма от фона генератора — затемняется до цвета травинки.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/cut_grass_hi.gd

const SRC_DIR := "res://assets/src/flora/grass_hi/"
const OUT := "res://assets/textures/grass_tufts_hi.png"
const COLS := 4
const ROWS := 2
const CELL_W := 640
const CELL_H := 896
const ALPHA_MIN := 0.08


func _init() -> void:
	var srcs: Array[Image] = []
	for i in range(1, 32):
		var p := ProjectSettings.globalize_path(SRC_DIR + "tuft_%d.webp" % i)
		if not FileAccess.file_exists(p):
			p = p.get_basename() + ".png"
			if not FileAccess.file_exists(p):
				break
		var im := Image.load_from_file(p)
		im.convert(Image.FORMAT_RGBA8)
		srcs.append(_crop(im))
	print("кустов: ", srcs.size())
	var at := Image.create(COLS * CELL_W, ROWS * CELL_H, false, Image.FORMAT_RGBA8)
	at.fill(Color(0, 0, 0, 0))
	for n in COLS * ROWS:
		var img := (srcs[n % srcs.size()].duplicate() as Image)
		if n >= srcs.size():
			img.flip_x()      # повтор — зеркально
		var k := minf(float(CELL_W - 8) / img.get_width(), float(CELL_H - 6) / img.get_height())
		var sw := roundi(img.get_width() * k)
		var sh := roundi(img.get_height() * k)
		img.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
		at.blend_rect(img, Rect2i(0, 0, sw, sh), Vector2i((n % COLS) * CELL_W + (CELL_W - sw) / 2, (n / COLS) * CELL_H + CELL_H - sh))
		print("ячейка %d: %dx%d" % [n, sw, sh])
	_bleed(at)
	at.save_png(OUT)
	print("атлас ", OUT, " ", at.get_size())
	quit()


## Обрезать по содержимому; светлую полупрозрачную кайму — к цвету травинки.
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


## Цвет полупрозрачной каймы травинок — от ближайшего плотного пикселя (у генератора край смешан с тёмным или белым
## фоном: вдали, в мелких мипмапах, такая кайма даёт тёмный/белый контур). Прозрачность сохраняется.
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
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var px := x + d.x
					var py := y + d.y
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


## Цвет прозрачных пикселей — от соседних (без тёмной каймы в мипмапах).
func _bleed(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for pass_i in 8:
		var src := data.duplicate()
		for y in h:
			for x in w:
				var i := (y * w + x) * 4
				if src[i + 3] > 12:
					continue
				var r := 0
				var g := 0
				var b := 0
				var n := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var px := x + d.x
					var py := y + d.y
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var j := (py * w + px) * 4
					if src[j + 3] > 12 or (src[j] + src[j + 1] + src[j + 2]) > 0:
						r += src[j]
						g += src[j + 1]
						b += src[j + 2]
						n += 1
				if n > 0 and (src[i] + src[i + 1] + src[i + 2]) == 0:
					data[i] = r / n
					data[i + 1] = g / n
					data[i + 2] = b / n
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
