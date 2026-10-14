class_name Debris
extends RefCounted
## Осколки и пыль — плоские частицы (CPUParticles3D, без физики): осколок — кусочек текстуры материала неровной
## формы (атлас 4x4 фрагментов, вырезанных из текстуры), разлетается, крутится и тает; пыль — мягкие облачка.
## Без текстуры — те же формы цветом color.

static var active := 0
const MAX_ACTIVE := 40     # одновременных вспышек частиц
const ATLAS := 128         # атлас осколков: 4x4 по 32 px
const TILES := 4

static var _quad: QuadMesh
static var _atlas := {}     # rid текстуры (или "plain") -> Texture2D атлас осколков
static var _mats := {}      # ключ -> StandardMaterial3D
static var _dust_mat: StandardMaterial3D
static var _shrink: Curve
static var _grow: Curve
static var _layer_tex := {} # слой массива текстур блоков -> Texture2D


## Совместимо с прежним вызовом: count — сколько кусков, speed — скорость разлёта, size — размер (м), life — ориентир
## длительности; tex — текстура материала (или null — цвет color), flat — не используется (плоские и так), tint — оттенок.
static func burst(parent: Node, pos: Vector3, color: Color, count: int, speed: float = 3.0, size: float = 0.12, life: float = 5.0,
		tex: Texture2D = null, flat: float = 1.0, tint: Color = Color.WHITE) -> void:
	if parent == null or not parent.is_inside_tree() or active >= MAX_ACTIVE or count <= 0:
		return
	_ensure()
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.material_override = _material(tex, tint if tex != null else color)
	p.amount = clampi(count * 2, 3, 24)
	p.lifetime = clampf(life * 0.2, 0.5, 1.0)
	p.one_shot = true
	p.explosiveness = 0.95
	p.randomness = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed * 1.05
	p.gravity = Vector3(0, -12.0, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	var s := clampf(size, 0.03, 0.2) * 1.3
	p.scale_amount_min = s * 0.55
	p.scale_amount_max = s * 1.25
	p.scale_amount_curve = _shrink
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0           # у каждого осколка — свой фрагмент атласа
	_launch(parent, p, pos)


## Пыль: облачко при разрушении (блоки, реквизит). color — цвет материала (пыль — светлее и серее), k — размер.
static func dust(parent: Node, pos: Vector3, color: Color, k: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree() or active >= MAX_ACTIVE:
		return
	_ensure()
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.material_override = _dust_mat
	p.amount = 10
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35 * k
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.scale_amount_min = 0.55 * k
	p.scale_amount_max = 1.0 * k
	p.scale_amount_curve = _grow
	var c := color.lerp(Color(0.62, 0.6, 0.56), 0.55)
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.15, Color(c, 0.55))
	g.add_point(0.55, Color(c, 0.3))
	p.color_ramp = g
	_launch(parent, p, pos)


static func _launch(parent: Node, p: CPUParticles3D, pos: Vector3) -> void:
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	active += 1
	p.tree_exiting.connect(func() -> void: active -= 1)
	p.finished.connect(p.queue_free)


static func _ensure() -> void:
	if _quad != null:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(0.65, 1.0))
	_shrink.add_point(Vector2(1.0, 0.0))
	_grow = Curve.new()
	_grow.add_point(Vector2(0.0, 0.45))
	_grow.add_point(Vector2(1.0, 1.0))
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.albedo_texture = _soft_circle()
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.billboard_keep_scale = true
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.disable_receive_shadows = true
	_dust_mat.roughness = 1.0


static func _material(tex: Texture2D, col: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [tex.get_rid() if tex != null else "plain", col.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _chip_atlas(tex)
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # иначе масштаб частиц игнорируется (квад 1 м)
	m.particles_anim_h_frames = TILES
	m.particles_anim_v_frames = TILES
	m.particles_anim_loop = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


## Атлас осколков: 16 фрагментов текстуры (или белого с лёгким рельефом), каждый обрезан неровным многоугольником,
## края чуть темнее — «скол».
static func _chip_atlas(tex: Texture2D) -> Texture2D:
	var key: Variant = tex.get_rid() if tex != null else "plain"
	if _atlas.has(key):
		return _atlas[key]
	var src: Image = null
	if tex != null:
		src = tex.get_image()
		if src != null:
			if src.is_compressed():
				src.decompress()
			src.convert(Image.FORMAT_RGBA8)
			# средний участок текстуры (фрагменты — крупным планом, а не вся текстура в 32 px)
			var side := mini(src.get_width(), src.get_height()) / 2
			src = src.get_region(Rect2i(src.get_width() / 4, src.get_height() / 4, side, side))
			src.resize(ATLAS, ATLAS, Image.INTERPOLATE_BILINEAR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var img := Image.create(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	var ts := ATLAS / TILES
	for ty in TILES:
		for tx in TILES:
			# неровный многоугольник в клетке
			var n := rng.randi_range(5, 8)
			var poly := PackedVector2Array()
			var inner := PackedVector2Array()   # тот же многоугольник, чуть меньше: между ними — тёмный край скола
			var ctr := Vector2(ts * 0.5, ts * 0.5)
			var a0 := rng.randf() * TAU
			for i in n:
				var a := a0 + TAU * (i + rng.randf_range(-0.25, 0.25)) / n
				var r := rng.randf_range(0.55, 0.95) * ts * 0.5
				var v := ctr + Vector2(cos(a), sin(a)) * r
				poly.append(v)
				inner.append(ctr + (v - ctr) * (1.0 - 1.8 / maxf(r, 2.0)))
			for y in ts:
				for x in ts:
					var pt := Vector2(x + 0.5, y + 0.5)
					if not Geometry2D.is_point_in_polygon(pt, poly):
						continue
					var c := src.get_pixel(tx * ts + x, ty * ts + y) if src != null else \
						Color(1, 1, 1).darkened(0.12 * absf(sin(x * 0.7 + y * 0.45)))
					if not Geometry2D.is_point_in_polygon(pt, inner):
						c = c.darkened(0.3)
					c.a = 1.0
					img.set_pixel(tx * ts + x, ty * ts + y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_atlas[key] = t
	return t


static func _soft_circle() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.75 + 0.25 * noise.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Текстура слоя массива текстур блоков (для осколков блока).
static func block_layer_tex(layer: int) -> Texture2D:
	if _layer_tex.has(layer):
		return _layer_tex[layer]
	var t: Texture2D = null
	var arr := BlockRegistry.texture_array()
	if arr != null and layer >= 0 and layer < arr.get_layers():
		var img := arr.get_layer_data(layer)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_layer_tex[layer] = t
	return t


## Текстура материала модели (кора, порода, обычный материал) — первая найденная у сеток узла.
static func node_tex(n: Node) -> Texture2D:
	if n == null:
		return null
	var mis: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		mis.push_front(n)
	for mi: MeshInstance3D in mis:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is ShaderMaterial:
				for p in ["tex_bark", "tex_rock", "tex", "albedo_tex", "tex_albedo"]:
					var t: Variant = (m as ShaderMaterial).get_shader_parameter(p)
					if t is Texture2D:
						return t
			elif m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
				return (m as BaseMaterial3D).albedo_texture
	return null


## Оттенок материала модели (параметр шейдера tint: приглушённые и обугленные коры), иначе белый.
static func node_tint(n: Node) -> Color:
	if n == null:
		return Color.WHITE
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("tex_bark") is Texture2D:
				var t: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
				return Color(t.x, t.y, t.z) if t is Vector3 else Color.WHITE
	return Color.WHITE


## Текстура по имени файла assets/textures/<имя>.png (земля, дороги).
static func file_tex(tex_name: String) -> Texture2D:
	return TexCache.texture("res://assets/textures/%s.png" % tex_name, true, 512)
