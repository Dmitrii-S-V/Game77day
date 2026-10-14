class_name BlockGrid
extends RefCounted
## Трёхмерная сетка блоков здания (ячейка 1 м, как воксель ландшафта). Нулевой блок — воздух.
## cells — id (старые блоки 1..18 и новые из BlockRegistry, id >= 32), meta — поворот/tier/вариант/
## состояние/признак «часть многоячеечного блока» (см. BlockRegistry). Многоячеечный блок хранится как
## якорь (минимальный угол footprint) с полными данными и «части» с флагом и смещением от якоря.

const CS := 8        # размер куска меша в ячейках
const B := 1.0       # размер ячейки, м (= воксель ландшафта: 1 блок земли = 1 блок здания)

var nx := 0
var ny := 0
var nz := 0
var tint := 0        # вариант оттенка здания 0..3
var ground_cells := 1   # ячейки с y < ground_cells — под землёй; первый слой над землёй y = ground_cells
var cells := PackedByteArray()
var meta := PackedInt32Array()
var decals := {}        # ячейка*8 + грань -> упакованная декаль (см. BlockDecals); только кубы
var sink := 0          # слоёв, на которые здание погружается в землю при постановке в мир (префабы: слой пола вровень с землёй)
var has_new := false   # есть блоки нового типа (id >= 32): нужны узлы коллизии/света
var hp := {}         # idx якоря -> оставшаяся прочность повреждённых блоков
var props: Array = []   # предметы внутри: {"name", "pos": Vector3 (м в пространстве сетки), "yaw", "support": Vector3i (клетка опоры)}
var ground := {}        # покрытие земли под постройкой: Vector2i(x, z) ячейки -> ключ GroundTypes (asphalt, gravel…)
var plants: Array = []  # посаженное в редакторе: {type (PlantTypes), x, z (м от угла сетки), rot, scale, hue}


func _init(x: int = 1, y: int = 1, z: int = 1) -> void:
	nx = x
	ny = y
	nz = z
	cells.resize(x * y * z)
	meta.resize(x * y * z)


func idx(x: int, y: int, z: int) -> int:
	return x + nx * (y + ny * z)


func cell_of(i: int) -> Vector3i:
	var x := i % nx
	var r := i / nx
	return Vector3i(x, r % ny, r / ny)


func inside(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < nx and y < ny and z < nz


func get_cell(x: int, y: int, z: int) -> int:
	if not inside(x, y, z):
		return 0
	return cells[x + nx * (y + ny * z)]


func get_meta_at(x: int, y: int, z: int) -> int:
	if not inside(x, y, z):
		return 0
	return meta[x + nx * (y + ny * z)]


func set_cell(x: int, y: int, z: int, id: int, m: int = 0) -> void:
	if inside(x, y, z):
		var i := x + nx * (y + ny * z)
		cells[i] = id
		meta[i] = m
		if id == 0 and not decals.is_empty():
			clear_decals(i)


## Заливка [x0,x1) x [y0,y1) x [z0,z1) старым блоком (без meta).
func fill(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, id: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, nz)):
		for y in range(maxi(y0, 0), mini(y1, ny)):
			for x in range(maxi(x0, 0), mini(x1, nx)):
				var i := x + nx * (y + ny * z)
				cells[i] = id
				meta[i] = 0
				if id == 0 and not decals.is_empty():
					clear_decals(i)


func clear_decals(cell_idx: int) -> void:
	for f in 6:
		decals.erase(cell_idx * 8 + f)


func chunk_dims() -> Vector3i:
	return Vector3i(ceili(nx / float(CS)), ceili(ny / float(CS)), ceili(nz / float(CS)))


func duplicate_grid() -> BlockGrid:
	var g := BlockGrid.new(nx, ny, nz)
	g.cells = cells.duplicate()
	g.meta = meta.duplicate()
	g.tint = tint
	g.ground_cells = ground_cells
	g.has_new = has_new
	g.sink = sink
	g.decals = decals.duplicate()
	g.props = props.duplicate(true)
	g.ground = ground.duplicate()
	g.plants = plants.duplicate(true)
	return g


# --- многоячеечные блоки --------------------------------------------------------------

## Якорь блока, которому принадлежит ячейка (для частей — по смещению).
func anchor_of(c: Vector3i) -> Vector3i:
	var m := get_meta_at(c.x, c.y, c.z)
	if BlockRegistry.is_part(m) and get_cell(c.x, c.y, c.z) != 0:
		return c - BlockRegistry.part_offset(m)
	return c


func footprint_cells(anchor: Vector3i, id: int, rot: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var f := BlockRegistry.footprint(id, rot)
	for dz in f.z:
		for dy in f.y:
			for dx in f.x:
				out.append(anchor + Vector3i(dx, dy, dz))
	return out


func can_place(anchor: Vector3i, id: int, rot: int) -> bool:
	for c in footprint_cells(anchor, id, rot):
		if not inside(c.x, c.y, c.z) or get_cell(c.x, c.y, c.z) != 0:
			return false
	return true


## Ставит блок (якорь + части). Возвращает занятые ячейки.
func place_block(anchor: Vector3i, id: int, m: int) -> Array[Vector3i]:
	var rot := BlockRegistry.rot_of(m)
	var cs := footprint_cells(anchor, id, rot)
	for c in cs:
		var off := c - anchor
		if off == Vector3i.ZERO:
			set_cell(c.x, c.y, c.z, id, m)
		else:
			set_cell(c.x, c.y, c.z, id, BlockRegistry.make_part(off.x, off.y, off.z))
	hp.erase(idx(anchor.x, anchor.y, anchor.z))
	if id >= BlockRegistry.FIRST_ID:
		has_new = true
	return cs


## Снимает блок, которому принадлежит ячейка. Возвращает {anchor, id, meta, cells} или пустой словарь.
func remove_block(c: Vector3i) -> Dictionary:
	var id := get_cell(c.x, c.y, c.z)
	if id == 0:
		return {}
	var a := anchor_of(c)
	var am := get_meta_at(a.x, a.y, a.z)
	var aid := get_cell(a.x, a.y, a.z)
	var cs: Array[Vector3i] = []
	if BlockRegistry.is_new(aid):
		cs = footprint_cells(a, aid, BlockRegistry.rot_of(am))
	else:
		cs = [c]
		a = c
		am = get_meta_at(c.x, c.y, c.z)
		aid = id
	for q in cs:
		if get_cell(q.x, q.y, q.z) == aid:
			set_cell(q.x, q.y, q.z, 0, 0)
	hp.erase(idx(a.x, a.y, a.z))
	return {"anchor": a, "id": aid, "meta": am, "cells": cs}


## Поддерживающая ячейка с твёрдой опорой (земля тоже опора).
func solid_support_at(x: int, y: int, z: int) -> bool:
	if y < ground_cells and x >= 0 and z >= 0 and x < nx and z < nz:
		return true
	if not inside(x, y, z):
		return false
	var id := get_cell(x, y, z)
	return BlockRegistry.supports(id, get_meta_at(x, y, z))


## Есть ли опора у крепящегося блока (свеча/ковёр снизу, люстра сверху, паутина сбоку).
func is_supported(anchor: Vector3i, id: int, m: int) -> bool:
	var mode := BlockRegistry.support_mode(id)
	if mode == "":
		return true
	var f := BlockRegistry.footprint(id, BlockRegistry.rot_of(m))
	for dz in f.z:
		for dx in f.x:
			var below := solid_support_at(anchor.x + dx, anchor.y - 1, anchor.z + dz)
			var above := solid_support_at(anchor.x + dx, anchor.y + f.y, anchor.z + dz)
			match mode:
				"below":
					if not below:
						return false
				"above":
					if not above:
						return false
				"any":
					if below or above:
						return true
	if mode == "any":
		for dy in f.y:
			for dz in f.z:
				if solid_support_at(anchor.x - 1, anchor.y + dy, anchor.z + dz) or solid_support_at(anchor.x + f.x, anchor.y + dy, anchor.z + dz):
					return true
			for dx in f.x:
				if solid_support_at(anchor.x + dx, anchor.y + dy, anchor.z - 1) or solid_support_at(anchor.x + dx, anchor.y + dy, anchor.z + f.z):
					return true
		return false
	return true


## Луч по сетке (координаты — метры в пространстве сетки). Возвращает {cell, normal, pos, dist} или {}.
## Пустая земля (y = ground_cells - 1 снизу, плоскость y = ground_cells * B) тоже ловится: cell = ячейка над землёй, ground = true.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var d := dir.normalized()
	var p := origin / B
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1, 1 if d.z > 0.0 else -1)
	var tmax := Vector3(INF, INF, INF)
	var tdelta := Vector3(INF, INF, INF)
	for a in 3:
		if absf(d[a]) > 1e-8:
			var next_edge := float(cell[a] + (1 if step[a] > 0 else 0))
			tmax[a] = (next_edge - p[a]) / d[a]
			tdelta[a] = float(step[a]) / d[a]
	var t := 0.0
	var normal := Vector3i.ZERO
	var limit := max_dist / B
	for i in 600:
		if inside(cell.x, cell.y, cell.z) and cells[idx(cell.x, cell.y, cell.z)] != 0:
			return {"cell": cell, "normal": normal, "pos": (p + d * t) * B, "dist": t * B, "ground": false}
		var axis := 0
		if tmax.y < tmax.x and tmax.y <= tmax.z:
			axis = 1
		elif tmax.z < tmax.x and tmax.z < tmax.y:
			axis = 2
		t = tmax[axis]
		if t > limit:
			break
		cell[axis] += step[axis]
		tmax[axis] += tdelta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
		# вошли в слой земли сверху: грань земли
		if axis == 1 and step.y < 0 and cell.y == ground_cells - 1:
			var gp := p + d * t
			if gp.x >= 0.0 and gp.z >= 0.0 and gp.x < nx and gp.z < nz:
				return {"cell": Vector3i(cell.x, ground_cells, cell.z), "normal": Vector3i(0, 1, 0), "pos": gp * B, "dist": t * B, "ground": true, "ground_cell": Vector3i(floori(gp.x), ground_cells - 1, floori(gp.z))}
	return {}
