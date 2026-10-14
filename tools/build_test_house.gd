extends SceneTree
## Собирает тестовый дом и сохраняет префабом res://prefabs/test_house.json.
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/build_test_house.gd


func _init() -> void:
	var g := TestHouse.build()
	var d := PrefabIO.to_dict(g, {"name": "test_house", "category": "house", "tags": ["test", "дом", "заброшенный"], "weight": 1.0, "biomes": ["any"], "margin": 2, "sink": 1})
	var ok := PrefabIO.save_dict(d, PrefabIO.DIR_RES + "test_house.json")
	print("test_house saved: ", ok, " blocks ", d["blocks"].size(), " size ", d["size"], " footprint ", d["footprint"])
	quit()
