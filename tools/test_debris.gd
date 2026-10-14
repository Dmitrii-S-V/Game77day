extends SceneTree
## Осколки с текстурой материала: по кучке на материал (слои блоков, земля, асфальт, камень, кора) и снимок.
## C:\Godot\godot.exe --path D:\77Days --script res://tools/test_debris.gd -- <out.png>

var _f := 0
var _out := ""
var _cam: Camera3D


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else ""
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	root.add_child(sun)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(40, 1, 40)
	cs.shape = sh
	cs.position.y = -0.5
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	gm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.33, 0.27)
	gm.material_override = mat
	ground.add_child(gm)
	root.add_child(ground)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 1.5, 2.3), Vector3(0, 0.05, 0.1))


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		var texs: Array = []
		var names: Array = []
		BlockRegistry.ensure()
		var ln: Array = BlockRegistry._layer_names
		for k in 4:
			var l := ln.size() * k / 4 + 1
			texs.append(Debris.block_layer_tex(l))
			names.append("blk:%s" % ln[l])
		for n in ["dirt_a", "road_asphalt", "terrain_stone", "bark"]:
			texs.append(Debris.file_tex(n))
			names.append(n)
		var ok := 0
		for i in texs.size():
			if texs[i] != null:
				ok += 1
			var p := Vector3(-2.1 + (i % 4) * 1.4, 0.4, -0.6 + (i / 4) * 1.3)
			Debris.burst(root, p, Color(1, 0, 1), 8, 2.2, 0.12, 4.0, texs[i])
			if i % 4 == 0:
				Debris.dust(root, p + Vector3(0, -0.2, 0), Color(0.55, 0.5, 0.45), 1.0)
		print("TEX ", ok, "/", texs.size(), " ", names, " active ", Debris.active)
	if _f == 24:
		if _out != "":
			root.get_viewport().get_texture().get_image().save_png(_out)
		print("DONE")
		return true
	return false
