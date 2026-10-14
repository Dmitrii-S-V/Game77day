class_name BlockDefs
extends RefCounted
## Материалы блоков построек: прочность, цвет (для обломков), множители урона по инструментам.

const AIR := 0
const WOOD := 1
const BRICK := 2
const CONCRETE := 3
const METAL := 4
const GLASS := 5
const SHINGLE := 6
const WOODFLOOR := 7
const TILE := 8
const PLASTER := 9
const LOG := 10
const STONE := 11
const FURNITURE := 12
const FABRIC := 13
const BARN := 14
const ROOFMETAL := 15
const SHELF := 16
const HAY := 17
const CRATE := 18

const HP := [0, 50, 120, 220, 90, 6, 60, 60, 80, 60, 90, 200, 30, 20, 60, 70, 40, 20, 25]
const COLORS := [
	Color(0, 0, 0), Color(0.55, 0.42, 0.28), Color(0.58, 0.28, 0.20), Color(0.55, 0.55, 0.53), Color(0.50, 0.55, 0.58),
	Color(0.55, 0.75, 0.85), Color(0.28, 0.22, 0.20), Color(0.50, 0.36, 0.22), Color(0.75, 0.75, 0.72), Color(0.80, 0.76, 0.68),
	Color(0.42, 0.28, 0.17), Color(0.45, 0.45, 0.43), Color(0.45, 0.30, 0.18), Color(0.60, 0.20, 0.20), Color(0.50, 0.13, 0.10),
	Color(0.40, 0.42, 0.45), Color(0.35, 0.40, 0.45), Color(0.75, 0.65, 0.30), Color(0.50, 0.38, 0.22),
]
# множитель урона топора по материалу
const AXE := [0.0, 1.0, 0.55, 0.28, 0.35, 10.0, 0.8, 1.0, 0.6, 0.9, 1.0, 0.3, 1.2, 3.0, 1.0, 0.35, 0.9, 3.0, 1.2]


static func hp(id: int) -> int:
	return HP[id]


static func color(id: int) -> Color:
	return COLORS[id]


static func is_transparent(id: int) -> bool:
	return id == GLASS
