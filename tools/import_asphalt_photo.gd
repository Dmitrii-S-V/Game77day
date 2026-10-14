extends SceneTree
## Импорт своего фото-асфальта (assets/src/asphalt_photo: color, height, gloss, normal, ao — png/webp/jpg)
## в текстуры дороги: road_asphalt.png (цвет * AO), road_asphalt_n.png (нормаль RGB + высота A), road_asphalt_r.png.
## Края делаются бесшовными (если фото не тайлится): перекрёстное смешивание со сдвигом на полразмера.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/import_asphalt_photo.gd [-- size=2048 nodx]

const SRC := "res://assets/src/asphalt_photo/"
const DST := "res://assets/textures/"


func _load(base: String) -> Image:
	for ext in ["png", "jpg", "jpeg", "webp", "tga"]:
		var p := ProjectSettings.globalize_path(SRC + base + "." + ext)
		if FileAccess.file_exists(p):
			var im := Image.load_from_file(p)
			if im != null:
				im.convert(Image.FORMAT_RGBA8)
				print("  ", base, ": ", p.get_file(), " ", im.get_size())
				return im
	print("  ", base, ": нет файла")
	return null


## Насколько шов заметен: средняя разница цвета между краями (тайлинг) против соседних столбцов внутри.
func _seam(im: Image) -> float:
	var w := im.get_width()
	var h := im.get_height()
	var edge := 0.0
	var inner := 0.0
	for y in range(0, h, 4):
		var a := im.get_pixel(w - 1, y)
		var b := im.get_pixel(0, y)
		var c := im.get_pixel(w / 2, y)
		var d := im.get_pixel(w / 2 + 1, y)
		edge += absf(a.get_luminance() - b.get_luminance())
		inner += absf(c.get_luminance() - d.get_luminance())
	return edge / maxf(inner, 1e-4)


## Бесшовность: результат = смесь исходника и его копии, сдвинутой на полразмера, с весом,
## растущим к краям (у краёв видна сдвинутая копия, у которой там середина — швов нет).
func _make_tileable(im: Image, band: float) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var out := Image.create(w, h, false, im.get_format())
	for y in h:
		for x in w:
			var ex := minf(x, w - 1 - x) / (w * band)
			var ey := minf(y, h - 1 - y) / (h * band)
			var t := 1.0 - clampf(minf(ex, ey), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var a := im.get_pixel(x, y)
			var b := im.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			out.set_pixel(x, y, a.lerp(b, t))
	return out


func _init() -> void:
	var size := 2048
	var dx := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			size = int(a.substr(5))
		elif a == "nodx":
			dx = false
	print("Загрузка:")
	var col := _load("color")
	var hgt := _load("height")
	var gloss := _load("gloss")
	var nrm := _load("normal")
	var ao := _load("ao")
	if col == null:
		print("Нет color — выход")
		quit(1)
		return
	var n := col.get_width()
	for im: Image in [hgt, gloss, nrm, ao]:
		if im != null and im.get_size() != col.get_size():
			im.resize(n, col.get_height(), Image.INTERPOLATE_LANCZOS)
	var seam := _seam(col)
	print("шов по цвету (1 = как внутри): %.2f" % seam)
	var fix := seam > 1.6
	if fix:
		print("делаю бесшовным")
		col = _make_tileable(col, 0.18)
		if hgt != null: hgt = _make_tileable(hgt, 0.18)
		if gloss != null: gloss = _make_tileable(gloss, 0.18)
		if ao != null: ao = _make_tileable(ao, 0.18)
		# нормаль: пересчитываем из бесшовной высоты (смешивать готовые нормали некорректно)
		if hgt != null:
			nrm = null
	# нормаль из высоты, если её нет
	if nrm == null and hgt != null:
		nrm = Image.create(n, n, false, Image.FORMAT_RGBA8)
		var k := 3.0
		for y in n:
			for x in n:
				var l := hgt.get_pixel((x - 1 + n) % n, y).r
				var r := hgt.get_pixel((x + 1) % n, y).r
				var u := hgt.get_pixel(x, (y - 1 + n) % n).r
				var d := hgt.get_pixel(x, (y + 1) % n).r
				var v := Vector3((l - r) * k, (d - u) * k, 1.0).normalized()   # OpenGL: +Y вверх по картинке
				nrm.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5, 1.0))
		dx = false
		print("нормаль пересчитана из высоты")
	# цвет * AO (мягко)
	if ao != null:
		for y in n:
			for x in n:
				var c := col.get_pixel(x, y)
				var kk := lerpf(1.0, ao.get_pixel(x, y).r, 0.6)
				col.set_pixel(x, y, Color(c.r * kk, c.g * kk, c.b * kk, 1.0))
	# нормаль: DirectX -> OpenGL (G инвертирован), A = высота
	if nrm != null:
		for y in n:
			for x in n:
				var c2 := nrm.get_pixel(x, y)
				if dx:
					c2.g = 1.0 - c2.g
				c2.a = hgt.get_pixel(x, y).r if hgt != null else 0.5
				nrm.set_pixel(x, y, c2)
	# шероховатость = 1 - блеск (камешки гладкие, битум матовый), в разумном диапазоне
	var rough: Image = null
	if gloss != null:
		rough = Image.create(n, n, false, Image.FORMAT_L8)
		for y in n:
			for x in n:
				rough.set_pixel(x, y, Color.from_hsv(0, 0, lerpf(0.95, 0.6, gloss.get_pixel(x, y).r)))
	for pair in [[col, "road_asphalt"], [nrm, "road_asphalt_n"], [rough, "road_asphalt_r"]]:
		var im2: Image = pair[0]
		if im2 == null:
			continue
		if im2.get_width() != size:
			im2.resize(size, size, Image.INTERPOLATE_LANCZOS)
		im2.save_png(ProjectSettings.globalize_path(DST + String(pair[1]) + ".png"))
		print("сохранено ", pair[1], ".png ", im2.get_size())
	var mf := FileAccess.open(DST + "road_asphalt.photo", FileAccess.WRITE)
	mf.store_string("own photo asphalt - do not overwrite\n")
	# превью 2x2 (проверка швов)
	var pv := col.duplicate() as Image
	pv.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	var m := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	for j in 2:
		for i in 2:
			m.blit_rect(pv, Rect2i(0, 0, 512, 512), Vector2i(i * 512, j * 512))
	m.save_png(ProjectSettings.globalize_path("res://assets/src/asphalt_photo/_tile_preview.png"))
	quit()
