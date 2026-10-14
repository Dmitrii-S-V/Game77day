extends SceneTree
## Нарезка текстур из исходных листов (assets/source/*.webp) в игровые ассеты.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/prepare_textures.gd
## Выход: assets/textures/*.png, assets/textures/road_decals.png (атлас 4x4 декалей с альфой),
## shots/crops_*.png — контрольные листы для проверки координат.

const OUT := "res://assets/textures/"

# (имя, лист, x, y, w, h, режим[, размер_выхода])  режимы: seamless | plain
const CROPS := [
	["road_asphalt", "roads", 1308, 26, 218, 222, "seamless", 512],
	["road_asphalt_rough", "roads", 1092, 472, 180, 114, "seamless", 512],
	["road_dirt", "roads", 1000, 826, 228, 140, "seamless", 512],
	["sidewalk_slab", "roads", 526, 630, 80, 70, "seamless", 512],
	["sidewalk_brick", "roads", 814, 624, 98, 160, "seamless", 512],
	["road_concrete", "roads", 526, 708, 80, 70, "seamless", 512],
	["sidewalk_brick_2", "roads", 818, 628, 90, 150, "seamless", 512],
	["road_markings_a", "roads", 996, 26, 150, 224, "plain", 512],
	["wood_planks", "props", 252, 40, 150, 112, "seamless", 512],
	["metal_clean", "props", 774, 50, 96, 92, "seamless", 512],
	["metal_rust", "props", 1246, 46, 122, 100, "seamless", 512],
	["bark", "props", 1358, 414, 70, 96, "seamless", 512],
]

# декали с альфой (белый фон -> прозрачность): (x, y, w, h)
const DECALS := [
	[10, 4, 160, 168],     # 0 сеть трещин
	[496, 128, 78, 126],   # 1 дерево трещин
	[148, 176, 98, 140],   # 2 стёртая разметка / дорога
	[200, 8, 222, 170],    # 3 яма с обломками
	[440, 14, 112, 112],   # 4 яма круглая
	[248, 194, 164, 152],  # 5 яма с грязью
	[4, 204, 134, 108],    # 6 вскрытый асфальт 1
	[4, 318, 184, 110],    # 7 вскрытый асфальт 2
	[434, 402, 178, 146],  # 8 вскрытый асфальт 3
	[642, 428, 184, 120],  # 9 вскрытый асфальт 4
	[640, 196, 72, 118],   # 10 пятно масла
	[696, 104, 98, 62],    # 11 пятно 2
	[694, 148, 144, 160],  # 12 следы шин
	[330, 340, 226, 60],   # 13 стёртая поперечная разметка
	[436, 206, 58, 54],    # 14 люк
	[698, 344, 96, 74],    # 15 решётка
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var sheets := {}
	for n in ["roads", "props", "decals"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/source/%s.webp" % n))
		img.convert(Image.FORMAT_RGBA8)
		sheets[n] = img
	var thumbs: Array[Image] = []
	for c in CROPS:
		var src: Image = sheets[c[1]]
		var crop := src.get_region(Rect2i(c[2], c[3], c[4], c[5]))
		var size: int = c[7]
		crop.resize(size, size, Image.INTERPOLATE_LANCZOS)
		if c[6] == "seamless":
			crop = _seamless(crop)
			crop = _unsharp(crop, 2, 0.6)
		if not _photo(c[0]):
			crop.save_png(ProjectSettings.globalize_path(OUT + c[0] + ".png"))
		var t := crop.duplicate() as Image
		t.resize(200, 200)
		thumbs.append(t)
	_sheet(thumbs, 6, "res://shots/crops_textures.png")

	# атлас декалей 4x4 по 512
	var atlas := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var dthumbs: Array[Image] = []
	for i in DECALS.size():
		var d: Array = DECALS[i]
		var crop := (sheets["decals"] as Image).get_region(Rect2i(d[0], d[1], d[2], d[3]))
		var scale := minf(500.0 / crop.get_width(), 500.0 / crop.get_height())
		crop.resize(int(crop.get_width() * scale), int(crop.get_height() * scale), Image.INTERPOLATE_LANCZOS)
		var cell := Vector2i((i % 4) * 512, (i / 4) * 512)
		var off := Vector2i((512 - crop.get_width()) / 2, (512 - crop.get_height()) / 2)
		for yy in crop.get_height():
			for xx in crop.get_width():
				var pc := crop.get_pixel(xx, yy)
				if pc.a > 0.0:
					atlas.set_pixel(cell.x + off.x + xx, cell.y + off.y + yy, pc)
		var t := crop.duplicate() as Image
		t.resize(200, 200 * crop.get_height() / maxi(crop.get_width(), 1))
		dthumbs.append(t)
	_foliage()
	_grass()
	_sedge()
	_normals()
	atlas.save_png(ProjectSettings.globalize_path(OUT + "road_decals.png"))
	# контрольный лист на сером фоне
	var prev := atlas.duplicate() as Image
	prev.resize(1024, 1024)
	var bg := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.35, 0.35, 0.37, 1))
	bg.blend_rect(prev, Rect2i(0, 0, 1024, 1024), Vector2i.ZERO)
	bg.save_png(ProjectSettings.globalize_path("res://shots/crops_decals.png"))
	print("done")
	quit()


## Лист листвы (3 блока 4x2: лиственные / хвоя / сухие) -> атласы карточек 2048x768 с альфой.
## Ячейка 512x384; ветка растягивается на всю ячейку (квад в игре имеет пропорции 4:3).
## Текстура импортирована через tools/import_pbr.gd (dir=terrain): маркер <имя>.photo рядом — не перезаписывать.
func _photo(tex_name: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(OUT + tex_name + ".photo"))


func _foliage() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/source/foliage.webp"))
	sheet.convert(Image.FORMAT_RGBA8)
	var w := sheet.get_width()
	var h := sheet.get_height()
	print("foliage sheet ", w, "x", h)
	var names := ["foliage_leaf", "foliage_pine", "foliage_dry"]
	var y0 := [0.0, 0.340, 0.660]
	var y1 := [0.338, 0.656, 1.0]
	var prev := Image.create(2048, 768 * 3, false, Image.FORMAT_RGBA8)
	prev.fill(Color(0.3, 0.45, 0.6, 1))
	for g in 3:
		var atlas := Image.create(2048, 768, false, Image.FORMAT_RGBA8)
		atlas.fill(Color(0, 0, 0, 0))
		var by := int(y0[g] * h)
		var bh := int((y1[g] - y0[g]) * h)
		for i in 8:
			var cw := w / 4
			var ch := bh / 2
			var rect := Rect2i((i % 4) * cw + 4, by + (i / 4) * ch + 3, cw - 8, ch - 6)
			var crop := sheet.get_region(rect)
			crop.resize(512, 384, Image.INTERPOLATE_LANCZOS)
			var al := PackedFloat32Array()
			al.resize(512 * 384)
			for yy in 384:
				for xx in 512:
					var c := crop.get_pixel(xx, yy)
					var d := 1.0 - minf(c.r, minf(c.g, c.b))
					al[xx + 512 * yy] = smoothstep(0.10, 0.28, d)
			# граница: эрозия маски на 1 пиксель (убирает светлую окантовку от смешения с белым фоном),
			# цвет у границы уводим в тёмный цвет листвы
			var a1 := al if g == 1 else _min_filter(al, 512, 384, 1)   # хвоя тонкая — без эрозии
			var a2 := _min_filter(al, 512, 384, 1 if g == 1 else 3)
			for yy in 384:
				for xx in 512:
					var pi := xx + 512 * yy
					var a := a1[pi]
					var c := crop.get_pixel(xx, yy)
					if a < 0.02:
						crop.set_pixel(xx, yy, Color(0.12, 0.2, 0.08, 0.0))
					else:
						var mixk := smoothstep(0.2, 0.95, a2[pi])
						var edge := Color(0.10, 0.15, 0.06)
						crop.set_pixel(xx, yy, Color(lerpf(edge.r, c.r, mixk), lerpf(edge.g, c.g, mixk), lerpf(edge.b, c.b, mixk), a))
			atlas.blit_rect(crop, Rect2i(0, 0, 512, 384), Vector2i((i % 4) * 512, (i / 4) * 384))
		atlas.save_png(ProjectSettings.globalize_path(OUT + names[g] + ".png"))
		prev.blend_rect(atlas, Rect2i(0, 0, 2048, 768), Vector2i(0, g * 768))
	prev.resize(1024, 1152)
	prev.save_png(ProjectSettings.globalize_path("res://shots/crops_foliage.png"))


## Лист осоки (2 ряда по 4 куста на белом) -> атлас 2048x2048 (ячейки 512x1024, корень внизу по центру).
## Границы кустов ищем по занятости столбцов (кусты слегка выходят за равные ячейки).
func _sedge() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/source/sedge.webp"))
	sheet.convert(Image.FORMAT_RGBA8)
	var w := sheet.get_width()
	var h := sheet.get_height()
	var atlas := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.3, 0.25, 0.12, 0.0))
	for row in 2:
		var y0 := row * h / 2
		var y1 := y0 + h / 2
		var occ := PackedByteArray()
		occ.resize(w)
		for x in w:
			var cnt := 0
			for y in range(y0, y1):
				var c := sheet.get_pixel(x, y)
				if minf(c.r, minf(c.g, c.b)) < 0.72:
					cnt += 1
					if cnt >= 3:
						occ[x] = 1
						break
		# сливаем пробелы короче 10 px
		var runs: Array = []
		var start := -1
		var gap := 0
		for x in w:
			if occ[x] == 1:
				if start < 0:
					start = x
				gap = 0
			elif start >= 0:
				gap += 1
				if gap > 6:
					runs.append([start, x - gap])
					start = -1
		if start >= 0:
			runs.append([start, w - 1 - gap])
		while runs.size() > 4:
			var bi := 0
			var bg := 1 << 30
			for q in runs.size() - 1:
				var gp: int = runs[q + 1][0] - runs[q][1]
				if gp < bg:
					bg = gp
					bi = q
			runs[bi] = [runs[bi][0], runs[bi + 1][1]]
			runs.remove_at(bi + 1)
		print("sedge row ", row, " runs ", runs.size())
		for i in mini(runs.size(), 4):
			var xa: int = maxi(runs[i][0] - 3, 0)
			var xb: int = mini(runs[i][1] + 3, w - 1)
			var ya := y1
			var yb := y0
			for y in range(y0, y1):
				for x in range(xa, xb, 2):
					var c := sheet.get_pixel(x, y)
					if minf(c.r, minf(c.g, c.b)) < 0.82:
						ya = mini(ya, y)
						yb = maxi(yb, y)
						break
			var crop := sheet.get_region(Rect2i(xa, maxi(ya - 3, 0), xb - xa + 1, mini(yb - ya + 7, h - ya)))
			var s := minf(500.0 / crop.get_width(), 1010.0 / crop.get_height())
			crop.resize(int(crop.get_width() * s), int(crop.get_height() * s), Image.INTERPOLATE_LANCZOS)
			for yy in crop.get_height():
				for xx in crop.get_width():
					var c := crop.get_pixel(xx, yy)
					var a := smoothstep(0.08, 0.3, 1.0 - minf(c.r, minf(c.g, c.b)))
					if a < 0.02:
						crop.set_pixel(xx, yy, Color(0.3, 0.25, 0.12, 0.0))
					else:
						var mixk := smoothstep(0.3, 0.85, a)
						var edge := Color(0.28, 0.22, 0.1)
						var k := 1.0 - a
						var r := clampf((c.r - k) / a, 0.0, 1.0)
						var g := clampf((c.g - k) / a, 0.0, 1.0)
						var b := clampf((c.b - k) / a, 0.0, 1.0)
						crop.set_pixel(xx, yy, Color(lerpf(edge.r, r, mixk), lerpf(edge.g, g, mixk), lerpf(edge.b, b, mixk), a))
			var cell := Vector2i(i * 512, row * 1024)
			var off := Vector2i((512 - crop.get_width()) / 2, 1024 - crop.get_height() - 4)
			atlas.blit_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()), cell + off)
	atlas.save_png(ProjectSettings.globalize_path(OUT + "sedge.png"))
	var prev := atlas.duplicate() as Image
	prev.resize(1024, 1024)
	var bg := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.3, 0.5, 0.7, 1))
	bg.blend_rect(prev, Rect2i(0, 0, 1024, 1024), Vector2i.ZERO)
	bg.save_png(ProjectSettings.globalize_path("res://shots/crops_sedge.png"))


## Лист 2x2 (трава / сухая трава / земля с травой / высокая трава) -> 1024x1024 текстуры ландшафта.
## Стыковка краёв только в узкой полосе у границы, чтобы не терять детали в центре.
func _grass() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/source/grass.webp"))
	sheet.convert(Image.FORMAT_RGBA8)
	var h := sheet.get_width() / 2
	var names := {0: "grass_a", 1: "grass_c", 2: "dirt_a", 3: "grass_b"}
	for q in 4:
		var crop := sheet.get_region(Rect2i((q % 2) * h, (q / 2) * h, h, h))
		crop.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		crop = _seamless_band(crop, 0.16)
		crop = _unsharp(crop, 3, 0.8)
		if not _photo(names[q]):
			crop.save_png(ProjectSettings.globalize_path(OUT + names[q] + ".png"))


func _seamless_band(img: Image, band: float) -> Image:
	var w := img.get_width()
	var hh := img.get_height()
	var out := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	for y in hh:
		var wy := smoothstep(0.0, band, minf(float(y), float(hh - 1 - y)) / hh)
		for x in w:
			var wx := smoothstep(0.0, band, minf(float(x), float(w - 1 - x)) / w)
			var a := img.get_pixel(x, y)
			var b := img.get_pixel((x + w / 2) % w, (y + hh / 2) % hh)
			out.set_pixel(x, y, b.lerp(a, wx * wy))
	return out


## Размытие в окне (2r+1) по кругу (тайлится), по одной плоскости float.
func _blur_wrap(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var inv := 1.0 / float(2 * r + 1)
	for y in h:
		var row := y * w
		var s := 0.0
		for k in range(-r, r + 1):
			s += src[row + posmod(k, w)]
		for x in w:
			tmp[row + x] = s * inv
			s += src[row + posmod(x + r + 1, w)] - src[row + posmod(x - r, w)]
	var out := PackedFloat32Array()
	out.resize(w * h)
	for x in w:
		var s := 0.0
		for k in range(-r, r + 1):
			s += tmp[posmod(k, h) * w + x]
		for y in h:
			out[y * w + x] = s * inv
			s += tmp[posmod(y + r + 1, h) * w + x] - tmp[posmod(y - r, h) * w + x]
	return out


## Нерезкая маска: повышает чёткость и локальный контраст (цвет по каналам, альфа не трогаем).
func _unsharp(img: Image, r: int, amount: float) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var out := data.duplicate()
	for c in 3:
		var pl := PackedFloat32Array()
		pl.resize(w * h)
		for i in w * h:
			pl[i] = data[i * 4 + c]
		var bl := _blur_wrap(pl, w, h, r)
		for i in w * h:
			out[i * 4 + c] = int(clampf(pl[i] + (pl[i] - bl[i]) * amount, 0.0, 255.0))
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## Карты нормалей (RGB) и высоты (A) из яркости: <имя>_n.png. Высота — высокие частоты яркости.
const NORMAL_LIST := [["grass_a", 5.0], ["grass_b", 5.0], ["grass_c", 5.0], ["dirt_a", 6.0],
	["road_asphalt", 5.0], ["road_asphalt_rough", 6.0], ["road_dirt", 5.0], ["sidewalk_slab", 4.0],
	["road_concrete", 3.0], ["terrain_stone", 6.0], ["terrain_sand", 3.0], ["terrain_gravel", 6.0]]


func _normals() -> void:
	for e in NORMAL_LIST:
		if _photo(e[0]):
			continue   # фотореалистичный импорт: нормали настоящие, не пересчитываем
		var img := Image.load_from_file(ProjectSettings.globalize_path(OUT + e[0] + ".png"))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data := img.get_data()
		var lum := PackedFloat32Array()
		lum.resize(w * h)
		for i in w * h:
			lum[i] = (data[i * 4] * 0.3 + data[i * 4 + 1] * 0.59 + data[i * 4 + 2] * 0.11) / 255.0
		var bl := _blur_wrap(lum, w, h, maxi(w / 24, 4))
		var ht := PackedFloat32Array()
		ht.resize(w * h)
		for i in w * h:
			ht[i] = clampf(0.5 + (lum[i] - bl[i]) * 2.2, 0.0, 1.0)
		var s: float = float(e[1]) * w / 512.0
		var out := PackedByteArray()
		out.resize(w * h * 4)
		for y in h:
			for x in w:
				var dx := ht[y * w + posmod(x + 1, w)] - ht[y * w + posmod(x - 1, w)]
				var dy := ht[posmod(y + 1, h) * w + x] - ht[posmod(y - 1, h) * w + x]
				var inv := 1.0 / sqrt(dx * dx * s * s + dy * dy * s * s + 1.0)
				var i := (y * w + x) * 4
				out[i] = int(clampf((-dx * s * inv) * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				out[i + 1] = int(clampf((-dy * s * inv) * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				out[i + 2] = int(clampf(inv * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				out[i + 3] = int(ht[y * w + x] * 255.0)
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out).save_png(ProjectSettings.globalize_path(OUT + e[0] + "_n.png"))


## Минимум в окне (2r+1)^2, разделимо.
func _min_filter(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:
		for x in w:
			var m := 1.0
			for dx in range(maxi(x - r, 0), mini(x + r, w - 1) + 1):
				m = minf(m, src[dx + w * y])
			tmp[x + w * y] = m
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var m := 1.0
			for dy in range(maxi(y - r, 0), mini(y + r, h - 1) + 1):
				m = minf(m, tmp[x + w * dy])
			out[x + w * y] = m
	return out


## Белый фон -> прозрачность по яркости; цвет оставляем как есть (без пересчёта, чтобы не было каймы).
func _key_white(img: Image) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var mn := minf(c.r, minf(c.g, c.b))
			var a := clampf((0.9 - lum) / 0.3, 0.0, 1.0)
			a = maxf(a, clampf((0.8 - mn) * 4.0, 0.0, 1.0))
			var k := lerpf(0.55, 1.0, a)   # края затемняем, чтобы не светились
			out.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, a))
	return out

## Бесшовность: перекрёстное смешивание со сдвинутой на половину копией.
func _seamless(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / h
		var wy := 1.0 - absf(v * 2.0 - 1.0)   # 0 на краях, 1 в центре
		wy = smoothstep(0.0, 0.5, wy)
		for x in w:
			var u := float(x) / w
			var wx := smoothstep(0.0, 0.5, 1.0 - absf(u * 2.0 - 1.0))
			var wgt := wx * wy
			var a := img.get_pixel(x, y)
			var b := img.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			out.set_pixel(x, y, b.lerp(a, wgt))
	return out


func _sheet(thumbs: Array[Image], cols: int, path: String) -> void:
	var rows := ceili(thumbs.size() / float(cols))
	var sheet := Image.create(cols * 204, rows * 204, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1, 1))
	for i in thumbs.size():
		sheet.blend_rect(thumbs[i], Rect2i(0, 0, thumbs[i].get_width(), thumbs[i].get_height()), Vector2i((i % cols) * 204 + 2, (i / cols) * 204 + 2))
	sheet.save_png(ProjectSettings.globalize_path(path))
