class_name ZombieDirector
extends Node
## Появление зомби по образцу 7 Days to Die:
## - «биомные»: мир поделён на клетки CELL м, у каждой — квота (в городе больше, ночью больше). Зомби появляются
##   в клетках вокруг игрока на 40–100 м, вне поля зрения. Убитые не возвращаются, пока клетка не «восстановится»
##   (RESPAWN_DAYS игровых суток); ушедшие далеко удаляются и возвращаются в квоту клетки;
## - «спящие» в зданиях: при подходе к зданию на SLEEPER_R м внутри (на первом этаже) появляются спящие зомби,
##   число — по размеру здания; убитые запоминаются (и сохраняются). Будят их шум и игрок рядом;
## - бродячие орды: раз в несколько игровых часов группа идёт мимо игрока;
## - кровавая луна: каждую 7-ю ночь с 22:00 до 04:00 — волны бегущих зомби, которые всегда знают, где игрок.
## Шум игрока (шаги, удары, двери) — noise(): ближние зомби идут проверить, спящие могут проснуться.

const CELL := 48.0
const RESPAWN_DAYS := 0.75
const SPAWN_MIN := 40.0
const SPAWN_MAX := 100.0
const DESPAWN := 125.0
const SLEEPER_R := 45.0
const BIOME_MAX_DAY := 6
const BIOME_MAX_NIGHT := 10
const SLEEPER_MAX := 14
const HORDE_MAX := 8
const BLOOD_MAX := 10
const TICK := 0.5
const MUDWORN_SHARE := 0.35   # доля прыгунов (модель mudworn) среди новых зомби

static var inst: ZombieDirector
static var sleepers_killed := {}   # ключ здания (Settlement.building_key) -> убито спящих (сохраняется)

var main: Node
var enabled := true
var _t := 2.0
var _sep_t := 0.0
var _cells := {}         # Vector2i -> {alive, killed, respawn}
var _cell_lots := {}     # Vector2i -> число зданий в клетке (город — больше зомби)
var _active_bld := {}    # ключ здания -> Vector2 (спящие уже расставлены, пока игрок рядом)
var _bld_t := 0.0
var _horde_t := 120.0
var _blood := false
var _blood_budget := 0
var _blood_t := 0.0
var _log := OS.get_cmdline_user_args().has("--zlog=1")   # отладка: раз в 5 с — сколько зомби и в каких состояниях
var _log_t := 0.0
var _log_n := 0


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Шум в точке: зомби в радиусе слышат его (чем ближе, тем громче) — растёт их заметность (Zombie.hear).
## src — кто шумел (игрок). У клиента сетевой игры шум уходит хосту (зомби живут там).
static func noise(pos: Vector3, radius: float, src: Node3D = null) -> void:
	if Net.is_client():
		Net.inst.send_noise(pos, radius)
		return
	if inst == null or not inst.enabled:
		return
	radius /= Zombie.SENSE_RANGE_DIV     # слух зомби короче исходных радиусов шумов
	for z: Zombie in inst.get_children():
		if z.dead:
			continue
		var d := z.global_position.distance_to(pos)
		if d < radius:
			z.hear(pos, 1.0 - d / radius, src)


## Все игроки (свой и по сети); alive_only — только живые.
func players(alive_only := false) -> Array:
	var out: Array = []
	if main != null and main.player != null:
		out.append(main.player)
	if Net.active():
		out.append_array(Net.inst.remotes.values())
	if alive_only:
		out = out.filter(func(p: Node3D) -> bool: return is_instance_valid(p) and float(p.get("_dead_t")) <= 0.0)
	return out


func _nearest_dist(pos: Vector3) -> float:
	var best := 1e9
	for p: Node3D in players():
		if is_instance_valid(p):
			best = minf(best, p.global_position.distance_to(pos))
	return best


## Дальние зомби (упрощённое движение) физически друг с другом не сталкиваются — их мягко расталкиваем здесь,
## 10 раз в секунду (иначе толпа сливается в одну точку).
func _separate() -> void:
	var list: Array[Zombie] = []
	for z: Zombie in get_children():
		if z._simple and not z.dead and z.state != Zombie.S.SLEEP:
			list.append(z)
	for i in list.size():
		var a := list[i]
		for j in range(i + 1, list.size()):
			var b := list[j]
			var d := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
			var l := d.length()
			if l < 0.75 and absf(a.global_position.y - b.global_position.y) < 1.5:
				var push := (d / maxf(l, 0.01) if l > 0.01 else Vector2(randf() - 0.5, randf() - 0.5).normalized()) * (0.75 - l) * 0.5
				a.global_position -= Vector3(push.x, 0.0, push.y)
				b.global_position += Vector3(push.x, 0.0, push.y)


func _process(delta: float) -> void:
	if not enabled or main == null or main.player == null or not main._spawned:
		return
	_sep_t -= delta
	if _sep_t <= 0.0:
		_sep_t = 0.1
		_separate()
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	_tick()


func _tick() -> void:
	var pl: Node3D = main.player
	var tod: float = main.time_of_day
	var night := tod < 0.22 or tod > 0.8
	var now := float(main.day) + tod
	var pp := pl.global_position
	var n_biome := 0
	var n_sleep := 0
	var n_horde := 0
	var n_blood := 0
	for z: Zombie in get_children():
		if z.is_queued_for_deletion():
			continue
		z.night = night
		if z.dead:
			continue
		var dh := z.global_position.distance_to(pp)
		var d := _nearest_dist(z.global_position) if Net.active() else dh
		# далеко от всех игроков и не гонится — убрать (биомный возвращается в квоту клетки)
		if d > DESPAWN and (z.state != Zombie.S.CHASE or d > DESPAWN * 1.5):
			_despawn(z)
			continue
		z.set_shadows(dh < 40.0)
		# у хоста физика ландшафта есть только вокруг его игрока: дальше — упрощённое движение по поверхности
		z.set_lod(d if dh < 60.0 else maxf(d, Zombie.SIMPLE_DIST + 1.0))
		match z.kind:
			"biome": n_biome += 1
			"sleeper": n_sleep += 1
			"horde": n_horde += 1
			"blood": n_blood += 1
	if _log:
		_log_t -= TICK
		if _log_t <= 0.0:
			_log_t = 5.0
			_log_n += 1
			if _log_n == 4 and OS.get_cmdline_user_args().has("--znoise=1"):
				print("ZLOG noise 60 m at player")
				noise(pp, 60.0)
			var st := {}
			var md := 1e9
			for z: Zombie in get_children():
				if not z.dead and z.state == Zombie.S.CHASE:
					md = minf(md, z.global_position.distance_to(pl.global_position))
					st["near"] = "%.1f v%.1f wall%s" % [md, z.velocity.length(), z.is_on_wall()] if md == z.global_position.distance_to(pl.global_position) else st.get("near", "")
				var k := "%s/%s" % [z.kind, "dead" if z.dead else Zombie.S.keys()[z.state]]
				st[k] = int(st.get(k, 0)) + 1
			var mud := 0
			for z: Zombie in get_children():
				if z.ztype == "mudworn" and not z.dead:
					mud += 1
			print("ZLOG day %d %02d:%02d blood %s budget %d active_bld %d hp %.0f mudworn %d leaps %d hits %d | %s" % [main.day, int(tod * 24.0),
				int(tod * 1440.0) % 60, _blood, _blood_budget, _active_bld.size(), float(pl.get("health")), mud, Zombie.leap_count, Zombie.leap_hits, st])
	# появление — вокруг случайного живого игрока (в сетевой игре — по очереди у всех)
	var alive_pl := players(true)
	var focus: Node3D = alive_pl.pick_random() if not alive_pl.is_empty() else pl
	_blood_moon_tick(focus, n_blood)
	if not _blood:
		_biome_tick(focus, night, now, n_biome)
		_horde_tick(focus, night, n_horde)
	_bld_t -= TICK
	if _bld_t <= 0.0:
		_bld_t = 2.0
		_sleeper_tick(pl, n_sleep)


# --- общее ---------------------------------------------------------------------

func _make(kind: String, pos: Vector3) -> Zombie:
	var zb := Zombie.new()
	zb.ztype = "mudworn" if randf() < MUDWORN_SHARE else "friend"
	zb.player = main.player
	zb.gen = main.terrain.gen
	zb.terrain = main.terrain
	zb.kind = kind
	zb.night = main.time_of_day < 0.22 or main.time_of_day > 0.8
	zb.feral = randf() < 0.08
	# позиция — ДО добавления в сцену: иначе тело на миг появляется в (0,0,0) и физика его «телепортирует»
	zb.position = pos
	zb.rotation.y = randf() * TAU
	zb.killed.connect(_on_killed)
	var t0 := Time.get_ticks_usec()
	add_child(zb)
	Prof.add("z_spawn", Time.get_ticks_usec() - t0)
	zb.set_lod(pos.distance_to(main.player.global_position))
	return zb


func _despawn(z: Zombie) -> void:
	if z.kind == "biome" and _cells.has(z.home):
		_cells[z.home]["alive"] = maxi(0, int(_cells[z.home]["alive"]) - 1)
	z.queue_free()


func _on_killed(z: Zombie) -> void:
	match z.kind:
		"biome":
			var c := _cell(z.home)
			c["alive"] = maxi(0, int(c["alive"]) - 1)
			c["killed"] = int(c["killed"]) + 1
			c["respawn"] = float(main.day) + main.time_of_day + RESPAWN_DAYS
		"sleeper":
			sleepers_killed[z.home_key] = int(sleepers_killed.get(z.home_key, 0)) + 1


## Точка на поверхности (построенный ландшафт, не в воде) или NAN.
func _ground(x: float, z: float) -> float:
	var terrain: Terrain = main.terrain
	if not terrain.is_column_done(floori(x / 16.0), floori(z / 16.0)):
		return NAN
	var y := terrain.surface_y(x, z, terrain.gen.height_at(x, z))
	if is_nan(y) or y < WorldGen.WATER_LEVEL + 0.3:
		return NAN
	return y


## Места хватает для тела (не внутри стены, дерева, камня).
func _fits(pos: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), pos + Vector3.UP * 0.95)
	q.collision_mask = 2
	return main.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Кто-то из игроков видит точку (в кадре камеры и ближе far_d) — там появляться нельзя.
## Игроки по сети — по направлению взгляда (конус ~140°).
func _visible(pos: Vector3, far_d: float) -> bool:
	var cam: Camera3D = main.player.cam
	if cam.global_position.distance_to(pos) <= far_d and cam.is_position_in_frustum(pos + Vector3.UP * 1.0):
		return true
	if Net.active():
		for rp: Node3D in Net.inst.remotes.values():
			var to := pos - rp.global_position
			if to.length() <= far_d and (-rp.global_basis.z).dot(Vector3(to.x, 0.0, to.z).normalized()) > 0.35:
				return true
	return false


# --- биомные ---------------------------------------------------------------------

func _cell(c: Vector2i) -> Dictionary:
	if not _cells.has(c):
		_cells[c] = {"alive": 0, "killed": 0, "respawn": 0.0}
	return _cells[c]


## Квота клетки: в глуши 0–1 днём / 1–2 ночью, в городе (много участков) больше.
func _cell_cap(c: Vector2i, night: bool) -> int:
	var h := absi(hash([c, 4242])) % 1000 / 1000.0
	if not _cell_lots.has(c):
		var roads: RoadNet = main.settlement.roads
		var cnt := 0
		if roads != null:
			for l: Dictionary in roads.lots_in(c.x * CELL, (c.x + 1) * CELL, c.y * CELL, (c.y + 1) * CELL):
				if String(l["btype"]) != "":
					cnt += 1
		_cell_lots[c] = cnt
	var lots: int = _cell_lots[c]
	var cap := (1 if h < 0.55 else 0) if not night else (2 if h < 0.4 else 1)
	if lots >= 3:
		cap += 2 if night else 1
	return cap


func _biome_tick(pl: Node3D, night: bool, now: float, alive: int) -> void:
	if alive >= (BIOME_MAX_NIGHT if night else BIOME_MAX_DAY):
		return
	var pp := pl.global_position
	var c0 := Vector2i(floori(pp.x / CELL), floori(pp.z / CELL))
	var cands: Array[Vector2i] = []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := c0 + Vector2i(dx, dz)
			var st := _cell(c)
			if int(st["killed"]) > 0 and now >= float(st["respawn"]):
				st["killed"] = 0
			if _cell_cap(c, night) - int(st["alive"]) - int(st["killed"]) > 0:
				cands.append(c)
	if cands.is_empty():
		return
	var c: Vector2i = cands.pick_random()
	for attempt in 6:
		var x := (c.x + randf()) * CELL
		var z := (c.y + randf()) * CELL
		var d := Vector2(x - pp.x, z - pp.z).length()
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		var y := _ground(x, z)
		if is_nan(y):
			continue
		var p := Vector3(x, y + 0.2, z)
		if _visible(p, 80.0) or not _fits(p):
			continue
		var zb := _make("biome", p)
		zb.home = c
		_cell(c)["alive"] = int(_cell(c)["alive"]) + 1
		return


# --- спящие в зданиях -------------------------------------------------------------

func _sleeper_tick(pl: Node3D, alive: int) -> void:
	var roads: RoadNet = main.settlement.roads
	if roads == null:
		return
	var spots: Array[Vector2] = []
	for p: Node3D in players():
		if is_instance_valid(p):
			spots.append(Vector2(p.global_position.x, p.global_position.z))
	if spots.is_empty():
		spots.append(Vector2(pl.global_position.x, pl.global_position.z))
	# ушли от здания все игроки — спящие (и не гонящиеся) уходят; при возвращении появятся снова
	for key: String in _active_bld.keys():
		var bc := _active_bld[key] as Vector2
		var near := false
		for s in spots:
			near = near or s.distance_to(bc) <= SLEEPER_R * 2.2
		if not near:
			_active_bld.erase(key)
			for z: Zombie in get_children():
				if z.kind == "sleeper" and z.home_key == key and not z.dead and z.state != Zombie.S.CHASE:
					z.queue_free()
	if alive >= SLEEPER_MAX:
		return
	for p2 in spots:
		for lot: Dictionary in roads.lots_in(p2.x - SLEEPER_R, p2.x + SLEEPER_R, p2.y - SLEEPER_R, p2.y + SLEEPER_R):
			if String(lot["btype"]) == "":
				continue
			var c: Vector2 = lot["pos"]
			if c.distance_to(p2) > SLEEPER_R:
				continue
			var key := Settlement.building_key(c)
			if _active_bld.has(key):
				continue
			var n := _place_sleepers(lot, key, Vector3(p2.x, pl.global_position.y, p2.y))
			if n >= 0:
				_active_bld[key] = c
				alive += n
				if alive >= SLEEPER_MAX:
					return


## Спящие в здании: на зонах спавна (блоки-зоны из редактора структур, у каждой свой цвет) — по зомби случайного
## типа на зону, минус уже убитые. Здание без зон: в POI — как раньше (случайно на первом этаже), иначе никого.
## -1 — здание ещё не построено (попробовать позже).
func _place_sleepers(lot: Dictionary, key: String, pp: Vector3) -> int:
	if not Settlement.keeps_lot(lot) or String(lot["btype"]) == "park":
		return 0
	var bb := Settlement.live_building(key)
	if bb == null or not bb.is_ready():
		return -1
	var spots := bb.marker_spots("spawn")
	if spots.is_empty():
		return _place_random_sleepers(lot, key, pp) if bool(lot.get("poi", false)) else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, 778])
	for i in range(spots.size() - 1, 0, -1):      # порядок — по зданию (убитые не возвращаются с тех же зон)
		var j := rng.randi_range(0, i)
		var t: Variant = spots[i]
		spots[i] = spots[j]
		spots[j] = t
	var placed := 0
	for i in range(int(sleepers_killed.get(key, 0)), spots.size()):
		var p: Vector3 = spots[i]["pos"]
		if p.distance_to(pp) < 2.5:
			continue      # игрок стоит прямо на зоне
		var zb := _make("sleeper", p)
		zb.home_key = key
		zb.wake_color = String(spots[i]["color"])
		zb.feral = false
		zb.sleep()
		placed += 1
	return placed


## Триггерная зона цвета color в здании key: проснуться всем спящим зомби этого цвета в нём (и заметить игрока).
static func trigger(key: String, color: String, who: Node3D) -> void:
	if inst == null or not inst.enabled or Net.is_client():
		return
	for z: Zombie in inst.get_children():
		if not z.dead and z.home_key == key and z.wake_color == color and z.state == Zombie.S.SLEEP:
			z.wake_by_trigger(who)


## Здание POI без зон спавна: спящие случайно на первом этаже, число по площади.
func _place_random_sleepers(lot: Dictionary, key: String, pp: Vector3) -> int:
	var hx: float = lot["hx"]
	var hz: float = lot["hz"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, 777])
	var want := clampi(int(hx * hz * 4.0 / 50.0) + rng.randi_range(0, 1), 1, 4)
	if String(lot["btype"]) in ["silo", "gas_canopy"]:
		want = rng.randi_range(0, 1)
	want -= int(sleepers_killed.get(key, 0))
	var c: Vector2 = lot["pos"]
	var floor_y: float = float(lot["plateau"]) + 0.06
	var rot: float = -float(lot["rot"])
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var found_floor := false
	var placed := 0
	for attempt in want * 10:
		if placed >= want:
			break
		var lo := Vector3(rng.randf_range(-1.0, 1.0) * maxf(0.5, hx - 2.5), 0.0, rng.randf_range(-1.0, 1.0) * maxf(0.5, hz - 2.5)).rotated(Vector3.UP, rot)
		var top := Vector3(c.x + lo.x, floor_y + 1.7, c.y + lo.z)
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 2.2, 2)
		var h := space.intersect_ray(q)
		if h.is_empty() or not (h["collider"] as Object).has_meta("block_building"):
			continue
		found_floor = true
		var p: Vector3 = h["position"] + Vector3.UP * 0.05
		if p.distance_to(pp) < 6.0 or not _fits(p):
			continue
		var zb := _make("sleeper", p)
		zb.home_key = key
		zb.feral = false
		zb.sleep()
		placed += 1
	if not found_floor and want > 0:
		return -1
	return placed


# --- бродячие орды ---------------------------------------------------------------

func _horde_tick(pl: Node3D, night: bool, alive: int) -> void:
	_horde_t -= TICK
	if _horde_t > 0.0:
		return
	var day_len: float = main.day_length
	if alive > 0 or randf() > 0.6:
		_horde_t = day_len * randf_range(0.17, 0.3)    # следующая проверка через 4–7 игровых часов
		return
	var pp := pl.global_position
	var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var center := pp + dir * randf_range(70.0, 85.0)
	if is_nan(_ground(center.x, center.z)):
		_horde_t = 5.0    # там ещё нет ландшафта — попробовать позже
		return
	# идут через место игрока и дальше (мимо, если не заметят)
	var side := dir.cross(Vector3.UP) * randf_range(-15.0, 15.0)
	var goal := pp - dir * 70.0 + side
	var n := mini(randi_range(5, 8) if night else randi_range(4, 6), HORDE_MAX)
	var made := 0
	for i in n * 3:
		if made >= n:
			break
		var x := center.x + randf_range(-6.0, 6.0)
		var z := center.z + randf_range(-6.0, 6.0)
		var y := _ground(x, z)
		if is_nan(y):
			continue
		var p := Vector3(x, y + 0.2, z)
		if not _fits(p):
			continue
		var zb := _make("horde", p)
		zb.state = Zombie.S.HORDE
		zb.target = goal + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		made += 1
	_horde_t = day_len * randf_range(0.17, 0.3)


# --- кровавая луна ----------------------------------------------------------------

## Каждая 7-я ночь: с 22:00 дня 7, 14, 21... до 04:00 следующего дня.
func is_blood_moon() -> bool:
	var d: int = main.day
	var tod: float = main.time_of_day
	return (d % 7 == 0 and tod >= 22.0 / 24.0) or (d % 7 == 1 and d > 1 and tod < 4.0 / 24.0)


func _blood_moon_tick(pl: Node3D, alive: int) -> void:
	var on := is_blood_moon()
	if on and not _blood:
		_blood = true
		var day: int = main.day
		_blood_budget = clampi(12 + (day / 7 - 1) * 6, 12, 48)   # с каждой луной орда больше
		_blood_t = 3.0
		main.player.call("_toast", "Кровавая луна! Орда идёт", 5.0)
		Net.toast_all("Кровавая луна! Орда идёт")
	elif not on and _blood:
		_blood = false
		for z: Zombie in get_children():
			z.blood_moon = false     # рассвет: уцелевшие становятся обычными
		main.player.call("_toast", "Рассвет — орда отступила", 4.0)
		Net.toast_all("Рассвет — орда отступила")
	if not _blood or _blood_budget <= 0 or alive >= BLOOD_MAX:
		return
	_blood_t -= TICK
	if _blood_t > 0.0:
		return
	var pp := pl.global_position
	for attempt in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var p := pp + dir * randf_range(28.0, 45.0)
		var y := _ground(p.x, p.z)
		if is_nan(y):
			continue
		p.y = y + 0.2
		if (attempt < 6 and _visible(p, 60.0)) or not _fits(p):
			continue
		var zb := _make("blood", p)
		zb.blood_moon = true
		zb.player = pl
		zb.state = Zombie.S.CHASE
		zb.target = pp
		_blood_budget -= 1
		_blood_t = randf_range(1.5, 3.5)
		return


func clear() -> void:
	for z in get_children():
		z.queue_free()
	_cells.clear()
	_active_bld.clear()
