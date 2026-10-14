extends SceneTree
## Текстуры ландшафта из сгенерированных картинок (assets/src/terrain_gen/<имя>.webp, вид сверху):
## бесшовность (смешивание со сдвинутой на полтайла копией по краям), 2048 px, карта нормалей (_n: RGB нормаль из
## яркости, A — высота) и шероховатости (_r). Старые файлы — в assets/src/_backup_textures/.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/make_ground_tex.gd -- grass_a grass_b ...

const SRC := "res://assets/src/terrain_gen/"
const DST := "res://assets/textures/"
const BACKUP := "res://assets/src/_backup_textures/"
const SIZE := 2048
const BLEND := 0.22        # доля тайла у каждого края, где смешивается со сдвинутой копией
const NORMAL_K := 3.0      # сила рельефа
## Углубление теней: тёмные пиксели (линейная яркость ниже SHADOW_PIVOT) умножаются до DEEPEN (у самых тёмных).
const SHADOW_PIVOT := 0.07
const DEEPEN := {"grass_a": 0.4, "grass_b": 0.45, "grass_c": 0.45, "ground_moss": 0.5}
const SAT := 1.0           # насыщенность (>1 даёт «салатовость» — не поднимать)
## Множитель яркости (линейный): тёмные контрастные текстуры (как в 7DTD) лишь слегка светлее, тени остаются тёмными.
const GAIN := {"grass_a": 1.0, "grass_b": 1.05, "grass_c": 1.0, "dirt_a": 1.9, "ground_moss": 1.6, "ground_trampled": 1.3}


func _init() -> void:
	var names := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP))
	for n in names:
		var p := ProjectSettings.globalize_path(SRC + n + ".png")
		if not FileAccess.file_exists(p):
			p = p.get_basename() + ".webp"
		var im := Image.load_from_file(p)
		if im == null:
			print("нет ", p)
			continue
		im.convert(Image.FORMAT_RGBA8)
		var s := mini(im.get_width(), im.get_height())
		im = im.get_region(Rect2i(0, 0, s, s))
		var t := _seamless(im)
		t.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		_grade(t, float(GAIN.get(n, 1.2)), float(DEEPEN.get(n, 1.0)))
		for suf in ["", "_n", "_r"]:
			var f := ProjectSettings.globalize_path(DST + n + suf + ".png")
			var b := ProjectSettings.globalize_path(BACKUP + n + suf + ".png")
			if FileAccess.file_exists(f) and not FileAccess.file_exists(b):
				DirAccess.copy_absolute(f, b)
		t.convert(Image.FORMAT_RGB8)
		t.save_png(ProjectSettings.globalize_path(DST + n + ".png"))
		var maps := _maps(t)
		maps[0].save_png(ProjectSettings.globalize_path(DST + n + "_n.png"))
		maps[1].save_png(ProjectSettings.globalize_path(DST + n + "_r.png"))
		print("готово ", n)
	quit()


## Края тайла — из копии, сдвинутой на половину (у неё шов в середине, а края непрерывны при повторе);
## середина — оригинал. Переход плавный.
func _seamless(im: Image) -> Image:
	var s := im.get_width()
	var h := s / 2
	var sh := Image.create(s, s, false, Image.FORMAT_RGBA8)
	sh.blit_rect(im, Rect2i(h, h, s - h, s - h), Vector2i(0, 0))
	sh.blit_rect(im, Rect2i(0, h, h, s - h), Vector2i(s - h, 0))
	sh.blit_rect(im, Rect2i(h, 0, s - h, h), Vector2i(0, s - h))
	sh.blit_rect(im, Rect2i(0, 0, h, h), Vector2i(s - h, s - h))
	var a := im.get_data()
	var b := sh.get_data()
	var out := PackedByteArray()
	out.resize(a.size())
	var bw := BLEND * s
	for y in s:
		var wy := clampf(minf(y, s - 1 - y) / bw, 0.0, 1.0)
		for x in s:
			var wx := clampf(minf(x, s - 1 - x) / bw, 0.0, 1.0)
			var w := smoothstep(0.0, 1.0, minf(wx, wy))
			var i := (y * s + x) * 4
			for c in 3:
				out[i + c] = int(lerpf(b[i + c], a[i + c], w))
			out[i + 3] = 255
	return Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, out)


## Высота — яркость (тёмные щели ниже, светлые травинки выше), сглаженная; нормаль — по градиенту с повтором.
func _maps(col: Image) -> Array:
	var s := col.get_width()
	var d := col.get_data()
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for i in s * s:
		hgt[i] = (d[i * 3] * 0.3 + d[i * 3 + 1] * 0.59 + d[i * 3 + 2] * 0.11) / 255.0
	# лёгкое размытие (3x3), чтобы рельеф не шумел
	var hb := PackedFloat32Array()
	hb.resize(s * s)
	for y in s:
		for x in s:
			var acc := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					acc += hgt[posmod(y + dy, s) * s + posmod(x + dx, s)]
			hb[y * s + x] = acc / 9.0
	var nd := PackedByteArray()
	nd.resize(s * s * 4)
	var rd := PackedByteArray()
	rd.resize(s * s)
	for y in s:
		for x in s:
			var gx := hb[y * s + posmod(x + 1, s)] - hb[y * s + posmod(x - 1, s)]
			var gy := hb[posmod(y + 1, s) * s + x] - hb[posmod(y - 1, s) * s + x]
			var n := Vector3(-gx * NORMAL_K, -gy * NORMAL_K, 1.0).normalized()
			var i := y * s + x
			nd[i * 4] = int((n.x * 0.5 + 0.5) * 255.0)
			nd[i * 4 + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			nd[i * 4 + 2] = int((n.z * 0.5 + 0.5) * 255.0)
			nd[i * 4 + 3] = int(clampf(hb[i] * 1.6, 0.0, 1.0) * 255.0)
			rd[i] = int(clampf(1.0 - hgt[i] * 0.12, 0.9, 1.0) * 255.0)   # трава и земля матовые (иначе блики неба — серая плёнка)
	return [Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, nd), Image.create_from_data(s, s, false, Image.FORMAT_L8, rd)]


static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _srgb(c: float) -> float:
	c = clampf(c, 0.0, 1.0)
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


## Яркость (линейный множитель k) и насыщенность.
func _grade(img: Image, k: float, deepen: float = 1.0) -> void:
	var s := img.get_width()
	var d := img.get_data()
	var lut := PackedFloat32Array()
	lut.resize(256)
	for i in 256:
		lut[i] = _lin(i / 255.0)
	for i in s * s:
		var r := lut[d[i * 4]] * k
		var g := lut[d[i * 4 + 1]] * k
		var b := lut[d[i * 4 + 2]] * k
		var l := r * 0.2126 + g * 0.7152 + b * 0.0722
		# тёмные участки (щели между травинками) — ещё темнее: контраст как в 7DTD
		var dk := lerpf(deepen, 1.0, smoothstep(0.0, SHADOW_PIVOT, l))
		r *= dk
		g *= dk
		b *= dk
		l *= dk
		d[i * 4] = int(_srgb(l + (r - l) * SAT) * 255.0 + 0.5)
		d[i * 4 + 1] = int(_srgb(l + (g - l) * SAT) * 255.0 + 0.5)
		d[i * 4 + 2] = int(_srgb(l + (b - l) * SAT) * 255.0 + 0.5)
	img.set_data(s, s, false, Image.FORMAT_RGBA8, d)
	print("  яркость ×%.2f" % k)
