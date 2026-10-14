extends SceneTree
## Отладка: положение костей модели в начале и в конце анимации (в Godot). -- <res://модель.glb> <анимация> [кости через запятую]

var _ap: AnimationPlayer
var _sk: Skeleton3D
var _names: PackedStringArray
var _frame := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var m := (load(a[0]) as PackedScene).instantiate() as Node3D
	root.add_child(m)
	_ap = m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_sk = m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_names = (a[2] if a.size() > 2 else "Hips,Head,LeftFoot,hips,head,foot_l").split(",")
	print("ANIMS ", _ap.get_animation_list())
	_ap.play(a[1])


func _report() -> void:
	var s := "t=%.2f" % _ap.current_animation_position
	for bi in _sk.get_bone_count():
		var bn := _sk.get_bone_name(bi)
		for n in _names:
			if bn == n or bn.ends_with(n) and (bn.length() == n.length() or not bn[bn.length() - n.length() - 1].is_valid_identifier()):
				var gp := _sk.global_transform * _sk.get_bone_global_pose(bi)
				s += "  %s y=%.3f z=%.3f" % [bn, gp.origin.y, gp.origin.z]
	print(s)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_report()
	if _frame == 150:
		_report()
		return true
	return false
