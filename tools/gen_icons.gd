extends SceneTree
## Иконки предметов инвентаря: 3D-модель предмета снимается на прозрачном фоне -> assets/icons/<id>.png (128 px).
## Модели в руке (топор, дубина, пистолет, бутылки, еда) — те же, что в игре; для остальных — простые модельки здесь.
## Запуск с окном (нужен рендер): C:\Godot\godot.exe --path D:\77Days --script res://tools/gen_icons.gd [-- id ...]
## После — импорт: godot --headless --path D:\77Days --import --quit

const SIZE := 128
const OUT := "res://assets/icons/"

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _ids: Array = []
var _i := 0
var _wait := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_ids = args if not args.is_empty() else ItemDB.ITEMS.keys()
	# свои картинки (tools/import_ui_images.gd) не перезаписываем
	if FileAccess.file_exists(OUT + "custom.txt"):
		for l in FileAccess.get_file_as_string(OUT + "custom.txt").split("\n", false):
			_ids.erase(l.strip_edges())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	key.light_energy = 1.35
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	rim.light_energy = 0.5
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 28.0
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)


func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := _vp.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path(OUT + "%s.png" % _ids[_i]))
			print("ICON ", _ids[_i])
			_i += 1
		return false
	if _i >= _ids.size():
		print("DONE ", _ids.size())
		return true
	for c in _holder.get_children():
		c.free()
	var m := model(String(_ids[_i]))
	_holder.add_child(m)
	_frame(m)
	_wait = 4
	return false


## Камера: вид спереди-сверху-сбоку, предмет целиком в кадре.
func _frame(m: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.01)
	var dir := Vector3(0.55, 0.62, 1.0).normalized()
	# длинные тонкие предметы (по диагонали кадра) — ближе: рамка по диагонали AABB для них слишком велика
	var zoom: float = {"stone_axe": 0.62, "wooden_club": 0.6, "candy_bar": 0.8}.get(String(_ids[_i]), 1.0)
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.02 * zoom
	_cam.look_at_from_position(c + dir * dist, c)
	_cam.near = dist * 0.05
	_cam.far = dist * 4.0


static func _vc() -> StandardMaterial3D:
	return ItemModels.vertex_color_material()


static func _node(mb: MeshBuilder) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	mi.material_override = _vc()
	n.add_child(mi)
	return n


static func _cyl(mb: MeshBuilder, r: float, h: float, col: Color, xf: Transform3D, sides := 12) -> void:
	mb.append_mesh(ItemModels.lathe([Vector2(0.0, -h * 0.5), Vector2(r, -h * 0.5), Vector2(r, h * 0.5), Vector2(0.0, h * 0.5)], sides, col), xf)


## Модель предмета для иконки.
static func model(id: String) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var mb := MeshBuilder.new()
	match id:
		"stone_axe":
			var n := ItemModels.stone_axe()
			n.rotation = Vector3(0, 0, deg_to_rad(-35))
			return n
		"wooden_club":
			var n2 := ItemModels.club()
			n2.rotation = Vector3(0, 0, deg_to_rad(-35))
			return n2
		"pistol":
			var n3 := ItemModels.pistol()
			n3.rotation = Vector3(0, deg_to_rad(-80), 0)
			return n3
		"water_bottle", "glass_bottle":
			return ItemModels.bottle(id == "water_bottle")["root"]
		"canned_food", "berries":
			return ItemModels.food(id)
		"candy_bar":
			var n5 := ItemModels.food(id)
			n5.rotation = Vector3(deg_to_rad(-20), 0, deg_to_rad(-62))
			return n5
		"penicillin":
			# баночка таблеток: оранжевый корпус, белая крышка, этикетка
			mb.append_mesh(ItemModels.lathe([Vector2(0, 0), Vector2(0.03, 0), Vector2(0.031, 0.07), Vector2(0, 0.07)], 16, Color(0.85, 0.45, 0.12)))
			mb.append_mesh(ItemModels.lathe([Vector2(0.0315, 0.018), Vector2(0.0315, 0.055)], 16, Color(0.93, 0.93, 0.9)))
			mb.append_mesh(ItemModels.lathe([Vector2(0, 0.07), Vector2(0.034, 0.07), Vector2(0.034, 0.088), Vector2(0, 0.088)], 16, Color(0.95, 0.95, 0.95)))
			mb.box(Vector3(0, 0.036, 0.032), Vector3(0.022, 0.008, 0.002), Color(0.75, 0.12, 0.1))   # красный крест
			mb.box(Vector3(0, 0.036, 0.032), Vector3(0.008, 0.022, 0.002), Color(0.75, 0.12, 0.1))
		"ammo_9mm":
			for k in 5:
				var cm := MeshBuilder.new()
				cm.append_mesh(ItemModels.lathe([Vector2(0, 0), Vector2(0.0048, 0), Vector2(0.0048, 0.019), Vector2(0.0047, 0.019)], 12, Color(0.78, 0.6, 0.25)))
				cm.append_mesh(ItemModels.lathe([Vector2(0.0047, 0.019), Vector2(0.0045, 0.024), Vector2(0.0028, 0.029), Vector2(0, 0.0305)], 12, Color(0.62, 0.38, 0.22)))
				mb.append(cm, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-30 + k * 15)), Vector3((k - 2) * 0.011, 0, k % 2 * 0.004)))
		"wood":
			for k in 3:
				var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.15, 0.15)),
					Vector3(0, [0.0, 0.0, 0.07][k], [-0.04, 0.04, 0.0][k]))
				_cyl(mb, 0.035, 0.26, Color(0.36, 0.25, 0.16), xf)
				_cyl(mb, 0.031, 0.262, Color(0.78, 0.62, 0.4), xf)   # светлые торцы
		"planks":
			for k in 4:
				var c := Color(0.72, 0.53, 0.32).darkened(rng.randf_range(0.0, 0.18))
				mb.box(Vector3(rng.randf_range(-0.02, 0.02), k * 0.024, 0), Vector3(0.3, 0.022, 0.07), c)
				mb.box(Vector3(rng.randf_range(-0.05, 0.05), k * 0.024 + 0.0115, 0.0), Vector3(0.002, 0.001, 0.07), c.darkened(0.4))
		"stone":
			var n4 := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = load("res://assets/models/rock_0.res") if ResourceLoader.exists("res://assets/models/rock_0.res") else SphereMesh.new()
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = TexCache.texture("res://assets/textures/rock_a.png", true, 512)
			sm.uv1_triplanar = true
			sm.uv1_scale = Vector3(0.6, 0.6, 0.6)
			sm.roughness = 0.9
			mi.material_override = sm
			n4.add_child(mi)
			return n4
		"fiber", "grass":
			# пучок: волокно — сухие светло-зелёные нити; трава — зелёные стебли с мягкими кончиками
			var base := Color(0.55, 0.6, 0.3) if id == "fiber" else Color(0.25, 0.5, 0.16)
			for k in 22:
				var a := rng.randf_range(-0.35, 0.35)
				var c2 := base.lerp(Color(0.75, 0.8, 0.45), rng.randf() * 0.5)
				var len := rng.randf_range(0.16, 0.24)
				var xf2 := Transform3D(Basis(Vector3.FORWARD, a).rotated(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-0.01, 0.01), 0, rng.randf_range(-0.01, 0.01)))
				var bm := MeshBuilder.new()
				bm.box(Vector3(0, len * 0.5, 0), Vector3(0.006 if id == "fiber" else 0.009, len, 0.0025), c2)
				mb.append(bm, xf2)
			_cyl(mb, 0.022, 0.018, Color(0.45, 0.33, 0.2), Transform3D(Basis(), Vector3(0, 0.06, 0)))   # перевязка
		"broken_glass":
			# осколки бутылки: острые клинья зеленоватого стекла и кусок горлышка
			for k in 6:
				var sh := MeshBuilder.new()
				var c6 := Color(0.55, 0.72, 0.62).lerp(Color(0.82, 0.9, 0.86), rng.randf())
				var a6 := Vector3(0, 0, 0)
				var b6 := Vector3(rng.randf_range(0.04, 0.07), 0, rng.randf_range(-0.015, 0.015))
				var c7 := Vector3(rng.randf_range(0.01, 0.03), rng.randf_range(0.005, 0.01), rng.randf_range(0.02, 0.04))
				sh.tface(a6, b6, c7, Vector3.UP, c6)
				sh.tface(a6, c7, b6, Vector3.DOWN, c6.darkened(0.3))
				mb.append(sh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)),
					Vector3(rng.randf_range(-0.03, 0.03), k * 0.004, rng.randf_range(-0.03, 0.03))))
			mb.append_mesh(ItemModels.lathe([Vector2(0.012, 0), Vector2(0.012, 0.03), Vector2(0.014, 0.032), Vector2(0.014, 0.036)], 10,
				Color(0.5, 0.68, 0.58)), Transform3D(Basis(Vector3.FORWARD, 1.2), Vector3(0.03, 0.01, 0.02)))
		"grass_rope":
			# моток верёвки: несколько колец-витков, перевязанных посередине
			var rope_c := Color(0.45, 0.47, 0.26)
			for k in 5:
				var ring := ItemModels.lathe([Vector2(0.075 + k * 0.004, -0.007), Vector2(0.083 + k * 0.004, -0.007), Vector2(0.083 + k * 0.004, 0.007),
					Vector2(0.075 + k * 0.004, 0.007), Vector2(0.075 + k * 0.004, -0.007)], 18, rope_c.lerp(Color(0.58, 0.5, 0.3), k / 5.0))
				mb.append_mesh(ring, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.15, 0.15)).scaled(Vector3(1.0, 1.0, 0.55)), Vector3(0, 0, k * 0.003)))
			mb.box(Vector3(0, 0, 0.0), Vector3(0.03, 0.12, 0.05), Color(0.4, 0.38, 0.22))   # перевязка
		"rubber":
			# кусок покрышки: дуга с протектором
			for k in 9:
				var a2 := deg_to_rad(-50 + k * 12.5)
				var p := Vector3(sin(a2) * 0.12, cos(a2) * 0.12 - 0.12, 0)
				var bm2 := MeshBuilder.new()
				bm2.box(Vector3.ZERO, Vector3(0.03, 0.03, 0.09), Color(0.1, 0.1, 0.11))
				bm2.box(Vector3(0, 0.016, 0), Vector3(0.012, 0.006, 0.092), Color(0.05, 0.05, 0.055))
				mb.append(bm2, Transform3D(Basis(Vector3.FORWARD, -a2), p))
		"cloth":
			for k in 3:
				var c3: Color = [Color(0.6, 0.52, 0.42), Color(0.42, 0.45, 0.5), Color(0.55, 0.3, 0.25)][k]
				var bm3 := MeshBuilder.new()
				bm3.box(Vector3.ZERO, Vector3(0.18, 0.018, 0.13), c3)
				mb.append(bm3, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(-0.01, 0.01), k * 0.019, rng.randf_range(-0.01, 0.01))))
		"plastic":
			mb.append_mesh(ItemModels.lathe([Vector2(0, 0), Vector2(0.032, 0.0), Vector2(0.034, 0.02), Vector2(0.03, 0.1), Vector2(0.012, 0.13),
				Vector2(0.011, 0.15), Vector2(0, 0.15)], 12, Color(0.35, 0.6, 0.85)), Transform3D(Basis(Vector3.FORWARD, PI * 0.42), Vector3.ZERO))
			mb.append_mesh(ItemModels.lathe([Vector2(0, 0.15), Vector2(0.013, 0.15), Vector2(0.013, 0.165), Vector2(0, 0.165)], 12, Color(0.9, 0.9, 0.92)),
				Transform3D(Basis(Vector3.FORWARD, PI * 0.42), Vector3.ZERO))
		"paper":
			for k in 6:
				var bm4 := MeshBuilder.new()
				bm4.box(Vector3.ZERO, Vector3(0.15, 0.003, 0.2), Color(0.92, 0.9, 0.84).darkened(k * 0.02))
				if k == 5:
					for ln in 6:
						bm4.box(Vector3(-0.01, 0.002, -0.06 + ln * 0.022), Vector3(0.1, 0.001, 0.004), Color(0.3, 0.32, 0.38))
				mb.append(bm4, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), Vector3(0, k * 0.0035, 0)))
		"scrap_metal":
			for k in 4:
				var bm5 := MeshBuilder.new()
				var c5 := Color(0.5, 0.5, 0.52).lerp(Color(0.5, 0.3, 0.18), rng.randf() * 0.6)
				bm5.box(Vector3.ZERO, Vector3(rng.randf_range(0.08, 0.16), 0.006, rng.randf_range(0.05, 0.09)), c5)
				mb.append(bm5, Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))),
					Vector3(rng.randf_range(-0.03, 0.03), k * 0.015, rng.randf_range(-0.03, 0.03))))
		"duct_tape":
			mb.append_mesh(ItemModels.lathe([Vector2(0.032, -0.022), Vector2(0.052, -0.022), Vector2(0.052, 0.022), Vector2(0.032, 0.022), Vector2(0.032, -0.022)], 20,
				Color(0.42, 0.44, 0.47)), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3.ZERO))
			mb.append_mesh(ItemModels.lathe([Vector2(0.028, -0.023), Vector2(0.032, -0.023), Vector2(0.032, 0.023), Vector2(0.028, 0.023), Vector2(0.028, -0.023)], 20,
				Color(0.62, 0.5, 0.35)), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3.ZERO))   # картонная втулка
		"nails":
			for k in 6:
				var bm6 := MeshBuilder.new()
				bm6.append_mesh(ItemModels.lathe([Vector2(0, 0), Vector2(0.0022, 0.004), Vector2(0.0022, 0.07), Vector2(0, 0.07)], 8, Color(0.6, 0.6, 0.63)))
				bm6.append_mesh(ItemModels.lathe([Vector2(0, 0.07), Vector2(0.0055, 0.07), Vector2(0.0055, 0.073), Vector2(0, 0.073)], 10, Color(0.55, 0.55, 0.58)))
				mb.append(bm6, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-0.03, 0.03), k * 0.005, rng.randf_range(-0.03, 0.03))))
		_:
			mb.box(Vector3.ZERO, Vector3(0.1, 0.1, 0.1), ItemDB.info(id)["color"])
	return _node(mb)
