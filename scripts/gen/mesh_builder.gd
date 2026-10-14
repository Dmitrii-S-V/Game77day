class_name MeshBuilder
extends RefCounted
## Сборщик процедурных мешей с цветом в вершинах. Порядок вершин в tri() — против часовой
## стрелки, если смотреть снаружи; внутри конвертируется в порядок Godot (по часовой).

var verts := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var uvs := PackedVector2Array()
var nrms := PackedVector3Array()    # заданные нормали (нулевая — считать по граням)


func vert(p: Vector3, c: Color) -> int:
	verts.append(p)
	cols.append(c)
	uvs.append(Vector2.ZERO)
	nrms.append(Vector3.ZERO)
	return verts.size() - 1


## Вершина с UV и явной нормалью (карточки листвы).
func vert_full(p: Vector3, c: Color, uv: Vector2, n: Vector3) -> int:
	verts.append(p)
	cols.append(c)
	uvs.append(uv)
	nrms.append(n)
	return verts.size() - 1


func tri(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(c)
	idx.append(b)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## Плоская грань с собственными вершинами; ориентируется сама, чтобы смотреть в сторону outward.
func face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var t := b
		b = d
		d = t
	quad(vert(a, col), vert(b, col), vert(c, col), vert(d, col))


func tface(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
	tri(vert(a, col), vert(b, col), vert(c, col))


func box(center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	face(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT, col)
	face(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT, col)
	face(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
	face(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, col)
	face(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, col)
	face(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, col)


## Добавляет готовый ArrayMesh (вершины, цвета, индексы) как есть.
func append_mesh(m: ArrayMesh, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var arr := m.surface_get_arrays(0)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var off := verts.size()
	for i in vv.size():
		verts.append(xf * vv[i])
		cols.append(cc[i] if i < cc.size() else Color.WHITE)
		uvs.append(Vector2.ZERO)
		nrms.append(Vector3.ZERO)
	for i in ii:
		idx.append(i + off)


func append(o: MeshBuilder, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var off := verts.size()
	for i in o.verts.size():
		verts.append(xf * o.verts[i])
		cols.append(o.cols[i])
		uvs.append(o.uvs[i])
		nrms.append(xf.basis * o.nrms[i])
	for i in o.idx:
		idx.append(i + off)


func to_mesh() -> ArrayMesh:
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var c := idx[t + 1]
		var b := idx[t + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		nrm[a] += n
		nrm[b] += n
		nrm[c] += n
	for i in nrm.size():
		if nrms[i].length_squared() > 1e-6:
			nrm[i] = nrms[i].normalized()
		else:
			nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 1e-12 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
