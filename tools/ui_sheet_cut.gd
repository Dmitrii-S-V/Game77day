extends SceneTree
## Нарезка листа оформления (assets/src/ui_in/ui_sheet.png, 1536x1024) на элементы интерфейса -> assets/ui/<имя>.png.
## UiTheme подхватывает их вместо процедурных (ячейки, панель, кнопки-плашки, пиктограммы).
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/ui_sheet_cut.gd [-- preview.png]

const SRC := "res://assets/src/ui_in/ui_sheet.png"
const OUT := "res://assets/ui/"

## имя -> [x, y, w, h] на листе
const REGIONS := {
	# ячейки
	"slot": [34, 579, 75, 77], "slot_hover": [126, 579, 75, 77], "slot_sel": [218, 579, 77, 77], "slot_bad": [311, 579, 77, 77],
	# окна / фоны
	"panel": [962, 888, 166, 109], "panel_light": [1143, 888, 169, 109], "panel_torn": [1327, 888, 170, 109],
	# плашки (кнопки, вкладки, строки)
	"strip_dark": [1293, 712, 210, 40], "strip_green": [1293, 762, 207, 38], "strip_rust": [1293, 811, 210, 39],
	# полоски-индикаторы (рамка с заливкой)
	"bar_red": [731, 715, 182, 22], "bar_yellow": [731, 751, 182, 22], "bar_blue": [731, 787, 182, 22], "bar_green": [731, 823, 182, 22],
}
## пиктограммы 52x52: сетка «ИКОНКИ (ПРИМЕРЫ)», два ряда по 10
const ICONS_ROW1 := ["backpack", "craft", "pistol", "knife", "ammo", "medical", "food", "water", "fire", "sleep"]
const ICONS_ROW2 := ["map", "notes", "trophy", "shield", "skull", "bio", "cold", "plant", "warning", "star"]
## индикаторы: сердце, вилка, капля, молния
const STAT_ICONS := {"heart": [699, 712, 25, 26], "hunger": [699, 749, 25, 26], "thirst": [699, 785, 25, 26], "stamina": [699, 821, 25, 26]}


func _init() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if sheet == null:
		print("нет ", SRC)
		quit()
		return
	sheet.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "icons/"))
	var parts := {}
	var raw := {}
	for n: String in REGIONS:
		var r: Array = REGIONS[n]
		raw[n] = sheet.get_region(Rect2i(r[0], r[1], r[2], r[3]))
		var rr := Rect2i(r[0], r[1], r[2], r[3])
		# плашки и шкалы (скруглённые/рваные края) — заливкой фона от края; прямоугольные ячейки и окна — по рамке
		parts[n] = _clean(sheet, rr) if n.begins_with("bar") or n.begins_with("strip") else _tight(sheet, rr)
	# производные: кнопки и вкладки из плашек, строки списка — из ячеек
	parts["button"] = parts["strip_dark"]
	parts["button_hover"] = _adjust(parts["strip_dark"], 1.25)
	parts["button_press"] = parts["strip_rust"]
	parts["button_off"] = _adjust(parts["strip_dark"], 0.6)
	parts["tab"] = _adjust(parts["strip_dark"], 0.8)
	parts["tab_hover"] = parts["strip_dark"]
	parts["tab_on"] = _adjust(parts["strip_dark"], 1.45)
	# полоски: пустая рамка (из красной — заливка затемняется) и заливки цветов (средняя часть)
	parts["bar_bg"] = _empty_bar(parts["bar_red"])
	for c in ["red", "yellow", "blue", "green"]:
		parts["bar_fill_" + c] = (raw["bar_" + c] as Image).get_region(Rect2i(9, 6, 60, 10))
	parts["row"] = parts["slot"]
	parts["row_hover"] = parts["slot_hover"]
	parts["row_sel"] = parts["slot_sel"]
	for n: String in parts:
		(parts[n] as Image).save_png(ProjectSettings.globalize_path(OUT + n + ".png"))
	var icons := {}
	for row in 2:
		var names: Array = ICONS_ROW1 if row == 0 else ICONS_ROW2
		for k in names.size():
			var x := 31 + roundi(k * 64.6)
			var y := 712 + row * 67
			icons[names[k]] = _cut_tile(sheet.get_region(Rect2i(x, y, 53, 54)))
	for n: String in STAT_ICONS:
		var r2: Array = STAT_ICONS[n]
		icons[n] = _key_dark(sheet.get_region(Rect2i(r2[0], r2[1], r2[2], r2[3])))
	for n: String in icons:
		(icons[n] as Image).save_png(ProjectSettings.globalize_path(OUT + "icons/" + n + ".png"))
	print("CUT ", parts.size(), " parts, ", icons.size(), " icons")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_preview(parts, icons, args[0])
	quit()


static func _adjust(img: Image, k: float) -> Image:
	var o := img.duplicate() as Image
	for y in o.get_height():
		for x in o.get_width():
			var c := o.get_pixel(x, y)
			o.set_pixel(x, y, Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a))
	return o


## Элемент листа без чёрного фона: область с запасом 6 px, чёрный фон листа, связанный с краем (за скруглёнными
## и потёртыми углами), — прозрачный, затем обрезка по содержимому (ровные края без ручной подгонки координат).
static func _clean(sheet: Image, r: Rect2i) -> Image:
	var g := r.grow(6).intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
	var img := sheet.get_region(g)
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	var st: Array[int] = []
	for x in w:
		st.append(x)
		st.append((h - 1) * w + x)
	for y in h:
		st.append(y * w)
		st.append(y * w + w - 1)
	while not st.is_empty():
		var i: int = st.pop_back()
		if mask[i] != 0:
			continue
		var x := i % w
		var y := i / w
		# только кольцо у края (запас 6 px + 8 px внутрь: скруглённые/потёртые углы) — середина тёмных панелей не трогается
		if mini(mini(x, y), mini(w - 1 - x, h - 1 - y)) > 14:
			continue
		var c := img.get_pixel(x, y)
		if maxf(c.r, maxf(c.g, c.b)) > 0.07:
			continue
		mask[i] = 1
		if x > 0: st.append(i - 1)
		if x < w - 1: st.append(i + 1)
		if y > 0: st.append(i - w)
		if y < h - 1: st.append(i + w)
	for y in h:
		for x in w:
			if mask[y * w + x] != 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var used := img.get_used_rect()
	return img.get_region(used) if used.size.x > 0 else img


## Прямоугольный элемент (ячейка, окно): точная обрезка по внешней границе рамки (крайние строки/столбцы, где
## заметная доля пикселей светлее фона листа), углы за скруглением рамки — прозрачные.
static func _tight(sheet: Image, r: Rect2i) -> Image:
	var g := r.grow(6).intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
	var img := sheet.get_region(g)
	var w := img.get_width()
	var h := img.get_height()
	var lit := func(x: int, y: int) -> bool:
		var c := img.get_pixel(x, y)
		return maxf(c.r, maxf(c.g, c.b)) > 0.09
	var col_ok := func(x: int) -> bool:
		var n := 0
		for y in h:
			if lit.call(x, y):
				n += 1
		return n > h * 0.35
	var row_ok := func(y: int) -> bool:
		var n := 0
		for x in w:
			if lit.call(x, y):
				n += 1
		return n > w * 0.35
	var x0 := 0
	while x0 < w - 1 and not col_ok.call(x0):
		x0 += 1
	var x1 := w - 1
	while x1 > x0 and not col_ok.call(x1):
		x1 -= 1
	var y0 := 0
	while y0 < h - 1 and not row_ok.call(y0):
		y0 += 1
	var y1 := h - 1
	while y1 > y0 and not row_ok.call(y1):
		y1 -= 1
	var out := img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	# углы: тёмные пиксели за скруглением (треугольник 5 px от угла)
	var ow := out.get_width()
	var oh := out.get_height()
	for k in 5:
		for j in 5 - k:
			for p in [Vector2i(j, k), Vector2i(ow - 1 - j, k), Vector2i(j, oh - 1 - k), Vector2i(ow - 1 - j, oh - 1 - k)]:
				var c := out.get_pixelv(p)
				if maxf(c.r, maxf(c.g, c.b)) < 0.08:
					out.set_pixelv(p, Color(0, 0, 0, 0))
	return out


## Пустая полоска: насыщенные (цветные) пиксели заливки -> тёмный жёлоб как в правой, пустой части.
static func _empty_bar(img: Image) -> Image:
	var o := img.duplicate() as Image
	var track := o.get_pixel(o.get_width() - 20, o.get_height() / 2)
	for y in o.get_height():
		for x in o.get_width():
			var c := o.get_pixel(x, y)
			if c.a > 0.5 and c.s > 0.22 and c.v > 0.18:
				o.set_pixel(x, y, track)
	return o


## Пиктограмма из плитки: светлый символ на тёмной плитке -> светлый символ на прозрачном (альфа по яркости).
static func _cut_tile(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var o := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := c.get_luminance()
			# рамка плитки по краю (5 px) — убрать
			var edge := mini(mini(x, y), mini(w - 1 - x, h - 1 - y)) < 6
			var a := 0.0 if edge else clampf((l - 0.32) / 0.3, 0.0, 1.0)
			o.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return o


## Значок на чёрном фоне: альфа по яркости/насыщенности (цветные сердце/капля сохраняются).
static func _key_dark(img: Image) -> Image:
	var o := img.duplicate() as Image
	for y in o.get_height():
		for x in o.get_width():
			var c := o.get_pixel(x, y)
			var v := maxf(c.r, maxf(c.g, c.b))
			o.set_pixel(x, y, Color(c.r, c.g, c.b, clampf((v - 0.12) / 0.25, 0.0, 1.0)))
	return o


func _preview(parts: Dictionary, icons: Dictionary, path: String) -> void:
	var pv := Image.create(1200, 1150, false, Image.FORMAT_RGBA8)
	pv.fill(Color(0.35, 0.4, 0.33))
	var x := 10
	var y := 10
	var rowh := 0
	for n: String in icons:
		var im3: Image = (icons[n] as Image).duplicate()
		im3.resize(im3.get_width() * 2, im3.get_height() * 2, Image.INTERPOLATE_BILINEAR)
		if x + im3.get_width() > 1190:
			x = 10
			y += 116
		pv.blend_rect(im3, Rect2i(Vector2i.ZERO, im3.get_size()), Vector2i(x, y))
		x += im3.get_width() + 8
	x = 10
	y += 130
	for n: String in parts:
		var im: Image = (parts[n] as Image).duplicate()
		im.resize(im.get_width() * 2, im.get_height() * 2, Image.INTERPOLATE_NEAREST)
		if x + im.get_width() > 1190:
			x = 10
			y += rowh + 10
			rowh = 0
		pv.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, y))
		x += im.get_width() + 10
		rowh = maxi(rowh, im.get_height())
	x = 10
	y += rowh + 20
	for n: String in icons:
		var im2: Image = (icons[n] as Image).duplicate()
		im2.resize(im2.get_width() * 2, im2.get_height() * 2, Image.INTERPOLATE_BILINEAR)
		if x + im2.get_width() > 1190:
			x = 10
			y += 120
		pv.blend_rect(im2, Rect2i(Vector2i.ZERO, im2.get_size()), Vector2i(x, y))
		x += im2.get_width() + 8
	pv.save_png(path)
