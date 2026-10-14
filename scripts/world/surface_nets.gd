class_name SurfaceNets
extends RefCounted
## Surface Nets: превращает поле плотности (с отступом в 1 узел вокруг чанка) в
## гладкую сетку. Вершины на стыках чанков совпадают, швов нет.
## Вход: PAD^3 значений плотности/материала, индекс x + PAD*(y + PAD*z), где узел 0 = координата -1.
## Веса материалов (до 9): COLOR = 0..3, CUSTOM0 = 4..7, UV.x = 8.

const N := WorldGen.CHUNK
const PAD := N + 2
const COFF := [0, 1, PAD, PAD + 1, PAD * PAD, PAD * PAD + 1, PAD * PAD + PAD, PAD * PAD + PAD + 1]
const CPOS := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]
const EA := [0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3]
const EB := [1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7]

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var custom0 := PackedFloat32Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()

var _cell := PackedInt32Array()
var _d := PackedFloat32Array()
var _m := PackedByteArray()


func build(d: PackedFloat32Array, m: PackedByteArray) -> bool:
	_d = d
	_m = m
	_cell.resize(PAD * PAD * PAD)
	_cell.fill(-1)
	for z in range(1, N + 1):
		for y in range(1, N + 1):
			for x in range(1, N + 1):
				var i := x + PAD * (y + PAD * z)
				var s := d[i] > 0.0
				if s != (d[i + 1] > 0.0):
					_quad(_v(x, y - 1, z - 1), _v(x, y, z - 1), _v(x, y, z), _v(x, y - 1, z), s)
				if s != (d[i + PAD] > 0.0):
					_quad(_v(x - 1, y, z - 1), _v(x - 1, y, z), _v(x, y, z), _v(x, y, z - 1), s)
				if s != (d[i + PAD * PAD] > 0.0):
					_quad(_v(x - 1, y - 1, z), _v(x, y - 1, z), _v(x, y, z), _v(x - 1, y, z), s)
	return indices.size() > 0


func _quad(a: int, b: int, c: int, d: int, flip: bool) -> void:
	if flip:
		indices.append_array(PackedInt32Array([a, d, c, a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c, a, c, d]))


func _v(x: int, y: int, z: int) -> int:
	var ci := x + PAD * (y + PAD * z)
	var v := _cell[ci]
	if v < 0:
		v = _make_vertex(x, y, z)
		_cell[ci] = v
	return v


func _make_vertex(x: int, y: int, z: int) -> int:
	var base := x + PAD * (y + PAD * z)
	var cv := PackedFloat32Array()
	cv.resize(8)
	for i in 8:
		cv[i] = _d[base + COFF[i]]

	var sum := Vector3.ZERO
	var cnt := 0
	for e in 12:
		var ca: int = EA[e]
		var cb: int = EB[e]
		var a := cv[ca]
		var b := cv[cb]
		if (a > 0.0) != (b > 0.0):
			var pa: Vector3 = CPOS[ca]
			var pb: Vector3 = CPOS[cb]
			sum += pa.lerp(pb, a / (a - b))
			cnt += 1
	var pos := Vector3(x - 1, y - 1, z - 1) + sum / float(maxi(cnt, 1))

	var g := Vector3(
		cv[1] - cv[0] + cv[3] - cv[2] + cv[5] - cv[4] + cv[7] - cv[6],
		cv[2] - cv[0] + cv[3] - cv[1] + cv[6] - cv[4] + cv[7] - cv[5],
		cv[4] - cv[0] + cv[5] - cv[1] + cv[6] - cv[2] + cv[7] - cv[3])
	var nrm := Vector3.UP
	if g.length_squared() > 1e-12:
		nrm = -g.normalized()

	var w := PackedFloat32Array()
	w.resize(9)
	var total := 0.0
	for i in 8:
		if cv[i] > 0.0:
			w[mini(_m[base + COFF[i]], 8)] += 1.0
			total += 1.0
	total = maxf(total, 1.0)

	verts.append(pos)
	norms.append(nrm)
	cols.append(Color(w[0] / total, w[1] / total, w[2] / total, w[3] / total))
	custom0.append_array(PackedFloat32Array([w[4] / total, w[5] / total, w[6] / total, w[7] / total]))
	uvs.append(Vector2(w[8] / total, 0.0))
	return verts.size() - 1
