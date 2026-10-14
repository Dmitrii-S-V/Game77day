class_name SaveGame
extends RefCounted
## Сохранение и загрузка (user://saves/save1.sav, var_to_bytes + сжатие).
## Мир не хранится целиком — только параметры генерации (сид и т.д., мир детерминирован) и всё, что изменил игрок:
## изменённые чанки ландшафта, изменённые здания, срубленные растения, обысканные контейнеры; плюс игрок
## (позиция, взгляд, здоровье, жажда, голод, инвентарь), время суток и номер дня.

const DIR := "user://saves/"
const VERSION := 1


static func path(slot: int = 1) -> String:
	return DIR + "save%d.sav" % slot


static func exists(slot: int = 1) -> bool:
	return FileAccess.file_exists(path(slot))


static func params_to_dict(p: WorldParams) -> Dictionary:
	return {"seed": p.seed_value, "size": p.size, "towns": p.towns, "pois": p.pois, "rivers": p.rivers, "lakes": p.lakes,
		"mount": p.pct_mountain, "hill": p.pct_hill, "plain": p.pct_plain, "burn": p.pct_burn}


static func params_from_dict(d: Dictionary) -> WorldParams:
	var p := WorldParams.new()
	p.seed_value = int(d["seed"])
	p.size = int(d["size"])
	p.towns = int(d["towns"])
	p.pois = int(d["pois"])
	p.rivers = int(d["rivers"])
	p.lakes = int(d["lakes"])
	p.pct_mountain = int(d["mount"])
	p.pct_hill = int(d["hill"])
	p.pct_plain = int(d["plain"])
	p.pct_burn = int(d["burn"])
	return p


static func _grid_to_dict(g: BlockGrid) -> Dictionary:
	return {"nx": g.nx, "ny": g.ny, "nz": g.nz, "tint": g.tint, "ground": g.ground_cells, "cells": g.cells, "meta": g.meta,
		"decals": g.decals, "sink": g.sink, "has_new": g.has_new, "hp": g.hp, "props": g.props}


static func _grid_from_dict(d: Dictionary) -> BlockGrid:
	var g := BlockGrid.new(int(d["nx"]), int(d["ny"]), int(d["nz"]))
	g.tint = int(d["tint"])
	g.ground_cells = int(d["ground"])
	g.cells = d["cells"]
	g.meta = d["meta"]
	g.decals = d["decals"]
	g.sink = int(d["sink"])
	g.has_new = bool(d["has_new"])
	g.hp = d["hp"]
	g.props = d["props"]
	return g


## Сохранить текущую игру (m — main.gd). Возвращает true при успехе.
static func save(m: Node, slot: int = 1) -> bool:
	var pl: Player = m.player
	var terrain: Terrain = m.terrain
	var chunks := {}
	terrain._data_mutex.lock()
	for cc: Vector3i in terrain._data.keys():
		var cd: ChunkData = terrain._data[cc]
		if cd.edited:
			chunks[cc] = [cd.dens, cd.mat]
	terrain._data_mutex.unlock()
	var grids := {}
	for k: String in m.settlement.edited_grids:
		grids[k] = _grid_to_dict(m.settlement.edited_grids[k])
	var data := {
		"version": VERSION,
		"params": params_to_dict(m.world.params),
		"time": m.time_of_day, "day": m.day,
		"player": {"pos": pl.global_position, "yaw": pl.rotation.y, "pitch": pl._pitch, "health": pl.health,
			"thirst": pl.thirst, "hunger": pl.hunger, "slots": pl.inventory.slots, "selected": pl.inventory.selected,
			"backpack": pl.inventory.has_backpack, "spawn": pl.spawn_point},
		"map_marks": Minimap.marks,
		"chunks": chunks,
		"buildings": grids,
		"plants": Vegetation.removed.keys(),
		"grass_cut": GrassField.cut.keys(),
		"gear": Gear.to_dict(),
		"looted": Loot._looted.keys(),
		"sleepers_killed": ZombieDirector.sleepers_killed.duplicate(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(data, false)
	f.close()
	# запись через временный файл: при сбое старое сохранение не портится
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path(slot)))
	return true


## Прочитать сохранение (или {} при ошибке).
static func read(slot: int = 1) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open_compressed(path(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d: Variant = f.get_var(false)
	return d if d is Dictionary else {}


## Краткое описание для меню: «День 3, 14:25 — сохранено 2026-10-09 18:40».
static func describe(slot: int = 1) -> String:
	var d := read(slot)
	if d.is_empty():
		return ""
	var mins := int(float(d["time"]) * 1440.0)
	return "День %d, %02d:%02d — сид %d — %s" % [int(d["day"]), mins / 60, mins % 60, int(d["params"]["seed"]), String(d.get("saved_at", ""))]


## Применить мировые изменения ДО начала стриминга (чанки, здания, растения, контейнеры).
static func apply_world(m: Node, d: Dictionary) -> void:
	var terrain: Terrain = m.terrain
	terrain._data_mutex.lock()
	for cc: Vector3i in d["chunks"]:
		var cd := ChunkData.new()
		cd.dens = d["chunks"][cc][0]
		cd.mat = d["chunks"][cc][1]
		cd.edited = true
		terrain._data[cc] = cd
	terrain._data_mutex.unlock()
	for k: String in d["buildings"]:
		m.settlement.edited_grids[k] = _grid_from_dict(d["buildings"][k])
	Vegetation.removed.clear()
	for k: Vector2i in d["plants"]:
		Vegetation.removed[k] = true
	GrassField.cut.clear()
	for k: Vector2i in d.get("grass_cut", []):
		GrassField.cut[k] = true
	Gear.from_dict(d.get("gear", {}))
	Loot._looted.clear()
	for k: Vector3i in d["looted"]:
		Loot._looted[k] = true
	ZombieDirector.sleepers_killed = (d.get("sleepers_killed", {}) as Dictionary).duplicate()
	m.time_of_day = float(d["time"])
	m.day = int(d["day"])


## Применить состояние игрока (после его создания).
static func apply_player(pl: Player, d: Dictionary) -> void:
	var p: Dictionary = d["player"]
	pl.global_position = p["pos"]
	pl.spawn_point = p.get("spawn", p["pos"])
	pl.set_look(float(p["yaw"]), float(p["pitch"]))
	pl.health = float(p["health"])
	pl.thirst = float(p["thirst"])
	pl.hunger = float(p["hunger"])
	var slots: Array = p["slots"]
	for i in mini(slots.size(), pl.inventory.slots.size()):
		pl.inventory.slots[i] = slots[i]
	pl.inventory.select(int(p["selected"]))
	Minimap.marks = (d.get("map_marks", []) as Array).duplicate(true)
	# старые сохранения без флага: если в дополнительных ячейках есть вещи — рюкзак считаем надетым
	var worn := bool(p.get("backpack", pl.inventory.has_extra_items()))
	if worn and pl.UI != null:
		pl.UI.wear_backpack_silently()
	else:
		pl.inventory.has_backpack = worn
