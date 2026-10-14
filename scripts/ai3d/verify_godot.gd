extends SceneTree
# Usage: godot --headless --path D:\77Days -s scripts/ai3d/verify_godot.gd -- res://assets/ready/street_lamp.glb
# Loads the imported scene and prints its AABB in Godot axes (Y up), triangles and UV/material info.

func _initialize() -> void:
	var path := "res://assets/ready/street_lamp.glb"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var ps := load(path) as PackedScene
	if ps == null:
		print("VERIFY FAIL: cannot load ", path)
		quit(1)
		return
	var root := ps.instantiate()
	get_root().add_child(root)
	var aabb := AABB()
	var first := true
	var tris := 0
	var has_uv := false
	var has_tex := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			has_uv = has_uv or arr[Mesh.ARRAY_TEX_UV] != null
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			has_tex = has_tex or (mat != null and mat.albedo_texture != null)
	print("VERIFY OK ", path, " tris=", tris, " size=", aabb.size, " min=", aabb.position,
		" uv=", has_uv, " albedo_texture=", has_tex)
	root.free()
	quit(0)
