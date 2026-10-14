class_name TestHouse
extends RefCounted
## Тестовый дом для системы блоков (ячейка 1 м): собирается теми же вызовами BlockGrid, что и редактор, затем
## сохраняется префабом "test_house" (tools/build_test_house.gd). Состав: каркас, доски 4 степеней гнилости,
## 4 вида бетона, двери (рабочая и заколоченная), окна трёх видов, паутина, ковёр, свеча на столе, люстра.
## Слои: y=0 фундамент (под землёй), y=1 пол (на уровне земли после sink=1), y=2..4 стены, y=5 потолок, y=6 крыша.

const NX := 12
const NZ := 10
const NY := 7
# tier'ы блока "wall" (см. blocks.json)
const T_FRAME := 0
const T_FRESH := 1
const T_WORN := 2
const T_ROTTEN := 3
const T_DYING := 4
const T_CON_SMOOTH := 5
const T_CON_CRACKED := 6
const T_CON_REINF := 7
const T_CON_DIRTY := 8


static func wall(g: BlockGrid, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, tier: int, variant: int = 0) -> void:
	var id := BlockRegistry.id_by_key("wall")
	for z in range(z0, z1):
		for y in range(y0, y1):
			for x in range(x0, x1):
				g.place_block(Vector3i(x, y, z), id, BlockRegistry.make_meta(0, tier, variant))


static func put(g: BlockGrid, key: String, a: Vector3i, rot: int = 0, tier: int = 0, variant: int = 0) -> bool:
	var id := BlockRegistry.id_by_key(key)
	var m := BlockRegistry.make_meta(rot, tier, variant)
	if not g.can_place(a, id, rot):
		return false
	g.place_block(a, id, m)
	return true


static func build() -> BlockGrid:
	var g := BlockGrid.new(NX, NY, NZ)
	g.ground_cells = 1
	# фундамент (армированный бетон) и пол
	wall(g, 0, 0, 0, NX, 1, NZ, T_CON_REINF)
	wall(g, 0, 1, 0, NX, 2, NZ, T_WORN)
	# стены y = 2..4: передняя свежие доски, задняя потрёпанные, левая гнилые, правая почти сгнившие
	wall(g, 0, 2, NZ - 1, NX, 5, NZ, T_FRESH)
	wall(g, 0, 2, 0, NX, 5, 1, T_WORN)
	wall(g, 0, 2, 1, 1, 5, NZ - 1, T_ROTTEN)
	wall(g, NX - 1, 2, 1, NX, 5, NZ - 1, T_DYING)
	# цоколь из гладкого бетона по фасаду и армированная колонна в углу
	wall(g, 0, 2, NZ - 1, NX, 3, NZ, T_CON_SMOOTH)
	wall(g, NX - 1, 2, NZ - 1, NX, 5, NZ, T_CON_REINF)
	# внутренняя перегородка: потрескавшийся и грязный бетон
	wall(g, 6, 2, 1, 7, 5, 5, T_CON_CRACKED)
	wall(g, 6, 2, 5, 7, 5, NZ - 1, T_CON_DIRTY)
	# недостроенный участок правой стены остался каркасом
	wall(g, NX - 1, 2, 2, NX, 5, 5, T_FRAME)
	# потолок и крыша
	wall(g, 0, 5, 0, NX, 6, NZ, T_CON_SMOOTH)
	wall(g, 0, 6, 0, NX, 7, NZ, T_CON_CRACKED)
	# двери: парадная (рабочая), заколоченная сзади, внутренняя в перегородке (поворот 1: полотно вдоль Z)
	_clear(g, Vector3i(4, 2, NZ - 1), Vector3i(1, 2, 1))
	put(g, "door_wood", Vector3i(4, 2, NZ - 1))
	_clear(g, Vector3i(2, 2, 0), Vector3i(1, 2, 1))
	put(g, "door_boarded", Vector3i(2, 2, 0))
	_clear(g, Vector3i(6, 2, 5), Vector3i(1, 2, 1))
	put(g, "door_wood", Vector3i(6, 2, 5), 1)
	# окна: целое и разбитое на фасаде, заколоченное на левой стене, целое сзади
	_clear(g, Vector3i(2, 3, NZ - 1), Vector3i(1, 1, 1))
	put(g, "window_ok", Vector3i(2, 3, NZ - 1))
	_clear(g, Vector3i(8, 3, NZ - 1), Vector3i(1, 1, 1))
	put(g, "window_broken", Vector3i(8, 3, NZ - 1))
	_clear(g, Vector3i(0, 3, 5), Vector3i(1, 1, 1))
	put(g, "window_boarded", Vector3i(0, 3, 5), 1)
	_clear(g, Vector3i(8, 3, 0), Vector3i(1, 1, 1))
	put(g, "window_ok", Vector3i(8, 3, 0))
	# внутри: паутина в углах, ковёр, стол, свеча, люстра
	put(g, "web", Vector3i(1, 4, 1))
	put(g, "web", Vector3i(NX - 2, 4, NZ - 2))
	for z in range(4, 7):
		for x in range(2, 5):
			put(g, "carpet", Vector3i(x, 2, z), 0, 0, 0)
	wall(g, 8, 2, 3, 10, 3, 4, T_FRESH, 1)    # стол — блок из свежих досок
	put(g, "candle", Vector3i(8, 3, 3))
	put(g, "chandelier", Vector3i(3, 4, 5))
	return g


static func _clear(g: BlockGrid, a: Vector3i, size: Vector3i) -> void:
	for dz in size.z:
		for dy in size.y:
			for dx in size.x:
				g.remove_block(a + Vector3i(dx, dy, dz))
