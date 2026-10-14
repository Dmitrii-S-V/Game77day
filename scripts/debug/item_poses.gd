class_name ItemPoses
extends RefCounted
## Сохранённые позы предметов в руке (data/item_poses.json): положение/поворот/масштаб предмета в хвате и положение руки.
## Редактируется отладчиком ItemPoseDebug (F9 в игре). Формат записи по id предмета:
##   {"item_pos": [x, y, z] (м, в системе хвата), "item_rot": [x, y, z] (градусы), "item_scale": s,
##    "hand_pos": [x, y, z], "hand_rot": [x, y, z] (градусы)}
## Нет записи или поля — берутся значения по умолчанию из кода (HandRig).

const PATH := "res://data/item_poses.json"
static var _data := {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_data = d


static func get_pose(id: String) -> Dictionary:
	ensure()
	return _data.get(id, {})


static func set_pose(id: String, pose: Dictionary) -> void:
	ensure()
	_data[id] = pose


static func save() -> bool:
	ensure()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_data, "  "))
	return true


static func vec(a: Variant, def: Vector3) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return def
