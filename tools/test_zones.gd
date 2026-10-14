extends SceneTree
## Зоны спящих (блоки «Зона спавна» и «Триггерная зона», цвета — tier): в игре невидимы и без столкновений,
## зоны спавна находятся (цвет, место), триггер чужого цвета не будит, своего — будит и зомби замечает игрока.
## C:\Godot\godot.exe --headless --fixed-fps 60 --path D:\77Days --script res://tools/test_zones.gd

class Walker extends CharacterBody3D:
	var crouching := false
	var _sprinting := false
	var _dead_t := 0.0
	var peer_id := 1

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		cs.shape = cap
		cs.position.y = 0.9
		add_child(cs)
		add_to_group("survivors")

	func take_damage(_a: float) -> void:
		pass


var fails := 0
var _f := 0
var _bb: BlockBuilding
var _z: Zombie
var _w: Walker
var _dir: ZombieDirector


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _tier(id: int, key: String) -> int:
	var tiers: Array = BlockRegistry.block(id).get("tiers", [])
	for i in tiers.size():
		if String(tiers[i]["key"]) == key:
			return i
	return -1


func _init() -> void:
	var spawn := BlockRegistry.id_by_key("sleeper_spawn")
	var trig := BlockRegistry.id_by_key("sleeper_trigger")
	check("блоки зон есть в реестре (%d, %d)" % [spawn, trig], spawn > 0 and trig > 0)
	check("14 цветов у зон", BlockRegistry.tier_count(spawn) == 14 and BlockRegistry.tier_count(trig) == 14)
	var g := BlockGrid.new(8, 3, 8)
	var wall := BlockRegistry.id_by_key("wall")
	for z in 8:
		for x in 8:
			g.set_cell(x, 0, z, wall, BlockRegistry.make_meta(0, 5, 0))
	g.set_cell(2, 1, 2, spawn, BlockRegistry.make_meta(0, _tier(spawn, "red"), 0))
	g.set_cell(5, 1, 2, spawn, BlockRegistry.make_meta(0, _tier(spawn, "blue"), 0))
	g.set_cell(2, 1, 6, trig, BlockRegistry.make_meta(0, _tier(trig, "blue"), 0))
	g.set_cell(6, 1, 6, trig, BlockRegistry.make_meta(0, _tier(trig, "red"), 0))
	g.has_new = true      # как у сохранённых префабов (новые блоки)
	var mat := StandardMaterial3D.new()
	_bb = BlockBuilding.new()
	root.add_child(_bb)
	_bb.setup(g, mat, mat)
	_bb.set_meta("bkey", "zone_test")
	_dir = ZombieDirector.new()
	root.add_child(_dir)
	_w = Walker.new()
	_w.position = Vector3(-10, 1.1, -10)
	root.add_child(_w)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		var sp := _bb.marker_spots("spawn")
		check("зоны спавна найдены: %d" % sp.size(), sp.size() == 2)
		var red: Dictionary = {}
		for s: Dictionary in sp:
			if s["color"] == "red":
				red = s
		check("красная зона на своём месте", not red.is_empty() and (red["pos"] as Vector3).distance_to(_bb.to_global(_bb.origin + Vector3(2.5, 1.02, 2.5) * BlockGrid.B)) < 0.05)
		# ни одного видимого меша и столкновения у зон в игре
		var bodies := 0
		for e: Dictionary in _bb._custom.values():
			for n: Node in e["nodes"]:
				if n is StaticBody3D or n is MeshInstance3D:
					bodies += 1
		check("в игре зоны невидимы и без столкновений", bodies == 0)
		var space := _bb.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(_bb.to_global(_bb.origin + Vector3(2.5, 2.9, 2.5)), _bb.to_global(_bb.origin + Vector3(2.5, 1.05, 2.5)), 2 | 8)
		check("луч сквозь зону спавна не упирается", space.intersect_ray(q).is_empty())
		_z = Zombie.new()
		_z.position = red["pos"]
		_z.home_key = "zone_test"
		_z.wake_color = "red"
		_z.player = _w
		_dir.add_child(_z)
		_z.sleep()
	if _f == 60:
		_w.global_position = _bb.to_global(_bb.origin + Vector3(2.5, 1.0, 6.5))    # синий триггер
	if _f == 61 or _f == 91:
		var areas: Array = []
		for e: Dictionary in _bb._custom.values():
			for n: Node in e["nodes"]:
				if n is Area3D:
					areas.append([(n as Area3D).global_position, (n as Area3D).get_overlapping_bodies().size()])
		print("DBG areas ", areas, " walker ", _w.global_position, " z ", _z.global_position)
	if _f == 90:
		check("синий триггер не будит красного", _z.state == Zombie.S.SLEEP)
		_w.global_position = _bb.to_global(_bb.origin + Vector3(6.5, 1.0, 6.5))    # красный
	if _f == 120:
		check("красный триггер разбудил, зомби гонится за игроком (%s)" % Zombie.S.keys()[_z.state], _z.state == Zombie.S.CHASE and _z.player == _w)
		print("RESULT fails=%d" % fails)
		return true
	return false
