extends SceneTree
## Запекает процедурные модели в assets/models/*.res
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_models.gd

const OUT := "res://assets/models/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 3:
		_save(ModelGen.rock(100 + i, 0.9 + i * 0.5), "rock_%d" % i)
		_save(ModelGen.pine(200 + i), "pine_%d" % i)
		_save(ModelGen.oak(300 + i, true), "oak_%d" % i)
		_save(ModelGen.bush(500 + i, i == 2), "bush_%d" % i)
	for i in 2:
		_save(ModelGen.oak(600 + i, true, true), "oak_dry_%d" % i)
	_save(ModelGen.oak(400, false), "dead_tree_0")
	# облегчённые версии деревьев для среднего расстояния (FarProps)
	ModelGen.lod_density = 0.28
	for i in 3:
		_save(ModelGen.pine(200 + i), "pine_lod_%d" % i)
		_save(ModelGen.oak(300 + i, true), "oak_lod_%d" % i)
	for i in 2:
		_save(ModelGen.oak(600 + i, true, true), "oak_dry_lod_%d" % i)
	ModelGen.lod_density = 1.0
	quit()


func _save(mesh: Mesh, name: String) -> void:
	var err := ResourceSaver.save(mesh, OUT + name + ".res")
	print("%s: %d verts, err %d" % [name, (mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), err])
