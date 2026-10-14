extends SceneTree
## Снимок модели игрока от третьего лица (PlayerAvatar) в разных позах: -- <файл.png>  (с окном)

var _f := 0
var _out := ""
var _av: Array = []


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else "avatar.png"
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
	sun.shadow_enabled = true
	root.add_child(sun)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	gm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.4, 0.3)
	gm.material_override = mat
	root.add_child(gm)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(1.0, 1.7, -5.2), Vector3(1.0, 0.9, 0))
	var setups := [["stone_axe", 2], ["wooden_club", 1], ["pistol", 3], ["", 4], ["water_bottle", 0], ["", 5]]
	for i in setups.size():
		var av := PlayerAvatar.new()
		root.add_child(av)
		av.position = Vector3(-3.0 + i * 1.3, 0, 0)
		av.rotation.y = 0.5    # лицом к камере (модель смотрит на -Z), вполоборота
		av.build(PlayerAvatar.tint_for(i + 1), "Игрок %d" % (i + 1))
		av.set_item(setups[i][0])
		_av.append([av, setups[i][1]])


func _process(d: float) -> bool:
	_f += 1
	for e: Array in _av:
		var av: PlayerAvatar = e[0]
		match int(e[1]):
			0: av.animate(d, 0.0, false, 0.0, false)
			1: av.animate(d, 5.0, false, 0.0, false)                # шагом
			2:
				if _f == 2:
					av.play_action("swing")
				av.animate(d if _f < 14 else 0.0, 0.0, false, 0.0, false)   # замах (кадр в середине)
			3: av.animate(d, 0.0, true, 0.3, false)                 # пригнулся, целится вверх
			4: av.animate(d, 8.5, false, 0.0, false)                # бег
			5: av.animate(d, 0.0, false, 0.0, true)                 # мёртв
	if _f == 40:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
