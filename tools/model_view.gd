extends Node3D
## Просмотр модели: godot --path . res://tools/model_view.tscn -- --model=res://assets/ready/x.glb --shot=out.png [--ry=0 --rx=0 --rz=0]
func _ready() -> void:
	var model := ""; var shot := ""; var rot := Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model = a.substr(8)
		elif a.begins_with("--shot="): shot = a.substr(7)
		elif a.begins_with("--rx="): rot.x = deg_to_rad(float(a.substr(5)))
		elif a.begins_with("--ry="): rot.y = deg_to_rad(float(a.substr(5)))
		elif a.begins_with("--rz="): rot.z = deg_to_rad(float(a.substr(5)))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.4, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-40, 30, 0); add_child(l)
	var m := (load(model) as PackedScene).instantiate() as Node3D
	m.rotation = rot
	add_child(m)
	var cam := Camera3D.new(); cam.position = Vector3(0, 0, 2.6); add_child(cam)
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
