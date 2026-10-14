class_name CraftDB
extends RefCounted
## Рецепты крафта (вкладка «Крафт» инвентаря). need — {предмет: сколько} ("id@L" — экземпляр уровня L), out/n —
## результат, lvl — уровень результата (Gear), cat — категория. Рецепты уровней 2–5 открываются развитием
## (Gear.unlocked: урон этим оружием по зомби/блокам).

const CATEGORIES := ["Все", "Инструменты", "Оружие", "Ресурсы"]

const BASE := [
	{"out": "grass_rope", "n": 1, "cat": "Ресурсы", "need": {"grass": 5}},
	{"out": "stone_axe", "n": 1, "lvl": 1, "cat": "Инструменты", "need": {"grass_rope": 3, "stone": 1, "planks": 15}},
	{"out": "wooden_club", "n": 1, "lvl": 1, "cat": "Оружие", "need": {"wood": 10}},
	{"out": "backpack", "n": 1, "cat": "Ресурсы", "need": {"grass_rope": 3, "cloth": 6}},
	{"out": "hard_hat", "n": 1, "cat": "Ресурсы", "need": {"cloth": 4, "grass_rope": 2}},
	{"out": "rag_vest", "n": 1, "cat": "Ресурсы", "need": {"cloth": 8, "grass_rope": 3}},
	{"out": "rag_boots", "n": 1, "cat": "Ресурсы", "need": {"cloth": 5, "grass_rope": 2}},
]

static var _all: Array = []


## Все рецепты: базовые + уровни 2–5 оружия/инструментов.
static func recipes() -> Array:
	if _all.is_empty():
		_all = BASE.duplicate(true)
		for l in range(2, Gear.MAX_LVL + 1):
			_all.append({"out": "stone_axe", "n": 1, "lvl": l, "cat": "Инструменты",
				"need": {"stone_axe@%d" % (l - 1): 1, "grass_rope": l, "stone": l, "planks": 5 * l}})
			_all.append({"out": "wooden_club", "n": 1, "lvl": l, "cat": "Оружие",
				"need": {"wooden_club@%d" % (l - 1): 1, "wood": 5 * l, "nails": 5 * (l - 1)}})
			_all.append({"out": "pistol", "n": 1, "lvl": l, "cat": "Оружие",
				"need": {"pistol@%d" % (l - 1): 1, "scrap_metal": 8 * l, "duct_tape": l - 1}})
	return _all


static func title(r: Dictionary) -> String:
	var t := ItemDB.item_name(r["out"])
	return t + (" ур. %d" % int(r["lvl"]) if int(r.get("lvl", 1)) > 1 else "")


static func list(cat: String = "Все", search: String = "") -> Array:
	var out: Array = []
	var s := search.strip_edges().to_lower()
	for r: Dictionary in recipes():
		if cat != "Все" and r["cat"] != cat:
			continue
		if s != "" and not title(r).to_lower().contains(s):
			continue
		out.append(r)
	return out


## Открыт ли рецепт (уровни 2–5 — после развития).
static func is_unlocked(r: Dictionary) -> bool:
	var l := int(r.get("lvl", 1))
	return l <= 1 or Gear.unlocked(String(r["out"])) >= l


static func _split(key: String) -> Array:
	var p := key.split("@")
	return [p[0], int(p[1]) if p.size() > 1 else 0]


## Сколько есть: "id" — всего, "id@L" — экземпляров уровня L.
static func have(inv: Inventory, key: String) -> int:
	var k := _split(key)
	if int(k[1]) == 0:
		return inv.count(k[0])
	var n := 0
	for s: Variant in inv.slots:
		if s != null and s["id"] == k[0] and Gear.lvl(s) == int(k[1]):
			n += int(s["n"])
	return n


static func need_name(key: String) -> String:
	var k := _split(key)
	return ItemDB.item_name(k[0]) + (" ур. %d" % int(k[1]) if int(k[1]) > 0 else "")


static func need_id(key: String) -> String:
	return String(_split(key)[0])


static func can_craft(inv: Inventory, r: Dictionary) -> bool:
	if not is_unlocked(r):
		return false
	for key: String in r["need"]:
		if have(inv, key) < int(r["need"][key]):
			return false
	return true


## Скрафтить один раз: забрать ингредиенты, выдать результат (уровень, полная прочность). Нет места — false.
static func craft(inv: Inventory, r: Dictionary) -> bool:
	if not can_craft(inv, r):
		return false
	var taken: Array = []
	for key: String in r["need"]:
		var k := _split(key)
		if int(k[1]) > 0:
			for i in inv.slots.size():
				var s: Variant = inv.slots[i]
				if s != null and s["id"] == k[0] and Gear.lvl(s) == int(k[1]):
					taken.append(s)
					inv.slots[i] = null
					break
		else:
			inv.take(k[0], int(r["need"][key]))
	var left := inv.add(r["out"], int(r["n"]), Gear.extra(r["out"], int(r.get("lvl", 1))))
	if left > 0:
		inv.take(r["out"], int(r["n"]) - left)
		for key: String in r["need"]:
			if int(_split(key)[1]) == 0:
				inv.add(need_id(key), int(r["need"][key]))
		for s: Dictionary in taken:
			inv.add(s["id"], 1, s)
		inv.changed.emit()
		return false
	inv.changed.emit()
	return true
