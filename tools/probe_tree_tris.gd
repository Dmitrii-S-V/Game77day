extends SceneTree
## Число вершин/треугольников в моделях деревьев (полные и lod): godot --headless --path . --script res://tools/probe_tree_tris.gd
func _init() -> void:
	var d := DirAccess.open("res://assets/models")
	var names: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".res") and (f.contains("tree") or f.contains("pine") or f.contains("oak") or f.contains("birch") or f.contains("lod")):
			names.append(f)
	names.sort()
	var tot := 0
	for f in names:
		var m := load("res://assets/models/" + f) as ArrayMesh
		if m == null:
			continue
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("%-28s surfaces %d  tris %d" % [f, m.get_surface_count(), tris])
		tot += tris
	quit()
