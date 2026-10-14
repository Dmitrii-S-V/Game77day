extends SceneTree
## Запечь сжатые текстуры, которые грузятся не при старте мира, а позже (осколки земли, кора дубины):
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/bake_textures.gd -- --bake-tex
## Основные — запуском мира с --bake-tex (см. docs/HANDOFF.md, «Сборка exe»).


func _init() -> void:
	for n in ["terrain_stone", "terrain_sand", "road_asphalt", "road_concrete", "terrain_gravel", "road_dirt", "dirt_a"]:
		Debris.file_tex(n)
	TexCache.texture("res://assets/textures/bark_1.png", true, 1024)   # дубина (ItemModels.club)
	print("done")
	quit()
