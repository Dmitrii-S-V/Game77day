extends SceneTree
## Тест смерти зомби: ragdoll падает на землю, физика выключается (поза зафиксирована), через 30 с тело гниёт,
## остаются кости; корпус для обыска на месте. Обе модели (friend, mudworn).
## C:\Godot\godot.exe --headless --fixed-fps 60 --path D:\77Days --script res://tools/test_ragdoll.gd

var fails := 0
var _zs: Array = []
var _frame := 0
var _settled := {}
var _shot := ""
var _cam: Camera3D


func _snap(tag: String) -> void:
	if _shot != "":
		var c := Vector3.ZERO
		for z: Zombie in _zs:
			c += z._ragdoll.bone_global("hips") if z._ragdoll != null else z.global_position
		c /= float(_zs.size())
		var off := Vector3(0, 1.7, 1.6) if tag == "bones" else Vector3(0, 3.4, 3.2)
		if tag == "bones":
			c = _zs[0]._ragdoll.bone_global("hips")
		_cam.look_at_from_position(c + off, c)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_shot, tag])


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1


func _init() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(40, 1, 40)
	cs.shape = sh
	cs.position.y = -0.5
	ground.add_child(cs)
	root.add_child(ground)
	Zombie.preload_model()
	var a := OS.get_cmdline_user_args()
	_shot = a[0] if a.size() > 0 else ""
	if _shot != "":
		# с окном: свет, небо, камера — снимки «лёг», «гниёт», «кости»
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
		sun.shadow_enabled = true
		root.add_child(sun)
		var gm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(40, 40)
		gm.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.36, 0.25)
		gm.material_override = mat
		root.add_child(gm)
		_cam = Camera3D.new()
		root.add_child(_cam)
		_cam.look_at_from_position(Vector3(0, 2.6, 5.8), Vector3(0, 0.1, 2.2))
	for t in ["friend", "mudworn"]:
		var z := Zombie.new()
		z.ztype = t
		z.position = Vector3(-3.0 if t == "friend" else 3.0, 0.05, 0)
		root.add_child(z)
		_zs.append(z)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 10:
		for z: Zombie in _zs:
			z.velocity = Vector3(0, 0, 4.0)
			z.take_hit(1000.0, Vector3(0, 0, 1), z.global_position + Vector3.UP * 1.2)
		_check(_zs.all(func(z: Zombie) -> bool: return z._ragdoll != null), "ragdoll создан у обеих моделей")
	if _frame == 10 + 60 * 7:
		for z: Zombie in _zs:
			var rd: ZombieRagdoll = z._ragdoll
			var hips := rd.bone_global("hips")
			var head := rd.bone_global("head")
			_check(rd._state == 1, "%s: тело легло, физика выключена (state %d)" % [z.ztype, rd._state])
			_check(hips.y < 0.45 and head.y < 0.6, "%s: лежит на земле (таз %.2f, голова %.2f)" % [z.ztype, hips.y, head.y])
			_check(not z._cs.disabled and z.collision_layer == Zombie.CORPSE_LAYER, "%s: труп можно обыскать" % z.ztype)
			_settled[z] = head
	if _frame == 10 + 30:
		_snap("fall")
	if _frame == 10 + 60 * 8:
		_snap("lying")
	if _frame == 10 + 60 * 35:
		_snap("rot")
	if _frame == 10 + 60 * 45:
		_snap("bones")
	if _frame == 10 + 60 * 9:
		for z: Zombie in _zs:
			var rd: ZombieRagdoll = z._ragdoll
			_check(rd.bone_global("head").distance_to(_settled[z]) < 0.01, "%s: поза не меняется после выключения физики" % z.ztype)
	if _frame == 10 + 60 * 46:
		for z: Zombie in _zs:
			if not is_instance_valid(z):
				_check(false, "зомби пропал раньше времени")
				continue
			var rd: ZombieRagdoll = z._ragdoll
			_check(rd._state == 3 and not z._model.visible, "%s: сгнил, остались кости (state %d)" % [z.ztype, rd._state])
		print("RESULT fails=%d" % fails)
		return true
	return false
