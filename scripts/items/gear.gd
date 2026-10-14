class_name Gear
extends RefCounted
## Уровни (1–5) и прочность оружия/инструментов, развитие (урон по зомби/блокам/животным открывает крафт следующего
## уровня) и статистика. Экземпляр предмета в слоте: {"id", "n", "lvl" (1..5), "dur" (прочность)}; нет ключей —
## уровень 1, прочность полная.

const MAX_LVL := 5
## base_dur — прочность 1-го уровня (удары/выстрелы); kind — класс для шансов сбить/оглушить (Zombie.chances)
const LEVELED := {
	"stone_axe": {"dur": 200.0, "kind": "melee"},
	"wooden_club": {"dur": 160.0, "kind": "bat"},
	"pistol": {"dur": 400.0, "kind": "gun"},
}
const DMG_STEP := 0.2        # урон: каждый уровень +20% к предыдущему
const BAT_STEP := 0.03       # бита: +3% к шансам сбить с ног и оглушить за уровень
const DUR_STEP := 0.15       # прочность: +15% за уровень
const XP_STEP := 1000.0      # открыть уровень L: нанести урона 1000·(L−1) сверх предыдущего порога

# статистика (сохраняется)
static var dealt := {}       # id -> всего урона этим типом оружия (зомби, блоки, животные)
static var kills := 0        # убито зомби
static var total_dmg := 0.0
static var broken := 0       # сломано предметов


static func is_leveled(id: String) -> bool:
	return LEVELED.has(id)


static func lvl(item: Variant) -> int:
	if item == null or not (item is Dictionary):
		return 1
	return clampi(int((item as Dictionary).get("lvl", 1)), 1, MAX_LVL)


static func dmg_mult(level: int) -> float:
	return pow(1.0 + DMG_STEP, level - 1)


## Прибавка к шансам сбить/оглушить: только у биты.
static func chance_bonus(id: String, level: int) -> float:
	return BAT_STEP * (level - 1) if String(LEVELED.get(id, {}).get("kind", "")) == "bat" else 0.0


static func kind_of(id: String) -> String:
	if id == "" or not LEVELED.has(id):
		return "fist" if id == "" or not ItemDB.info(id).has("dmg") else "melee"
	return String(LEVELED[id]["kind"])


static func max_dur(id: String, level: int) -> float:
	return float(LEVELED.get(id, {}).get("dur", 0.0)) * (1.0 + DUR_STEP * (level - 1))


static func dur(item: Variant) -> float:
	var id := String(item["id"])
	return float((item as Dictionary).get("dur", max_dur(id, lvl(item))))


static func dur_frac(item: Variant) -> float:
	var m := max_dur(String(item["id"]), lvl(item))
	return clampf(dur(item) / m, 0.0, 1.0) if m > 0.0 else 1.0


## Новый экземпляр уровня L (полная прочность).
static func extra(id: String, level: int = 1) -> Dictionary:
	return {"lvl": level, "dur": max_dur(id, level)} if LEVELED.has(id) else {}


## Износ на 1 удар/выстрел. true — предмет сломался (прочность кончилась).
static func wear(item: Variant, amount: float = 1.0) -> bool:
	if item == null or not LEVELED.has(String(item["id"])):
		return false
	var d := dur(item) - amount
	item["dur"] = maxf(d, 0.0)
	if d <= 0.0:
		broken += 1
		return true
	return false


static func roman(level: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(level, 0, 5)]


## Сколько всего урона нужно, чтобы открыть уровень L (2 → 1000, 3 → 3000, 4 → 6000, 5 → 10000).
static func need_for(level: int) -> float:
	var s := 0.0
	for k in range(1, level):
		s += XP_STEP * k
	return s


## Наибольший открытый для крафта уровень.
static func unlocked(id: String) -> int:
	var d := float(dealt.get(id, 0.0))
	var l := 1
	while l < MAX_LVL and d >= need_for(l + 1):
		l += 1
	return l


static func add_damage(id: String, v: float) -> void:
	if v <= 0.0:
		return
	total_dmg += v
	if LEVELED.has(id):
		dealt[id] = float(dealt.get(id, 0.0)) + v


static func reset() -> void:
	dealt = {}
	kills = 0
	total_dmg = 0.0
	broken = 0


static func to_dict() -> Dictionary:
	return {"dealt": dealt.duplicate(), "kills": kills, "total": total_dmg, "broken": broken}


static func from_dict(d: Dictionary) -> void:
	dealt = (d.get("dealt", {}) as Dictionary).duplicate()
	kills = int(d.get("kills", 0))
	total_dmg = float(d.get("total", 0.0))
	broken = int(d.get("broken", 0))
