extends SceneTree
## Собирает data/blocks/decals.json из decals_raw.json (результат tools/prepare_decals.gd): присваивает спрайтам
## класс и физический размер. Классы и размеры можно править прямо в decals.json (этот скрипт перезапишет только
## спрайты, которых там ещё нет — уже заданные вручную значения не трогает).
## Запуск: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/build_decal_table.gd
##
## kind: grime (грязь, подтёки, масло), print (отпечатки рук/ног), sign (знаки, таблички), poster (афиши, старая бумага),
##       hole (пробоины), scratch (царапины), rust (ржавые пятна), stencil (трафаретные цифры), plant (травянистые карточки),
##       ground (напочвенные пятна: камешки, почва, мох, листва), rock (камни), skip (мусор нарезки).

const SIGN_KIND := {
	0: "sign", 1: "sign", 2: "sign", 3: "stencil", 4: "sign", 5: "sign", 6: "sign", 7: "sign", 8: "rust", 9: "skip", 10: "hole", 11: "hole",
	12: "stencil", 13: "rust", 14: "hole", 15: "hole", 16: "hole", 17: "hole", 18: "scratch", 19: "scratch", 20: "rust", 21: "stencil",
	22: "stencil", 23: "stencil", 24: "rust", 25: "scratch", 26: "sign", 27: "sign", 28: "sign", 29: "rust",
}
const NATURE_KIND := {
	0: "plant", 1: "skip", 2: "plant", 3: "plant", 4: "plant", 5: "plant", 6: "plant", 7: "plant", 8: "plant", 9: "plant", 10: "rock",
	11: "plant", 12: "plant", 13: "rock", 14: "rock", 15: "rock", 16: "rock", 17: "rock", 18: "rock", 19: "ground", 20: "ground",
	21: "ground", 22: "rock", 23: "skip", 24: "ground", 25: "skip", 26: "ground", 27: "ground", 28: "ground", 29: "skip", 30: "ground",
	31: "plant", 32: "ground",
}


func _init() -> void:
	var raw_f := FileAccess.open(ProjectSettings.globalize_path("res://data/blocks/decals_raw.json"), FileAccess.READ)
	var raw: Array = JSON.parse_string(raw_f.get_as_text())
	var table_path := ProjectSettings.globalize_path("res://data/blocks/decals.json")
	var existing := {}
	if FileAccess.file_exists(table_path):
		var old: Variant = JSON.parse_string(FileAccess.open(table_path, FileAccess.READ).get_as_text())
		if old is Dictionary:
			for d: Dictionary in old.get("decals", []):
				existing[String(d["key"])] = d
	var out: Array = []
	var next_id := 1
	for r: Dictionary in raw:
		var key: String = r["key"]
		var d: Dictionary
		if existing.has(key):
			d = existing[key]
		else:
			d = _classify(r)
		d["id"] = next_id
		next_id += 1
		out.append(d)
	var data := {
		"_comment": "Таблица декалей. Спрайты: assets/textures/decals/<key>.png (квадрат, альфа). kind — класс (см. tools/build_decal_table.gd), size — сторона квадрата спрайта в метрах на стене/земле, weight — вес при случайном износе, places — где применять: wall (грани блоков), ground (ландшафт), card (вертикальные карточки растений). Правьте вручную — скрипт сборки не перезапишет уже существующие записи.",
		"decals": out,
	}
	var f := FileAccess.open(table_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	var counts := {}
	for d: Dictionary in out:
		counts[d["kind"]] = int(counts.get(d["kind"], 0)) + 1
	print("decals: ", out.size(), " ", counts)
	quit()


func _classify(r: Dictionary) -> Dictionary:
	var sheet: String = r["sheet"]
	var idx: int = r["index"]
	var px: int = r["px"]
	var bb: Array = r["bbox"]
	var kind := "grime"
	var size := 0.9
	var weight := 1.0
	var places := ["wall"]
	match sheet:
		"mud":
			var cx := float(bb[0]) + float(bb[2]) * 0.5
			var cy := float(bb[1]) + float(bb[3]) * 0.5
			if cx > 768.0 and cy < 512.0:
				kind = "print"
				size = 0.35
				weight = 0.6
			else:
				size = 1.0 if px >= 260 else (0.7 if px >= 150 else 0.45)
				places = ["wall", "ground"]
		"signs":
			kind = SIGN_KIND.get(idx, "sign")
			match kind:
				"sign":
					size = 0.9 if px >= 300 else 0.7
					weight = 0.5
				"stencil":
					size = 0.5
					weight = 0.4
				"hole":
					size = 0.2 if px < 140 else 0.28
					weight = 1.2
				"scratch":
					size = 0.6
				"rust":
					size = 0.9
					weight = 1.0
		"supply":
			kind = "sign"
			size = 0.85 if px >= 300 else (0.65 if px >= 200 else 0.5)
			weight = 0.4
		"posters":
			kind = "poster"
			size = 0.9
			weight = 0.35
		"nature":
			kind = NATURE_KIND.get(idx, "skip")
			match kind:
				"plant":
					places = ["card"]
					size = 1.0
				"ground":
					places = ["ground"]
					size = 3.0
				"rock":
					places = ["ground"]
					size = 0.6
				_:
					places = []
	return {"key": r["key"], "file": "res://assets/textures/decals/%s.png" % r["key"], "kind": kind, "size": size,
		"weight": weight, "places": places, "aspect": snappedf(float(r["aspect"]), 0.01)}
