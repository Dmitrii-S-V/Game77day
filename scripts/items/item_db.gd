class_name ItemDB
extends RefCounted
## Каталог предметов. desc — описание (панель описания в инвентаре), recycle — переработка (R в инвентаре):
## {предмет: сколько} за одну штуку.

const ITEMS := {
	# dmg — базовый урон удара по целям (tier 1): tree — деревья, ground — воксели ландшафта, rock/bush — камни и кусты, block — блоки построек
	"stone_axe": {"name": "Каменный топор", "stack": 1, "color": Color(0.55, 0.5, 0.45), "tool": true,
		"desc": "Камень, привязанный верёвкой к рукояти. Рубит деревья, ломает постройки, годится как оружие.",
		"dmg": {"tree": 39.0, "ground": 25.0, "rock": 20.0, "bush": 40.0, "block": 16.0, "zombie": 22.0},
		"rate": 1.0, "stam": 5.0,     # удар раз в 1 с
		"recycle": {"wood": 3}},
	# дубина: оружие ближнего боя — сильная по зомби, слабая как инструмент
	"wooden_club": {"name": "Деревянная дубина (бита)", "stack": 1, "color": Color(0.5, 0.38, 0.26), "tool": true,
		"desc": "Тяжёлая дубина. Сильна против зомби и чаще других сбивает с ног (33%), плохой инструмент. Крафт — 10 дерева.",
		"dmg": {"tree": 12.0, "ground": 6.0, "rock": 4.0, "bush": 30.0, "block": 20.0, "zombie": 45.0},
		"rate": 0.85, "stam": 4.5},    # удар раз в 0.85 с
	# пистолет: ЛКМ — выстрел, R — перезарядка; gun.dmg — урон пулей (в голову x2), mag — магазин, ammo — патроны
	"pistol": {"name": "Пистолет 9 мм", "stack": 1, "color": Color(0.2, 0.2, 0.22),
		"desc": "Пистолет на 12 патронов 9 мм. ЛКМ — выстрел, R — перезарядка. Выстрел слышно далеко.",
		"gun": {"dmg": 38.0, "block": 6.0, "mag": 12, "ammo": "ammo_9mm", "range": 120.0, "spread": 0.006, "noise": 70.0}},
	# рюкзак: крафтится, надевается сразу и открывает все ячейки инвентаря (логика в InventoryUI)
	"backpack": {"name": "Рюкзак", "stack": 1, "color": Color(0.55, 0.38, 0.2), "wear": "back",
		"desc": "Рюкзак из верёвок и тряпья. Надевается на спину (двойной клик/касание, Ctrl+ЛКМ или слот «Спина») и открывает все ячейки инвентаря."},
	# лекарства: пенициллин — с деревьев, поражённых лишаем (17% при рубке), в рюкзаках
	"penicillin": {"name": "Пенициллин", "stack": 10, "color": Color(0.85, 0.88, 0.8),
		"desc": "Антибиотик. Встречается в рюкзаках, иногда — на деревьях, поражённых лишаем."},
	"ammo_9mm": {"name": "Патроны 9 мм", "stack": 150, "color": Color(0.75, 0.6, 0.3),
		"desc": "Патроны для пистолета."},
	# еда: hunger/thirst/health — сколько восстанавливает одна штука; bleed — вызывает внутреннее кровотечение
	"canned_food": {"name": "Консервы", "stack": 10, "color": Color(0.7, 0.3, 0.15), "food": {"hunger": 35.0, "thirst": 4.0, "health": 3.0},
		"desc": "Банка тушёнки. Хорошо утоляет голод."},
	"berries": {"name": "Ягоды", "stack": 30, "color": Color(0.45, 0.08, 0.15), "food": {"hunger": 7.0, "thirst": 3.0},
		"desc": "Лесные ягоды с кустов. Немного еды и воды."},
	"candy_bar": {"name": "Шоколадный батончик", "stack": 10, "color": Color(0.55, 0.3, 0.15), "food": {"hunger": 16.0, "thirst": -2.0, "health": 1.0},
		"desc": "Сладкий батончик. Сытно, но хочется пить."},
	"broken_glass": {"name": "Разбитое стекло", "stack": 20, "color": Color(0.7, 0.82, 0.8), "food": {"bleed": true},
		"desc": "Осколки бутылки. Есть можно… но вызывает внутреннее кровотечение: −10 здоровья в секунду, пока не умрёшь."},
	"water_bottle": {"name": "Бутылка с водой", "stack": 1, "color": Color(0.35, 0.62, 0.85), "bottle": true,
		"desc": "Стеклянная бутылка с водой. ПКМ — пить.", "recycle": {"broken_glass": 1}},
	"glass_bottle": {"name": "Стеклянная бутылка", "stack": 1, "color": Color(0.7, 0.85, 0.8), "bottle": true,
		"desc": "Пустая бутылка. Можно наполнить водой или бросить.", "recycle": {"broken_glass": 1}},
	"wood": {"name": "Дерево", "stack": 99, "color": Color(0.55, 0.38, 0.22),
		"desc": "Поленья и обломки дерева."},
	"planks": {"name": "Доски", "stack": 250, "color": Color(0.68, 0.5, 0.3),
		"desc": "Старые доски — с деревьев и разобранных построек."},
	"stone": {"name": "Камень", "stack": 500, "color": Color(0.55, 0.55, 0.55),
		"desc": "Небольшой камень. Подбирается с земли (E) или откалывается от валунов."},
	"fiber": {"name": "Растительное волокно", "stack": 99, "color": Color(0.45, 0.6, 0.25),
		"desc": "Волокно из кустов."},
	"grass": {"name": "Трава", "stack": 99, "color": Color(0.42, 0.58, 0.22),      # срезанная трава — материал для крафта
		"desc": "Срезанная трава (удар по траве). Из неё плетут верёвку."},
	"grass_rope": {"name": "Верёвка из травы", "stack": 20, "color": Color(0.5, 0.52, 0.3),
		"desc": "Грубая верёвка, сплетённая из травы. Для связки инструментов."},
	"rubber": {"name": "Резина", "stack": 50, "color": Color(0.12, 0.12, 0.13),     # из покрышек
		"desc": "Куски резины с разбитых покрышек."},
	# лут из мусора
	"cloth": {"name": "Тряпьё", "stack": 100, "color": Color(0.62, 0.55, 0.45),
		"desc": "Обрывки ткани."},
	"plastic": {"name": "Пластик", "stack": 100, "color": Color(0.3, 0.45, 0.6),
		"desc": "Мятые бутылки и пакеты."},
	"paper": {"name": "Бумага", "stack": 100, "color": Color(0.85, 0.82, 0.72),
		"desc": "Листы бумаги, картон."},
	"scrap_metal": {"name": "Металлолом", "stack": 100, "color": Color(0.45, 0.42, 0.4),
		"desc": "Куски металла — со столбов, бочек и банок."},
	"duct_tape": {"name": "Изолента", "stack": 20, "color": Color(0.5, 0.52, 0.55),
		"desc": "Моток изоленты."},
	"nails": {"name": "Гвозди", "stack": 200, "color": Color(0.6, 0.6, 0.62),
		"desc": "Гвозди."},
}


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "stack": 1, "color": Color.GRAY})


static func item_name(id: String) -> String:
	return String(info(id)["name"])


static func stack_size(id: String) -> int:
	return int(info(id)["stack"])


## Урон предмета в руке по классу цели (без инструмента — слабый удар кулаком).
const HAND_DMG := {"tree": 8.0, "ground": 6.0, "rock": 2.0, "bush": 25.0, "block": 5.0, "zombie": 9.0}
## Удар рукой: раз в 0.7 с, 2.5 выносливости. У оружия — "rate"/"stam" в описании предмета.
const HAND_ATTACK := {"rate": 0.7, "stam": 2.5}


## Темп удара (с между ударами) и расход выносливости для предмета в руке.
static func attack(id: String) -> Dictionary:
	var it := info(id)
	if id == "" or not it.has("dmg"):
		return HAND_ATTACK
	return {"rate": float(it.get("rate", 0.8)), "stam": float(it.get("stam", 8.0))}


static func damage(id: String, target: String) -> float:
	var d: Dictionary = info(id).get("dmg", HAND_DMG)
	return float(d.get(target, HAND_DMG.get(target, 5.0)))


## Строки характеристик для панели описания (урон, еда, патроны).
static func stats_lines(id: String) -> Array:
	var it := info(id)
	var out: Array = []
	if it.has("dmg"):
		var d: Dictionary = it["dmg"]
		out.append("Урон: зомби %d · дерево %d · постройки %d" % [int(d.get("zombie", 0)), int(d.get("tree", 0)), int(d.get("block", 0))])
		var a := attack(id)
		out.append("Удар раз в %.2f с · выносливость −%s" % [float(a["rate"]), String.num(float(a["stam"]), 1)])
	if it.has("gun"):
		out.append("Урон пулей %d (в голову ×2) · магазин %d" % [int(it["gun"]["dmg"]), int(it["gun"]["mag"])])
	if it.has("food"):
		var f: Dictionary = it["food"]
		var parts: Array = []
		for k in [["hunger", "сытость"], ["thirst", "вода"], ["health", "здоровье"]]:
			if f.has(k[0]):
				parts.append("%s %+d" % [k[1], int(f[k[0]])])
		if f.get("bleed", false):
			parts.append("кровотечение!")
		out.append("Еда: " + ", ".join(parts))
	if it.has("recycle"):
		var r: Array = []
		for k: String in it["recycle"]:
			r.append("%s ×%d" % [item_name(k), int(it["recycle"][k])])
		out.append("R — переработать: " + ", ".join(r))
	out.append("В стопке до %d" % int(it["stack"]))
	return out
