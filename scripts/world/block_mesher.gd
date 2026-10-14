class_name BlockMesher
extends RefCounted
## Меш одного куска (8x8x8 ячеек) здания: только видимые грани кубов, AO по вершинам.
## Два меша: непрозрачный и стеклянный. Координаты — в пространстве сетки (метры).
## Старые блоки (id 1..18) рисует процедурный шейдер по id; новые (id >= 32) берут текстуру из
## Texture2DArray (UV2.x — слой, UV2.y — режим: 0 куб, 1 каркас, 2 UV грани, 3 UV грани светящийся).
## Нестандартные блоки (двери, окна, декор) эмитятся из BlockShapes только с ячейки-якоря и тоже
## попадают в меш куска (батчинг); их коллизия — отдельные тела в BlockBuilding.

const B := BlockGrid.B
const CS := BlockGrid.CS
const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const TU := [Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]
const TV := [Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 1, 0)]
const SU := [-1, 1, 1, -1]
const SV := [-1, -1, 1, 1]
const QUAD_ORDER := [[0, 1, 2, 3], [0, 3, 2, 1]]


## Закрывает ли ячейка грани соседей и даёт ли тень AO.
static func _occ(g: BlockGrid, x: int, y: int, z: int) -> bool:
	var id := g.get_cell(x, y, z)
	if id == 0 or id == BlockDefs.GLASS:
		return false
	if id < BlockRegistry.FIRST_ID:
		return true
	return BlockRegistry.occludes(id, g.get_meta_at(x, y, z))


static func build_chunk(g: BlockGrid, cx: int, cy: int, cz: int) -> Dictionary:
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	var ou := PackedVector2Array()
	var ou2 := PackedVector2Array()
	var oi := PackedInt32Array()
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var gc := PackedColorArray()
	var gi := PackedInt32Array()
	var faces := PackedVector3Array()
	var tint := g.tint / 4.0
	for z in range(cz * CS, mini((cz + 1) * CS, g.nz)):
		for y in range(cy * CS, mini((cy + 1) * CS, g.ny)):
			for x in range(cx * CS, mini((cx + 1) * CS, g.nx)):
				var ci := x + g.nx * (y + g.ny * z)
				var id := g.cells[ci]
				if id == 0:
					continue
				var is_new := id >= BlockRegistry.FIRST_ID
				var cell_meta := g.meta[ci]
				var layer := 0
				var mode := 0.0
				var inv_tile := 1.0
				if is_new:
					if not BlockRegistry.is_cube(id):
						if not BlockRegistry.is_part(cell_meta):
							_emit_custom(g, Vector3i(x, y, z), id, cell_meta, tint, ov, on, oc, ou, ou2, oi, gv, gn, gc, gi)
						continue
					var tier := BlockRegistry.tier_of(cell_meta)
					layer = BlockRegistry.tex_layer(id, tier, BlockRegistry.variant_of(cell_meta))
					mode = 1.0 if BlockRegistry.is_frame(id, tier) else 0.0
					inv_tile = 1.0 / BlockRegistry.tile_of(id, tier)
				var glass := id == BlockDefs.GLASS
				var var_h := float((((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 255)) / 255.0
				for d in 6:
					var n: Vector3i = DIRS[d]
					if glass:
						if g.get_cell(x + n.x, y + n.y, z + n.z) != 0:
							continue
					elif _occ(g, x + n.x, y + n.y, z + n.z):
						continue
					var tu: Vector3i = TU[d]
					var tv: Vector3i = TV[d]
					var plane := 1 if (n.x > 0 or n.y > 0 or n.z > 0) else 0
					var qv: Array[Vector3] = []
					var qa: Array[float] = []
					for k in 4:
						var su: int = SU[k]
						var sv: int = SV[k]
						var p := Vector3(x, y, z) + Vector3(absi(n.x), absi(n.y), absi(n.z)) * plane
						p += Vector3(tu) * (1.0 if su > 0 else 0.0) + Vector3(tv) * (1.0 if sv > 0 else 0.0)
						qv.append(p * B)
						var base := Vector3i(x, y, z) + n
						var s1 := _occ(g, base.x + tu.x * su, base.y + tu.y * su, base.z + tu.z * su)
						var s2 := _occ(g, base.x + tv.x * sv, base.y + tv.y * sv, base.z + tv.z * sv)
						var c2 := _occ(g, base.x + tu.x * su + tv.x * sv, base.y + tu.y * su + tv.y * sv, base.z + tu.z * su + tv.z * sv)
						var occ := 3 if (s1 and s2) else (int(s1) + int(s2) + int(c2))
						qa.append(1.0 - occ * 0.18)
					var order: Array = QUAD_ORDER[d % 2]
					var nrm := Vector3(n)
					if glass:
						var bi := gv.size()
						for k in 4:
							var o: int = order[k]
							gv.append(qv[o])
							gn.append(nrm)
							gc.append(Color(id / 255.0, 0.5, qa[o], tint))
						gi.append_array(PackedInt32Array([bi, bi + 2, bi + 1, bi, bi + 3, bi + 2]))
					else:
						var bi := ov.size()
						for k in 4:
							var o: int = order[k]
							ov.append(qv[o])
							on.append(nrm)
							oc.append(Color(id / 255.0, var_h, qa[o], tint))
							ou.append(Vector2(inv_tile, float(g.decals.get(ci * 8 + d, 0))))
							ou2.append(Vector2(layer, mode))
						oi.append_array(PackedInt32Array([bi, bi + 2, bi + 1, bi, bi + 3, bi + 2]))
					for t in [0, 2, 1, 0, 3, 2]:
						faces.append(qv[order[t]])
	return {"ov": ov, "on": on, "oc": oc, "ou": ou, "ou2": ou2, "oi": oi, "gv": gv, "gn": gn, "gc": gc, "gi": gi, "faces": faces}


# --- нестандартные блоки -----------------------------------------------------------------

static func _emit_custom(g: BlockGrid, anchor: Vector3i, id: int, m: int, tint: float, ov: PackedVector3Array, on: PackedVector3Array, oc: PackedColorArray, ou: PackedVector2Array, ou2: PackedVector2Array, oi: PackedInt32Array, gv: PackedVector3Array, gn: PackedVector3Array, gc: PackedColorArray, gi: PackedInt32Array) -> void:
	var parts := BlockShapes.build(id, m)
	var org := Vector3(anchor) * B
	var ptile := 1.0 / BlockRegistry.tile_of(id, BlockRegistry.tier_of(m))
	var col := Color(id / 255.0, 0.5, 0.92, tint)
	for b: Dictionary in parts["boxes"]:
		if b.get("hidden", false):
			continue
		var a: Vector3 = org + (b["a"] as Vector3)
		var c: Vector3 = org + (b["b"] as Vector3)
		var layer: int = b["layer"]
		var mode: float = float(b["mode"])
		var glass: bool = b["glass"]
		var faces: Array = [
			[Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, c.z), Vector3(a.x, c.y, c.z), Vector3(a.x, c.y, a.z), Vector3(-1, 0, 0)],
			[Vector3(c.x, a.y, a.z), Vector3(c.x, c.y, a.z), Vector3(c.x, c.y, c.z), Vector3(c.x, a.y, c.z), Vector3(1, 0, 0)],
			[Vector3(a.x, a.y, a.z), Vector3(c.x, a.y, a.z), Vector3(c.x, a.y, c.z), Vector3(a.x, a.y, c.z), Vector3(0, -1, 0)],
			[Vector3(a.x, c.y, a.z), Vector3(a.x, c.y, c.z), Vector3(c.x, c.y, c.z), Vector3(c.x, c.y, a.z), Vector3(0, 1, 0)],
			[Vector3(a.x, a.y, a.z), Vector3(a.x, c.y, a.z), Vector3(c.x, c.y, a.z), Vector3(c.x, a.y, a.z), Vector3(0, 0, -1)],
			[Vector3(a.x, a.y, c.z), Vector3(c.x, a.y, c.z), Vector3(c.x, c.y, c.z), Vector3(a.x, c.y, c.z), Vector3(0, 0, 1)],
		]
		for f: Array in faces:
			var nrm: Vector3 = f[4]
			var q: Array = [f[0], f[1], f[2], f[3]]
			if glass:
				_quad_glass(q, nrm, col, gv, gn, gc, gi)
			else:
				_quad(q, nrm, col, layer, mode, ov, on, oc, ou, ou2, oi, false)
	for pl: Dictionary in parts.get("polys", []):
		var pp: Array = pl["p"]
		var wp: Array = []
		for p: Vector3 in pp:
			wp.append(org + p)
		_poly(wp, col, int(pl["layer"]), float(pl["mode"]), ptile, ov, on, oc, ou, ou2, oi)
	for qd: Dictionary in parts["quads"]:
		var pts: Array = []
		for p: Vector3 in qd["p"]:
			pts.append(org + p)
		var nrm := ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[3] as Vector3) - (pts[0] as Vector3)).normalized()
		_quad(pts, nrm, col, int(qd["layer"]), float(qd["mode"]), ov, on, oc, ou, ou2, oi, true)


## Четырёхугольник v0..v3 (обход по контуру) с UV 0..1; нужный порядок вершин (по часовой снаружи) подбирается по нормали.
static func _quad(q: Array, nrm: Vector3, col: Color, layer: int, mode: float, ov: PackedVector3Array, on: PackedVector3Array, oc: PackedColorArray, ou: PackedVector2Array, ou2: PackedVector2Array, oi: PackedInt32Array, both: bool) -> void:
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for side in (2 if both else 1):
		var n2 := nrm if side == 0 else -nrm
		var order := [0, 1, 2, 3]
		var cr := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3))
		var need_swap := cr.dot(n2) > 0.0   # по часовой при виде снаружи: нормаль грани противоположна векторному произведению
		if need_swap:
			order = [0, 3, 2, 1]
		var bi := ov.size()
		for k in 4:
			var o: int = order[k]
			ov.append(q[o])
			on.append(n2)
			oc.append(col)
			ou.append(uvs[o])
			ou2.append(Vector2(layer, mode))
		oi.append_array(PackedInt32Array([bi, bi + 1, bi + 2, bi, bi + 2, bi + 3]))


static func _quad_glass(q: Array, nrm: Vector3, col: Color, gv: PackedVector3Array, gn: PackedVector3Array, gc: PackedColorArray, gi: PackedInt32Array) -> void:
	var order := [0, 1, 2, 3]
	var cr := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3))
	if cr.dot(nrm) > 0.0:
		order = [0, 3, 2, 1]
	var bi := gv.size()
	for k in 4:
		var o: int = order[k]
		gv.append(q[o])
		gn.append(nrm)
		gc.append(col)
	gi.append_array(PackedInt32Array([bi, bi + 1, bi + 2, bi, bi + 2, bi + 3]))


## Выпуклый многоугольник (вершины против часовой при виде снаружи) -> веер треугольников, плоская нормаль,
## UV проекцией по доминирующей оси нормали (в метрах объекта, как у кубов).
static func _poly(pts: Array, col: Color, layer: int, mode: float, inv_tile: float, ov: PackedVector3Array, on: PackedVector3Array, oc: PackedColorArray, ou: PackedVector2Array, ou2: PackedVector2Array, oi: PackedInt32Array) -> void:
	var n := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	n = n.normalized()
	var axis := 1 if (absf(n.y) >= absf(n.x) and absf(n.y) >= absf(n.z)) else (0 if absf(n.x) > absf(n.z) else 2)
	var bi := ov.size()
	for p: Vector3 in pts:
		ov.append(p)
		on.append(n)
		oc.append(col)
		var u := Vector2.ZERO
		match axis:
			0: u = Vector2(p.z, p.y)
			1: u = Vector2(p.x, p.z)
			_: u = Vector2(p.x, p.y)
		ou.append(u * inv_tile)
		ou2.append(Vector2(layer, mode))
	# CCW снаружи -> по часовой в Godot: разворачиваем веер
	for i in range(1, pts.size() - 1):
		oi.append_array(PackedInt32Array([bi, bi + i + 1, bi + i]))