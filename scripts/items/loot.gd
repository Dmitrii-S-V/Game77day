class_name Loot
extends RefCounted
## Обыскиваемые контейнеры (мешки и кучи мусора): таблицы лута и список уже обысканных.
## Обысканный контейнер запоминается по округлённой позиции — после перезагрузки чанка он остаётся пустым.

# id таблицы -> {time: секунд на обыск, rolls: [min, max] предметов, items: [[id, вес, min, max], ...], empty: шанс пустого}
const TABLES := {
	"trash_pile": {"time": 1.6, "rolls": [1, 3], "empty": 0.12, "items": [
		["cloth", 30, 1, 3], ["plastic", 28, 1, 4], ["paper", 24, 1, 5], ["glass_bottle", 10, 1, 1],
		["scrap_metal", 12, 1, 2], ["duct_tape", 5, 1, 1], ["nails", 7, 2, 6],
		["canned_food", 9, 1, 1], ["candy_bar", 7, 1, 2], ["wooden_club", 1, 1, 1], ["ammo_9mm", 5, 3, 8], ["pistol", 1, 1, 1]]},
	"trash_bag": {"time": 1.2, "rolls": [1, 2], "empty": 0.2, "items": [
		["cloth", 30, 1, 2], ["plastic", 30, 1, 3], ["paper", 30, 1, 4], ["glass_bottle", 6, 1, 1], ["duct_tape", 3, 1, 1],
		["canned_food", 6, 1, 1], ["candy_bar", 6, 1, 1]]},
	# брошенный рюкзак на территории построек: реже, но ценнее мусора
	"backpack": {"time": 1.8, "rolls": [2, 4], "empty": 0.08, "items": [
		["canned_food", 18, 1, 2], ["candy_bar", 14, 1, 2], ["cloth", 16, 1, 3], ["duct_tape", 10, 1, 1], ["ammo_9mm", 10, 4, 12],
		["penicillin", 5, 1, 1], ["nails", 8, 3, 8], ["scrap_metal", 8, 1, 2], ["glass_bottle", 8, 1, 1], ["pistol", 1, 1, 1]]},
	# труп зомби (как «мешок зомби» в 7DTD — чаще пусто)
	"zombie": {"time": 1.4, "rolls": [1, 2], "empty": 0.45, "items": [
		["cloth", 35, 1, 3], ["paper", 10, 1, 2], ["scrap_metal", 10, 1, 1], ["duct_tape", 6, 1, 1], ["nails", 6, 1, 4],
		["canned_food", 8, 1, 1], ["candy_bar", 10, 1, 1], ["glass_bottle", 6, 1, 1], ["ammo_9mm", 8, 2, 6]]},
}

static var _looted := {}


static func key_of(pos: Vector3) -> Vector3i:
	return Vector3i(roundi(pos.x * 2.0), roundi(pos.y), roundi(pos.z * 2.0))


static func is_looted(pos: Vector3) -> bool:
	return _looted.has(key_of(pos))


static func mark_looted(pos: Vector3) -> void:
	_looted[key_of(pos)] = true


## Контейнер исчез навсегда (труп зомби) — не хранить его в сохранении.
static func forget(pos: Vector3) -> void:
	_looted.erase(key_of(pos))


static func search_time(table: String) -> float:
	return float(TABLES.get(table, {}).get("time", 1.5))


## Случайный лут: массив [id, n]. Детерминирован по позиции контейнера (повторный обыск не «перекатывает» удачу).
static func roll(table: String, pos: Vector3) -> Array:
	var t: Dictionary = TABLES.get(table, {})
	if t.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key_of(pos), table, 31337])
	if rng.randf() < float(t["empty"]):
		return []
	var items: Array = t["items"]
	var total := 0.0
	for it: Array in items:
		total += float(it[1])
	var out := {}
	var n := rng.randi_range(int(t["rolls"][0]), int(t["rolls"][1]))
	for i in n:
		var r := rng.randf() * total
		for it: Array in items:
			r -= float(it[1])
			if r <= 0.0:
				out[it[0]] = int(out.get(it[0], 0)) + rng.randi_range(int(it[2]), int(it[3]))
				break
	var res := []
	for id: String in out:
		res.append([id, out[id]])
	return res
