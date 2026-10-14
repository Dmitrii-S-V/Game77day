extends SceneTree
## Кровь: брызги и пятна от ударов, лужа под убитым зомби. -- <снимки> (с окном)

var _f := 0
var _z: Zombie
var _shot := ""
var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_shot = a[0] if a.size() > 0 else ""
	var ground := StaticBody3D.new()
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
	mat.albedo_color = Color(0.42, 0.44, 0.36)
	gm.material_override = mat
	ground.add_child(gm)
	root.add_child(ground)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(2.4, 2.4, 3.6), Vector3(0, 0.3, 0.6))
	Zombie.preload_model()
	_z = Zombie.new()
	_z.position = Vector3(0, 0.05, 0)
	root.add_child(_z)


func _snap(tag: String) -> void:
	if _shot != "":
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_shot, tag])


func _process(_d: float) -> bool:
	_f += 1
	if _f == 10:
		for i in 3:
			Blood.spray(root, _z.global_position + Vector3(0, 1.2, 0.2), Vector3(randf_range(-0.4, 0.4), 0, 1), 1.0 + i * 0.2)
		check("пятна на земле есть (%d)" % Blood._splats.size(), Blood._splats.size() > 0)
	if _f == 10 + 18:
		_snap("spray")
	if _f == 10 + 60:
		_z.take_hit(1e6, Vector3(0, 0, 1), _z.global_position + Vector3.UP)
	if _f == 10 + 60 * 11:
		var pools := 0
		for c in _z.get_children():
			if c is Decal:
				pools += 1
		check("лужа под трупом (%d)" % pools, pools > 0)
		_snap("pool")
		print("RESULT fails=%d" % fails)
		return true
	return false
