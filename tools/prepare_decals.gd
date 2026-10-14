extends SceneTree
## Нарезка листов декалей (assets/source/decal_*.webp, белый фон) в спрайты с альфой.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/prepare_decals.gd
## Выход: assets/textures/decals/<лист>_<n>.png (квадрат 256x256, предмет по центру, альфа вместо белого фона),
##        data/blocks/decals_raw.json (список спрайтов: ключ, лист, bbox, цвета) и shots/decals_<лист>.png (контрольные листы).
## Классы/размеры спрайтов задаются в data/blocks/decals.json (собирается tools/build_decal_table.gd из decals_raw.json).

const SHEETS := {
	"mud": {"th": 0.22, "grow": 8, "min_cells": 25, "key": true},
	"signs": {"th": 0.03, "grow": 1, "min_cells": 12},
	"supply": {"th": 0.03, "grow": 1, "min_cells": 12},
	"posters": {"th": 0.03, "grow": 2, "min_cells": 40},
	"nature": {"th": 0.12, "grow": 5, "min_cells": 15, "key": true},
}
const G := 4          # шаг сетки поиска компонент (пиксели)
const SPR := 256
const BG := 0.92      # min(r,g,b) выше — «белый фон»


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/textures/decals"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var raw: Array = []
	for sheet: String in SHEETS:
		var cfg: Dictionary = SHEETS[sheet]
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/source/decal_%s.webp" % sheet))
		img.convert(Image.FORMAT_RGBA8)
		var items := _extract(img, float(cfg["th"]), int(cfg["grow"]), int(cfg["min_cells"]), bool(cfg.get("key", false)))
		print(sheet, ": ", items.size(), " спрайтов")
		var thumbs: Array[Image] = []
		for i in items.size():
			var it: Dictionary = items[i]
			var spr: Image = it["sprite"]
			var key := "%s_%d" % [sheet, i]
			spr.save_png(ProjectSettings.globalize_path("res://assets/textures/decals/%s.png" % key))
			raw.append({"key": key, "sheet": sheet, "index": i, "bbox": it["bbox"], "aspect": it["aspect"],
				"green": it["green"], "sat": it["sat"], "px": it["px"]})
			var t := spr.duplicate() as Image
			t.resize(120, 120)
			thumbs.append(t)
		_sheet(thumbs, 12, "res://shots/decals_%s.png" % sheet)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://data/blocks/decals_raw.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw, "  "))
	quit()


func _extract(img: Image, th: float, grow: int, min_cells: int, key: bool) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var gw := w / G
	var gh := h / G
	var data := img.get_data()
	# плотность «чернил» по сетке G x G; блоб = ячейка, у которой сглаженная (3x3) плотность >= th
	var frac := PackedFloat32Array()
	frac.resize(gw * gh)
	var ink := PackedByteArray()
	ink.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var cnt := 0
			for y in range(gy * G, gy * G + G):
				for x in range(gx * G, gx * G + G):
					var p := (y * w + x) * 4
					if mini(data[p], mini(data[p + 1], data[p + 2])) < int(BG * 255.0):
						cnt += 1
			frac[gy * gw + gx] = float(cnt) / float(G * G)
			ink[gy * gw + gx] = 1 if cnt > 0 else 0
	var dm := PackedByteArray()
	dm.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var s := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := gx + dx
					var ny := gy + dy
					if nx >= 0 and ny >= 0 and nx < gw and ny < gh:
						s += frac[ny * gw + nx]
			dm[gy * gw + gx] = 1 if s / 9.0 >= th else 0
	# компоненты по плотной маске
	var label := PackedInt32Array()
	label.resize(gw * gh)
	var comps: Array = []
	for s in gw * gh:
		if dm[s] == 0 or label[s] != 0:
			continue
		var id := comps.size() + 1
		var stack := [s]
		label[s] = id
		var cells := 0
		while not stack.is_empty():
			var c: int = stack.pop_back()
			cells += 1
			var cx := c % gw
			var cy := c / gw
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx >= 0 and ny >= 0 and nx < gw and ny < gh:
					var ni := ny * gw + nx
					if dm[ni] == 1 and label[ni] == 0:
						label[ni] = id
						stack.append(ni)
		comps.append({"id": id, "cells": cells, "bbox": Rect2i(0, 0, 1, 1)})
	# обрастание: брызги вокруг блоба (ячейки с чернилами в радиусе grow) переходят в его компоненту
	for step in grow:
		var upd := label.duplicate()
		for gy in gh:
			for gx in gw:
				var i := gy * gw + gx
				if label[i] != 0 or ink[i] == 0:
					continue
				var best := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var nx: int = gx + d.x
					var ny: int = gy + d.y
					if nx >= 0 and ny >= 0 and nx < gw and ny < gh and label[ny * gw + nx] != 0:
						best = label[ny * gw + nx]
				if best != 0:
					upd[i] = best
		label = upd
	# bbox по итоговым меткам
	for c: Dictionary in comps:
		c["bbox"] = Rect2i(gw, gh, 0, 0)
	var x0s := PackedInt32Array()
	x0s.resize(comps.size() + 1)
	x0s.fill(gw)
	var y0s := x0s.duplicate()
	var x1s := PackedInt32Array()
	x1s.resize(comps.size() + 1)
	var y1s := x1s.duplicate()
	for gy in gh:
		for gx in gw:
			var l := label[gy * gw + gx]
			if l != 0:
				x0s[l] = mini(x0s[l], gx)
				y0s[l] = mini(y0s[l], gy)
				x1s[l] = maxi(x1s[l], gx)
				y1s[l] = maxi(y1s[l], gy)
	for c: Dictionary in comps:
		var l: int = c["id"]
		c["bbox"] = Rect2i(x0s[l], y0s[l], x1s[l] - x0s[l] + 1, y1s[l] - y0s[l] + 1)	# порядок: по строкам сверху вниз, внутри строки слева направо
	var good: Array = []
	for c: Dictionary in comps:
		if int(c["cells"]) >= min_cells:
			good.append(c)
	good.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2i = a["bbox"]
		var rb: Rect2i = b["bbox"]
		var ya := (ra.position.y + ra.size.y / 2) / 40
		var yb := (rb.position.y + rb.size.y / 2) / 40
		if ya != yb:
			return ya < yb
		return ra.position.x < rb.position.x)
	var out: Array = []
	for c: Dictionary in good:
		var r: Rect2i = c["bbox"]
		var px := Rect2i(maxi(r.position.x * G - 6, 0), maxi(r.position.y * G - 6, 0), r.size.x * G + 12, r.size.y * G + 12)
		px = px.intersection(Rect2i(0, 0, w, h))
		out.append(_sprite(img, data, w, label, gw, int(c["id"]), px, key))
	return out


func _sprite(img: Image, data: PackedByteArray, w: int, label: PackedInt32Array, gw: int, id: int, px: Rect2i, key: bool) -> Dictionary:
	var cw := px.size.x
	var ch := px.size.y
	if key:
		return _sprite_key(img, w, label, gw, id, px)
	# фон: белое, связанное с границей кадра (внутренности знаков остаются)
	var bgm := PackedByteArray()
	bgm.resize(cw * ch)
	var stack: Array[int] = []
	var is_bg := func(x: int, y: int) -> bool:
		var p := ((px.position.y + y) * w + px.position.x + x) * 4
		var gi := ((px.position.y + y) / G) * gw + (px.position.x + x) / G
		var own := label[gi] == id
		return mini(data[p], mini(data[p + 1], data[p + 2])) >= int(BG * 255.0) or not own
	for x in cw:
		for y in [0, ch - 1]:
			if bgm[y * cw + x] == 0 and is_bg.call(x, y):
				bgm[y * cw + x] = 1
				stack.append(y * cw + x)
	for y in ch:
		for x in [0, cw - 1]:
			if bgm[y * cw + x] == 0 and is_bg.call(x, y):
				bgm[y * cw + x] = 1
				stack.append(y * cw + x)
	while not stack.is_empty():
		var c: int = stack.pop_back()
		var cx := c % cw
		var cy := c / cw
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx >= 0 and ny >= 0 and nx < cw and ny < ch and bgm[ny * cw + nx] == 0 and is_bg.call(nx, ny):
				bgm[ny * cw + nx] = 1
				stack.append(ny * cw + nx)
	# альфа с эрозией на 1 px у границы (убирает белую кайму) и мягким краем
	var crop := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	var green := 0.0
	var sat := 0.0
	var n_op := 0
	for y in ch:
		for x in cw:
			var i := y * cw + x
			var c0 := img.get_pixel(px.position.x + x, px.position.y + y)
			if bgm[i] == 1:
				crop.set_pixel(x, y, Color(c0.r, c0.g, c0.b, 0.0))
				continue
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= cw or ny >= ch or bgm[ny * cw + nx] == 1:
					edge = true
			var mn := minf(c0.r, minf(c0.g, c0.b))
			var a := 1.0
			if edge:
				a = clampf((0.95 - mn) / 0.35, 0.0, 1.0)   # светлая кайма у границы — прозрачнее
			crop.set_pixel(x, y, Color(c0.r, c0.g, c0.b, a))
			if a > 0.5:
				n_op += 1
				if c0.g > c0.r * 1.05 and c0.g > c0.b * 1.1:
					green += 1.0
				sat += (maxf(c0.r, maxf(c0.g, c0.b)) - mn)
	var aspect := float(cw) / float(ch)
	var sc := float(SPR) / float(maxi(cw, ch))
	crop.resize(maxi(int(cw * sc), 1), maxi(int(ch * sc), 1), Image.INTERPOLATE_LANCZOS)
	var spr := Image.create(SPR, SPR, false, Image.FORMAT_RGBA8)
	spr.fill(Color(0, 0, 0, 0))
	spr.blit_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()), Vector2i((SPR - crop.get_width()) / 2, (SPR - crop.get_height()) / 2))
	return {"sprite": spr, "bbox": [px.position.x, px.position.y, cw, ch], "aspect": aspect,
		"green": green / maxf(n_op, 1.0), "sat": sat / maxf(n_op, 1.0), "px": maxi(cw, ch)}


func _sheet(thumbs: Array[Image], cols: int, path: String) -> void:
	var rows := ceili(thumbs.size() / float(cols))
	var sheet := Image.create(cols * 124, maxi(rows, 1) * 124, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.45, 0.6, 1))
	for i in thumbs.size():
		sheet.blend_rect(thumbs[i], Rect2i(0, 0, 120, 120), Vector2i((i % cols) * 124 + 2, (i / cols) * 124 + 2))
	sheet.save_png(ProjectSettings.globalize_path(path))


## Грязь/природа: белый (где угодно, в т.ч. внутри) -> прозрачность по яркости, цвет без белой подмешки.
func _sprite_key(img: Image, w: int, label: PackedInt32Array, gw: int, id: int, px: Rect2i) -> Dictionary:
	var cw := px.size.x
	var ch := px.size.y
	var crop := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	var green := 0.0
	var sat := 0.0
	var n_op := 0
	for y in ch:
		for x in cw:
			var gi := ((px.position.y + y) / G) * gw + (px.position.x + x) / G
			var c0 := img.get_pixel(px.position.x + x, px.position.y + y)
			if label[gi] != id:
				crop.set_pixel(x, y, Color(c0.r, c0.g, c0.b, 0.0))
				continue
			var mn := minf(c0.r, minf(c0.g, c0.b))
			var a := clampf((0.96 - mn) / 0.34, 0.0, 1.0)
			if a < 0.02:
				crop.set_pixel(x, y, Color(c0.r, c0.g, c0.b, 0.0))
				continue
			var k := 1.0 - a
			var r := clampf((c0.r - k) / a, 0.0, 1.0)
			var g := clampf((c0.g - k) / a, 0.0, 1.0)
			var b := clampf((c0.b - k) / a, 0.0, 1.0)
			crop.set_pixel(x, y, Color(r, g, b, a))
			if a > 0.5:
				n_op += 1
				if g > r * 1.05 and g > b * 1.1:
					green += 1.0
				sat += maxf(r, maxf(g, b)) - minf(r, minf(g, b))
	var aspect := float(cw) / float(ch)
	var sc := float(SPR) / float(maxi(cw, ch))
	crop.resize(maxi(int(cw * sc), 1), maxi(int(ch * sc), 1), Image.INTERPOLATE_LANCZOS)
	var spr := Image.create(SPR, SPR, false, Image.FORMAT_RGBA8)
	spr.fill(Color(0, 0, 0, 0))
	spr.blit_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()), Vector2i((SPR - crop.get_width()) / 2, (SPR - crop.get_height()) / 2))
	return {"sprite": spr, "bbox": [px.position.x, px.position.y, cw, ch], "aspect": aspect,
		"green": green / maxf(n_op, 1.0), "sat": sat / maxf(n_op, 1.0), "px": maxi(cw, ch)}