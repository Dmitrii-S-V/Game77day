class_name UiTheme
extends RefCounted
## Стиль интерфейса (инвентарь, крафт): тёмные потёртые панели, ячейки, кнопки-пластины, вкладки, узкий шрифт,
## курсор. Текстуры рисуются процедурно; если есть файл assets/ui/<имя>.png (например вырезанный из листа оформления),
## берётся он. Имена: panel, slot, slot_hover, slot_sel, slot_bad, button, button_hover, button_press, button_off,
## tab, tab_on, row, row_sel, cursor.

const DIR := "res://assets/ui/"
const STYLE_VER := 1    # поменять при правке процедурных текстур (сбрасывает кэш)
const GOLD := Color(0.86, 0.7, 0.36)
const TEXT := Color(0.86, 0.84, 0.8)
const DIM := Color(0.55, 0.53, 0.5)
const OK := Color(0.45, 0.78, 0.38)
const BAD := Color(0.86, 0.32, 0.27)

static var _boxes := {}
static var _font: Font
static var _cursor_set := false


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI"])
		f.font_weight = 600
		f.font_stretch = 87
		_font = f
	return _font


## Метка в стиле интерфейса.
static func label(text: String, size: int = 15, col: Color = TEXT, upper := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if upper else text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(kind: String) -> StyleBox:
	if _boxes.has(kind):
		return _boxes[kind]
	var tex: Texture2D = null
	var path := DIR + kind + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		# процедурная — один раз, дальше из кэша (user://texcache)
		tex = ImageTexture.create_from_image(TexCache.image("ui_%s_v%d" % [kind, STYLE_VER], [], func() -> Image: return _draw(kind)))
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	# поля растяжения (9-slice): у нарезки из листа оформления — шире (потёртые края не тянутся)
	var m := Vector2(14, 14) if kind == "panel" else Vector2(8, 8)
	if ResourceLoader.exists(path):
		if kind.begins_with("panel"):
			m = Vector2(26, 26)
		elif kind.begins_with("button") or kind.begins_with("tab"):
			m = Vector2(24, 13)
		else:
			m = Vector2(13, 13)
	sb.texture_margin_left = m.x
	sb.texture_margin_right = m.x
	sb.texture_margin_top = m.y
	sb.texture_margin_bottom = m.y
	var c := 14.0 if kind == "panel" else 6.0
	sb.content_margin_left = c
	sb.content_margin_right = c
	sb.content_margin_top = c * 0.6
	sb.content_margin_bottom = c * 0.6
	_boxes[kind] = sb
	return sb


## Пиктограмма интерфейса (assets/ui/icons/<имя>.png — из листа оформления: backpack, craft, star, plant, heart…).
static func ui_icon(name: String) -> Texture2D:
	var p := DIR + "icons/" + name + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Кнопка-пластина (или вкладка/строка списка: kind_base = "tab"/"row").
static func style_button(b: BaseButton, kind_base: String = "button") -> void:
	match kind_base:
		"tab":
			b.add_theme_stylebox_override("normal", box("tab"))
			b.add_theme_stylebox_override("hover", box("tab_hover"))
			b.add_theme_stylebox_override("pressed", box("tab_on"))
			b.add_theme_stylebox_override("hover_pressed", box("tab_on"))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		"row":
			b.add_theme_stylebox_override("normal", box("row"))
			b.add_theme_stylebox_override("hover", box("row_hover"))
			b.add_theme_stylebox_override("pressed", box("row_sel"))
			b.add_theme_stylebox_override("hover_pressed", box("row_sel"))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_:
			b.add_theme_stylebox_override("normal", box("button"))
			b.add_theme_stylebox_override("hover", box("button_hover"))
			b.add_theme_stylebox_override("pressed", box("button_press"))
			b.add_theme_stylebox_override("disabled", box("button_off"))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if b is Button:
		var bt := b as Button
		bt.add_theme_font_override("font", font())
		bt.add_theme_color_override("font_color", TEXT)
		bt.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.85))
		bt.add_theme_color_override("font_pressed_color", GOLD)
		bt.add_theme_color_override("font_hover_pressed_color", GOLD)
		bt.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.4))


## Курсор мыши: assets/ui/cursor.png или процедурная ржавая стрелка.
static func apply_cursor() -> void:
	if _cursor_set:
		return
	_cursor_set = true
	var tex: Texture2D = null
	if ResourceLoader.exists(DIR + "cursor.png"):
		tex = load(DIR + "cursor.png")
	else:
		tex = ImageTexture.create_from_image(TexCache.image("ui_cursor_v%d" % STYLE_VER, [], _draw_cursor))
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(2, 2))


# --- процедурные текстуры -------------------------------------------------------------------------------------

static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	return n


## Потёртая пластина: основа, крупные пятна и мелкая крошка, тёмная кромка, светлая фаска сверху, царапины.
static func _plate(w: int, h: int, base: Color, border: Color, bw: int, seed_v: int, rust := 0.0, hi := 0.08) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var big := _noise(seed_v, 0.035)
	var fine := _noise(seed_v + 7, 0.45)
	var rn := _noise(seed_v + 13, 0.06)
	for y in h:
		for x in w:
			var c := base
			c = c.lightened(0.07 * big.get_noise_2d(x, y)) if big.get_noise_2d(x, y) > 0.0 else c.darkened(-0.12 * big.get_noise_2d(x, y))
			var f := fine.get_noise_2d(x, y)
			c = c.lightened(f * 0.12) if f > 0.0 else c.darkened(-f * 0.18)
			var e := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if e < bw:
				var bc := border
				if rust > 0.0:
					bc = bc.lerp(Color(0.42, 0.22, 0.12), clampf(rn.get_noise_2d(x * 2.0, y * 2.0) * 1.6 + 0.3, 0.0, 1.0) * rust)
				c = bc.lightened(f * 0.15) if f > 0 else bc.darkened(-f * 0.25)
				if e == 0:
					c = c.darkened(0.45)
			elif e < bw + 2:
				c = c.darkened(0.25)          # тень под кромкой
			if e >= bw and y == bw:
				c = c.lightened(hi)            # фаска
			c.a = 1.0
			img.set_pixel(x, y, c)
	# царапины
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for k in int(w * h / 2600.0) + 2:
		var p := Vector2(rng.randf_range(bw + 2, w - bw - 2), rng.randf_range(bw + 2, h - bw - 2))
		var d := Vector2.from_angle(rng.randf() * TAU)
		for t in rng.randi_range(5, 18):
			var q := p + d * t
			if q.x >= bw and q.y >= bw and q.x < w - bw and q.y < h - bw:
				img.set_pixelv(Vector2i(q), img.get_pixelv(Vector2i(q)).lightened(0.09))
	return img


static func _draw(kind: String) -> Image:
	match kind:
		"panel":
			return _plate(160, 160, Color(0.105, 0.1, 0.095), Color(0.24, 0.21, 0.18), 5, 11, 0.7, 0.05)
		"slot":
			return _plate(64, 64, Color(0.075, 0.072, 0.07), Color(0.2, 0.19, 0.18), 2, 21, 0.0, 0.03)
		"slot_hover":
			return _plate(64, 64, Color(0.1, 0.097, 0.094), Color(0.4, 0.37, 0.33), 2, 21, 0.0, 0.05)
		"slot_sel":
			return _plate(64, 64, Color(0.09, 0.085, 0.078), GOLD.darkened(0.15), 3, 21, 0.0, 0.05)
		"slot_bad":
			return _plate(64, 64, Color(0.09, 0.07, 0.07), Color(0.6, 0.18, 0.15), 3, 21, 0.0, 0.05)
		"button":
			return _plate(96, 48, Color(0.19, 0.18, 0.17), Color(0.33, 0.31, 0.28), 3, 31, 0.3, 0.12)
		"button_hover":
			return _plate(96, 48, Color(0.24, 0.23, 0.21), Color(0.5, 0.46, 0.4), 3, 31, 0.3, 0.16)
		"button_press":
			return _plate(96, 48, Color(0.14, 0.13, 0.12), GOLD.darkened(0.2), 3, 31, 0.0, 0.0)
		"button_off":
			return _plate(96, 48, Color(0.12, 0.115, 0.11), Color(0.2, 0.19, 0.18), 3, 31, 0.0, 0.0)
		"tab":
			return _plate(96, 40, Color(0.13, 0.125, 0.12), Color(0.26, 0.24, 0.22), 2, 41, 0.3, 0.06)
		"tab_hover":
			return _plate(96, 40, Color(0.17, 0.16, 0.15), Color(0.4, 0.37, 0.33), 2, 41, 0.3, 0.1)
		"tab_on":
			return _plate(96, 40, Color(0.25, 0.235, 0.215), Color(0.55, 0.5, 0.42), 2, 41, 0.3, 0.16)
		"row":
			return _plate(96, 40, Color(0.095, 0.09, 0.085), Color(0.17, 0.16, 0.15), 1, 51, 0.0, 0.03)
		"row_hover":
			return _plate(96, 40, Color(0.13, 0.125, 0.12), Color(0.3, 0.28, 0.25), 1, 51, 0.0, 0.05)
		"row_sel":
			return _plate(96, 40, Color(0.15, 0.14, 0.125), GOLD.darkened(0.1), 2, 51, 0.0, 0.06)
	return _plate(32, 32, Color(0.1, 0.1, 0.1), Color(0.3, 0.3, 0.3), 2, 1)


## Ржавый наконечник-стрелка с обмоткой (как на листе оформления), 40 px.
static func _draw_cursor() -> Image:
	var s := 40
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var head := PackedVector2Array([Vector2(1, 1), Vector2(26, 19), Vector2(16, 20), Vector2(9, 29)])
	var inner := PackedVector2Array([Vector2(5, 6), Vector2(20, 17.5), Vector2(14.5, 18.3), Vector2(9.3, 24)])
	var shaft := PackedVector2Array([Vector2(14, 21), Vector2(18, 18), Vector2(31, 33), Vector2(27, 36)])
	var nz := _noise(77, 0.5)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var f := nz.get_noise_2d(x, y)
			var c := Color(0, 0, 0, 0)
			if Geometry2D.is_point_in_polygon(p, shaft):
				c = Color(0.36, 0.2, 0.12).lerp(Color(0.48, 0.42, 0.26), 0.7 if int(x + y) % 4 < 2 and x + y > 38 else 0.0)
			if Geometry2D.is_point_in_polygon(p, head):
				c = Color(0.5, 0.26, 0.13) if not Geometry2D.is_point_in_polygon(p, inner) else Color(0.16, 0.15, 0.14)
			if c.a > 0.0:
				c = c.lightened(f * 0.15) if f > 0 else c.darkened(-f * 0.25)
				c.a = 1.0
			img.set_pixel(x, y, c)
	# тёмный контур для читаемости на любом фоне
	var out := img.duplicate() as Image
	for y in s:
		for x in s:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < s and q.y < s and img.get_pixelv(q).a > 0.0:
					out.set_pixel(x, y, Color(0.03, 0.025, 0.02, 0.9))
					break
	return out
