class_name BlockGen
extends RefCounted
## Здания из блоков с интерьерами. Ячейка 1 м (= воксель ландшафта). Ось X — ширина, Z — глубина, фасад на +Z.
## По Y: плита пола нижнего этажа лежит на уровне земли (верх плиты = земля, ground_cells = 1),
## этажи по FH = 4 ячейки (плита + 3 м стены), у стен 1 ячейка отступа под свесы крыши.

const M := 1
const FH := 4   # шаг этажа по Y: плита + 3 ячейки стены

var g: BlockGrid
var rng := RandomNumberGenerator.new()


static func generate(btype: String, w: float, d: float, seed_v: int) -> BlockGrid:
	var gen := BlockGen.new()
	gen.rng.seed = seed_v
	var nx := maxi(4, int(round(w / BlockGrid.B)))
	var nz := maxi(4, int(round(d / BlockGrid.B)))
	match btype:
		"house", "farmhouse":
			gen._house(maxi(nx, 9), maxi(nz, 9), btype == "farmhouse")
		"shop":
			gen._shop(maxi(nx, 11), maxi(nz, 10), false)
		"gas_store":
			gen._shop(maxi(nx, 10), maxi(nz, 8), true)
		"office":
			gen._tower(maxi(nx, 10), maxi(nz, 10), true)
		"apartment":
			gen._tower(maxi(nx, 10), maxi(nz, 10), false)
		"warehouse":
			gen._warehouse(maxi(nx, 11), maxi(nz, 10))
		"barn":
			gen._barn(maxi(nx, 12), maxi(nz, 14))
		"silo":
			gen._silo(maxi(nx / 2, 3))
		"shed":
			gen._shed(maxi(nx, 4), maxi(nz, 4))
		"cabin":
			gen._cabin(maxi(nx, 7), maxi(nz, 6))
		"gas_canopy":
			gen._canopy(maxi(nx, 10), maxi(nz, 5))
		_:
			gen.g = BlockGrid.new(nx, 6, nz)
			gen.g.fill(0, 0, 0, nx, 4, nz, BlockDefs.CONCRETE)
	gen.g.tint = gen.rng.randi() % 4
	return gen.g


# --- помощники ----------------------------------------------------------------------

func _new(nx: int, nz: int, levels: int, extra_y: int, porch: int = 0) -> void:
	g = BlockGrid.new(nx + 2 * M, 1 + levels * FH + extra_y, nz + 2 * M + porch)


func _y(level: int) -> int:
	return level * FH


## Плиты перекрытий всех уровней и стены периметра (нижняя плита — на уровне земли).
func _shell(x0: int, z0: int, x1: int, z1: int, levels: int, wall: int, floor_id: int, top_id: int) -> void:
	for lv in levels:
		var y := _y(lv)
		g.fill(x0, y, z0, x1, y + 1, z1, floor_id)
		_ring(x0, z0, x1, z1, y + 1, y + FH, wall)
	g.fill(x0, _y(levels), z0, x1, _y(levels) + 1, z1, top_id)


func _ring(x0: int, z0: int, x1: int, z1: int, ya: int, yb: int, id: int) -> void:
	g.fill(x0, ya, z0, x1, yb, z0 + 1, id)
	g.fill(x0, ya, z1 - 1, x1, yb, z1, id)
	g.fill(x0, ya, z0, x0 + 1, yb, z1, id)
	g.fill(x1 - 1, ya, z0, x1, yb, z1, id)


func _carve(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	g.fill(x0, y0, z0, x1, y1, z1, 0)


## Окна: стекло на стене по оси Z (front) или X (side), по умолчанию 1x1 м.
func _win_z(x: int, z: int, y: int, w: int = 1, h: int = 1) -> void:
	g.fill(x, y, z, x + w, y + h, z + 1, BlockDefs.GLASS)


func _win_x(x: int, z: int, y: int, w: int = 1, h: int = 1) -> void:
	g.fill(x, y, z, x + 1, y + h, z + w, BlockDefs.GLASS)


func _windows_ring(x0: int, z0: int, x1: int, z1: int, level: int, step: int, avoid_x: Array, avoid_z: Array, w: int = 1) -> void:
	var y := _y(level) + 2
	var x := x0 + 2
	while x + w <= x1 - 2:
		var ok := true
		for ax: int in avoid_x:
			if absi(x - ax) < w + 1:
				ok = false
		if ok:
			_win_z(x, z0, y, w)
			_win_z(x, z1 - 1, y, w)
		x += step
	var z := z0 + 2
	while z + w <= z1 - 2:
		var ok2 := true
		for az: int in avoid_z:
			if absi(z - az) < w + 1:
				ok2 = false
		if ok2:
			_win_x(x0, z, y, w)
			_win_x(x1 - 1, z, y, w)
		z += step


## Проём двери: ширина w ячеек, высота h (по умолчанию 1x2 м).
func _door_z(x: int, z: int, level: int, w: int = 1, h: int = 2) -> void:
	_carve(x, _y(level) + 1, z, x + w, _y(level) + 1 + h, z + 1)


func _door_x(x: int, z: int, level: int, w: int = 1, h: int = 2) -> void:
	_carve(x, _y(level) + 1, z, x + 1, _y(level) + 1 + h, z + w)


## Двускатная крыша с коньком вдоль X. y0 — первая строка крыши. Скат: подъём 1 на 2.
func _gable(x0: int, z0: int, x1: int, z1: int, y0: int, roof: int, gable_wall: int) -> void:
	var k := 0
	var zl := z0 - 1
	var zr := z1 + 1
	while zl < zr:
		var y := y0 + k
		var zl2 := mini(zl + 2, zr)
		var zr2 := maxi(zr - 2, zl)
		g.fill(x0 - 1, y, zl, x1 + 1, y + 1, zl2, roof)
		g.fill(x0 - 1, y, zr2, x1 + 1, y + 1, zr, roof)
		# фронтон между скатами
		if zl2 < zr2:
			g.fill(x0, y, zl2, x0 + 1, y + 1, zr2, gable_wall)
			g.fill(x1 - 1, y, zl2, x1, y + 1, zr2, gable_wall)
		k += 1
		zl += 2
		zr -= 2


func _box(x: int, y: int, z: int, sx: int, sy: int, sz: int, id: int) -> void:
	g.fill(x, y, z, x + sx, y + sy, z + sz, id)


## Унитаз (модель) у западной стены комнаты: x_in — первая клетка внутри, za..zb — диапазон Z (ячеек).
func _toilet(x_in: int, za: int, zb: int) -> void:
	var zc := (za + zb) * 0.5 * BlockGrid.B
	g.props.append({"name": "toilet", "pos": Vector3(x_in * BlockGrid.B + 0.4, (_y(0) + 1) * BlockGrid.B, zc), "yaw": 0.0,
		"support": Vector3i(x_in, _y(0), (za + zb) / 2)})


## Лестница: ступени вдоль +Z высотой по 1 ячейке (прыжком берётся), ширина w; level — с этажа на следующий.
func _stairs(x: int, z: int, level: int, w: int) -> void:
	var y0 := _y(level)
	_carve(x, _y(level + 1), z + 1, x + w, _y(level + 1) + 1, z + 4)   # проём в перекрытии
	for s in 4:
		_box(x, y0 + 1, z + s, w, 1 + s, 1, BlockDefs.WOODFLOOR)


# --- дом ---------------------------------------------------------------------------

func _house(nx: int, nz: int, farm: bool) -> void:
	var levels := 2 if (nx >= 11 and nz >= 13 and rng.randf() < 0.4 and not farm) else 1
	_new(nx, nz, levels, nz / 4 + 6, 2)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	var wall := BlockDefs.WOOD if rng.randf() < 0.55 else BlockDefs.BRICK
	_shell(x0, z0, x1, z1, levels, wall, BlockDefs.WOODFLOOR, BlockDefs.PLASTER)
	var xm := x0 + nx / 2
	var zs := z0 + int(nz * 0.5)
	var door_x := x0 + nx / 2 + 2
	for lv in levels:
		var y := _y(lv)
		# перегородки: центральная вертикальная (сзади) и горизонтальная поперёк
		_box(xm, y + 1, z0 + 1, 1, FH - 1, zs - z0 - 1, BlockDefs.PLASTER)
		_box(x0 + 1, y + 1, zs, nx - 2, FH - 1, 1, BlockDefs.PLASTER)
		_door_x(xm, z0 + 3, lv)
		_door_z(x0 + 3, zs, lv)
		_door_z(xm + 2, zs, lv)
		# кухня: плитка
		g.fill(xm + 1, y, z0 + 1, x1 - 1, y + 1, zs, BlockDefs.TILE)
		_windows_ring(x0, z0, x1, z1, lv, 4, [xm, door_x], [zs])
	_door_z(door_x, z1 - 1, 0)
	_door_z(x0 + 2, z0, 0)
	# мебель первого этажа
	var yf := _y(0) + 1
	_box(xm + 2, yf, z0 + 1, maxi(nx / 2 - 3, 1), 1, 1, BlockDefs.FURNITURE)    # кухонный гарнитур вдоль задней стены
	_box(x1 - 3, yf, z0 + 2, 1, 1, 1, BlockDefs.METAL)                           # плита
	_box(x0 + 2, yf, z0 + 2, 2, 1, 2, BlockDefs.FABRIC)                          # кровать
	_box(x0 + 2, yf + 1, z0 + 1, 2, 1, 1, BlockDefs.FURNITURE)                   # изголовье
	_box(xm - 2, yf, z0 + 1, 1, 2, 1, BlockDefs.FURNITURE)                       # шкаф
	var cx := x0 + nx / 2 - 2
	var cz := zs + (z1 - zs) / 2 - 1
	_box(cx, yf, cz, 2, 1, 2, BlockDefs.FURNITURE)                               # стол
	_box(x1 - 3, yf, zs + 2, 1, 2, 3, BlockDefs.SHELF)                           # стеллаж с книгами
	if levels == 1 and nx >= 11 and nz >= 11:
		# туалет в переднем левом углу: перегородки, плиточный пол, унитаз
		var wzs := z1 - 5
		_box(x0 + 3, yf, wzs, 1, FH - 1, z1 - 1 - wzs, BlockDefs.PLASTER)
		_box(x0 + 1, yf, wzs, 2, FH - 1, 1, BlockDefs.PLASTER)
		_box(x0 + 1, yf, wzs, 1, 1, 1, BlockDefs.PLASTER)
		_carve(x0 + 1, yf, wzs, x0 + 2, yf + 2, wzs + 1)
		g.fill(x0 + 1, _y(0), wzs + 1, x0 + 3, _y(0) + 1, z1 - 1, BlockDefs.TILE)
		_toilet(x0 + 1, wzs + 1, z1 - 1)
	# лестница на второй этаж
	if levels > 1:
		_stairs(x0 + 2, zs + 2, 0, 2)
	# крыша
	var ytop := _y(levels)
	_gable(x0, z0, x1, z1, ytop + 1, BlockDefs.SHINGLE, wall)
	if not farm:
		_box(x0 + 2, ytop + 1, z0 + 2, 1, 4, 1, BlockDefs.BRICK)               # дымоход
	# крыльцо
	_box(door_x - 1, 0, z1, 3, 1, 2, BlockDefs.WOODFLOOR)
	_box(door_x - 1, 1, z1 + 1, 1, 3, 1, BlockDefs.WOOD)
	_box(door_x + 1, 1, z1 + 1, 1, 3, 1, BlockDefs.WOOD)


# --- магазин / АЗС --------------------------------------------------------------

func _shop(nx: int, nz: int, gas: bool) -> void:
	_new(nx, nz, 1, 3)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	var wall := BlockDefs.BRICK if not gas else BlockDefs.CONCRETE
	_shell(x0, z0, x1, z1, 1, wall, BlockDefs.TILE, BlockDefs.CONCRETE)
	var y := _y(0) + 1
	# витрина и дверь на фасаде
	g.fill(x0 + 2, y, z1 - 1, x1 - 5, y + 2, z1, BlockDefs.GLASS)
	_door_z(x1 - 4, z1 - 1, 0, 2)
	_win_x(x1 - 1, z0 + 12 if nz > 16 else z0 + nz - 4, y + 1, 2, 1)
	_win_x(x0, z0 + nz / 2, y + 1, 2, 1)
	# стойка и стеллажи
	_box(x0 + 2, y, z1 - 5, 6, 1, 1, BlockDefs.FURNITURE)
	_box(x0 + 2, y, z1 - 5, 1, 1, 4, BlockDefs.FURNITURE)
	for sx in [x0 + 3, x0 + 6]:
		if sx < x1 - 6:
			_box(sx, y, z0 + 1, 1, 2, maxi(nz / 2 - 2, 1), BlockDefs.SHELF)
	if gas:
		_box(x1 - 3, y, z0 + 6, 1, 2, clampi(nz - 9, 1, 3), BlockDefs.METAL)   # холодильники у правой стены
	# подсобка = туалет: угол с перегородками, плиткой и унитазом
	_box(x1 - 5, y, z0 + 1, 1, FH - 1, 5, BlockDefs.PLASTER)
	_box(x1 - 5, y, z0 + 5, 4, FH - 1, 1, BlockDefs.PLASTER)
	_door_x(x1 - 5, z0 + 2, 0)
	g.fill(x1 - 4, _y(0), z0 + 1, x1 - 1, _y(0) + 1, z0 + 5, BlockDefs.TILE)
	_toilet(x1 - 4, z0 + 3, z0 + 4)
	# крыша: плоская с парапетом
	var yr := _y(1)
	g.fill(x0 - 1, yr, z0 - 1, x1 + 1, yr + 1, z1 + 1, BlockDefs.CONCRETE)
	_ring(x0 - 1, z0 - 1, x1 + 1, z1 + 1, yr + 1, yr + 2, wall)


# --- многоэтажка / офис --------------------------------------------------------------

func _tower(nx: int, nz: int, office: bool) -> void:
	var levels := rng.randi_range(5, 8) if office else rng.randi_range(4, 6)
	nx = mini(nx, 14)
	nz = mini(nz, 14)
	_new(nx, nz, levels, 4)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	var wall := BlockDefs.CONCRETE
	_shell(x0, z0, x1, z1, levels, wall, BlockDefs.CONCRETE, BlockDefs.CONCRETE)
	var xa := x0 + 4
	var xb := x1 - 5
	for lv in levels:
		var y := _y(lv)
		# окна лентой по периметру
		var x := x0 + 2
		while x + 2 <= x1 - 2:
			_win_z(x, z0, y + 2, 2, 2)
			_win_z(x, z1 - 1, y + 2, 2, 2)
			x += 3
		var z := z0 + 2
		while z + 2 <= z1 - 2:
			_win_x(x0, z, y + 2, 2, 2)
			_win_x(x1 - 1, z, y + 2, 2, 2)
			z += 3
		# коридор по центру: перегородки слева и справа с дверями
		_box(xa, y + 1, z0 + 1, 1, FH - 1, nz - 2, BlockDefs.PLASTER)
		_box(xb, y + 1, z0 + 1, 1, FH - 1, nz - 2, BlockDefs.PLASTER)
		var zz := z0 + 7
		while zz < z1 - 3:
			_box(x0 + 1, y + 1, zz, xa - x0 - 1, FH - 1, 1, BlockDefs.PLASTER)
			_box(xb + 1, y + 1, zz, x1 - xb - 2, FH - 1, 1, BlockDefs.PLASTER)
			_door_x(xa, zz + 1, lv)
			_door_x(xb, zz + 1, lv)
			# мебель в комнатах
			if office:
				_box(x0 + 1, y + 1, zz - 3, 2, 1, 1, BlockDefs.FURNITURE)
				_box(xb + 1, y + 1, zz - 3, 2, 1, 1, BlockDefs.FURNITURE)
			else:
				_box(x0 + 1, y + 1, zz - 3, 1, 1, 2, BlockDefs.FABRIC)
				_box(xb + 2, y + 1, zz - 2, 2, 1, 1, BlockDefs.FURNITURE)
			zz += 4
	# вход
	_door_z(x0 + nx / 2 - 1, z1 - 1, 0, 2, 3)
	g.fill(x0 + 2, _y(0) + 2, z1 - 1, x0 + nx / 2 - 2, _y(0) + 4, z1, BlockDefs.GLASS)
	# лестница в углу, один пролёт на этаж
	for lv in levels - 1:
		_stairs(x0 + 1, z0 + 2, lv, 2)
	# крыша
	var yr := _y(levels)
	_ring(x0 - 1, z0 - 1, x1 + 1, z1 + 1, yr + 1, yr + 2, wall)
	g.fill(x0 - 1, yr, z0 - 1, x1 + 1, yr + 1, z1 + 1, BlockDefs.CONCRETE)
	_box(x1 - 6, yr + 1, z0 + 2, 4, 1, 4, BlockDefs.METAL)
	_box(x0 + 2, yr + 1, z0 + 2, 2, 2, 2, BlockDefs.CONCRETE)


# --- склад -----------------------------------------------------------------------------

func _warehouse(nx: int, nz: int) -> void:
	_new(nx, nz, 1, 8)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	_shell(x0, z0, x1, z1, 1, BlockDefs.METAL, BlockDefs.CONCRETE, BlockDefs.CONCRETE)
	# потолка нет: стены выше этажа ещё на 2 ряда
	var yt := _y(1)
	g.fill(x0, yt, z0, x1, yt + 1, z1, 0)
	_ring(x0, z0, x1, z1, yt, yt + 2, BlockDefs.METAL)
	_carve(x0 + 2, _y(0) + 1, z1 - 1, x0 + 6, _y(0) + 5, z1)
	for x in range(x0 + 8, x1 - 2, 3):
		_win_z(x, z1 - 1, _y(0) + 4, 2, 1)
	for z in range(z0 + 2, z1 - 2, 4):
		_win_x(x0, z, _y(0) + 4, 2, 1)
		_win_x(x1 - 1, z, _y(0) + 4, 2, 1)
	# стеллажи рядами: стойки и полки
	var y := _y(0) + 1
	for x in range(x0 + 8, x1 - 2, 3):
		for z in [z0 + 2, z0 + 2 + 6]:
			_shelf_unit(x, y, z, 1, 5, 3)
	# ящики
	for i in 9:
		var cx := rng.randi_range(x0 + 2, x1 - 4)
		var cz := rng.randi_range(z0 + 2, z1 - 4)
		var h := rng.randi_range(1, 2)
		if cx > x0 + 6 and cz > z1 - 5:
			continue
		_box(cx, y, cz, 1, h, 1, BlockDefs.CRATE)
	_gable(x0, z0, x1, z1, yt + 2, BlockDefs.ROOFMETAL, BlockDefs.METAL)


func _shelf_unit(x: int, y: int, z: int, sx: int, sz: int, h: int) -> void:
	for lvl in range(0, h, 2):
		_box(x, y + lvl, z, sx, 1, sz, BlockDefs.SHELF)
	for pz in [z, z + sz - 1]:
		_box(x, y, pz, sx, h, 1, BlockDefs.SHELF)
	for zz in range(z + 1, z + sz - 1, 2):
		if rng.randf() < 0.6:
			_box(x, y + 1, zz, sx, 1, 1, BlockDefs.CRATE)


# --- амбар -----------------------------------------------------------------------------

func _barn(nx: int, nz: int) -> void:
	_new(nx, nz, 1, 8)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	_shell(x0, z0, x1, z1, 1, BlockDefs.BARN, BlockDefs.WOODFLOOR, BlockDefs.WOODFLOOR)
	var yt := _y(1)
	# высокая крыша: перекрытие только над задней половиной (сеновал)
	g.fill(x0, yt, z0, x1, yt + 1, z1, 0)
	g.fill(x0, yt, z0, x1, yt + 1, z0 + nz / 2, BlockDefs.WOODFLOOR)
	_ring(x0, z0, x1, z1, yt, yt + 2, BlockDefs.BARN)
	_carve(x0 + nx / 2 - 2, _y(0) + 1, z1 - 1, x0 + nx / 2 + 2, _y(0) + 4, z1)   # большие ворота
	_win_z(x0 + nx / 2, z1 - 1, yt + 1, 1, 1)                                      # окно сеновала
	var y := _y(0) + 1
	for i in 7:
		var bx := rng.randi_range(x0 + 1, x1 - 3)
		var bz := rng.randi_range(z0 + 1, z0 + nz / 2 - 2)
		_box(bx, y, bz, 2, 1, 1, BlockDefs.HAY)
		if rng.randf() < 0.5:
			_box(bx, y + 1, bz, 2, 1, 1, BlockDefs.HAY)
	_box(x0 + 1, yt + 1, z0 + 1, 2, 1, 1, BlockDefs.HAY)
	_stairs(x1 - 3, z0 + 2, 0, 2)
	_gable(x0, z0, x1, z1, yt + 2, BlockDefs.ROOFMETAL, BlockDefs.BARN)


# --- силос -----------------------------------------------------------------------------

func _silo(r: int) -> void:
	var h := 14
	g = BlockGrid.new(2 * r + 2, h + r + 3, 2 * r + 2)
	var cx := r + 1
	var cz := r + 1
	for y in range(0, h):
		for z in 2 * r + 2:
			for x in 2 * r + 2:
				var d := Vector2(x - cx + 0.5, z - cz + 0.5).length()
				if y == 0:
					if d <= r:
						g.set_cell(x, y, z, BlockDefs.CONCRETE)
				elif d <= r and d > r - 1.0:
					g.set_cell(x, y, z, BlockDefs.CONCRETE)
	# дверь
	_carve(cx, 1, cz + r - 1, cx + 1, 3, cz + r + 1)
	# купол
	for k in range(0, r):
		var rr := sqrt(maxf(float(r * r) - float(k * k) * 1.6, 0.0))
		for z in 2 * r + 2:
			for x in 2 * r + 2:
				var d := Vector2(x - cx + 0.5, z - cz + 0.5).length()
				if d <= rr and d > rr - 1.2:
					g.set_cell(x, h + k, z, BlockDefs.METAL)
	g.fill(cx - 1, h + r - 1, cz - 1, cx + 1, h + r, cz + 1, BlockDefs.METAL)


# --- сарай -----------------------------------------------------------------------------

func _shed(nx: int, nz: int) -> void:
	g = BlockGrid.new(nx + 2, nz / 3 + 7, nz + 2)
	var x0 := 1
	var x1 := 1 + nx
	var z0 := 1
	var z1 := 1 + nz
	g.fill(x0, 0, z0, x1, 1, z1, BlockDefs.WOODFLOOR)
	_ring(x0, z0, x1, z1, 1, 4, BlockDefs.WOOD)
	_carve(x0 + nx / 2, 1, z1 - 1, x0 + nx / 2 + 1, 3, z1)
	_win_x(x1 - 1, z0 + 1, 2, 1, 1)
	_box(x0 + 1, 1, z0 + 1, 1, 2, nz - 2, BlockDefs.SHELF)
	# односкатная крыша: ступени вдоль Z
	for k in nz + 2:
		var y := 4 + k / 3
		g.fill(x0 - 1, y, z0 - 1 + k, x1 + 1, y + 1, z0 + k, BlockDefs.ROOFMETAL)
		if k >= 1 and k <= nz:
			g.fill(x0, 4, z0 + k - 1, x0 + 1, y, z0 + k, BlockDefs.WOOD)
			g.fill(x1 - 1, 4, z0 + k - 1, x1, y, z0 + k, BlockDefs.WOOD)


# --- хижина ----------------------------------------------------------------------------

func _cabin(nx: int, nz: int) -> void:
	_new(nx, nz, 1, nz / 4 + 5, 3)
	var x0 := M
	var x1 := M + nx
	var z0 := M
	var z1 := M + nz
	_shell(x0, z0, x1, z1, 1, BlockDefs.LOG, BlockDefs.WOODFLOOR, BlockDefs.WOODFLOOR)
	_door_z(x0 + 2, z1 - 1, 0)
	_win_z(x0 + nx - 4, z1 - 1, _y(0) + 2)
	_win_x(x1 - 1, z0 + nz / 2, _y(0) + 2)
	_win_x(x0, z0 + nz / 2, _y(0) + 2)
	var y := _y(0) + 1
	_box(x0 + 1, y, z0 + 1, 2, 1, 3, BlockDefs.FABRIC)
	_box(x0 + 1, y + 1, z0 + 1, 2, 1, 1, BlockDefs.FURNITURE)
	_box(x1 - 4, y, z0 + nz / 2, 2, 1, 2, BlockDefs.FURNITURE)
	_box(x1 - 3, y, z0 + 1, 2, 3, 2, BlockDefs.STONE)             # камин
	_gable(x0, z0, x1, z1, _y(1) + 1, BlockDefs.SHINGLE, BlockDefs.LOG)
	_box(x0 + 1, 0, z1, nx - 2, 1, 3, BlockDefs.WOODFLOOR)          # терраса


# --- навес АЗС ---------------------------------------------------------------------------

func _canopy(nx: int, nz: int) -> void:
	g = BlockGrid.new(nx + 2, 9, nz + 2)
	var x0 := 1
	var x1 := 1 + nx
	var z0 := 1
	var z1 := 1 + nz
	for px in [x0 + 1, x1 - 2]:
		for pz in [z0 + 1, z1 - 2]:
			g.fill(px, 1, pz, px + 1, 6, pz + 1, BlockDefs.CONCRETE)
	g.fill(x0 - 1, 6, z0 - 1, x1 + 1, 7, z1 + 1, BlockDefs.METAL)
	g.fill(x0 - 1, 5, z1, x1 + 1, 6, z1 + 1, BlockDefs.BARN)
	for px in [x0 + nx / 3, x0 + 2 * nx / 3 - 1]:
		g.fill(px, 1, z0 + nz / 2, px + 1, 3, z0 + nz / 2 + 1, BlockDefs.METAL)
		g.fill(px, 3, z0 + nz / 2, px + 1, 4, z0 + nz / 2 + 1, BlockDefs.GLASS)
