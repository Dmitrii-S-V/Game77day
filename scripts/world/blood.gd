class_name Blood
extends RefCounted
## Кровь: брызги при попадании (капли-частицы по направлению удара + пятна-декали на земле, тают через SPLAT_LIFE)
## и лужа под убитым зомби (декаль, растекается POOL_GROW секунд). Текстуры — процедурные (кэш user://texcache).

const SPLAT_LIFE := 40.0
const MAX_SPLATS := 60
const POOL_GROW := 7.0
const COLOR := Color(0.32, 0.02, 0.02)

static var _drop_mat: StandardMaterial3D
static var _quad: QuadMesh
static var _splat_tex: Texture2D
static var _pool_tex: Texture2D
static var _splats: Array = []


## Брызги из точки попадания по направлению удара dir; k — сила (огнестрел больше).
static func spray(parent: Node, pos: Vector3, dir: Vector3, k: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_ensure()
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.material_override = _drop_mat
	p.amount = clampi(roundi(16 * k), 6, 32)
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.randomness = 0.6
	p.local_coords = false
	var d := (dir.normalized() + Vector3.UP * 0.35).normalized()
	p.direction = d
	p.spread = 32.0
	p.initial_velocity_min = 1.6 * k
	p.initial_velocity_max = 4.2 * k
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.07
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(0.75, 0.9))
	c.add_point(Vector2(1, 0))
	p.scale_amount_curve = c
	p.color = Color(0.45, 0.03, 0.03)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	# пятна на земле: куда долетят капли (вперёд по удару, ниже точки попадания)
	var w3 := parent.get_viewport().find_world_3d() if parent.get_viewport() != null else null
	if w3 == null:
		return
	var space := w3.direct_space_state
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	for i in clampi(roundi(2 * k), 1, 4):
		var at := pos + flat * randf_range(0.3, 1.4) * k + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 2.5, 1 | 2)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
			splat(parent, hit["position"], randf_range(0.25, 0.6) * k)


## Пятно крови на поверхности (декаль сверху вниз), тает и удаляется через SPLAT_LIFE.
static func splat(parent: Node, pos: Vector3, size: float) -> Decal:
	_ensure()
	while _splats.size() >= MAX_SPLATS:
		var old: Variant = _splats.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var dc := _decal(_splat_tex, size)
	parent.add_child(dc)
	dc.global_position = pos + Vector3.UP * 0.05
	dc.rotation.y = randf() * TAU
	_splats.append(dc)
	var tw := dc.create_tween()
	tw.tween_interval(SPLAT_LIFE)
	tw.tween_property(dc, "modulate:a", 0.0, 4.0)
	tw.tween_callback(dc.queue_free)
	return dc


## Лужа под телом: растекается от маленького пятна до size за POOL_GROW секунд. owner — чей это труп
## (лужа удаляется вместе с ним).
static func pool(owner: Node3D, pos: Vector3, size: float = 2.4) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	_ensure()
	var dc := _decal(_pool_tex, 0.25)
	owner.add_child(dc)
	dc.global_position = pos + Vector3.UP * 0.1
	dc.rotation.y = randf() * TAU
	var tw := dc.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(dc, "size", Vector3(size, 0.8, size), POOL_GROW)


static func _decal(tex: Texture2D, size: float) -> Decal:
	var dc := Decal.new()
	dc.texture_albedo = tex
	dc.size = Vector3(size, 0.8, size)
	dc.modulate = Color(1, 1, 1, 0.95)
	dc.normal_fade = 0.4         # на стены не ложится
	dc.upper_fade = 0.2
	dc.lower_fade = 0.4
	dc.cull_mask = 1             # только мир (не зомби и не игрок)
	return dc


static func _ensure() -> void:
	if _quad != null:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_texture = ImageTexture.create_from_image(_drop_image())
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_drop_mat.billboard_keep_scale = true
	_drop_mat.vertex_color_use_as_albedo = true
	_drop_mat.roughness = 0.3
	_splat_tex = ImageTexture.create_from_image(TexCache.image("blood_splat_v1", [], func() -> Image: return _blob_image(128, 0.55, 7, 11)))
	_pool_tex = ImageTexture.create_from_image(TexCache.image("blood_pool_v1", [], func() -> Image: return _blob_image(256, 0.8, 3, 23)))


static func _drop_image() -> Image:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf((1.0 - d) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return img


## Неровное пятно: основа с шумным краем, тёмная середина, вокруг — отдельные капли.
static func _blob_image(n: int, radius: float, drops: int, seed_v: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 3.5 / n
	var fine := FastNoiseLite.new()
	fine.seed = seed_v + 1
	fine.frequency = 18.0 / n
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var dots: Array = []
	for i in drops:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.75, 0.95)
		dots.append([Vector2(0.5, 0.5) + Vector2.from_angle(a) * r * 0.5, rng.randf_range(0.02, 0.06)])
	for y in n:
		for x in n:
			var uv := Vector2((x + 0.5) / n, (y + 0.5) / n)
			var d := uv.distance_to(Vector2(0.5, 0.5)) * 2.0
			var edge := radius * (0.82 + 0.3 * nz.get_noise_2d(x, y))
			var a := clampf((edge - d) * 12.0, 0.0, 1.0)
			for dt: Array in dots:
				a = maxf(a, clampf((float(dt[1]) - uv.distance_to(dt[0])) * 60.0, 0.0, 1.0))
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var depth := clampf((edge - d) * 2.0, 0.0, 1.0)     # к середине темнее и гуще
			var c := COLOR.lerp(Color(0.16, 0.01, 0.01), depth).lightened(0.06 * fine.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(c, a * (0.75 + 0.25 * depth)))
	img.generate_mipmaps()
	return img
