class_name PoleGen
extends RefCounted
## Столбы: деревянный, сломанный (верхушка лежит рядом), упавший, фонарь, ржавый фонарь,
## ржавая металлическая опора. Возвращает меш (цвета в вершинах) и коробки коллизии.

const WOOD_A := Color(0.78, 0.72, 0.66)
const WOOD_B := Color(1.0, 0.94, 0.88)
const METAL := Color(0.8, 0.84, 0.82)
const RUST_A := Color(0.85, 0.7, 0.62)
const RUST_B := Color(1.0, 0.9, 0.82)
const INSUL := Color(0.45, 0.55, 0.52)


static func make(kind: String, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mb := MeshBuilder.new()
	var boxes: Array = []
	match kind:
		"wood":
			_wood(mb, rng, 9.5)
			boxes.append([Vector3(0, 4.5, 0), Vector3(0.4, 9.0, 0.4)])
		"broken":
			_broken(mb, rng)
			boxes.append([Vector3(0, 2.2, 0), Vector3(0.4, 4.4, 0.4)])
		"fallen":
			var b := MeshBuilder.new()
			_wood(b, rng, 9.0)
			var xf := Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0, 0.17, 0))
			mb.append(b, xf)
			boxes.append([Vector3(4.5, 0.2, 0), Vector3(9.0, 0.4, 0.4)])
		"lamp":
			_lamp(mb, rng, false)
			boxes.append([Vector3(0, 3.5, 0), Vector3(0.3, 7.0, 0.3)])
		"lamp_rust":
			_lamp(mb, rng, true)
			boxes.append([Vector3(0, 3.5, 0), Vector3(0.3, 7.0, 0.3)])
		_:
			_metal(mb, rng)
			boxes.append([Vector3(0, 4.8, 0), Vector3(0.5, 9.6, 0.5)])
	return {"mesh": mb.to_mesh(), "boxes": boxes}


static func _pts(list: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in list:
		out.append(p)
	return out


static func _radii(list: Array) -> Array[float]:
	var out: Array[float] = []
	for r: float in list:
		out.append(r)
	return out


static func _wood(mb: MeshBuilder, rng: RandomNumberGenerator, h: float) -> void:
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	ModelGen._tube(mb, _pts([Vector3.ZERO, lean * 0.5 + Vector3(0, h * 0.5, 0), lean + Vector3(0, h, 0)]), _radii([0.2, 0.15, 0.11]), 8, WOOD_A, WOOD_B, rng)
	var top := lean + Vector3(0, h, 0)
	mb.box(top + Vector3(0, -0.8, 0), Vector3(2.1, 0.12, 0.14), WOOD_A)
	mb.box(top + Vector3(0, -1.7, 0), Vector3(1.4, 0.1, 0.12), WOOD_A)
	for x in [-0.85, 0.0, 0.85]:
		mb.box(top + Vector3(x, -0.68, 0), Vector3(0.08, 0.14, 0.08), INSUL)
	for x in [-0.55, 0.55]:
		mb.box(top + Vector3(x, -1.58, 0), Vector3(0.07, 0.12, 0.07), INSUL)


static func _broken(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var hb := rng.randf_range(3.6, 5.2)
	var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
	ModelGen._tube(mb, _pts([Vector3.ZERO, lean * 0.5 + Vector3(0, hb * 0.5, 0), lean + Vector3(0, hb, 0)]), _radii([0.2, 0.17, 0.15]), 8, WOOD_A, WOOD_B, rng)
	var top := lean + Vector3(0, hb, 0)
	for i in 4:
		var a := rng.randf() * TAU
		var tip := top + Vector3(cos(a) * 0.1, rng.randf_range(0.3, 0.9), sin(a) * 0.1)
		ModelGen._tube(mb, _pts([top + Vector3(cos(a) * 0.1, -0.05, sin(a) * 0.1), tip]), _radii([0.07, 0.015]), 5, WOOD_B, Color(0.62, 0.52, 0.38), rng)
	# верхняя часть лежит рядом на земле, с траверсой
	var piece := MeshBuilder.new()
	ModelGen._tube(piece, _pts([Vector3.ZERO, Vector3(0, 2.0, 0), Vector3(0, 4.0, 0)]), _radii([0.15, 0.13, 0.11]), 8, WOOD_A, WOOD_B, rng)
	piece.box(Vector3(0, 3.3, 0), Vector3(2.0, 0.12, 0.14), WOOD_A)
	for x in [-0.8, 0.0, 0.8]:
		piece.box(Vector3(x, 3.42, 0), Vector3(0.08, 0.14, 0.08), INSUL)
	var yaw := rng.randf() * TAU
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(1.5, 0.15, 0.8).rotated(Vector3.UP, yaw))
	mb.append(piece, xf)


static func _lamp(mb: MeshBuilder, rng: RandomNumberGenerator, rusty: bool) -> void:
	var ca := RUST_A if rusty else METAL
	var cb := RUST_B if rusty else METAL.lightened(0.12)
	var h := 7.2
	var lean := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
	if rusty:
		lean = Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.4, 0.4))
	ModelGen._tube(mb, _pts([Vector3(0, 0, 0), Vector3(0, 0.45, 0), lean * 0.5 + Vector3(0, h * 0.5, 0), lean + Vector3(0, h, 0)]), _radii([0.2, 0.12, 0.1, 0.07]), 8, ca, cb, rng)
	var top := lean + Vector3(0, h, 0)
	ModelGen._tube(mb, _pts([top, top + Vector3(0.5, 0.35, 0), top + Vector3(1.4, 0.4, 0)]), _radii([0.06, 0.05, 0.045]), 6, ca, cb, rng)
	var head := MeshBuilder.new()
	head.box(Vector3.ZERO, Vector3(0.75, 0.15, 0.32), ca.darkened(0.25))
	head.box(Vector3(0, -0.09, 0), Vector3(0.6, 0.04, 0.24), Color(0.85, 0.82, 0.65) if not rusty else Color(0.25, 0.25, 0.22))
	var hang := Basis(Vector3(0, 0, 1), rng.randf_range(0.5, 0.9)) if (rusty and rng.randf() < 0.5) else Basis.IDENTITY
	mb.append(head, Transform3D(hang, top + Vector3(1.5, 0.35, 0)))


static func _metal(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var h := 9.6
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
	ModelGen._tube(mb, _pts([Vector3.ZERO, lean * 0.5 + Vector3(0, h * 0.5, 0), lean + Vector3(0, h, 0)]), _radii([0.24, 0.17, 0.1]), 8, RUST_A, RUST_B, rng)
	var top := lean + Vector3(0, h, 0)
	mb.box(top + Vector3(0, -0.5, 0), Vector3(2.6, 0.1, 0.1), RUST_A)
	mb.box(top + Vector3(0, -1.3, 0), Vector3(1.8, 0.1, 0.1), RUST_A)
	for x in [-1.1, 0.0, 1.1]:
		mb.box(top + Vector3(x, -0.4, 0), Vector3(0.08, 0.16, 0.08), INSUL.darkened(0.2))
