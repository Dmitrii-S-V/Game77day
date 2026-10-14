extends SceneTree
## Витрина форм блоков (с окном): блоки id from..to в ряд, материалы чередуются (бетон / металл / доски / профлист).
## Снимки: -- <out_prefix> [from] [to]
## C:\Godot\godot.exe --path D:\77Days --script res://tools/shape_gallery.gd -- C:/tmp/gal 51 86

var _frame := 0
var _cam: Camera3D
var _out := ""
var _bb: BlockBuilding


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	var from := int(a[1]) if a.size() > 1 else 51
	var to := int(a[2]) if a.size() > 2 else 86
	BlockRegistry.ensure()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)
	var cols := 9
	var n := to - from + 1
	var rows := ceili(float(n) / cols)
	var g := BlockGrid.new(cols * 2 + 2, 4, rows * 3 + 2)
	var mats := ["concrete_dirty", "metal_rusty", "planks_worn", "metal_corrugated", "concrete_smooth"]
	if a.size() > 3:
		mats = Array(a[3].split(","))   # свои материалы: -- out 51 86 brick_painted,metal_sheet_rusty
	for i in n:
		var id := from + i
		if BlockRegistry.block(id).is_empty():
			continue
		var tier := 0
		var tiers: Array = BlockRegistry.block(id).get("tiers", [])
		for t in tiers.size():
			if String(tiers[t]["key"]) == mats[i % mats.size()]:
				tier = t
		g.place_block(Vector3i(1 + (i % cols) * 2, 0, 1 + (i / cols) * 3), id, BlockRegistry.make_meta(0, tier, 0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/block.gdshader")
	BlockRegistry.apply_to_material(mat)
	var glass := StandardMaterial3D.new()
	_bb = BlockBuilding.new()
	root.add_child(_bb)
	_bb.setup(g, mat, glass, true)
	# пол
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.33, 0.3)
	floor_mi.material_override = fm
	floor_mi.position = _bb.origin + Vector3(cols, -0.01, rows * 1.5)
	root.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 50
	root.add_child(_cam)
	_cam.look_at_from_position(_bb.origin + Vector3(cols, 9.0, rows * 3 + 9.0), _bb.origin + Vector3(cols, 0.5, rows * 1.3))


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 120:
		root.get_viewport().get_texture().get_image().save_png(_out + "_a.png")
		_cam.look_at_from_position(_bb.origin + Vector3(-3.0, 4.0, -3.0), _bb.origin + Vector3(7.0, 0.5, 6.0))
	if _frame == 160:
		root.get_viewport().get_texture().get_image().save_png(_out + "_b.png")
		return true
	return false
