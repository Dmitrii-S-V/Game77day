extends SceneTree
## Процедурные текстуры металла для блоков (512x512, бесшовные): ржавый металл (2 варианта), профлист (2 варианта)
## и сетка-рабица (с прозрачностью). Пишет <имя>.png, <имя>_n.png (нормаль OpenGL), <имя>_r.png (шероховатость)
## в assets/textures/blocks/. Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_metal_textures.gd

const N := 512
const DIR := "res://assets/textures/blocks/"


var _photo: Image   # фото-металл assets/textures/metal_rust.png — основа профлиста и первого варианта


func _init() -> void:
	_photo = Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/metal_rust.png"))
	_photo.convert(Image.FORMAT_RGBA8)
	_photo.resize(N, N, Image.INTERPOLATE_LANCZOS)
	# metal_rusty_0 — само фото (копия с картами нормалей и шероховатости), _1 — сильная ржавчина (процедурно)
	for suf in ["", "_n", "_r"]:
		var im := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/metal_rust%s.png" % suf))
		im.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		im.save_png(ProjectSettings.globalize_path(DIR + "metal_rusty_0%s.png" % suf))
	_save("metal_rusty_1", func(u: float, w: float) -> Array: return _rusty(u, w, 137, 0.0))
	for v in 2:
		_save("metal_corrugated_%d" % v, func(u: float, w: float) -> Array: return _corrugated(u, w, 300 + v * 41, v))
	_chainlink()
	print("metal textures done")
	quit()


# --- шум (бесшовный) -------------------------------------------------------------------
func _h(ix: int, iy: int, s: int) -> float:
	var n := ix * 374761393 + iy * 668265263 + s * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


func _vn(x: float, y: float, px: int, py: int, s: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0 := posmod(ix, px)
	var x1 := posmod(ix + 1, px)
	var y0 := posmod(iy, py)
	var y1 := posmod(iy + 1, py)
	return lerpf(lerpf(_h(x0, y0, s), _h(x1, y0, s), fx), lerpf(_h(x0, y1, s), _h(x1, y1, s), fx), fy)


func _fbm(u: float, v: float, f: int, s: int, oct: int = 5) -> float:
	var a := 0.5
	var t := 0.0
	var norm := 0.0
	for o in oct:
		var ff := f << o
		t += _vn(u * ff, v * ff, ff, ff, s + o * 17) * a
		norm += a
		a *= 0.5
	return t / norm


# --- материалы: [цвет, высота 0..1, шероховатость] ---------------------------------------
func _rusty(u: float, v: float, s: int, extra: float) -> Array:
	var base := Color(0.36, 0.35, 0.34)
	var rust_m := _fbm(u, v, 3, s)
	var rust := smoothstep(0.42, 0.62, rust_m + extra)
	var pits := _fbm(u, v, 16, s + 5, 3)
	var streak := _vn(u * 24.0, v * 3.0, 24, 3, s + 9)     # потёки сверху вниз
	var dark := Color(0.27, 0.15, 0.08)
	var orange := Color(0.55, 0.28, 0.12)
	var rc := dark.lerp(orange, _fbm(u, v, 8, s + 2, 3))
	var c := base.lerp(Color(0.46, 0.45, 0.43), _fbm(u, v, 10, s + 3, 3) * 0.6)
	c = c.lerp(rc, clampf(rust + streak * 0.25 * rust, 0.0, 1.0))
	c = c.darkened(pits * 0.18)
	var hgt := 0.5 + (pits - 0.5) * 0.35 * rust + rust * 0.1
	var rough := lerpf(0.45, 0.92, rust)
	return [c, hgt, rough]


func _corrugated(u: float, v: float, s: int, variant: int) -> Array:
	var r: Array = _rusty(u, v, s, -0.12 if variant == 0 else 0.05)
	# волны профлиста: 8 гребней на плитку (по u)
	var wave := 0.5 + 0.5 * sin(u * TAU * 8.0)
	var c: Color = r[0]
	if variant == 0:
		# фото-металл (серый с пятнами ржавчины) + лёгкая синева оцинковки
		c = _photo.get_pixel(int(u * N) % N, int(v * N) % N).lerp(Color(0.5, 0.55, 0.58), 0.15)
		r[2] = 0.6
	c = c.darkened((1.0 - wave) * 0.12)
	return [c, wave * 0.85 + float(r[1]) * 0.15, r[2]]


func _save(name: String, fn: Callable) -> void:
	var col := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var hm := PackedFloat32Array()
	hm.resize(N * N)
	var rough := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var r: Array = fn.call(float(x) / N, float(y) / N)
			col.set_pixel(x, y, r[0])
			hm[y * N + x] = r[1]
			var g: float = r[2]
			rough.set_pixel(x, y, Color(g, g, g))
	col.save_png(ProjectSettings.globalize_path(DIR + name + ".png"))
	rough.save_png(ProjectSettings.globalize_path(DIR + name + "_r.png"))
	_normal(hm, 4.0).save_png(ProjectSettings.globalize_path(DIR + name + "_n.png"))


func _normal(hm: PackedFloat32Array, strength: float) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dx := hm[y * N + posmod(x + 1, N)] - hm[y * N + posmod(x - 1, N)]
			var dy := hm[posmod(y + 1, N) * N + x] - hm[posmod(y - 1, N) * N + x]
			var n := Vector3(-dx * strength, dy * strength, 1.0).normalized()   # OpenGL: +Y вверх
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return img


## Сетка-рабица: ромбы из оцинкованной проволоки, остальное прозрачно (10 ромбов на плитку).
func _chainlink() -> void:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var cells := 10.0
	for y in N:
		for x in N:
			var u := float(x) / N * cells
			var v := float(y) / N * cells
			# две системы диагоналей
			var d1 := absf(fposmod(u + v, 1.0) - 0.5)
			var d2 := absf(fposmod(u - v, 1.0) - 0.5)
			var w := maxf(smoothstep(0.41, 0.46, d1), smoothstep(0.41, 0.46, d2))
			var shade := 0.55 + 0.25 * sin((u + v) * PI * 2.0)
			var rust := _fbm(float(x) / N, float(y) / N, 4, 77, 3)
			var c := Color(shade, shade * 1.02, shade * 1.05).lerp(Color(0.45, 0.27, 0.15), smoothstep(0.55, 0.75, rust) * 0.7)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, w))
	img.save_png(ProjectSettings.globalize_path(DIR + "chainlink.png"))
