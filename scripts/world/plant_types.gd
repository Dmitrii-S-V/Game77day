class_name PlantTypes
extends RefCounted
## Что можно сажать/ставить в редакторе структур (вкладка «Растения», хранится в префабе «plants»):
## любые деревья леса (в т.ч. с лишаем), кусты, валуны, кустики травы, камешки, скамейки.
## Запись в BlockGrid.plants: {type, x, z (м от угла сетки), rot, scale, hue}.

const TYPES := {
	"oak_0": {"name": "Дуб 1", "kind": "oak", "res": "wood", "mesh": "oak_0"},
	"oak_1": {"name": "Дуб 2", "kind": "oak", "res": "wood", "mesh": "oak_1"},
	"oak_2": {"name": "Дуб 3", "kind": "oak", "res": "wood", "mesh": "oak_2"},
	"oak_lichen": {"name": "Дуб с лишаем", "kind": "oak", "res": "wood", "mesh": "oak_1", "lichen": 1},
	"oak_dry_0": {"name": "Дуб сухой 1", "kind": "oak", "res": "wood", "mesh": "oak_dry_0"},
	"oak_dry_1": {"name": "Дуб сухой 2", "kind": "oak", "res": "wood", "mesh": "oak_dry_1"},
	"pine_0": {"name": "Сосна 1", "kind": "pine", "res": "wood", "mesh": "pine_0"},
	"pine_1": {"name": "Сосна 2", "kind": "pine", "res": "wood", "mesh": "pine_1"},
	"pine_2": {"name": "Сосна 3", "kind": "pine", "res": "wood", "mesh": "pine_2"},
	"dead_tree": {"name": "Мёртвое дерево", "kind": "dead_tree", "res": "wood", "mesh": "dead_tree_0"},
	"dead_lichen": {"name": "Мёртвое дерево с лишаем", "kind": "dead_tree", "res": "wood", "mesh": "dead_tree_0", "lichen": 1},
	"bush_0": {"name": "Куст 1", "kind": "bush", "res": "fiber", "mesh": "bush_0"},
	"bush_1": {"name": "Куст 2", "kind": "bush", "res": "fiber", "mesh": "bush_1"},
	"bush_2": {"name": "Куст 3", "kind": "bush", "res": "fiber", "mesh": "bush_2"},
	"rock_0": {"name": "Валун 1", "kind": "rock", "res": "stone", "mesh": "rock_0"},
	"rock_1": {"name": "Валун 2", "kind": "rock", "res": "stone", "mesh": "rock_1"},
	"grass": {"name": "Трава (кустик)", "kind": "grass_tuft"},
	"pebble": {"name": "Камешек (подобрать)", "kind": "pebble"},
	"bench": {"name": "Скамейка", "kind": "bench"},
}
const ORDER := ["oak_0", "oak_1", "oak_2", "oak_lichen", "oak_dry_0", "oak_dry_1", "pine_0", "pine_1", "pine_2", "dead_tree",
	"dead_lichen", "bush_0", "bush_1", "bush_2", "rock_0", "rock_1", "grass", "pebble", "bench"]


## Узел растения/предмета в системе родителя (pos — локальная позиция основания). global_pos — для лишая по месту.
static func make(p: Dictionary, pos: Vector3, global_pos: Vector3) -> Node3D:
	var t: Dictionary = TYPES.get(String(p["type"]), {})
	if t.is_empty():
		return null
	var rot := float(p.get("rot", 0.0))
	var sc := float(p.get("scale", 1.0))
	var node: Node3D = null
	match String(t["kind"]):
		"bench":
			node = PropFactory.bench(float(p.get("hue", 0.45)))
		"grass_tuft":
			node = PropFactory.tuft(absi(hash(Vector2i(roundi(global_pos.x * 4.0), roundi(global_pos.z * 4.0)))), 5)
		"pebble":
			node = PropFactory.pebble(0.1 * sc)
		_:
			if Vegetation.shared == null:
				return null
			var lichen := int(t.get("lichen", -1))
			if lichen < 0:
				lichen = 1 if absi(hash([Vegetation.plant_key(global_pos.x, global_pos.z), 911])) % 100 < Vegetation.LICHEN_P else 0
			node = Vegetation.shared.make_plant(String(t["mesh"]), String(t["kind"]), String(t["res"]), Vector3.ZERO, 0.0, sc, lichen)
			if node == null:
				return null
			pos.y -= 0.12
	node.position = pos
	node.rotation.y = rot
	if String(t["kind"]) in ["bench", "pebble", "grass_tuft"]:
		node.scale = Vector3.ONE if String(t["kind"]) != "grass_tuft" else Vector3.ONE * sc
	return node
