class_name ModelGen
extends RefCounted
## Процедурные модели: камни, сосны, дубы, мёртвые деревья. Цвет — в вершинах.
## Запекаются в assets/models/*.res скриптом tools/gen_models.gd.


static func rock(seed_v: int, size: float = 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	var ico := _icosphere(4)
	var scl := Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.6, 0.95), rng.randf_range(0.8, 1.3)) * size
	var mb := MeshBuilder.new()
	var src: PackedVector3Array = ico[0]
	for v in src:
		var d := v.normalized()
		var r := 1.0 + noise.get_noise_3d(d.x * 1.6, d.y * 1.6, d.z * 1.6) * 0.38 + noise.get_noise_3d(d.x * 6.0, d.y * 6.0, d.z * 6.0) * 0.07
		var p := d * r
		p.y = maxf(p.y, -0.45)
		p *= scl
		var shade := 0.5 + noise.get_noise_3d(d.x * 3.0 + 9.0, d.y * 3.0, d.z * 3.0) * 0.35
		var col := Color(0.36, 0.35, 0.34).lerp(Color(0.55, 0.53, 0.50), shade)
		col = col.lerp(Color(0.30, 0.38, 0.22), clampf(d.y - 0.5, 0.0, 1.0) * 0.35)  # мох сверху
		mb.vert(p, col)
	var tris: PackedInt32Array = ico[1]
	for i in range(0, tris.size(), 3):
		mb.tri(tris[i], tris[i + 1], tris[i + 2])
	return mb.to_mesh()


static var lod_density := 1.0   # 1 — полная модель; <1 — облегчённая для среднего расстояния (меньше карточек, они крупнее)

static func pine(seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mb := MeshBuilder.new()
	var h := rng.randf_range(9.0, 13.0)
	var bark_a := Color(0.20, 0.13, 0.08)
	var bark_b := Color(0.33, 0.22, 0.13)
	var pts: Array[Vector3] = []
	var rad: Array[float] = []
	var segs := 8
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(Vector3(rng.randf_range(-0.04, 0.04) * h * t, h * t * 0.92, rng.randf_range(-0.04, 0.04) * h * t))
		rad.append(lerpf(0.42, 0.06, pow(t, 0.8)) * (1.0 + (0.5 * pow(1.0 - t, 8.0))))
	_tube(mb, pts, rad, 9, bark_a, bark_b, rng)

	var lb := MeshBuilder.new()
	var tiers := 8
	for k in tiers:
		var t := float(k) / (tiers - 1)
		var y := h * (0.22 + 0.74 * t)
		var big := lerpf(3.3, 0.7, t) * rng.randf_range(0.9, 1.1)
		var tall := lerpf(2.6, 1.5, t)
		var n := maxi(int(lerpf(28.0, 12.0, t) * lod_density), 3)
		var ang0 := rng.randf() * TAU
		for j in n:
			var a := ang0 + TAU * j / n + rng.randf_range(-0.15, 0.15)
			var dir := Vector3(cos(a), rng.randf_range(-0.38, -0.12), sin(a)).normalized()
			var origin := Vector3(0, y + rng.randf_range(0.0, 0.5), 0) + Vector3(dir.x, 0, dir.z) * 0.15
			var roll := PI * 0.5 + rng.randf_range(-0.55, 0.55) if rng.randf() < 0.65 else rng.randf_range(-0.6, 0.6)
			_card(lb, rng, origin, dir, roll, big * rng.randf_range(0.95, 1.2), Vector3(0, y - 1.2, 0), 0.0)
	return _pack(mb, lb)


## dry: осенние/сухие карточки (атлас foliage_dry), реже и без плотной сердцевины.
static func oak(seed_v: int, leaves: bool = true, dry: bool = false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mb := MeshBuilder.new()
	var lb := MeshBuilder.new()
	_branch(mb, lb, rng, Vector3.ZERO, Vector3.UP, rng.randf_range(3.2, 4.2), 0.40, 3, leaves, dry)
	return _pack(mb, lb)


## Куст (с ягодами — будущий ресурс).
static func bush(seed_v: int, berries: bool = false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mb := MeshBuilder.new()
	var lb := MeshBuilder.new()
	for i in 20:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), rng.randf_range(0.0, 0.8), sin(a)).normalized()
		_card(lb, rng, Vector3(0, rng.randf_range(0.1, 0.45), 0) + Vector3(dir.x, 0, dir.z) * 0.1, dir, rng.randf_range(-0.7, 0.7), rng.randf_range(0.85, 1.3), Vector3(0, 0.1, 0), 0.0)
	if berries:
		for i in 16:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			_ball(mb, Vector3(d.x * 0.85, 0.55 + d.y * 0.5, d.z * 0.85), 0.06, Color(0.75, 0.05, 0.10))
	return _pack(mb, lb)


## Ствол/ветки/сердцевина — поверхность 0; карточки листвы с UV — поверхность 1.
static func _pack(wood: MeshBuilder, leaf: MeshBuilder) -> ArrayMesh:
	if wood.verts.is_empty():   # поверхность 0 обязана существовать (кусты без ягод): вырожденный треугольник
		var o := wood.vert(Vector3.ZERO, Color.BLACK)
		wood.tri(o, o, o)
	var m := wood.to_mesh()
	if leaf.verts.size() > 0:
		var lm := leaf.to_mesh()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lm.surface_get_arrays(0))
	return m


## Карточка листвы: основание ветки в origin, ветка растёт вдоль dir; roll — поворот вокруг dir
## (0 — «стоит» вертикально, PI/2 — лежит плашмя). Нормали направлены от центра кроны (мягкий свет).
static func _card(lb: MeshBuilder, rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, roll: float, w: float, crown: Vector3, _unused: float) -> void:
	var right := dir.normalized()
	var up := Vector3.UP - right * right.dot(Vector3.UP)
	if up.length_squared() < 0.01:
		up = Vector3.RIGHT - right * right.dot(Vector3.RIGHT)
	up = up.normalized().rotated(right, roll)
	w *= pow(1.0 / lod_density, 0.45)
	var h := w * 0.75
	var cell := rng.randi() % 8
	var u0 := (cell % 4) * 0.25 + 0.004
	var u1 := u0 + 0.25 - 0.008
	var v0 := (cell / 4) * 0.5 + 0.006
	var v1 := v0 + 0.5 - 0.012
	var tint := rng.randf_range(0.82, 1.08)
	var tc := Color(tint, tint * rng.randf_range(0.95, 1.05), tint * rng.randf_range(0.9, 1.0))
	var pts: Array[Vector3] = [origin + up * h * 0.5, origin - up * h * 0.5,
		origin + right * w - up * h * 0.5, origin + right * w + up * h * 0.5]
	var uvq: Array[Vector2] = [Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0)]
	var ids: Array[int] = []
	for i in 4:
		var rel := pts[i] - crown
		var n := (rel.normalized() + Vector3.UP * 0.35).normalized()
		var inner := clampf(rel.length() / (w * 1.4), 0.0, 1.0)
		var shade := lerpf(0.55, 1.0, inner)
		var sway := 0.15 if i < 2 else 1.0
		ids.append(lb.vert_full(pts[i], Color(tc.r * shade, tc.g * shade, tc.b * shade, sway), uvq[i], n))
	lb.quad(ids[0], ids[1], ids[2], ids[3])


# --- детали -------------------------------------------------------------------

static func _ball(mb: MeshBuilder, center: Vector3, radius: float, col: Color) -> void:
	var ico := _icosphere(1)
	var b := MeshBuilder.new()
	var src: PackedVector3Array = ico[0]
	for v in src:
		b.vert(center + v.normalized() * radius, col)
	var tris: PackedInt32Array = ico[1]
	for i in range(0, tris.size(), 3):
		b.tri(tris[i], tris[i + 1], tris[i + 2])
	mb.append(b)


static func _branch(mb: MeshBuilder, lb: MeshBuilder, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, leaves: bool, dry: bool) -> void:
	var pts: Array[Vector3] = [start]
	var rad: Array[float] = [radius]
	var segs := 5
	var p := start
	var d := dir
	for i in segs:
		d = (d + Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.05, 0.12), rng.randf_range(-0.22, 0.22))).normalized()
		p += d * (length / segs)
		pts.append(p)
		rad.append(radius * lerpf(1.0, 0.55, float(i + 1) / segs))
	_tube(mb, pts, rad, 7, Color(0.20, 0.14, 0.09), Color(0.34, 0.25, 0.17), rng)
	if depth > 0:
		var n := 3 if depth == 3 else rng.randi_range(2, 3)
		for c in n:
			var spread := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 0.9), rng.randf_range(-1, 1)).normalized()
			var nd := (d * 0.5 + spread * 0.9).normalized()
			var from_i := rng.randi_range(2, segs)
			_branch(mb, lb, rng, pts[from_i], nd, length * rng.randf_range(0.62, 0.8), rad[from_i] * 0.75, depth - 1, leaves, dry)
	elif leaves:
		var r := rng.randf_range(1.5, 2.2)
		var c := p + d * 0.3
		for i in maxi(int((9 if dry else 24) * lod_density), 4):
			var a := rng.randf() * TAU
			var dv := Vector3(cos(a), rng.randf_range(-0.2, 0.9), sin(a)).normalized()
			_card(lb, rng, c + dv * r * 0.12, dv, rng.randf_range(-0.8, 0.8), r * rng.randf_range(0.9, 1.35), c, 0.0)


static func _leaf_blob(mb: MeshBuilder, rng: RandomNumberGenerator, center: Vector3, radius: float, core: bool = false) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.2
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var ico := _icosphere(2)
	var b := MeshBuilder.new()
	var base := Color(0.13, 0.30, 0.08).lerp(Color(0.24, 0.42, 0.10), rng.randf())
	if core:
		base = Color(0.05, 0.12, 0.04).lerp(Color(0.09, 0.18, 0.06), rng.randf())
	var src: PackedVector3Array = ico[0]
	for v in src:
		var d := v.normalized()
		var r := radius * (1.0 + noise.get_noise_3d(d.x * 2.0, d.y * 2.0, d.z * 2.0) * 0.38)
		var p := center + Vector3(d.x * r * 1.15, d.y * r * 0.8, d.z * r * 1.15)
		var col := base.lerp(Color(0.46, 0.58, 0.18), clampf(d.y * 0.5 + 0.3, 0.0, 1.0) * 0.6)
		col = col.darkened(clampf(-d.y, 0.0, 1.0) * 0.45)
		b.vert(p, col)
	var tris: PackedInt32Array = ico[1]
	for i in range(0, tris.size(), 3):
		b.tri(tris[i], tris[i + 1], tris[i + 2])
	mb.append(b)


static func _cone(mb: MeshBuilder, base_center: Vector3, radius: float, height: float, sides: int, col: Color, rng: RandomNumberGenerator) -> void:
	var ring: Array[int] = []
	for j in sides:
		var a := TAU * j / sides
		var jag := 1.0 if j % 2 == 0 else 0.62
		var r := radius * jag * rng.randf_range(0.9, 1.08)
		var droop := (0.0 if j % 2 == 0 else 0.35)
		var p := base_center + Vector3(cos(a) * r, -droop - r * 0.12, sin(a) * r)
		ring.append(mb.vert(p, col.lightened(rng.randf_range(0.0, 0.08))))
	var apex := mb.vert(base_center + Vector3(0, height, 0), col.lightened(0.18))
	var under := mb.vert(base_center + Vector3(0, 0.25, 0), col.darkened(0.45))
	for j in sides:
		var j2 := (j + 1) % sides
		# верх (вершины идут по часовой сверху -> CCW снаружи сверху при обходе j2, j)
		mb.tri(ring[j2], ring[j], apex)
		# низ
		mb.tri(ring[j], ring[j2], under)


static func _tube(mb: MeshBuilder, pts: Array[Vector3], radii: Array[float], sides: int, col_a: Color, col_b: Color, rng: RandomNumberGenerator) -> void:
	var rings: Array = []
	var t := (pts[1] - pts[0]).normalized()
	var ref := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
	var u := t.cross(ref).normalized()
	var base_idx := mb.verts.size()
	for k in pts.size():
		if k > 0:
			t = (pts[k] - pts[k - 1]).normalized()
			if k < pts.size() - 1:
				t = (t + (pts[k + 1] - pts[k]).normalized()).normalized()
			u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		var row: Array[int] = []
		for j in sides:
			var a := TAU * j / sides
			var wob := 1.0 + rng.randf_range(-0.07, 0.07)
			var p := pts[k] + (u * cos(a) + v * sin(a)) * radii[k] * wob
			var col := col_a.lerp(col_b, rng.randf())
			row.append(mb.vert(p, col))
		rings.append(row)
	for k in pts.size() - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			mb.quad(rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j])
	var tip := mb.vert(pts[pts.size() - 1] + t * radii[radii.size() - 1] * 0.6, col_a)
	var last: Array = rings[rings.size() - 1]
	for j in sides:
		mb.tri(last[j], last[(j + 1) % sides], tip)


# Возвращает [PackedVector3Array вершин, PackedInt32Array индексов (CCW снаружи)]
static func _icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in subdiv:
		var cache := {}
		var nf := PackedInt32Array()
		for i in range(0, f.size(), 3):
			var a := f[i]
			var b := f[i + 1]
			var c := f[i + 2]
			var ab := _mid(v, cache, a, b)
			var bc := _mid(v, cache, b, c)
			var ca := _mid(v, cache, c, a)
			nf.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		f = nf
	return [v, f]


static func _mid(v: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 1000003 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	cache[key] = v.size() - 1
	return v.size() - 1
