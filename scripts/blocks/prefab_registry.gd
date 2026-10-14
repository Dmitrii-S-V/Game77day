class_name PrefabRegistry
extends RefCounted
## Реестр префабов: читает все *.json из res://prefabs/ (и user://prefabs/), таблица по категории и весу.
## Подключён к генерации поселений: Settlement для участка с типом здания спрашивает pick(), и если
## префаб подходит по размеру футпринта, ставит его вместо сгенерированного кодом здания.

const BASE_WEIGHT := 0.0    # вес «обычного» здания из BlockGen при выборе (0: кодовых домов в городах нет — свой префаб всегда)

## Какие категории префабов подходят для каких типов участков (btype). Нет в таблице — категория == btype.
const CATEGORY_LOTS := {
	"house": ["house", "farmhouse"],
	"shop": ["shop"],
	"gas_station": ["gas_store"],
	"gas_store": ["gas_store"],
	"warehouse": ["warehouse"],
	"barn": ["barn"],
	"office": ["office"],
	"apartment": ["apartment"],
	"cabin": ["cabin"],
	"shed": ["shed"],
	"park": ["park"],
}

static var _loaded := false
static var _items: Array = []       # {path, data, grid(BlockGrid|null)}


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_items = []
	for dir in [PrefabIO.DIR_RES, PrefabIO.DIR_USER]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".json"):
				var data := PrefabIO.load_dict(dir + f)
				if not data.is_empty() and data.has("blocks") and int(data.get("format", 1)) < PrefabIO.FORMAT:
					# старый формат (ячейка 0.5 м): копия .v1.bak и перезапись в формате 1 м
					DirAccess.copy_absolute(ProjectSettings.globalize_path(dir + f), ProjectSettings.globalize_path(dir + f) + ".v1.bak")
					data = PrefabIO.migrate(data)
					PrefabIO.save_dict(data, dir + f)
					print("Префаб мигрирован на ячейку 1 м: ", dir + f)
				if not data.is_empty() and data.has("blocks"):
					_items.append({"path": dir + f, "data": data, "grid": null})


static func reload() -> void:
	_loaded = false
	ensure()


static func all() -> Array:
	ensure()
	return _items


static func names() -> PackedStringArray:
	ensure()
	var out := PackedStringArray()
	for it: Dictionary in _items:
		out.append(String(it["data"].get("name", "")))
	return out


static func find(prefab_name: String) -> Dictionary:
	ensure()
	for it: Dictionary in _items:
		if String(it["data"].get("name", "")) == prefab_name:
			return it
	return {}


## Копия сетки префаба (кэш строится один раз).
static func grid_of(item: Dictionary) -> BlockGrid:
	if item["grid"] == null:
		item["grid"] = PrefabIO.from_dict(item["data"])
	return (item["grid"] as BlockGrid).duplicate_grid()


static func matches(item: Dictionary, btype: String) -> bool:
	var cat := String(item["data"].get("category", ""))
	var lots: Array = CATEGORY_LOTS.get(cat, [cat])
	return btype in lots


## Есть ли префаб городской категории, который не влезает в обычный квадратный участок lot_m x lot_m
## (тогда в городах-сетках часть кварталов отдаётся под одно крупное здание, см. RoadNet.BIG_BLOCK_P).
static func has_big(lot_m: float) -> bool:
	ensure()
	for it: Dictionary in _items:
		var cat := String(it["data"].get("category", ""))
		if not cat in ["house", "shop", "office", "apartment", "warehouse", "park"]:
			continue
		if float(it["data"].get("weight", 1.0)) <= 0.0:
			continue
		var fp: Array = it["data"].get("footprint", [1, 1])
		if maxf(float(fp[0]), float(fp[1])) * BlockGrid.B > lot_m:
			return true
	return false


## Выбор префаба для участка размера (width_m x depth_m): {item, rotated} или {}.
## rnd — детерминированное число 0..1 (из seed участка).
static func pick(btype: String, width_m: float, depth_m: float, rnd: float) -> Dictionary:
	ensure()
	var cands: Array = []
	var total := 0.0
	for it: Dictionary in _items:
		if not matches(it, btype):
			continue
		var fp: Array = it["data"].get("footprint", [1, 1])
		var fw := float(fp[0]) * BlockGrid.B
		var fd := float(fp[1]) * BlockGrid.B
		var rotated := false
		if fw <= width_m and fd <= depth_m:
			rotated = false
		elif fd <= width_m and fw <= depth_m:
			rotated = true
		else:
			continue
		var w := maxf(float(it["data"].get("weight", 1.0)), 0.0)
		# на большом участке предпочтительнее префабы, которые его лучше заполняют (крупный дом, а не будка)
		w *= clampf(fw * fd / maxf(width_m * depth_m, 1.0) * 2.0, 0.25, 1.5)
		cands.append({"item": it, "rotated": rotated, "w": w})
		total += w
	if cands.is_empty() or total <= 0.0:
		return {}
	if rnd * (total + BASE_WEIGHT) >= total:
		return {}   # победило обычное здание
	var r := rnd * (total + BASE_WEIGHT)
	var acc := 0.0
	for c: Dictionary in cands:
		acc += float(c["w"])
		if r <= acc:
			return c
	return cands[cands.size() - 1]
