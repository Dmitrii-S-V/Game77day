extends SceneTree
## Шкала заметности зомби: растёт от вида (не видит за спиной), 35+ — идёт проверить, 100 — погоня;
## от звука: тихий шум только поднимает шкалу, 100 от звука — ~50% «не заметил» (откат до 70, проверяет шум);
## спящий просыпается на своём пороге; шкала спадает сама.
## C:\Godot\godot.exe --headless --fixed-fps 60 --path D:\77Days --script res://tools/test_awareness.gd

class Stub extends Node3D:
	var crouching := false
	var _sprinting := false
	var _dead_t := 0.0
	var peer_id := 1
	var hits := 0.0

	func take_damage(a: float) -> void:
		hits += a


var fails := 0
var _f := 0
var _z: Zombie
var _z2: Zombie
var _p: Stub


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	cs.position.y = -0.5
	ground.add_child(cs)
	root.add_child(ground)
	_p = Stub.new()
	_p.add_to_group("survivors")
	_p.position = Vector3(0, 0, -10)      # за спиной зомби (он смотрит на +Z)
	root.add_child(_p)
	_z = Zombie.new()
	_z.position = Vector3(0, 0.05, 0)
	root.add_child(_z)
	_z2 = Zombie.new()                     # для проверок слуха — далеко, игрока не видит
	_z2.position = Vector3(150, 0.05, 150)
	root.add_child(_z2)


func _process(_d: float) -> bool:
	_f += 1
	if _f < 5:
		_z.rotation.y = 0.0
		_z._wander_t = 100.0      # не бродит, смотрит вперёд
		_z._wander = Vector3.ZERO
	if _f == 120:
		check("за спиной не видит: шкала %.0f" % _z.awareness, _z.awareness < 1.0 and _z.state == Zombie.S.IDLE)
		_p.position = Vector3(0, 0, 15)
	if _f == 120 + 36:
		check("видит в 15 м: шкала растёт постепенно (%.0f)" % _z.awareness, _z.awareness > 5.0 and _z.awareness < 100.0)
		check("ещё не погоня", _z.state != Zombie.S.CHASE)
	if _f == 120 + 60 * 4:
		check("заметил — погоня (шкала %.0f, состояние %s)" % [_z.awareness, Zombie.S.keys()[_z.state]], _z.state == Zombie.S.CHASE and _z.awareness >= 99.0)
		check("цель — игрок", _z.aw_target == _p)
		_hearing()
		_p.position = Vector3(0, 0, 300)    # ушёл далеко
	if _f == 120 + 60 * 4 + 60 * 20:
		check("потерял из виду — шкала спала (%.0f)" % _z.awareness, _z.awareness < 60.0 and _z.state != Zombie.S.CHASE)
		print("RESULT fails=%d" % fails)
		return true
	return false


func _hearing() -> void:
	var z := _z2
	var spot := z.global_position + Vector3(5, 0, 0)
	# тихий шум: шкала растёт, с места не сходит; второй такой же — идёт проверить
	z.state = Zombie.S.IDLE
	z.awareness = 0.0
	z.hear(spot, 0.3, _p)
	check("тихий шум: шкала %.0f, стоит" % z.awareness, absf(z.awareness - 19.5) < 0.6 and z.state == Zombie.S.IDLE)
	z.hear(spot, 0.3, _p)
	check("ещё шум: 35+ — идёт проверить (%.0f, %s)" % [z.awareness, Zombie.S.keys()[z.state]], z.state == Zombie.S.INVESTIGATE)
	# шкала заполнилась от звука: ~50% погоня, иначе откат до 70 и проверка
	var chase := 0
	var miss_ok := true
	var n := 400
	for i in n:
		z.state = Zombie.S.IDLE
		z.awareness = 90.0
		z._sees = false
		z.hear(spot, 0.5, _p)
		if z.state == Zombie.S.CHASE:
			chase += 1
		else:
			miss_ok = miss_ok and z.state == Zombie.S.INVESTIGATE and absf(z.awareness - Zombie.AW_MISS_BACK) < 0.01
	var k := float(chase) / n
	check("от звука заметил в %.0f%% случаев (~50%%)" % (k * 100.0), k > 0.42 and k < 0.58)
	check("не заметил — шкала 70 и идёт к шуму", miss_ok)
	# спящий: будит только шум ближе 2 блоков (любой громкости дальше — нет), урон и триггер своего цвета
	z.state = Zombie.S.SLEEP
	z.awareness = 0.0
	for i in 10:
		z.hear(spot, 1.0, _p)     # 5 м, максимальная громкость
	check("спящий: громкий шум в 5 м — спит (шкала %.0f)" % z.awareness, z.state == Zombie.S.SLEEP and z.awareness < 1.0)
	z.hear(z.global_position + Vector3(1.5, 0, 0), 0.2, _p)
	check("спящий: шум в 1.5 м — проснулся и заметил", z.state == Zombie.S.CHASE)
	z.state = Zombie.S.SLEEP
	z.home_key = "test_bld"
	z.wake_color = "red"
	ZombieDirector.trigger("test_bld", "blue", _p)
	check("триггер другого цвета не будит", z.state == Zombie.S.SLEEP)
	z.wake_by_trigger(_p)
	check("триггер своего цвета — проснулся и гонится", z.state == Zombie.S.CHASE and z.player == _p)
	z.state = Zombie.S.SLEEP
	z.take_hit(1.0, Vector3.FORWARD, z.global_position + Vector3.UP)
	check("урон будит спящего", z.state == Zombie.S.CHASE)
