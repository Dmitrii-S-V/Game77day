extends SceneTree
## Отладка: кости скелета модели (имя, родитель, длина до первого ребёнка). -- <res://модель.glb>


func _init() -> void:
	var m := (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate() as Node3D
	var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in sk.get_bone_count():
		var ch := sk.get_bone_children(i)
		var l := sk.get_bone_rest(ch[0]).origin.length() if ch.size() > 0 else 0.0
		print("BONE %d %s parent %d len %.3f children %s y %.2f" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), l, str(ch), sk.get_bone_global_rest(i).origin.y])
	quit()
