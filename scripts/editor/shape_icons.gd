class_name ShapeIcons
extends RefCounted
## Иконки форм блоков для палитры редактора: изометрический силуэт геометрии блока (BlockShapes), грани
## закрашены по освещённости и цвету материала. Рисуется программно (без рендера) и кэшируется.

const SZ := 48
static var _cache := {}


static func icon(id: int, tier: int = 0) -> Texture2D:
	var key := "%d:%d" % [id, tier]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(_draw(id, tier))
	_cache[key] = tex
	return tex


static func _faces(id: int, tier: int) -> Array:
	var parts := BlockShapes.build(id, BlockRegistry.make_meta(0, tier, 0))
	var faces: Array = []
	var hidden: Array = []
	for b: Dictionary in parts["boxes"]:
		(hidden if b.get("hidden", false) else faces).append_array(_box_faces(b["a"], b["b"]))
	for pl: Dictionary in parts.get("polys", []):
		faces.append(pl["p"])
	for q: Dictionary in parts.get("quads", []):
		faces.append(q["p"])
		var r: Array = (q["p"] as Array).duplicate()
		r.reverse()
		faces.append(r)
	if BlockRegistry.is_cube(id):
		faces = _box_faces(Vector3.ZERO, Vector3.ONE)
	if faces.is_empty():
		faces = hidden          # модель: силуэт по коробкам столкновений
	return faces


static func _box_faces(a: Vector3, b: Vector3) -> Array:
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var bc := (a + b) * 0.5
	var out: Array = []
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		var q := [p[f[0]], p[f[1]], p[f[2]], p[f[3]]]
		# порядок обхода — нормалью наружу (как у многоугольников BlockShapes)
		var n := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3))
		var fc := ((q[0] as Vector3) + (q[2] as Vector3)) * 0.5
		if n.dot(fc - bc) < 0.0:
			q.reverse()
		out.append(q)
	return out


static func _draw(id: int, tier: int) -> Image:
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var faces := _faces(id, tier)
	if faces.is_empty():
		return img
	var base := _mat_color(id, tier)
	var view := Vector3(1.0, 0.9, 1.25).normalized()   # камера спереди-справа-сверху (фасад блока — к +Z)
	var light := Vector3(0.5, 1.0, 0.7).normalized()
	# проекция и масштаб под размер иконки
	var proj := func(p: Vector3) -> Vector2:
		return Vector2((p.x - p.z) * 0.866, -p.y + (p.x + p.z) * 0.42)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for f: Array in faces:
		for p: Vector3 in f:
			var s: Vector2 = proj.call(p)
			lo = lo.min(s)
			hi = hi.max(s)
	var k := (SZ - 6) / maxf(hi.x - lo.x, hi.y - lo.y)
	var off := Vector2(SZ, SZ) * 0.5 - (lo + hi) * 0.5 * k
	# художник: от дальних граней к ближним
	var items: Array = []
	for f: Array in faces:
		var n := ((f[1] as Vector3) - (f[0] as Vector3)).cross((f[2] as Vector3) - (f[0] as Vector3))
		if n.length_squared() < 1e-10:
			continue
		n = n.normalized()
		if n.dot(view) <= 0.0:
			continue
		var c := Vector3.ZERO
		for p: Vector3 in f:
			c += p
		c /= float(f.size())
		var pts := PackedVector2Array()
		for p: Vector3 in f:
			pts.append((proj.call(p) as Vector2) * k + off)
		var sh := 0.45 + 0.55 * maxf(0.0, n.dot(light))
		items.append([c.dot(view), pts, Color(base.r * sh, base.g * sh, base.b * sh, 1.0)])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it: Array in items:
		_fill(img, it[1], it[2])
	return img


static func _mat_color(id: int, tier: int) -> Color:
	var zc := String(BlockRegistry.tier_def(id, tier).get("color", ""))
	if zc != "":
		return Color.html(zc)     # зоны зомби — своим цветом
	var list: Array = BlockRegistry.material(id, tier).get("tex", [])
	if list.is_empty():
		return Color(0.7, 0.7, 0.7)
	var im := BlockRegistry.texture_image(String(list[0]))
	im.resize(4, 4, Image.INTERPOLATE_BILINEAR)
	var c := Color(0, 0, 0)
	for y in 4:
		for x in 4:
			c += im.get_pixel(x, y)
	c /= 16.0
	return c.lerp(Color(0.75, 0.75, 0.75), 0.25)


## Заливка выпуклого многоугольника (точки в пикселях).
static func _fill(img: Image, pts: PackedVector2Array, col: Color) -> void:
	var lo := Vector2i(SZ, SZ)
	var hi := Vector2i(-1, -1)
	for p in pts:
		lo = lo.min(Vector2i(floori(p.x), floori(p.y)))
		hi = hi.max(Vector2i(ceili(p.x), ceili(p.y)))
	lo = lo.clamp(Vector2i.ZERO, Vector2i(SZ - 1, SZ - 1))
	hi = hi.clamp(Vector2i.ZERO, Vector2i(SZ - 1, SZ - 1))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, col)
