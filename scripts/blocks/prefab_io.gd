class_name PrefabIO
extends RefCounted
## Сохранение/загрузка структур (префабов) в JSON. Формат читаемый:
## {"format": 2, "cell": 1.0 (м), "name", "category", "tags": [...], "weight", "biomes": [...], "footprint": [x, z] (ячеек, с отступом),
##  "size": [nx, ny, nz], "ground_cells": 2, "blocks": [["wall", x, y, z, rot, tier, variant, state(, up)], ...]}
## Многоячеечные блоки хранятся одной записью (якорь). Координаты x, z отсчитываются от угла рамки построек,
## y — от дна сетки (земля на y = ground_cells).

const DIR_RES := "res://prefabs/"
const DIR_USER := "user://prefabs/"
const FORMAT := 2          # 2: ячейка 1 м (формат 1 — ячейка 0.5 м, мигрируется при загрузке)


## Собирает метаданные + блоки из сетки. margin — отступ футпринта вокруг построек в ячейках.
static func to_dict(grid: BlockGrid, info: Dictionary) -> Dictionary:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := Vector3i(-1, -1, -1)
	var blocks: Array = []
	for i in grid.cells.size():
		var id := grid.cells[i]
		if id < BlockRegistry.FIRST_ID or BlockRegistry.is_part(grid.meta[i]):
			continue
		var a := grid.cell_of(i)
		var m := grid.meta[i]
		var f := BlockRegistry.footprint(id, BlockRegistry.rot_of(m))
		lo = Vector3i(mini(lo.x, a.x), mini(lo.y, a.y), mini(lo.z, a.z))
		hi = Vector3i(maxi(hi.x, a.x + f.x), maxi(hi.y, a.y + f.y), maxi(hi.z, a.z + f.z))
		var rec := [BlockRegistry.block(id)["key"], a.x, a.y, a.z, BlockRegistry.rot_of(m), BlockRegistry.tier_of(m), BlockRegistry.variant_of(m), BlockRegistry.state_of(m)]
		if BlockRegistry.up_of(m) != 0:
			rec.append(BlockRegistry.up_of(m))   # 9-е поле — «верх» (поворот по всем осям), только если не 0
		blocks.append(rec)
	# покрытие земли тоже входит в размеры (может выходить за стены: площадка, дорожка)
	for gc: Vector2i in grid.ground:
		lo = Vector3i(mini(lo.x, gc.x), lo.y, mini(lo.z, gc.y))
		hi = Vector3i(maxi(hi.x, gc.x + 1), hi.y, maxi(hi.z, gc.y + 1))
	for pl: Dictionary in grid.plants:
		var pc := Vector2i(floori(float(pl["x"])), floori(float(pl["z"])))
		lo = Vector3i(mini(lo.x, pc.x), lo.y, mini(lo.z, pc.y))
		hi = Vector3i(maxi(hi.x, pc.x + 1), hi.y, maxi(hi.z, pc.y + 1))
	if blocks.is_empty() and grid.ground.is_empty() and grid.plants.is_empty():
		return {}
	if blocks.is_empty():
		hi.y = grid.ground_cells + 1
	for b: Array in blocks:
		b[1] -= lo.x
		b[3] -= lo.z
	var ground: Array = []
	for gc: Vector2i in grid.ground:
		ground.append([gc.x - lo.x, gc.y - lo.z, grid.ground[gc]])
	ground.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	var margin := int(info.get("margin", 2))
	var size := Vector3i(hi.x - lo.x, hi.y, hi.z - lo.z)
	var d := {
		"format": FORMAT,
		"cell": 1.0,
		"name": info.get("name", "prefab"),
		"category": info.get("category", "house"),
		"tags": info.get("tags", []),
		"weight": float(info.get("weight", 1.0)),
		"biomes": info.get("biomes", ["any"]),
		"footprint": info.get("footprint", [size.x + 2 * margin, size.z + 2 * margin]),
		"size": [size.x, size.y, size.z],
		"ground_cells": grid.ground_cells,
		"sink": int(info.get("sink", 0)),   # на сколько слоёв погрузить в землю при постановке в мир (0 — как в редакторе: нижний слой стоит на земле)
		"blocks": blocks,
	}
	if not ground.is_empty():
		d["ground"] = ground     # [[x, z, тип], ...] — покрытие земли (GroundTypes)
	if not grid.plants.is_empty():
		var pl_out: Array = []
		for pl: Dictionary in grid.plants:
			pl_out.append([pl["type"], snappedf(float(pl["x"]) - lo.x, 0.01), snappedf(float(pl["z"]) - lo.z, 0.01),
				snappedf(float(pl.get("rot", 0.0)), 0.01), snappedf(float(pl.get("scale", 1.0)), 0.01), snappedf(float(pl.get("hue", 0.45)), 0.01)])
		d["plants"] = pl_out     # [[тип, x, z, поворот, масштаб, оттенок], ...] — растения и предметы (PlantTypes)
	return d


static func from_dict(d: Dictionary) -> BlockGrid:
	var s: Array = d.get("size", [1, 1, 1])
	var g := BlockGrid.new(int(s[0]), int(s[1]), int(s[2]))
	g.ground_cells = int(d.get("ground_cells", 1))
	g.sink = int(d.get("sink", 1))
	for b: Array in d.get("blocks", []):
		var id := BlockRegistry.id_by_key(String(b[0]))
		if id == 0:
			push_warning("Префаб: неизвестный блок " + String(b[0]))
			continue
		var m := BlockRegistry.make_meta(int(b[4]), int(b[5]), int(b[6]), int(b[7]) if b.size() > 7 else 0, int(b[8]) if b.size() > 8 else 0)
		var a := Vector3i(int(b[1]), int(b[2]), int(b[3]))
		var rot := BlockRegistry.rot_of(m)
		var f := BlockRegistry.footprint(id, rot)
		if a.x + f.x > g.nx or a.y + f.y > g.ny or a.z + f.z > g.nz:
			continue
		g.place_block(a, id, m)
	for gr: Array in d.get("ground", []):
		var gc := Vector2i(int(gr[0]), int(gr[1]))
		if gc.x >= 0 and gc.y >= 0 and gc.x < g.nx and gc.y < g.nz and GroundTypes.TYPES.has(String(gr[2])):
			g.ground[gc] = String(gr[2])
	for pr: Array in d.get("plants", []):
		if PlantTypes.TYPES.has(String(pr[0])):
			g.plants.append({"type": String(pr[0]), "x": float(pr[1]), "z": float(pr[2]), "rot": float(pr[3]), "scale": float(pr[4]),
				"hue": float(pr[5]) if pr.size() > 5 else 0.45})
	return g


static func save_dict(d: Dictionary, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(_pretty(d))
	return true


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## JSON: метаданные построчно, блоки по одному на строку (удобно читать и сравнивать).
static func _pretty(d: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("{")
	var keys := ["format", "cell", "name", "category", "tags", "weight", "biomes", "footprint", "size", "ground_cells", "sink"]
	for k in keys:
		lines.append("  %s: %s," % [JSON.stringify(k), JSON.stringify(d[k])])
	lines.append("  \"blocks\": [")
	var blocks: Array = d["blocks"]
	for i in blocks.size():
		lines.append("    %s%s" % [JSON.stringify(blocks[i]), "," if i < blocks.size() - 1 else ""])
	for sect in ["ground", "plants"]:
		if d.has(sect):
			lines.append("  ],")
			lines.append("  \"%s\": [" % sect)
			var gl: Array = d[sect]
			for i in gl.size():
				lines.append("    %s%s" % [JSON.stringify(gl[i]), "," if i < gl.size() - 1 else ""])
	lines.append("  ]")
	lines.append("}")
	return "\n".join(lines) + "\n"


## Миграция формата 1 (ячейка 0.5 м) -> 2 (ячейка 1 м). Сетка огрубляется вдвое: кубы голосованием по группе 2x2x2
## (непустая группа = блок, побеждает самый частый материал), двери/окна/декор переносятся целиком (их footprint
## ровно вдвое меньше). Слой пола (первый над землёй) остаётся отдельным слоем, стены идут выше него.
static func migrate(d: Dictionary) -> Dictionary:
	if int(d.get("format", 1)) >= 2:
		return d
	var g_old := int(d.get("ground_cells", 2))
	var votes := {}        # Vector3i -> {"k|t|v": count}
	var specials: Array = []
	for b: Array in d.get("blocks", []):
		var id := BlockRegistry.id_by_key(String(b[0]))
		if id == 0:
			continue
		var x := int(b[1])
		var y := int(b[2])
		var z := int(b[3])
		var ny := 0 if y < g_old else 1 + int(ceil(float(y - g_old) / 2.0))
		var c := Vector3i(x / 2, ny, z / 2)
		if BlockRegistry.is_cube(id):
			var v: Dictionary = votes.get(c, {})
			var k := "%s|%d|%d" % [b[0], int(b[5]), int(b[6])]
			v[k] = int(v.get(k, 0)) + 1
			votes[c] = v
		else:
			specials.append([String(b[0]), c, int(b[4]), int(b[5]), int(b[6]), int(b[7]) if b.size() > 7 else 0, id])
	var out_blocks: Array = []
	var occ := {}
	for s: Array in specials:
		var rot := int(s[2])
		var f := BlockRegistry.footprint(int(s[6]), rot)
		var c: Vector3i = s[1]
		var free := true
		var cells: Array[Vector3i] = []
		for dz in f.z:
			for dy in f.y:
				for dx in f.x:
					var q := c + Vector3i(dx, dy, dz)
					cells.append(q)
					if occ.has(q):
						free = false
		if not free:
			continue
		for q in cells:
			occ[q] = true
		out_blocks.append([s[0], c.x, c.y, c.z, rot, s[3], s[4], s[5]])
	for c: Vector3i in votes:
		if occ.has(c):
			continue
		var best := ""
		var bn := -1
		for k: String in votes[c]:
			if int(votes[c][k]) > bn:
				bn = int(votes[c][k])
				best = k
		var p := best.split("|")
		out_blocks.append([p[0], c.x, c.y, c.z, 0, int(p[1]), int(p[2]), 0])
	out_blocks.sort_custom(func(a: Array, b: Array) -> bool:
		if a[2] != b[2]:
			return a[2] < b[2]
		if a[3] != b[3]:
			return a[3] < b[3]
		return a[1] < b[1])
	var hi := Vector3i(1, 1, 1)
	for b: Array in out_blocks:
		var f := BlockRegistry.footprint(BlockRegistry.id_by_key(String(b[0])), int(b[4]))
		hi = Vector3i(maxi(hi.x, int(b[1]) + f.x), maxi(hi.y, int(b[2]) + f.y), maxi(hi.z, int(b[3]) + f.z))
	var fp: Array = d.get("footprint", [hi.x * 2, hi.z * 2])
	var nd := d.duplicate()
	nd["format"] = FORMAT
	nd["cell"] = 1.0
	nd["ground_cells"] = 1
	nd["sink"] = 1
	nd["size"] = [hi.x, hi.y, hi.z]
	nd["footprint"] = [maxi(int(ceil(float(fp[0]) / 2.0)), hi.x), maxi(int(ceil(float(fp[1]) / 2.0)), hi.z)]
	nd["blocks"] = out_blocks
	return nd