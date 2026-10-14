class_name BlockShapes
extends RefCounted
## Геометрия нестандартных блоков (дверь, окно, паутина, люстра, свеча, ковёр). Каждый блок занимает целое
## число ячеек (footprint) и состоит из нескольких боксов/четырёхугольников внутри него, с упрощённой
## коллизией: "solid" (игрок упирается) или "soft" (игрок проходит, но блок выбирается и ломается).
## Координаты — метры в системе якоря (минимальный угол footprint) после поворота.

const B := BlockGrid.B


## -> {boxes: [{a, b, layer, mode, coll, glass}], quads: [{p: Array[Vector3], layer, mode}], size: Vector3}
## mode: 2 — UV грани 0..1, 3 — то же, самосветящийся. coll: solid | soft | none.
static func build(id: int, meta: int) -> Dictionary:
	var shape := BlockRegistry.shape_of(id)
	var rot := BlockRegistry.rot_of(meta)
	var tier := BlockRegistry.tier_of(meta)
	var variant := BlockRegistry.variant_of(meta)
	var main := BlockRegistry.tex_layer(id, tier, variant)
	var f0 := BlockRegistry.footprint(id, 0)
	var dims := Vector3(f0) * B
	var boxes: Array = []
	var quads: Array = []
	var polys: Array = []
	var hulls: Array = []
	match shape:
		"pillar_thick": _prism(_ngon(0.5, 0.5, 0.46, 12), 0.0, 1.0, main, polys, hulls)
		"pillar_thin": _prism(_ngon(0.5, 0.5, 0.2, 10), 0.0, 1.0, main, polys, hulls)
		"round_1": _prism(_rounded_rect(0.5, 1), 0.0, 1.0, main, polys, hulls)
		"round_4": _prism(_rounded_rect(0.32, 4), 0.0, 1.0, main, polys, hulls)
		"wedge": _wedge(1.0, main, polys, hulls)
		"wedge_low": _wedge(0.5, main, polys, hulls)
		"stake": _stake(main, polys, hulls)
		"door": _door(id, meta, main, boxes)
		"window": _window(id, main, boxes)
		"web": _web(main, quads, boxes)
		"carpet": boxes.append(_box(0.0, 0.0, 0.0, 1.0, 0.04, 1.0, main, "soft"))
		"candle": _candle(main, boxes, quads)
		"chandelier": _chandelier(main, boxes, quads)
		# --- простые формы (материал — из редактора; «_edge» прижаты к грани z=0, «_corner» — в угол x=0,z=0) ---
		"column": _pbox(0.25, 0.0, 0.25, 0.75, 1.0, 0.75, main, polys, boxes)
		"column_edge": _pbox(0.25, 0.0, 0.0, 0.75, 1.0, 0.5, main, polys, boxes)
		"column_corner": _pbox(0.0, 0.0, 0.0, 0.5, 1.0, 0.5, main, polys, boxes)
		"column_thin": _pbox(0.375, 0.0, 0.375, 0.625, 1.0, 0.625, main, polys, boxes)
		"column_thin_edge": _pbox(0.375, 0.0, 0.0, 0.625, 1.0, 0.25, main, polys, boxes)
		"column_thin_corner": _pbox(0.0, 0.0, 0.0, 0.25, 1.0, 0.25, main, polys, boxes)
		"column_rebar": _column_rebar(main, polys, boxes)
		"beam": _pbox(0.0, 0.25, 0.25, 1.0, 0.75, 0.75, main, polys, boxes)
		"beam_edge": _pbox(0.0, 0.5, 0.0, 1.0, 1.0, 0.5, main, polys, boxes)
		"beam_thin": _pbox(0.0, 0.375, 0.375, 1.0, 0.625, 0.625, main, polys, boxes)
		"beam_thin_edge": _pbox(0.0, 0.75, 0.0, 1.0, 1.0, 0.25, main, polys, boxes)
		"beam_rebar": _beam_rebar(main, polys, boxes)
		"ibeam": _ibeam(0.25, 0.3, main, polys, boxes)
		"ibeam_edge": _ibeam(0.5, 0.0, main, polys, boxes)
		"wall_slab": _pbox(0.0, 0.0, 0.375, 1.0, 1.0, 0.625, main, polys, boxes)
		"wall_slab_edge": _pbox(0.0, 0.0, 0.0, 1.0, 1.0, 0.25, main, polys, boxes)
		"wall_half": _pbox(0.0, 0.0, 0.375, 1.0, 0.5, 0.625, main, polys, boxes)
		"wall_half_edge": _pbox(0.0, 0.0, 0.0, 1.0, 0.5, 0.25, main, polys, boxes)
		"wall_window": _wall_window(0.375, main, polys, boxes)
		"wall_window_edge": _wall_window(0.0, main, polys, boxes)
		"wall_corner":
			_pbox(0.0, 0.0, 0.0, 1.0, 1.0, 0.25, main, polys, boxes)
			_pbox(0.0, 0.0, 0.25, 0.25, 1.0, 1.0, main, polys, boxes)
		"wall_slope": _wall_slope(main, polys, hulls)
		"doorway": _doorway(0.375, main, polys, boxes)
		"doorway_edge": _doorway(0.0, main, polys, boxes)
		"window_frame_block": _window_frame_block(main, polys, boxes)
		"curb": _pbox(0.0, 0.0, 0.375, 1.0, 0.25, 0.625, main, polys, boxes)
		"curb_edge": _pbox(0.0, 0.0, 0.0, 1.0, 0.25, 0.25, main, polys, boxes)
		"curb_corner":
			_pbox(0.0, 0.0, 0.0, 1.0, 0.25, 0.25, main, polys, boxes)
			_pbox(0.0, 0.0, 0.25, 0.25, 0.25, 1.0, main, polys, boxes)
		"stairs":
			for i in 4:   # 4 ступени по 25 см, подъём к +Z
				_pbox(0.0, i * 0.25, i * 0.25, 1.0, (i + 1) * 0.25, 1.0, main, polys, boxes)
		"roof_flat": _pbox(0.0, 0.0, 0.0, 1.0, 0.12, 1.0, main, polys, boxes)
		"roof_slope": _roof_slope(main, polys, hulls)
		"pipe_h": _pipe(true, main, polys, boxes)
		"pipe_v": _pipe(false, main, polys, boxes)
		"pipe_notch":
			_pbox(0.0, 0.0, 0.0, 1.0, 0.5, 1.0, main, polys, boxes)
			_pbox(0.0, 0.5, 0.0, 0.2, 1.0, 1.0, main, polys, boxes)
			_pbox(0.8, 0.5, 0.0, 1.0, 1.0, 1.0, main, polys, boxes)
		"railing": _railing(main, polys, boxes)
		"chainlink": _chainlink(main, polys, boxes, quads)
		"marker":
			# зона (спавн спящего / триггер): в игре невидима и без столкновений; коробка — для иконки и «призрака»
			# в редакторе (там её рисует BlockBuilding._sync_marker цветом зоны)
			var mb := _box(0.1, 0.0, 0.1, 0.9, 0.8 if String(BlockRegistry.block(id).get("marker", "")) == "spawn" else 0.15, 0.9, main, "none")
			mb["hidden"] = true
			boxes.append(mb)
		"model":
			# готовая модель (рисует BlockBuilding): здесь только невидимые коробки столкновений из blocks.json «coll»
			for c: Array in BlockRegistry.block(id).get("coll", [[0, 0, 0, dims.x, dims.y, dims.z]]):
				var bx := _box(c[0], c[1], c[2], c[3], c[4], c[5], main, "solid")
				bx["hidden"] = true
				boxes.append(bx)
	var out_boxes: Array = []
	for b: Dictionary in boxes:
		var r := _rot_box(b["a"], b["b"], dims, rot)
		b["a"] = r[0]
		b["b"] = r[1]
		out_boxes.append(b)
	var out_polys: Array = []
	for pl: Dictionary in polys:
		var pp: Array = []
		for p: Vector3 in pl["p"]:
			pp.append(_rot_point(p, dims, rot))
		pl["p"] = pp
		out_polys.append(pl)
	var out_hulls: Array = []
	for h: Dictionary in hulls:
		var hp: Array = []
		for p: Vector3 in h["pts"]:
			hp.append(_rot_point(p, dims, rot))
		h["pts"] = hp
		out_hulls.append(h)
	var out_quads: Array = []
	for q: Dictionary in quads:
		var pts: Array = []
		for p: Vector3 in q["p"]:
			pts.append(_rot_point(p, dims, rot))
		q["p"] = pts
		out_quads.append(q)
	var size := Vector3(BlockRegistry.footprint(id, rot)) * B
	# поворот по всем осям («верх» блока): только 1x1x1, вокруг центра ячейки
	var up := BlockRegistry.up_of(meta)
	if up != 0 and f0 == Vector3i.ONE:
		var ub := BlockRegistry.up_basis(up)
		var c := Vector3(0.5, 0.5, 0.5) * B
		var tp := func(p: Vector3) -> Vector3: return (ub * (p - c) + c).snapped(Vector3.ONE * 1e-5)
		for b: Dictionary in out_boxes:
			var p: Vector3 = tp.call(b["a"])
			var q: Vector3 = tp.call(b["b"])
			b["a"] = p.min(q)
			b["b"] = p.max(q)
		for pl: Dictionary in out_polys:
			pl["p"] = (pl["p"] as Array).map(tp)
		for h: Dictionary in out_hulls:
			h["pts"] = (h["pts"] as Array).map(tp)
		for q: Dictionary in out_quads:
			q["p"] = (q["p"] as Array).map(tp)
	return {"boxes": out_boxes, "quads": out_quads, "polys": out_polys, "hulls": out_hulls, "size": size}


static func _box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, layer: int, coll: String, mode: int = 2, glass: bool = false) -> Dictionary:
	return {"a": Vector3(x0, y0, z0), "b": Vector3(x1, y1, z1), "layer": layer, "mode": mode, "coll": coll, "glass": glass}


static func _rot_point(p: Vector3, dims: Vector3, rot: int) -> Vector3:
	var x := p.x
	var z := p.z
	var fx := dims.x
	var fz := dims.z
	for i in rot:
		var nx := z
		var nz := fx - x
		x = nx
		z = nz
		var t := fx
		fx = fz
		fz = t
	return Vector3(x, p.y, z)


static func _rot_box(a: Vector3, b: Vector3, dims: Vector3, rot: int) -> Array:
	var p := _rot_point(a, dims, rot)
	var q := _rot_point(b, dims, rot)
	return [Vector3(minf(p.x, q.x), minf(p.y, q.y), minf(p.z, q.z)), Vector3(maxf(p.x, q.x), maxf(p.y, q.y), maxf(p.z, q.z))]


# --- формы ----------------------------------------------------------------------------

static func _door(id: int, meta: int, main: int, boxes: Array) -> void:
	var wood := BlockRegistry.layer_of("frame")
	var open := (BlockRegistry.state_of(meta) & 1) == 1 and bool(BlockRegistry.block(id).get("openable", false))
	boxes.append(_box(0.0, 0.0, 0.18, 0.07, 2.0, 0.32, wood, "solid"))
	boxes.append(_box(0.93, 0.0, 0.18, 1.0, 2.0, 0.32, wood, "solid"))
	boxes.append(_box(0.07, 1.93, 0.18, 0.93, 2.0, 0.32, wood, "solid"))
	if open:
		boxes.append(_box(0.07, 0.0, 0.25, 0.13, 1.93, 1.09, main, "soft"))   # створка распахнута на 90°
	else:
		boxes.append(_box(0.07, 0.0, 0.22, 0.93, 1.93, 0.28, main, "solid"))
	if not bool(BlockRegistry.block(id).get("openable", true)):
		var boards := BlockRegistry.layer_of("boards")
		for y in [0.32, 0.86, 1.4]:
			boxes.append(_box(0.0, y, 0.12, 1.0, y + 0.14, 0.18, boards, "solid"))


static func _window(id: int, main: int, boxes: Array) -> void:
	var b := BlockRegistry.block(id)
	boxes.append(_box(0.0, 0.0, 0.18, 0.07, 1.0, 0.32, main, "solid"))
	boxes.append(_box(0.93, 0.0, 0.18, 1.0, 1.0, 0.32, main, "solid"))
	boxes.append(_box(0.07, 0.0, 0.18, 0.93, 0.07, 0.32, main, "solid"))
	boxes.append(_box(0.07, 0.93, 0.18, 0.93, 1.0, 0.32, main, "solid"))
	if bool(b.get("pane", false)):
		boxes.append(_box(0.465, 0.07, 0.2, 0.535, 0.93, 0.3, main, "solid"))
		boxes.append(_box(0.07, 0.07, 0.245, 0.93, 0.93, 0.255, main, "solid", 2, true))
	if bool(b.get("boards", false)):
		var boards := BlockRegistry.layer_of("boards")
		for i in 3:
			boxes.append(_box(0.0, 0.1 + i * 0.3, 0.12, 1.0, 0.26 + i * 0.3, 0.2, boards, "solid"))
	if bool(b.get("shards", false)):
		var sh := BlockRegistry.layer_of("glass_shard")
		boxes.append(_box(0.07, 0.07, 0.235, 0.24, 0.3, 0.265, sh, "none"))
		boxes.append(_box(0.76, 0.07, 0.235, 0.93, 0.22, 0.265, sh, "none"))
		boxes.append(_box(0.3, 0.07, 0.23, 0.52, 0.12, 0.27, sh, "none"))
		boxes.append(_box(0.07, 0.72, 0.235, 0.18, 0.93, 0.265, sh, "none"))


static func _web(main: int, quads: Array, boxes: Array) -> void:
	# диагональная плоскость от нижнего угла к верхнему
	quads.append({"p": [Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 0)], "layer": main, "mode": 2})
	boxes.append(_box(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, main, "soft", 2, false))
	(boxes[boxes.size() - 1] as Dictionary)["hidden"] = true


static func _candle(main: int, boxes: Array, quads: Array) -> void:
	var flame := BlockRegistry.layer_of("flame")
	boxes.append(_box(0.44, 0.0, 0.44, 0.56, 0.18, 0.56, main, "soft"))
	boxes.append(_box(0.495, 0.18, 0.495, 0.505, 0.22, 0.505, main, "none"))
	quads.append({"p": [Vector3(0.46, 0.21, 0.5), Vector3(0.54, 0.21, 0.5), Vector3(0.54, 0.37, 0.5), Vector3(0.46, 0.37, 0.5)], "layer": flame, "mode": 3})
	quads.append({"p": [Vector3(0.5, 0.21, 0.46), Vector3(0.5, 0.21, 0.54), Vector3(0.5, 0.37, 0.54), Vector3(0.5, 0.37, 0.46)], "layer": flame, "mode": 3})


## Люстра висит от верха ячейки: цепь вверх, крест из перекладин и четыре свечи.
static func _chandelier(main: int, boxes: Array, quads: Array) -> void:
	var flame := BlockRegistry.layer_of("flame")
	boxes.append(_box(0.49, 0.45, 0.49, 0.51, 1.0, 0.51, main, "none"))
	boxes.append(_box(0.2, 0.4, 0.47, 0.8, 0.46, 0.53, main, "soft"))
	boxes.append(_box(0.47, 0.4, 0.2, 0.53, 0.46, 0.8, main, "soft"))
	for p: Vector2 in [Vector2(0.2, 0.5), Vector2(0.8, 0.5), Vector2(0.5, 0.2), Vector2(0.5, 0.8)]:
		boxes.append(_box(p.x - 0.03, 0.46, p.y - 0.03, p.x + 0.03, 0.56, p.y + 0.03, main, "none"))
		quads.append({"p": [Vector3(p.x - 0.06, 0.55, p.y), Vector3(p.x + 0.06, 0.55, p.y), Vector3(p.x + 0.06, 0.72, p.y), Vector3(p.x - 0.06, 0.72, p.y)], "layer": flame, "mode": 3})
		quads.append({"p": [Vector3(p.x, 0.55, p.y - 0.06), Vector3(p.x, 0.55, p.y + 0.06), Vector3(p.x, 0.72, p.y + 0.06), Vector3(p.x, 0.72, p.y - 0.06)], "layer": flame, "mode": 3})

# --- простые формы: коробки с текстурой по миру ----------------------------------------

## Коробка из многоугольников (текстура тайлится по миру, как у стен — не растягивается на длинных балках)
## + невидимая коробка столкновений (coll: solid | soft | none).
static func _pbox(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, layer: int, polys: Array, boxes: Array, coll: String = "solid") -> void:
	var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var p := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		_add_poly(polys, [p[f[0]], p[f[1]], p[f[2]], p[f[3]]], c, layer)
	if coll != "none":
		var b := _box(x0, y0, z0, x1, y1, z1, layer, coll)
		b["hidden"] = true
		boxes.append(b)


## Выпуклое тело по точкам и граням (индексы) + коллизия-оболочка.
static func _hull_shape(pts: Array, faces: Array, layer: int, polys: Array, hulls: Array) -> void:
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= float(pts.size())
	for f: Array in faces:
		var fp: Array = []
		for i: int in f:
			fp.append(pts[i])
		_add_poly(polys, fp, c, layer)
	hulls.append({"pts": pts, "coll": "solid"})


static func _rebar_layer() -> int:
	return BlockRegistry.layer_of("metal_rusty_1")


static func _column_rebar(main: int, polys: Array, boxes: Array) -> void:
	_pbox(0.25, 0.0, 0.25, 0.75, 0.82, 0.75, main, polys, boxes)
	var rb := _rebar_layer()
	for p: Vector2 in [Vector2(0.33, 0.33), Vector2(0.67, 0.33), Vector2(0.33, 0.67), Vector2(0.67, 0.67)]:
		var top := 0.97 + fposmod(p.x * 7.3 + p.y * 3.1, 1.0) * 0.03 - 0.03   # разной длины
		_pbox(p.x - 0.015, 0.82, p.y - 0.015, p.x + 0.015, top, p.y + 0.015, rb, polys, boxes, "none")


static func _beam_rebar(main: int, polys: Array, boxes: Array) -> void:
	_pbox(0.12, 0.25, 0.25, 0.88, 0.75, 0.75, main, polys, boxes)
	var rb := _rebar_layer()
	for p: Vector2 in [Vector2(0.33, 0.33), Vector2(0.67, 0.33), Vector2(0.33, 0.67), Vector2(0.67, 0.67)]:
		_pbox(0.0, p.y - 0.015, p.x - 0.015, 0.12, p.y + 0.015, p.x + 0.015, rb, polys, boxes, "none")
		_pbox(0.88, p.y - 0.015, p.x - 0.015, 1.0, p.y + 0.015, p.x + 0.015, rb, polys, boxes, "none")


## Двутавр высотой 0.5 вдоль X: полки сверху и снизу, стенка посередине. y0 — низ, z0 — ближний край полок (ширина 0.4).
static func _ibeam(y0: float, z0: float, main: int, polys: Array, boxes: Array) -> void:
	var y1 := y0 + 0.5
	var z1 := z0 + 0.4
	var zc := (z0 + z1) * 0.5
	_pbox(0.0, y0, z0, 1.0, y0 + 0.05, z1, main, polys, boxes, "none")
	_pbox(0.0, y1 - 0.05, z0, 1.0, y1, z1, main, polys, boxes, "none")
	_pbox(0.0, y0 + 0.05, zc - 0.03, 1.0, y1 - 0.05, zc + 0.03, main, polys, boxes, "none")
	var b := _box(0.0, y0, z0, 1.0, y1, z1, main, "solid")
	b["hidden"] = true
	boxes.append(b)


static func _wall_window(z0: float, main: int, polys: Array, boxes: Array) -> void:
	var z1 := z0 + 0.25
	_pbox(0.0, 0.0, z0, 0.3, 1.0, z1, main, polys, boxes)
	_pbox(0.7, 0.0, z0, 1.0, 1.0, z1, main, polys, boxes)
	_pbox(0.3, 0.0, z0, 0.7, 0.35, z1, main, polys, boxes)
	_pbox(0.3, 0.75, z0, 0.7, 1.0, z1, main, polys, boxes)


static func _doorway(z0: float, main: int, polys: Array, boxes: Array) -> void:
	var z1 := z0 + 0.25
	_pbox(0.0, 0.0, z0, 0.14, 2.0, z1, main, polys, boxes)
	_pbox(0.86, 0.0, z0, 1.0, 2.0, z1, main, polys, boxes)
	_pbox(0.14, 1.86, z0, 0.86, 2.0, z1, main, polys, boxes)


static func _window_frame_block(main: int, polys: Array, boxes: Array) -> void:
	_pbox(0.0, 0.0, 0.4, 0.12, 1.0, 0.6, main, polys, boxes)
	_pbox(0.88, 0.0, 0.4, 1.0, 1.0, 0.6, main, polys, boxes)
	_pbox(0.12, 0.0, 0.4, 0.88, 0.12, 0.6, main, polys, boxes)
	_pbox(0.12, 0.88, 0.4, 0.88, 1.0, 0.6, main, polys, boxes)


## Наклонная стена: треугольник (низ по всей длине, подъём к +X), толщина 0.25 по центру ячейки.
static func _wall_slope(main: int, polys: Array, hulls: Array) -> void:
	var z0 := 0.375
	var z1 := 0.625
	var pts := [Vector3(0, 0, z0), Vector3(1, 0, z0), Vector3(1, 1, z0), Vector3(0, 0, z1), Vector3(1, 0, z1), Vector3(1, 1, z1)]
	_hull_shape(pts, [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [0, 2, 5, 3]], main, polys, hulls)


## Скат крыши: лист 12 см, от низа у z=0 до верха у z=1.
static func _roof_slope(main: int, polys: Array, hulls: Array) -> void:
	var t := 0.12
	var top := 1.0 - t
	var pts := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, top, 1), Vector3(0, top, 1),
		Vector3(0, t, 0), Vector3(1, t, 0), Vector3(1, 1.0, 1), Vector3(0, 1.0, 1)]
	_hull_shape(pts, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]], main, polys, hulls)


## Труба (полая): кольцо из 14 сегментов, наружный радиус 0.3, стенка 5 см. horizontal — вдоль X, иначе вдоль Y.
static func _pipe(horizontal: bool, main: int, polys: Array, boxes: Array) -> void:
	var n := 14
	var ro := 0.3
	var ri := 0.25
	var ax := func(t: float, a: float, r: float) -> Vector3:
		# t — вдоль оси трубы (0..1), a — угол, r — радиус
		return Vector3(t, 0.5 + cos(a) * r, 0.5 + sin(a) * r) if horizontal else Vector3(0.5 + cos(a) * r, t, 0.5 + sin(a) * r)
	var center := Vector3(0.5, 0.5, 0.5)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o00: Vector3 = ax.call(0.0, a0, ro)
		var o01: Vector3 = ax.call(0.0, a1, ro)
		var o10: Vector3 = ax.call(1.0, a0, ro)
		var o11: Vector3 = ax.call(1.0, a1, ro)
		var i00: Vector3 = ax.call(0.0, a0, ri)
		var i01: Vector3 = ax.call(0.0, a1, ri)
		var i10: Vector3 = ax.call(1.0, a0, ri)
		var i11: Vector3 = ax.call(1.0, a1, ri)
		_add_poly(polys, [o00, o01, o11, o10], center, main)                       # наружная поверхность
		var mid_i: Vector3 = ax.call(0.5, (a0 + a1) * 0.5, ri)
		var inner_c := mid_i + (mid_i - (Vector3(0.5, 0.5, 0.5) if not horizontal else Vector3(mid_i.x, 0.5, 0.5))).normalized()
		if not horizontal:
			inner_c = mid_i + (mid_i - Vector3(0.5, mid_i.y, 0.5)).normalized()
		_add_poly(polys, [i00, i01, i11, i10], inner_c, main)                      # внутренняя (нормаль внутрь трубы)
		var e0 := ax.call(-1.0, 0.0, 0.0) as Vector3
		var e1 := ax.call(2.0, 0.0, 0.0) as Vector3
		_add_poly(polys, [o00, o01, i01, i00], e1, main)                           # торец у t=0 (смотрит наружу)
		_add_poly(polys, [o10, o11, i11, i10], e0, main)                           # торец у t=1
	var b := _box(0.0, 0.2, 0.2, 1.0, 0.8, 0.8, main, "solid") if horizontal else _box(0.2, 0.0, 0.2, 0.8, 1.0, 0.8, main, "solid")
	b["hidden"] = true
	boxes.append(b)


## Деревянные перила у грани (z 0..0.1): стойки, верхний и нижний брус, балясины. Материал фиксированный.
static func _railing(main: int, polys: Array, boxes: Array) -> void:
	_pbox(0.0, 0.0, 0.02, 0.07, 1.0, 0.09, main, polys, boxes, "none")
	_pbox(0.93, 0.0, 0.02, 1.0, 1.0, 0.09, main, polys, boxes, "none")
	_pbox(0.0, 0.93, 0.01, 1.0, 1.0, 0.1, main, polys, boxes, "none")
	_pbox(0.07, 0.1, 0.03, 0.93, 0.15, 0.08, main, polys, boxes, "none")
	for k in 6:
		var x := 0.07 + (k + 1) * 0.86 / 7.0
		_pbox(x - 0.018, 0.15, 0.04, x + 0.018, 0.93, 0.07, main, polys, boxes, "none")
	var b := _box(0.0, 0.0, 0.0, 1.0, 1.0, 0.1, main, "solid")
	b["hidden"] = true
	boxes.append(b)


## Забор из сетки-рабицы у грани: металлическая рама из труб и сетка (прозрачная текстура, видна с обеих сторон).
static func _chainlink(main: int, polys: Array, boxes: Array, quads: Array) -> void:
	var frame := BlockRegistry.layer_of("metal_rusty_0")
	_pbox(0.0, 0.0, 0.02, 0.05, 1.0, 0.07, frame, polys, boxes, "none")
	_pbox(0.95, 0.0, 0.02, 1.0, 1.0, 0.07, frame, polys, boxes, "none")
	_pbox(0.05, 0.95, 0.025, 0.95, 0.99, 0.065, frame, polys, boxes, "none")
	_pbox(0.05, 0.03, 0.025, 0.95, 0.07, 0.065, frame, polys, boxes, "none")
	quads.append({"p": [Vector3(0.05, 0.07, 0.045), Vector3(0.95, 0.07, 0.045), Vector3(0.95, 0.95, 0.045), Vector3(0.05, 0.95, 0.045)], "layer": main, "mode": 2})
	var b := _box(0.0, 0.0, 0.0, 1.0, 1.0, 0.09, main, "solid")
	b["hidden"] = true
	boxes.append(b)


# --- объёмные формы (призмы, клинья, кол) ------------------------------------------------

## Правильный многоугольник в плане (x, z).
static func _ngon(cx: float, cz: float, r: float, n: int) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + TAU / float(n * 2)
		out.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	return out


## Квадрат 1x1 со скруглёнными углами радиуса r: corners = 1 (угол +x+z) или 4 (все).
static func _rounded_rect(r: float, corners: int) -> Array:
	var out: Array = []
	var segs := 5
	# обход против часовой по (x, z): начинаем с угла (0,0)
	var corner_defs := [
		[Vector2(0, 0), Vector2(r, r), PI, 1.5 * PI, false],
		[Vector2(1, 0), Vector2(1.0 - r, r), 1.5 * PI, 2.0 * PI, false],
		[Vector2(1, 1), Vector2(1.0 - r, 1.0 - r), 0.0, 0.5 * PI, true],
		[Vector2(0, 1), Vector2(r, 1.0 - r), 0.5 * PI, PI, false],
	]
	for cd: Array in corner_defs:
		var rounded: bool = corners == 4 or (corners == 1 and cd[4])
		if not rounded:
			out.append(cd[0])
		else:
			var c: Vector2 = cd[1]
			for s in segs + 1:
				var a: float = lerpf(cd[2], cd[3], float(s) / float(segs))
				out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _poly_uv_dir(n: Vector3) -> int:
	if absf(n.y) >= absf(n.x) and absf(n.y) >= absf(n.z):
		return 1
	return 0 if absf(n.x) > absf(n.z) else 2


## Призма: многоугольник плана poly (против часовой при виде сверху на +Y... обход по (x, z)) от y0 до y1.
static func _prism(poly: Array, y0: float, y1: float, layer: int, polys: Array, hulls: Array) -> void:
	var n := poly.size()
	var center := Vector3(0.5, (y0 + y1) * 0.5, 0.5)
	var top: Array = []
	var bot: Array = []
	for p: Vector2 in poly:
		top.append(Vector3(p.x, y1, p.y))
		bot.append(Vector3(p.x, y0, p.y))
	_add_poly(polys, top, center, layer)
	_add_poly(polys, bot, center, layer)
	for i in n:
		var j := (i + 1) % n
		_add_poly(polys, [bot[i], bot[j], top[j], top[i]], center, layer)
	var pts: Array = []
	pts.append_array(top)
	pts.append_array(bot)
	hulls.append({"pts": pts, "coll": "solid"})


static func _wedge(h: float, layer: int, polys: Array, hulls: Array) -> void:
	# клин: высота 0 при z=0, h при z=1 (подъём к +Z)
	var a0 := Vector3(0, 0, 0)
	var a1 := Vector3(1, 0, 0)
	var b0 := Vector3(0, 0, 1)
	var b1 := Vector3(1, 0, 1)
	var t0 := Vector3(0, h, 1)
	var t1 := Vector3(1, h, 1)
	var center := Vector3(0.5, h * 0.35, 0.6)
	_add_poly(polys, [a0, a1, b1, b0], center, layer)          # низ
	_add_poly(polys, [a0, b0, t0], center, layer)              # бок -x
	_add_poly(polys, [a1, t1, b1], center, layer)              # бок +x
	_add_poly(polys, [b0, b1, t1, t0], center, layer)          # задняя стенка +z
	_add_poly(polys, [a0, a1, t1, t0], center, layer)          # скат
	hulls.append({"pts": [a0, a1, b0, b1, t0, t1], "coll": "solid"})


static func _stake(layer: int, polys: Array, hulls: Array) -> void:
	var hw := 0.09
	var cy := 0.74    # высота цилиндрической части, дальше остриё
	var cx := 0.5
	var cz := 0.5
	var center := Vector3(cx, 0.5, cz)
	var ring_b: Array = []
	var ring_t: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0
		ring_b.append(Vector3(cx + cos(a) * hw, 0.0, cz + sin(a) * hw))
		ring_t.append(Vector3(cx + cos(a) * hw, cy, cz + sin(a) * hw))
	var tip := Vector3(cx, 1.0, cz)
	_add_poly(polys, ring_b, center, layer)
	for i in 6:
		var j := (i + 1) % 6
		_add_poly(polys, [ring_b[i], ring_b[j], ring_t[j], ring_t[i]], center, layer)
		_add_poly(polys, [ring_t[i], ring_t[j], tip], center, layer)
	var pts: Array = []
	pts.append_array(ring_b)
	pts.append_array(ring_t)
	pts.append(tip)
	hulls.append({"pts": pts, "coll": "solid"})


## Добавляет многоугольник; порядок вершин подбирается так, чтобы нормаль (правило правой руки) смотрела от center.
static func _add_poly(polys: Array, pts: Array, center: Vector3, layer: int) -> void:
	var nrm := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	var mid := Vector3.ZERO
	for p: Vector3 in pts:
		mid += p
	mid /= float(pts.size())
	var ordered := pts.duplicate()
	if nrm.dot(mid - center) < 0.0:
		ordered.reverse()
	polys.append({"p": ordered, "layer": layer, "mode": 2})