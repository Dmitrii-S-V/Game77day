extends SceneTree
## Фото-текстура блока из куска картинки: вырезает прямоугольник, делает бесшовной (перекрёстное смешивание краёв),
## пишет <имя>.png, <имя>_n.png (нормаль OpenGL из яркости) и <имя>_r.png (шероховатость) в assets/textures/blocks/.
## -- <картинка> <имя> <x> <y> <w> <h> [нахлёст 0..0.4 = 0.15] [сила нормали = 3] [шероховатость: база = 0.85]
## Пример: godot --headless --path D:\77Days --script res://tools/import_photo_tex.gd -- D:/77Days/assets/src/sheet.webp concrete_tiles_0 0 0 620 620

const OUT := 1024
const DIR := "res://assets/textures/blocks/"


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	var name := a[1]
	var rect := Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	var ov := float(a[6]) if a.size() > 6 else 0.15
	var nstr := float(a[7]) if a.size() > 7 else 3.0
	var rbase := float(a[8]) if a.size() > 8 else 0.85
	var out_dir := a[9] if a.size() > 9 else DIR   # другая папка: res://assets/textures/ (кора, земля)
	var img := src.get_region(rect)
	img = _seamless(img, ov)
	img.resize(OUT, OUT, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(out_dir + name + ".png"))
	# высота — сглаженная яркость (тёмные швы/сколы — ниже)
	var h := img.duplicate() as Image
	h.resize(OUT / 2, OUT / 2, Image.INTERPOLATE_BILINEAR)
	var n := h.get_width()
	var lum := PackedFloat32Array()
	lum.resize(n * n)
	for y in n:
		for x in n:
			lum[y * n + x] = h.get_pixel(x, y).get_luminance()
	var nimg := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rimg := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := lum[y * n + posmod(x + 1, n)] - lum[y * n + posmod(x - 1, n)]
			var dy := lum[posmod(y + 1, n) * n + x] - lum[posmod(y - 1, n) * n + x]
			var nv := Vector3(-dx * nstr, dy * nstr, 1.0).normalized()
			nimg.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
			var r := clampf(rbase + (0.5 - lum[y * n + x]) * 0.2, 0.3, 1.0)
			rimg.set_pixel(x, y, Color(r, r, r))
	nimg.resize(OUT, OUT, Image.INTERPOLATE_BILINEAR)
	nimg.save_png(ProjectSettings.globalize_path(out_dir + name + "_n.png"))
	rimg.save_png(ProjectSettings.globalize_path(out_dir + name + "_r.png"))
	print("photo tex ", name, " from ", rect)
	quit()


## Бесшовность: результат меньше исходника на нахлёст; полоса у края смешивается с участком за противоположным краем.
func _seamless(img: Image, ov: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var ox := int(w * ov)
	var oy := int(h * ov)
	var tw := w - ox
	var th := h - oy
	var t := Image.create(tw, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in tw:
			var c := img.get_pixel(x, y)
			if x < ox:
				var k := smoothstep(0.0, 1.0, float(x) / ox)
				c = img.get_pixel(x + tw, y).lerp(c, k)
			t.set_pixel(x, y, c)
	var o := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	for y in th:
		for x in tw:
			var c2 := t.get_pixel(x, y)
			if y < oy:
				var k2 := smoothstep(0.0, 1.0, float(y) / oy)
				c2 = t.get_pixel(x, y + th).lerp(c2, k2)
			o.set_pixel(x, y, c2)
	return o
