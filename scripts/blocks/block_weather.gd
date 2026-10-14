class_name BlockWeather
extends RefCounted
## Автоматический «износ» здания: случайные декали на наружных и внутренних гранях блоков (грязь у земли, отпечатки,
## ржавчина, пробоины, царапины, редкие знаки и афиши). Детерминирован по seed; таблица весов — data/blocks/decals.json ("weather").

## Тип материала старых блоков зданий (id 1..18); "" — не трогать (стекло, сено).
static func legacy_kind(id: int) -> String:
	match id:
		1, 6, 7, 10, 12, 14, 16, 18:
			return "wood"
		2, 3, 8, 9, 11:
			return "stone"
		4, 15:
			return "metal"
		13:
			return "cloth"
	return ""


static func cell_kind(g: BlockGrid, x: int, y: int, z: int) -> String:
	var id := g.get_cell(x, y, z)
	if id == 0 or id == BlockDefs.GLASS:
		return ""
	if id < BlockRegistry.FIRST_ID:
		return legacy_kind(id)
	if not BlockRegistry.is_cube(id):
		return ""
	var m := g.get_meta_at(x, y, z)
	var tier := BlockRegistry.tier_of(m)
	if BlockRegistry.is_frame(id, tier):
		return ""
	return BlockRegistry.kind(id, tier)


## density < 0 — взять из таблицы. Старые декали не стираются, новые не ставятся на грани, где декаль уже есть.
static func apply(g: BlockGrid, seed_v: int, density: float = -1.0) -> int:
	BlockDecals.ensure()
	var cfg := BlockDecals.weather_cfg()
	if cfg.is_empty() or BlockDecals.count() == 0:
		return 0
	if density < 0.0:
		density = float(cfg.get("density", 0.1))
	var kinds_cfg: Dictionary = cfg.get("kinds", {})
	var boost: Dictionary = cfg.get("ground_boost", {})
	var rows := int(cfg.get("ground_rows", 2))
	var floor_cfg: Dictionary = cfg.get("floor", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.22
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var placed := 0
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for z in g.nz:
		for y in g.ny:
			for x in g.nx:
				var kind_m := cell_kind(g, x, y, z)
				if kind_m == "" or not kinds_cfg.has(kind_m):
					continue
				var ci := g.idx(x, y, z)
				var patch := clampf(0.35 + noise.get_noise_3d(x, y * 1.5, z) * 1.6, 0.0, 1.6)
				var near_ground := y - g.ground_cells < rows
				for d in 6:
					if d == 3:
						continue
					var n: Vector3i = dirs[d]
					if g.get_cell(x + n.x, y + n.y, z + n.z) != 0:
						continue
					var key := ci * 8 + d
					if g.decals.has(key):
						continue
					var table: Dictionary = kinds_cfg[kind_m]
					var prob := density * patch
					if d == 2:
						# пол/плоская крыша: только грязь и отпечатки
						table = {}
						for k: String in floor_cfg.get("kinds", []):
							table[k] = 1.0
						prob = density * float(floor_cfg.get("prob", 0.25)) * patch
					elif near_ground:
						prob *= 1.6
					if table.is_empty() or rng.randf() > prob:
						continue
					var layer := _pick(rng, table, boost if near_ground else {})
					if layer < 0:
						continue
					var rot := rng.randi() % 4 if BlockDecals.can_rotate(layer) else 0
					g.decals[key] = BlockDecals.pack(layer, rot, rng.randf() < 0.5 and BlockDecals.can_rotate(layer), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
					placed += 1
	return placed


static func _pick(rng: RandomNumberGenerator, table: Dictionary, boost: Dictionary) -> int:
	var total := 0.0
	var w := {}
	for k: String in table:
		if BlockDecals.layers_of_kind(k).is_empty():
			continue
		var v := float(table[k]) * float(boost.get(k, 1.0))
		w[k] = v
		total += v
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	var kind := ""
	for k: String in w:
		r -= float(w[k])
		kind = k
		if r <= 0.0:
			break
	var layers: Array = BlockDecals.layers_of_kind(kind)
	if layers.is_empty():
		return -1
	# выбор спрайта внутри класса с учётом веса
	var tw := 0.0
	for l: int in layers:
		tw += float(BlockDecals.entry(l).get("weight", 1.0))
	var rr := rng.randf() * tw
	for l: int in layers:
		rr -= float(BlockDecals.entry(l).get("weight", 1.0))
		if rr <= 0.0:
			return l
	return layers[layers.size() - 1]
