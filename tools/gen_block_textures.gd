extends SceneTree
## Записывает процедурные заглушки текстур блоков в assets/textures/blocks/*.png.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_block_textures.gd
## Файлы с тем же именем, положенные вручную (например из ComfyUI, 128x128 или больше — масштабируются),
## сразу используются вместо заглушек. Существующие файлы без --force не перезаписываются.


func _init() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BlockRegistry.TEX_DIR))
	var names := BlockRegistry._layer_names
	BlockRegistry.ensure()
	names = BlockRegistry._layer_names
	var made := 0
	for n in names:
		var path := ProjectSettings.globalize_path(BlockRegistry.TEX_DIR + n + ".png")
		if FileAccess.file_exists(path) and not force:
			continue
		BlockTexGen.make(n).save_png(path)
		made += 1
	print("block textures: ", names.size(), " layers, written ", made)
	quit()
