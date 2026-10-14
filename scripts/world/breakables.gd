class_name Breakables
extends RefCounted
## Разрушаемый реквизит улиц и участков: столбы и фонари, покрышки, бочки, доски, пакеты, коробки, банки, кучи мусора,
## рюкзаки. Узел помечается Breakables.mark(узел, тип); удар — Player._hit_breakable. Сломанное не появляется снова
## (Vegetation.removed по месту), из пакетов/куч/рюкзаков при поломке выпадает их лут (если не обыскан).

## hp — прочность; dmg — класс урона предмета в руке (ItemDB dmg: block — твёрдое, bush — мягкое, tree — дерево);
## mat — звук и цвет осколков; drop — {предмет: [мин, макс]}; loot — при поломке выдать лут таблицы узла (мета loot).
const DEFS := {
	"pole_wood": {"name": "Столб", "hp": 240.0, "dmg": "tree", "mat": "wood", "drop": {"wood": [3, 6]}},
	"pole_metal": {"name": "Фонарный столб", "hp": 360.0, "dmg": "block", "mat": "metal", "drop": {"scrap_metal": [3, 6]}},
	"tire": {"name": "Покрышка", "hp": 70.0, "dmg": "block", "mat": "rubber", "drop": {"rubber": [2, 4]}},
	"barrel": {"name": "Бочка", "hp": 120.0, "dmg": "block", "mat": "metal", "drop": {"scrap_metal": [2, 4]}},
	"planks": {"name": "Доски", "hp": 60.0, "dmg": "tree", "mat": "wood", "drop": {"planks": [4, 8]}},
	"bag": {"name": "Пакет", "hp": 20.0, "dmg": "bush", "mat": "plastic", "drop": {"plastic": [1, 2]}, "loot": true},
	"box": {"name": "Коробка", "hp": 25.0, "dmg": "bush", "mat": "cardboard", "drop": {"paper": [2, 4]}},
	"cans": {"name": "Банки", "hp": 10.0, "dmg": "bush", "mat": "metal", "drop": {"scrap_metal": [1, 1]}},
	"pile": {"name": "Куча мусора", "hp": 45.0, "dmg": "bush", "mat": "plastic", "drop": {"plastic": [1, 3], "cloth": [0, 2]}, "loot": true},
	"backpack": {"name": "Рюкзак", "hp": 35.0, "dmg": "bush", "mat": "cloth", "drop": {"cloth": [2, 3]}, "loot": true},
}
const MAT_COLOR := {"wood": Color(0.5, 0.36, 0.22), "metal": Color(0.45, 0.45, 0.47), "rubber": Color(0.09, 0.09, 0.1),
	"plastic": Color(0.18, 0.18, 0.2), "cardboard": Color(0.6, 0.47, 0.3), "cloth": Color(0.35, 0.33, 0.28)}


## Радиус контактной тени под предметом, м (столбам — у основания).
const SHADOW_R := {"pole_wood": 0.35, "pole_metal": 0.35, "tire": 0.6, "barrel": 0.55, "planks": 0.8, "bag": 0.4,
	"box": 0.5, "cans": 0.3, "pile": 1.2, "backpack": 0.45}


static func mark(node: Node3D, type: String) -> void:
	node.set_meta("breakable", type)
	ContactShadow.add(node, float(SHADOW_R.get(type, 0.5)) * absf(node.scale.x), 0.6)


## Узел реквизита, которому принадлежит коллайдер (мета breakable на нём или выше по дереву), иначе null.
static func find(collider: Object) -> Node3D:
	var n := collider as Node
	for i in 5:
		if n == null:
			return null
		if n.has_meta("breakable") and n is Node3D:
			return n
		n = n.get_parent()
	return null


static func def(node: Node) -> Dictionary:
	return DEFS.get(String(node.get_meta("breakable", "")), {})


## Уже сломан на этом месте (не ставить при загрузке).
static func is_broken(pos: Vector3) -> bool:
	return Vegetation.removed.has(Vegetation.plant_key(pos.x, pos.z))


static func hit_sound(mat: String) -> String:
	match mat:
		"wood":
			return "hit_wood"
		"metal":
			return Sfx.pick("hit_metal", "hit_stone")
		"rubber":
			return "hit_dirt"
	return "rustle"


## Добыча по описанию: {предмет: число} (случайно в пределах).
static func roll_drop(d: Dictionary) -> Dictionary:
	var out := {}
	for id: String in d.get("drop", {}):
		var r: Array = d["drop"][id]
		var n := randi_range(int(r[0]), int(r[1]))
		if n > 0:
			out[id] = n
	return out
