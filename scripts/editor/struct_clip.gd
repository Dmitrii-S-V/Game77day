class_name StructClip
extends RefCounted
## Буфер/выделение редактора: список экземпляров блоков в прямоугольнике ячеек.
## Экземпляр: {off: Vector3i (якорь относительно угла прямоугольника), id, meta}. dims — размеры прямоугольника.
## Повороты и зеркала пересчитывают якоря и поворот каждого блока (многоячеечные блоки целиком).

var dims := Vector3i.ZERO
var inst: Array = []


static func capture(g: BlockGrid, lo: Vector3i, hi: Vector3i) -> StructClip:
	var c := StructClip.new()
	c.dims = hi - lo + Vector3i.ONE
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var id := g.get_cell(x, y, z)
				if id == 0 or not BlockRegistry.is_new(id):
					continue
				var m := g.get_meta_at(x, y, z)
				if BlockRegistry.is_part(m):
					continue
				c.inst.append({"off": Vector3i(x, y, z) - lo, "id": id, "meta": m})
	return c


func footprint_of(i: Dictionary) -> Vector3i:
	return BlockRegistry.footprint(int(i["id"]), BlockRegistry.rot_of(int(i["meta"])))


## Поворот на 90° вокруг вертикальной оси (в ту же сторону, что поворот блока в BlockShapes).
func rotated() -> StructClip:
	var out := StructClip.new()
	out.dims = Vector3i(dims.z, dims.y, dims.x)
	for i: Dictionary in inst:
		var o: Vector3i = i["off"]
		var f := footprint_of(i)
		var m: int = i["meta"]
		# с учётом «верха» (поворот по всем осям): та же ориентация, повёрнутая на 90° вокруг вертикали
		var nm := BlockRegistry.rotate_meta(m, Basis(Vector3.UP, PI * 0.5))
		out.inst.append({"off": Vector3i(o.z, o.y, dims.x - o.x - f.x), "id": i["id"], "meta": nm})
	return out


func mirrored_x() -> StructClip:
	var out := StructClip.new()
	out.dims = dims
	for i: Dictionary in inst:
		var o: Vector3i = i["off"]
		var f := footprint_of(i)
		var m: int = i["meta"]
		var r := BlockRegistry.rot_of(m)
		var nm := _with_rot(m, (r + 2) & 3) if (r & 1) == 1 else m
		out.inst.append({"off": Vector3i(dims.x - o.x - f.x, o.y, o.z), "id": i["id"], "meta": nm})
	return out


func mirrored_z() -> StructClip:
	var out := StructClip.new()
	out.dims = dims
	for i: Dictionary in inst:
		var o: Vector3i = i["off"]
		var f := footprint_of(i)
		var m: int = i["meta"]
		var r := BlockRegistry.rot_of(m)
		var nm := _with_rot(m, (r + 2) & 3) if (r & 1) == 0 else m
		out.inst.append({"off": Vector3i(o.x, o.y, dims.z - o.z - f.z), "id": i["id"], "meta": nm})
	return out


static func _with_rot(m: int, rot: int) -> int:
	return (m & ~3) | (rot & 3)


## Ставит экземпляры с углом прямоугольника в `at`. skip_blocked: пропускать занятые места.
## Возвращает занятые ячейки.
func place(g: BlockGrid, at: Vector3i, skip_blocked: bool = true) -> Array[Vector3i]:
	var placed: Array[Vector3i] = []
	for i: Dictionary in inst:
		var a: Vector3i = at + (i["off"] as Vector3i)
		var rot := BlockRegistry.rot_of(int(i["meta"]))
		if not g.can_place(a, int(i["id"]), rot):
			if skip_blocked:
				continue
		placed.append_array(g.place_block(a, int(i["id"]), int(i["meta"])))
	return placed
