class_name Hydro
extends RefCounted
## Реки и озёра: русла вырезаются в рельефе, уровень воды у каждой реки/озера свой.
## Данные только читаются после генерации (потокобезопасно).

const CELL := 32.0
const RS := 12   # шаг в массиве сегментов рек: ax az al bx bz bl hw0 hw1 minx maxx minz maxz
const LS := 8    # шаг в массиве озёр: cx cz R level depth ph1 ph2 reach

var rseg := PackedFloat32Array()
var rn := 0
var rcells := {}
var lake := PackedFloat32Array()
var ln := 0
var lcells := {}
var rivers: Array = []   # {pts, level, hw}
var lakes: Array = []    # {center, R, level, ph1, ph2}


func add_river(pts: PackedVector2Array, level: PackedFloat32Array, hw: PackedFloat32Array) -> void:
	rivers.append({"pts": pts, "level": level, "hw": hw})
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var m := maxf(hw[i], hw[i + 1]) * 2.6 + 8.0
		var minx := minf(a.x, b.x) - m
		var maxx := maxf(a.x, b.x) + m
		var minz := minf(a.y, b.y) - m
		var maxz := maxf(a.y, b.y) + m
		rseg.append_array(PackedFloat32Array([a.x, a.y, level[i], b.x, b.y, level[i + 1], hw[i], hw[i + 1], minx, maxx, minz, maxz]))
		_register(rcells, rn, minx, maxx, minz, maxz)
		rn += 1


func add_lake(c: Vector2, radius: float, level: float, depth: float, ph1: float, ph2: float) -> void:
	lakes.append({"center": c, "R": radius, "level": level, "ph1": ph1, "ph2": ph2})
	var reach := radius * 1.6
	lake.append_array(PackedFloat32Array([c.x, c.y, radius, level, depth, ph1, ph2, reach]))
	_register(lcells, ln, c.x - reach, c.x + reach, c.y - reach, c.y + reach)
	ln += 1


func lake_radius(r: float, ph1: float, ph2: float, ang: float) -> float:
	return r * (1.0 + 0.22 * sin(3.0 * ang + ph1) + 0.12 * sin(5.0 * ang + ph2))


func _register(cells: Dictionary, idx: int, minx: float, maxx: float, minz: float, maxz: float) -> void:
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			var arr: PackedInt32Array = cells.get(key, PackedInt32Array())
			arr.append(idx)
			cells[key] = arr


## Есть ли вода (русло или озеро) ближе чем r метров от точки.
func near(x: float, z: float, r: float) -> bool:
	if rn == 0 and ln == 0:
		return false
	var key0 := Vector2i(floori(x / CELL), floori(z / CELL))
	var cr := int(ceil(r / CELL)) + 1
	for cz in range(key0.y - cr, key0.y + cr + 1):
		for cx in range(key0.x - cr, key0.x + cr + 1):
			var key := Vector2i(cx, cz)
			if rcells.has(key):
				for i: int in rcells[key]:
					var q := i * RS
					var d := _seg_dist(x, z, rseg[q], rseg[q + 1], rseg[q + 3], rseg[q + 4])
					if d < maxf(rseg[q + 6], rseg[q + 7]) + r:
						return true
			if lcells.has(key):
				for i: int in lcells[key]:
					var q := i * LS
					var dd := Vector2(x - lake[q], z - lake[q + 1]).length()
					if dd < lake[q + 2] * 1.35 + r:
						return true
	return false


func in_lake(x: float, z: float, margin: float = 0.0) -> bool:
	if ln == 0:
		return false
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if not lcells.has(key):
		return false
	for i: int in lcells[key]:
		var q := i * LS
		var dx := x - lake[q]
		var dz := z - lake[q + 1]
		var r := sqrt(dx * dx + dz * dz)
		if r < lake_radius(lake[q + 2], lake[q + 5], lake[q + 6], atan2(dz, dx)) * 1.1 + margin:
			return true
	return false


## Минимальная высота дороги, чтобы она не оказалась под водой: уровень реки + запас (или -INF).
func min_road_height(x: float, z: float) -> float:
	if rn == 0:
		return -INF
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if not rcells.has(key):
		return -INF
	var best := -INF
	for i: int in rcells[key]:
		var q := i * RS
		var abx := rseg[q + 3] - rseg[q]
		var abz := rseg[q + 4] - rseg[q + 1]
		var l2 := abx * abx + abz * abz
		var t := 0.0
		if l2 > 1e-6:
			t = clampf(((x - rseg[q]) * abx + (z - rseg[q + 1]) * abz) / l2, 0.0, 1.0)
		var d := _seg_dist(x, z, rseg[q], rseg[q + 1], rseg[q + 3], rseg[q + 4])
		var hw := lerpf(rseg[q + 6], rseg[q + 7], t)
		if d < hw + 6.0:
			best = maxf(best, lerpf(rseg[q + 2], rseg[q + 5], t) + 0.9)
	return best


## Уровень воды, если точка в зоне русла или озера (иначе -1e9). Для дальнего ландшафта: не проседать ниже воды.
func water_floor(x: float, z: float) -> float:
	var best := -1e9
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if rcells.has(key):
		for i: int in rcells[key]:
			var q := i * RS
			var abx := rseg[q + 3] - rseg[q]
			var abz := rseg[q + 4] - rseg[q + 1]
			var l2 := abx * abx + abz * abz
			var t := 0.0
			if l2 > 1e-6:
				t = clampf(((x - rseg[q]) * abx + (z - rseg[q + 1]) * abz) / l2, 0.0, 1.0)
			var d := _seg_dist(x, z, rseg[q], rseg[q + 1], rseg[q + 3], rseg[q + 4])
			var hw := maxf(lerpf(rseg[q + 6], rseg[q + 7], t), 7.0)
			if d < hw * 1.6 + 6.0:
				best = maxf(best, lerpf(rseg[q + 2], rseg[q + 5], t))
	if lcells.has(key):
		for i: int in lcells[key]:
			var q := i * LS
			var dx := x - lake[q]
			var dz := z - lake[q + 1]
			if sqrt(dx * dx + dz * dz) < lake_radius(lake[q + 2], lake[q + 5], lake[q + 6], atan2(dz, dx)) * 1.5:
				best = maxf(best, lake[q + 3])
	return best

func carve_at(x: float, z: float, h: float, min_hw: float = 0.0) -> float:
	if rn == 0 and ln == 0:
		return h
	var arr := PackedFloat32Array([h])
	apply(int(floor(x)), int(floor(z)), 1, arr, PackedByteArray([0]), x - floor(x), z - floor(z), min_hw)
	return arr[0]


static func _seg_dist(x: float, z: float, ax: float, az: float, bx: float, bz: float) -> float:
	var abx := bx - ax
	var abz := bz - az
	var l2 := abx * abx + abz * abz
	var t := 0.0
	if l2 > 1e-6:
		t = clampf(((x - ax) * abx + (z - az) * abz) / l2, 0.0, 1.0)
	var dx := x - (ax + abx * t)
	var dz := z - (az + abz * t)
	return sqrt(dx * dx + dz * dz)


## Вырезает русла и озёра в высотах h (w x w узлов от (x0, z0)); flags[k]=1 — вода рядом.
func apply(x0: int, z0: int, w: int, h: PackedFloat32Array, flags: PackedByteArray, fx: float = 0.0, fz: float = 0.0, min_hw: float = 0.0) -> void:
	if rn == 0 and ln == 0:
		return
	var pad := 40.0
	var minx := x0 - pad
	var maxx := x0 + w + pad
	var minz := z0 - pad
	var maxz := z0 + w + pad
	var rs := PackedFloat32Array()
	var lk := PackedFloat32Array()
	var seen := {}
	var seen_l := {}
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			if rcells.has(key):
				for i: int in rcells[key]:
					if not seen.has(i):
						seen[i] = true
						rs.append_array(rseg.slice(i * RS, i * RS + RS))
			if lcells.has(key):
				for i: int in lcells[key]:
					if not seen_l.has(i):
						seen_l[i] = true
						lk.append_array(lake.slice(i * LS, i * LS + LS))
	if rs.is_empty() and lk.is_empty():
		return
	for j in w:
		var z := z0 + j + fz
		for i in w:
			var x := x0 + i + fx
			var k := i + w * j
			var hh := h[k]
			for q in range(0, rs.size(), RS):
				if x < rs[q + 8] or x > rs[q + 9] or z < rs[q + 10] or z > rs[q + 11]:
					continue
				var ax := rs[q]
				var az := rs[q + 1]
				var abx := rs[q + 3] - ax
				var abz := rs[q + 4] - az
				var l2 := abx * abx + abz * abz
				var t := 0.0
				if l2 > 1e-6:
					t = clampf(((x - ax) * abx + (z - az) * abz) / l2, 0.0, 1.0)
				var dx := x - (ax + abx * t)
				var dz := z - (az + abz * t)
				var d := sqrt(dx * dx + dz * dz)
				var hw := maxf(lerpf(rs[q + 6], rs[q + 7], t), min_hw)
				var bank := hw * 1.6 + 5.0
				if d < hw + bank:
					var level := lerpf(rs[q + 2], rs[q + 5], t)
					var edge := level + 0.5
					var bed := level - (1.3 + hw * 0.2)
					var wr := 1.0 - smoothstep(hw + bank * 0.55, hw + bank, d)
					var h0 := h[k]
					var hn := 0.0
					if d <= hw:
						var u := d / hw
						hn = bed + (edge - bed) * u * u
					else:
						hn = lerpf(edge, maxf(h0, edge), smoothstep(hw, hw + bank * 0.8, d))
					# только вниз: соседние сегменты не должны «досыпать» уже прорытое русло
					hh = minf(hh, lerpf(h0, hn, wr))
					if d < hw * 1.1 + 2.5:
						flags[k] = 1
			for q in range(0, lk.size(), LS):
				var dx := x - lk[q]
				var dz := z - lk[q + 1]
				var r := sqrt(dx * dx + dz * dz)
				if r > lk[q + 7]:
					continue
				var reff := lake_radius(lk[q + 2], lk[q + 5], lk[q + 6], atan2(dz, dx))
				if r < reff * 1.5:
					var edge := lk[q + 3] + 0.5
					var wr := 1.0 - smoothstep(reff * 1.15, reff * 1.5, r)
					var hn := 0.0
					if r <= reff:
						var u := r / reff
						hn = edge - (lk[q + 4] + 0.5) * (1.0 - u * u)
					else:
						hn = lerpf(edge, maxf(hh, edge), smoothstep(reff, reff * 1.3, r))
					hh = lerpf(hh, hn, wr)
					if r < reff * 1.1:
						flags[k] = 1
			h[k] = hh


## Меши воды: реки (ленты) и озёра (многоугольники). UV.x = поперёк 0..1, UV.y = вдоль в метрах.
func build_water_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r: Dictionary in rivers:
		var pts: PackedVector2Array = r["pts"]
		var lv: PackedFloat32Array = r["level"]
		var hw: PackedFloat32Array = r["hw"]
		var along := 0.0
		var base := verts.size()
		for i in pts.size():
			var dir := Vector2.ZERO
			if i > 0:
				dir += (pts[i] - pts[i - 1]).normalized()
			if i < pts.size() - 1:
				dir += (pts[i + 1] - pts[i]).normalized()
			dir = dir.normalized()
			var n := Vector2(-dir.y, dir.x)
			var half := hw[i] * 1.12
			var a := pts[i] + n * half
			var b := pts[i] - n * half
			if i > 0:
				along += pts[i].distance_to(pts[i - 1])
			verts.append(Vector3(a.x, lv[i] - 0.1, a.y))
			verts.append(Vector3(b.x, lv[i] - 0.1, b.y))
			uvs.append(Vector2(0.0, along))
			uvs.append(Vector2(1.0, along))
		for i in pts.size() - 1:
			var o := base + i * 2
			# a = левая кромка (+n), b = правая; порядок "по часовой" сверху
			idx.append_array(PackedInt32Array([o + 1, o + 3, o + 2, o + 1, o + 2, o]))
	for q in range(0, ln * LS, LS):
		var c := Vector2(lake[q], lake[q + 1])
		var level := lake[q + 3]
		var base := verts.size()
		verts.append(Vector3(c.x, level - 0.1, c.y))
		uvs.append(Vector2(0.5, 0.0))
		var seg := 56
		for s in seg:
			var ang := TAU * s / seg
			var rr := lake_radius(lake[q + 2], lake[q + 5], lake[q + 6], ang) * 1.05
			verts.append(Vector3(c.x + cos(ang) * rr, level - 0.1, c.y + sin(ang) * rr))
			uvs.append(Vector2(0.5, rr))
		for s in seg:
			idx.append_array(PackedInt32Array([base, base + 1 + s, base + 1 + (s + 1) % seg]))
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
