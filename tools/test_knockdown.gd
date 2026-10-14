extends SceneTree
## Стан и сбивание зомби: стан 33%, удар в лицо — падение 39% (ragdoll: падает, замирает, лежит, поза перетекает
## в лежачую позу death, встаёт — death задом наперёд), лежачего — снова 10%. Темп ударов и выносливость.
## C:\Godot\godot.exe --headless --fixed-fps 60 --path D:\77Days --script res://tools/test_knockdown.gd [-- <снимки>]

var fails := 0
var _f := 0
var _z: Zombie
var _phases := {}
var _t0 := 0
var _shot := ""
var _hips0 := Vector3.ZERO
var _up_pos := Vector3(1e6, 0, 0)
var _extra: Array = []


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(40, 1, 40)
	cs.shape = sh
	cs.position.y = -0.5
	ground.add_child(cs)
	root.add_child(ground)
	Zombie.preload_model()
	var a := OS.get_cmdline_user_args()
	_z = Zombie.new()
	if a.has("mudworn"):
		_z.ztype = "mudworn"
		a.erase("mudworn")
	_z.position = Vector3(0, 0.05, 0)
	root.add_child(_z)
	_shot = a[0] if a.size() > 0 else ""
	if _shot != "":
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.55, 0.62, 0.7)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.62, 0.66)
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
		root.add_child(sun)
		var gm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(40, 40)
		gm.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.4, 0.3)
		gm.material_override = mat
		root.add_child(gm)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.look_at_from_position(Vector3(3.6, 2.2, 3.6), Vector3(0, 0.5, 0.6))


func _snap(tag: String) -> void:
	if _shot != "":
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_shot, tag])


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		seed(12345)
		var again := 0
		var n := 1500
		# шансы по классу оружия: сбить (кулак 25, бита 33, прочее/огнестрел 15), оглушить (ближний 25, огнестрел 20)
		for kb in [["fist", 0.0, 0.25, 0.25], ["bat", 0.0, 0.33, 0.25], ["melee", 0.0, 0.15, 0.25], ["gun", 0.0, 0.15, 0.2],
				["bat", Gear.chance_bonus("wooden_club", 3), 0.39, 0.31]]:
			var down := 0
			var stun := 0
			for i in n:
				_z.hp = 1e9
				_z.reset_knock()
				_z._stagger = 0.0
				_z.take_hit(1.0, Vector3.FORWARD, _z.global_position + Vector3.UP * 0.9, kb[0], kb[1])
				if _z._kphase > 0 or _z._down_t > 0.0:
					down += 1
				elif _z._stagger > 0.0:
					stun += 1
			var exp_stun: float = (1.0 - float(kb[2])) * float(kb[3])
			check("%s%s: сбить ~%d%% (%.1f%%), оглушить ~%.1f%% (%.1f%%)" % [kb[0], " ур.3" if float(kb[1]) > 0 else "", roundi(float(kb[2]) * 100),
				100.0 * down / n, exp_stun * 100.0, 100.0 * stun / n],
				absf(float(down) / n - float(kb[2])) < 0.04 and absf(float(stun) / n - exp_stun) < 0.04)
		_z.reset_knock()
		_z._stagger = 0.0
		_z.take_hit(1.0, Vector3.FORWARD, Vector3.INF, "gun", 0.0)
		check("оглушение длится 1 с", _z._kphase > 0 or is_equal_approx(_z._stagger, 1.0) or _z._stagger == 0.0)
		# сбитый не бьёт
		_z.reset_knock()
		_z._knock_down()
		_z._cd = 0.0
		_z._start_attack({})
		check("сбитый зомби не начинает удар", _z._attack_t <= 0.0)
		_z.reset_knock()
		_z._stagger = 0.5
		_z._start_attack({})
		check("оглушённый зомби не начинает удар", _z._attack_t <= 0.0)
		_z._stagger = 0.0
		for i in n:
			_z.hp = 1e9
			_z.reset_knock()
			_z._kphase = 2          # лежит (ragdoll замер)
			_z._kt = 0.5
			_z.take_hit(1.0, Vector3.FORWARD, _z.global_position + Vector3.UP * 0.5)
			if _z._kt > 0.6:
				again += 1
		_z.reset_knock()
		check("лежачего роняет снова ~10%% (%.1f%%)" % (100.0 * again / n), absf(float(again) / n - 0.1) < 0.03)
		# сбить по-настоящему: ragdoll
		_z.hp = 100.0
		_z._stagger = 0.0
		_z._last_hit_dir = Vector3(0.3, 0, 1).normalized()
		_z._knock_down()
		check("сбит — ragdoll (фаза 1)", _z._kphase == 1 and _z._knock_rd != null)
		var bone: PhysicalBone3D = _z._knock_rd._bones[0]
		check("по падающему телу можно попасть: кость на слое зомби, капсула выключена",
			bone.collision_layer & Zombie.LAYER != 0 and _z._cs.disabled and Zombie.of(bone) == _z)
		check("здоровье зомби 300", is_equal_approx(Zombie.HP_MAX, 300.0))
		_t0 = _f
		for k in 2:
			var zz := Zombie.new()
			zz.position = Vector3(6 + k * 3, 0.05, -4)
			root.add_child(zz)
			_extra.append(zz)
	if _f == 7:
		for zz: Zombie in _extra:
			zz._knock_down()
	if _f == 7 + 15:
		_extra[0].take_hit(1e6, Vector3.FORWARD)      # убит, пока падает
		check("убит в падении — этот же ragdoll стал смертью", _extra[0].dead and _extra[0]._ragdoll != null and not _extra[0]._ragdoll.knock and _extra[0]._kphase == 0)
	if _f == 7 + 60 * 3 and _extra[1]._kphase == 2:
		_extra[1].take_hit(1e6, Vector3.FORWARD)      # убит, пока лежит
		check("убит лёжа — смертельный ragdoll из позы", _extra[1].dead and _extra[1]._ragdoll != null and _extra[1]._kphase == 0)
	elif _f == 7 + 60 * 3:
		check("второй лежит к 3 с (фаза %d)" % _extra[1]._kphase, false)
	if _f > 5 and _t0 > 0:
		if not _phases.has(_z._kphase):
			_phases[_z._kphase] = _f - _t0
			match _z._kphase:
				2:
					_hips0 = _z._knock_rd.bone_global("hips")
					_snap("2_lying")
					# лежит: коробка вдоль тела — луч сверху в таз попадает в зомби
					var q := PhysicsRayQueryParameters3D.create(_hips0 + Vector3.UP * 1.5, _hips0 + Vector3.DOWN * 0.5, Zombie.LAYER)
					var h := _z.get_world_3d().direct_space_state.intersect_ray(q)
					check("лежачего видно лучом сверху (попадание по телу)", not h.is_empty() and Zombie.of(h["collider"]) == _z)
				4:
					check("встаёт — капсула вернулась", not _z._cs.disabled and _z._cs.shape is CapsuleShape3D)
				3:
					_snap("3_blend")
				4:
					_snap("4_getup")
				0:
					_up_pos = _z.global_position    # только что встал
		if _phases.has(4) and _f - _t0 == int(_phases[4]) + 40:
			_snap("4b_getup")
	if _t0 > 0 and _f == _t0 + 25:
		_snap("1_fall")
	if _t0 > 0 and _f == _t0 + 60 * 8:
		_snap("5_up")
		check("фазы: падает → лежит → перетекает → встаёт → обычный (%s)" % str(_phases), _phases.has(2) and _phases.has(3) and _phases.has(4) and _z._kphase == 0)
		check("ragdoll замер быстро (%.1f с)" % (float(_phases.get(2, 999)) / 60.0), float(_phases.get(2, 999)) / 60.0 < 3.0)
		var moved := Vector2(_up_pos.x - _hips0.x, _up_pos.z - _hips0.z).length()
		check("встал там, где лежало тело (%.2f м от таза)" % moved, moved < 1.2)
		check("снова обычная анимация (%s), рэгдолл убран" % _z._cur, _z._cur != "getup" and _z._knock_rd == null and _z._anim.active)
		check("рэгдоллов активных нет (%d)" % ZombieRagdoll.active, ZombieRagdoll.active == 0)
		# темп ударов
		check("рука: раз в 0.7 с", is_equal_approx(ItemDB.attack("")["rate"], 0.7) and is_equal_approx(ItemDB.attack("stone")["rate"], 0.7))
		check("топор: раз в 1 с", is_equal_approx(ItemDB.attack("stone_axe")["rate"], 1.0))
		check("дубина: раз в 0.85 с", is_equal_approx(ItemDB.attack("wooden_club")["rate"], 0.85))
		check("топор по зомби слабее дубины", ItemDB.damage("stone_axe", "zombie") < ItemDB.damage("wooden_club", "zombie"))
		check("выносливость вдвое: рука 2.5, топор 5, дубина 4.5, бег 6.5/с, прыжок 6",
			is_equal_approx(ItemDB.attack("")["stam"], 2.5) and is_equal_approx(ItemDB.attack("stone_axe")["stam"], 5.0)
			and is_equal_approx(ItemDB.attack("wooden_club")["stam"], 4.5) and is_equal_approx(Player.STAM_SPRINT, 6.5) and is_equal_approx(Player.STAM_JUMP, 6.0))
		print("RESULT fails=%d" % fails)
		return true
	return false
