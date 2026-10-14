class_name BlockTexGen
extends RefCounted
## Процедурные заглушки текстур блоков (128x128, бесшовные). Позже заменяются файлами
## assets/textures/blocks/<имя>.png (например из ComfyUI): имя то же, код менять не нужно.
## Запись заглушек на диск: tools/gen_block_textures.gd.

const S := 128


static func make(tex_name: String) -> Image:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var seed_v := absi(tex_name.hash()) % 100000
	var variant := 0
	var base := tex_name
	var us := tex_name.rfind("_")
	if us > 0 and tex_name.substr(us + 1).is_valid_int():
		variant = tex_name.substr(us + 1).to_int()
		base = tex_name.substr(0, us)
	match base:
		"frame": _frame(img, seed_v)
		"planks_fresh": _planks(img, seed_v, variant, 0)
		"planks_worn": _planks(img, seed_v, variant, 1)
		"planks_rotten": _planks(img, seed_v, variant, 2)
		"planks_dying": _planks(img, seed_v, variant, 3)
		"concrete_smooth": _concrete(img, seed_v, variant, 0)
		"concrete_cracked": _concrete(img, seed_v, variant, 1)
		"concrete_reinforced": _concrete(img, seed_v, variant, 2)
		"concrete_dirty": _concrete(img, seed_v, variant, 3)
		"door_wood": _door(img, seed_v, variant, false)
		"door_boarded": _door(img, seed_v, variant, true)
		"window_frame": _window_frame(img, seed_v, variant)
		"window_boarded", "boards": _boards(img, seed_v, variant)
		"web": _web(img, seed_v, variant)
		"brass": _metal(img, seed_v)
		"wax": _wax(img, seed_v)
		"carpet": _carpet(img, seed_v, variant)
		"flame": _flame(img)
		"glass_shard": _shard(img, seed_v)
		_: img.fill(Color(0.8, 0.2, 0.8))
	return img


# --- шум с периодом (бесшовный) -----------------------------------------------------

static func _h(ix: int, iy: int, s: int) -> float:
	var n := ix * 374761393 + iy * 668265263 + s * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


static func _vn(x: float, y: float, per_x: int, per_y: int, s: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0 := posmod(ix, per_x)
	var x1 := posmod(ix + 1, per_x)
	var y0 := posmod(iy, per_y)
	var y1 := posmod(iy + 1, per_y)
	return lerpf(lerpf(_h(x0, y0, s), _h(x1, y0, s), fx), lerpf(_h(x0, y1, s), _h(x1, y1, s), fx), fy)


## fbm по uv 0..1, базовая частота f (целая), 3 октавы.
static func _fbm(u: float, v: float, f: int, s: int) -> float:
	return _vn(u * f, v * f, f, f, s) * 0.55 + _vn(u * f * 2, v * f * 2, f * 2, f * 2, s + 11) * 0.3 + _vn(u * f * 4, v * f * 4, f * 4, f * 4, s + 23) * 0.15


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, S), posmod(y, S), c)


# --- дерево ---------------------------------------------------------------------------

static func _frame(img: Image, s: int) -> void:
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var g := _vn(u * 3, v * 40, 3, 40, s) * 0.5 + _fbm(u, v, 6, s + 3) * 0.5
			var c := Color(0.55, 0.40, 0.24).lerp(Color(0.42, 0.29, 0.16), g)
			img.set_pixel(x, y, c)


## level: 0 свежие, 1 потрёпанные, 2 гнилые, 3 почти сгнившие.
static func _planks(img: Image, s: int, variant: int, level: int) -> void:
	var rows: int = [4, 3, 5][variant % 3]
	var vertical := variant == 1
	var base_cols := [Color(0.66, 0.48, 0.28), Color(0.52, 0.39, 0.26), Color(0.38, 0.31, 0.21), Color(0.30, 0.27, 0.21)]
	var dark_cols := [Color(0.5, 0.34, 0.18), Color(0.38, 0.28, 0.17), Color(0.26, 0.2, 0.13), Color(0.2, 0.18, 0.14)]
	var moss := Color(0.22, 0.32, 0.14)
	var crack_n: int = [0, 2, 5, 9][level]
	var cracks := PackedInt32Array()
	var rr := RandomNumberGenerator.new()
	rr.seed = s
	for i in crack_n:
		cracks.append(rr.randi_range(0, S - 1))
		cracks.append(rr.randi_range(0, S - 1))
		cracks.append(rr.randi_range(10, 38))
	for y in S:
		for x in S:
			var a := x if not vertical else y
			var b := y if not vertical else x
			var plank := b * rows / S
			var pf := float(b * rows % S) / S
			var u := float(x) / S
			var v := float(y) / S
			var ph := _h(plank, 0, s)
			var g := _vn(float(a) / S * 2.0, float(b) / S * 36.0, 2, 36, s + plank) * 0.6 + _fbm(u, v, 5, s + 7) * 0.4
			var c: Color = (base_cols[level] as Color).lerp(dark_cols[level], clampf(g * 0.9 + ph * 0.3 - 0.1, 0.0, 1.0))
			# швы между досками
			var edge := minf(pf, 1.0 - pf) * rows * 0.5
			if edge < 0.04:
				c = c.darkened(0.5)
			elif edge < 0.09:
				c = c.darkened(0.2)
			# торцы (стыки по длине)
			var joint := posmod(a + int(ph * S), S)
			if joint < 2:
				c = c.darkened(0.45)
			if level >= 1:
				c = c.darkened(_fbm(u, v, 3, s + 31) * 0.25 * level)
			if level >= 2:
				var m := _fbm(u, v, 4, s + 41)
				if m > 0.55:
					c = c.lerp(moss, clampf((m - 0.55) * 4.0, 0.0, 0.7))
			if level >= 3:
				var hole := _fbm(u, v, 6, s + 51)
				if hole > 0.66:
					c = c.lerp(Color(0.06, 0.05, 0.04), clampf((hole - 0.66) * 9.0, 0.0, 1.0))
			img.set_pixel(x, y, c)
	for i in crack_n:
		var cx: int = cracks[i * 3]
		var cy: int = cracks[i * 3 + 1]
		var ln: int = cracks[i * 3 + 2]
		for k in ln:
			var px := cx + (k if not vertical else int(sin(k * 0.7) * 2.0))
			var py := cy + (int(sin(k * 0.7) * 2.0) if not vertical else k)
			_px(img, px, py, Color(0.08, 0.06, 0.04))


static func _boards(img: Image, s: int, variant: int) -> void:
	_planks(img, s, 0, 2)
	# гвозди на концах досок
	for r in 4:
		var y := r * 32 + 16
		for x in [8, S - 9]:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					_px(img, x + dx, y + dy, Color(0.25, 0.24, 0.22))


# --- бетон ----------------------------------------------------------------------------

static func _concrete(img: Image, s: int, variant: int, kind: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = s
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var g := _fbm(u, v, 4, s) * 0.5 + _vn(u * 64, v * 64, 64, 64, s + 5) * 0.25 + _fbm(u, v, 12, s + 9) * 0.25
			var base := 0.58 + variant * 0.04
			var c := Color(base, base, base * 0.98) * (0.78 + g * 0.45)
			c.a = 1.0
			if kind == 3:
				var st := _vn(u * 6, v * 2, 6, 2, s + 13)
				c = c.lerp(Color(0.22, 0.2, 0.17), clampf((st - 0.45) * 1.6, 0.0, 0.8) * (0.6 + 0.4 * v))
				c = c.darkened(_fbm(u, v, 3, s + 17) * 0.25)
			img.set_pixel(x, y, c)
	if kind == 0 or kind == 1 or kind == 3:
		# стыки панелей
		for i in S:
			_px(img, i, 0, (img.get_pixel(i, 0) as Color).darkened(0.35))
			_px(img, 0, i, (img.get_pixel(0, i) as Color).darkened(0.35))
	if kind == 1 or kind == 3:
		var n := 5 if kind == 1 else 2
		for i in n:
			var x := rr.randf_range(8, 120)
			var y := rr.randf_range(8, 120)
			var ang := rr.randf() * TAU
			for k in rr.randi_range(30, 70):
				ang += rr.randf_range(-0.5, 0.5)
				x += cos(ang)
				y += sin(ang)
				_px(img, int(x), int(y), Color(0.12, 0.12, 0.12))
				if k % 3 == 0:
					_px(img, int(x) + 1, int(y), Color(0.2, 0.2, 0.2))
	if kind == 2:
		# армирование: сетка арматуры под ржавыми разводами и болты
		for g in [0, 32, 64, 96]:
			for i in S:
				_px(img, i, g + 16, (img.get_pixel(i, posmod(g + 16, S)) as Color).lerp(Color(0.45, 0.25, 0.14), 0.55))
				_px(img, g + 16, i, (img.get_pixel(posmod(g + 16, S), i) as Color).lerp(Color(0.45, 0.25, 0.14), 0.55))
		for gx in [16, 48, 80, 112]:
			for gy in [16, 48, 80, 112]:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if dx * dx + dy * dy <= 5:
							_px(img, gx + dx, gy + dy, Color(0.3, 0.3, 0.32))


# --- двери и окна -------------------------------------------------------------------

static func _door(img: Image, s: int, variant: int, boarded: bool) -> void:
	var cols := [Color(0.5, 0.33, 0.18), Color(0.34, 0.27, 0.2)]
	var base: Color = cols[variant % 2]
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var plank := x * 5 / S
			var pf := float(x * 5 % S) / S
			var g := _vn(u * 30, v * 3, 30, 3, s + plank) * 0.5 + _fbm(u, v, 5, s + 3) * 0.5
			var c := base.lerp(base.darkened(0.45), g)
			if minf(pf, 1.0 - pf) < 0.04:
				c = c.darkened(0.5)
			# филёнки
			var inset := minf(minf(x, S - 1 - x), minf(y, S - 1 - y))
			if inset > 12 and inset < 16:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	# ручка
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx * dx + dy * dy <= 9:
				_px(img, 106 + dx, 64 + dy, Color(0.78, 0.62, 0.22))
	if boarded:
		for r in 3:
			var y0 := 18 + r * 40 + (variant * 6)
			for y in range(y0, y0 + 22):
				for x in S:
					var u := float(x) / S
					var g := _vn(u * 2.0, float(y) / S * 30.0, 2, 30, s + 70 + r)
					var c := Color(0.36, 0.3, 0.2).lerp(Color(0.24, 0.2, 0.14), g)
					if y < y0 + 2 or y > y0 + 19:
						c = c.darkened(0.5)
					_px(img, x, y, c)
			for nx in [8, 64, 120]:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						_px(img, nx + dx, y0 + 11 + dy, Color(0.2, 0.2, 0.2))


static func _window_frame(img: Image, s: int, variant: int) -> void:
	var base := Color(0.82, 0.8, 0.74) if variant == 0 else Color(0.36, 0.25, 0.15)
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var g := _fbm(u, v, 6, s) * 0.5 + _vn(u * 4, v * 48, 4, 48, s + 5) * 0.5
			var c := base.lerp(base.darkened(0.35), g)
			if variant == 0:
				# облупившаяся краска
				var flake := _fbm(u, v, 9, s + 9)
				if flake > 0.62:
					c = c.lerp(Color(0.4, 0.3, 0.2), clampf((flake - 0.62) * 6.0, 0.0, 0.9))
			img.set_pixel(x, y, c)


# --- декор ----------------------------------------------------------------------------

static func _web(img: Image, s: int, variant: int) -> void:
	img.fill(Color(0.9, 0.9, 0.9, 0.0))
	var rr := RandomNumberGenerator.new()
	rr.seed = s
	var cx := 8.0 if variant == 0 else 64.0
	var cy := 8.0 if variant == 0 else 120.0
	var spokes := 9 + variant * 2
	var rings := 7
	var base_ang := 0.1 + variant * 0.4
	for sp in spokes:
		var a := base_ang + float(sp) / spokes * (PI * 0.5 if variant == 0 else PI)
		if variant == 1:
			a = base_ang + float(sp) / (spokes - 1) * PI - PI
		for r in range(0, 175):
			_dot(img, int(cx + cos(a) * r), int(cy + sin(a) * r), 0.8)
	for ring in range(1, rings + 1):
		var rad := ring * 20.0
		for sp in spokes - 1:
			var a0 := base_ang + float(sp) / spokes * (PI * 0.5 if variant == 0 else PI) if variant == 0 else base_ang + float(sp) / (spokes - 1) * PI - PI
			var a1 := base_ang + float(sp + 1) / spokes * (PI * 0.5 if variant == 0 else PI) if variant == 0 else base_ang + float(sp + 1) / (spokes - 1) * PI - PI
			var p0 := Vector2(cx + cos(a0) * rad, cy + sin(a0) * rad)
			var p1 := Vector2(cx + cos(a1) * rad, cy + sin(a1) * rad)
			var mid := (p0 + p1) * 0.5
			mid = mid.lerp(Vector2(cx, cy), 0.12)   # провисание нитей
			for k in 24:
				var t := float(k) / 23.0
				var q := p0.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(p1, (t - 0.5) * 2.0)
				_dot(img, int(q.x), int(q.y), 0.6)


static func _dot(img: Image, x: int, y: int, a: float) -> void:
	if x < 0 or y < 0 or x >= S or y >= S:
		return
	var c := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(0.92, 0.92, 0.9, maxf(c.a, a)))


static func _metal(img: Image, s: int) -> void:
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var g := _fbm(u, v, 6, s) * 0.6 + _vn(u * 2, v * 40, 2, 40, s + 3) * 0.4
			img.set_pixel(x, y, Color(0.55, 0.42, 0.18).lerp(Color(0.85, 0.7, 0.3), g))


static func _wax(img: Image, s: int) -> void:
	for y in S:
		for x in S:
			var g := _fbm(float(x) / S, float(y) / S, 4, s)
			img.set_pixel(x, y, Color(0.9, 0.86, 0.7).lerp(Color(0.78, 0.72, 0.55), g))


static func _carpet(img: Image, s: int, variant: int) -> void:
	var cols := [[Color(0.55, 0.12, 0.12), Color(0.85, 0.7, 0.35)], [Color(0.15, 0.3, 0.2), Color(0.75, 0.75, 0.6)], [Color(0.36, 0.26, 0.18), Color(0.6, 0.5, 0.36)]]
	var a: Color = cols[variant % 3][0]
	var b: Color = cols[variant % 3][1]
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var fiber := _vn(u * 90, v * 90, 90, 90, s) * 0.3 + _fbm(u, v, 5, s + 4) * 0.3
			var c := a.lerp(a.darkened(0.4), fiber)
			var edge := minf(minf(x, S - 1 - x), minf(y, S - 1 - y))
			if edge >= 6 and edge < 12:
				c = b.lerp(b.darkened(0.3), fiber)
			elif edge >= 20 and edge < 23:
				c = b.darkened(0.2)
			# орнамент ромбами в центре
			var dx := absf(float(x) - 64.0)
			var dy := absf(float(y) - 64.0)
			if dx + dy < 26 and int(dx + dy) % 9 < 3:
				c = b.lerp(c, 0.35)
			img.set_pixel(x, y, c)


static func _flame(img: Image) -> void:
	for y in S:
		for x in S:
			var dx := (float(x) - 64.0) / 36.0
			var dy := (float(y) - 74.0) / 56.0
			var d := sqrt(dx * dx + dy * dy * (1.0 if dy > 0 else 0.6))
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.55 + 0.4 * a, 0.15 + 0.5 * a * a, 1.0 if a > 0.15 else 0.0))


static func _shard(img: Image, s: int) -> void:
	for y in S:
		for x in S:
			var g := _fbm(float(x) / S, float(y) / S, 3, s)
			img.set_pixel(x, y, Color(0.7, 0.88, 0.95, 0.55 + g * 0.3))
