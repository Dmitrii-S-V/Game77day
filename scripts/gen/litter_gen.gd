class_name LitterGen
extends RefCounted
## Мусор вдоль дорог: покрышки, бочки, доски, пакеты, коробки, банки.
## Возвращает меш (цвета вершин; текстуры дают материалы Settlement) и коробки коллизии.


static func make(kind: String, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mb := MeshBuilder.new()
	var boxes: Array = []
	match kind:
		"tire":
			_torus(mb, 0.31, 0.125, Color(0.07, 0.07, 0.075))
			boxes.append([Vector3(0, 0.13, 0), Vector3(0.7, 0.26, 0.7)])
		"barrel":
			var col := Color(0.95, 0.75, 0.62) if rng.randf() < 0.6 else Color(0.55, 0.62, 0.7)
			mb.append_mesh(ItemModels.lathe([Vector2(0.0, 0.0), Vector2(0.27, 0.0), Vector2(0.295, 0.04), Vector2(0.295, 0.28), Vector2(0.31, 0.3),
				Vector2(0.295, 0.32), Vector2(0.295, 0.58), Vector2(0.31, 0.6), Vector2(0.295, 0.62), Vector2(0.295, 0.86), Vector2(0.27, 0.9), Vector2(0.0, 0.9)], 16, col))
			boxes.append([Vector3(0, 0.45, 0), Vector3(0.62, 0.9, 0.62)])
		"planks":
			for i in rng.randi_range(3, 5):
				var b := MeshBuilder.new()
				var l := rng.randf_range(0.9, 1.6)
				b.box(Vector3(0, 0.02, 0), Vector3(l, 0.035, rng.randf_range(0.1, 0.18)), Color(0.9, 0.85, 0.78).darkened(rng.randf_range(0.0, 0.3)))
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * 1.2 - 0.6) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06)), Vector3(rng.randf_range(-0.12, 0.12), i * 0.04, rng.randf_range(-0.2, 0.2)))
				mb.append(b, xf)
			boxes.append([Vector3(0, 0.1, 0), Vector3(1.4, 0.2, 0.5)])
		"bag":
			var ico := ModelGen._icosphere(2)
			var src: PackedVector3Array = ico[0]
			var noise := FastNoiseLite.new()
			noise.seed = seed_v
			noise.frequency = 2.5
			var b := MeshBuilder.new()
			var base := Color(0.05, 0.05, 0.055) if rng.randf() < 0.7 else Color(0.18, 0.2, 0.28)
			for v in src:
				var d := v.normalized()
				var r := 1.0 + noise.get_noise_3d(d.x * 3.0, d.y * 3.0, d.z * 3.0) * 0.25
				b.vert(Vector3(d.x * 0.3, maxf(d.y, -0.35) * 0.2 + 0.1, d.z * 0.25) * r, base.lightened(noise.get_noise_3d(d.x * 6.0, d.y * 6.0, d.z * 6.0) * 0.15 + 0.1))
			var tris: PackedInt32Array = ico[1]
			for i in range(0, tris.size(), 3):
				b.tri(tris[i], tris[i + 1], tris[i + 2])
			mb.append(b)
			boxes.append([Vector3(0, 0.12, 0), Vector3(0.55, 0.24, 0.45)])   # чтобы мешок можно было обыскать (луч E)
		"box":
			var c := Color(0.82, 0.66, 0.46).darkened(rng.randf_range(0.0, 0.3))
			var b := MeshBuilder.new()
			b.box(Vector3(0, 0.16, 0), Vector3(rng.randf_range(0.35, 0.55), rng.randf_range(0.22, 0.34), rng.randf_range(0.3, 0.45)), c)
			mb.append(b, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)), Vector3.ZERO))
			boxes.append([Vector3(0, 0.16, 0), Vector3(0.5, 0.32, 0.45)])
		_:
			for i in rng.randi_range(2, 4):
				var colors := [Color(0.82, 0.84, 0.86), Color(0.7, 0.1, 0.1), Color(0.15, 0.45, 0.2), Color(0.2, 0.35, 0.7)]
				var can := ItemModels.lathe([Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.034, 0.004), Vector2(0.034, 0.108), Vector2(0.03, 0.114), Vector2(0.0, 0.114)], 10, colors[rng.randi() % 4])
				var cb := MeshBuilder.new()
				cb.append_mesh(can)
				var lying := rng.randf() < 0.65
				var basis := Basis(Vector3.FORWARD, PI * 0.5) if lying else Basis.IDENTITY
				mb.append(cb, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * basis, Vector3(rng.randf_range(-0.25, 0.25), 0.034 if lying else 0.0, rng.randf_range(-0.25, 0.25))))
	return {"mesh": mb.to_mesh(), "boxes": boxes}


static func _torus(mb: MeshBuilder, big: float, small: float, col: Color) -> void:
	var nu := 22
	var nv := 10
	var ids: Array = []
	for i in nu:
		var a := TAU * i / nu
		var row: Array[int] = []
		for j in nv:
			var b := TAU * j / nv
			var r := big + small * cos(b)
			var shade := 0.7 + 0.3 * (0.5 + 0.5 * sin(a * 11.0))   # протектор
			row.append(mb.vert(Vector3(cos(a) * r, small + small * sin(b) * 0.95, sin(a) * r), col.lightened(0.04 * shade)))
		ids.append(row)
	for i in nu:
		var i2 := (i + 1) % nu
		for j in nv:
			var j2 := (j + 1) % nv
			var a: int = ids[i][j]
			var b: int = ids[i2][j]
			var c: int = ids[i2][j2]
			var d: int = ids[i][j2]
			# ориентируем по направлению от оси трубки наружу
			var pa := mb.verts[a]
			var ring_center := Vector3(cos(TAU * i / nu) * big, small, sin(TAU * i / nu) * big)
			var out := pa - ring_center
			var n := (mb.verts[b] - pa).cross(mb.verts[c] - pa)
			if n.dot(out) >= 0.0:
				mb.quad(a, b, c, d)
			else:
				mb.quad(a, d, c, b)
