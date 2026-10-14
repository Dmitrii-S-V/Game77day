extends Node3D
## Точка входа: окружение, ландшафт, игрок, HUD.
## Мир берётся из меню (Game.world). Отладка без меню: godot --path . -- --shot=C:/path/out.png --view=ground|aerial|dig|town|street|forest [--size=1024 --seed=1 ...]

var world: WorldMap
var terrain: Terrain
var veg: Vegetation
var settlement: Settlement
var far: FarTerrain
var far_props: FarProps
var grass: GrassField
var atlas: RoadAtlas
var player: Player
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var moon: DirectionalLight3D
var shadows_on := true            # тени по настройкам графики (GraphicsSettings)
var post_layer: CanvasLayer        # плёночный постэффект
var _gfx_panel: PanelContainer
var water: MeshInstance3D
var hud: Label

var time_of_day := 0.32   # 0..1; 0.25 рассвет, 0.5 полдень, 0.75 закат
var day_length := 900.0   # секунд на сутки
var day := 1               # номер дня (растёт в полночь)
var zombies: ZombieDirector
const ZOMBIES_ON := true    # зомби в обычной игре
var _autosave_t := 180.0
var _clock: Label

var _spawn_pos := Vector3.ZERO
var _street_yaw := 0.0
var _spawned := false
var _hud_t := 0.0
var _boot_ms := 0
var _shot_path := ""
var _shot_view := "ground"
var _shot_btype := "house"
var _shot_select := -1
var _shot_act := ""
var _interior_lot := Vector2.ZERO
var _pos_arg := Vector2(-1, -1)
var _near_t := 0.0
var _alt_arg := 0.0
var _pitch_arg := -9.0
var _yaw_arg := -9.0
var _burn := 0.0                     # сглаженная выжженность вокруг игрока 0..1 (дымка, цвет неба, пепел)
var _ash: GPUParticles3D
var _embers: GPUParticles3D
var _tod_arg := -1.0               # --tod=0..1: время суток для скриншотов (0.9 — ночь)
var _perf_s := 0.0                # --perf=N: пролёт N секунд над картой с замером кадров и подсистем
var _perf_t := 0.0
var _perf_frames := PackedFloat32Array()
var _perf_sub := PackedInt32Array()
var _perf_subnames := ["terrain", "veg", "grass", "settle", "far", "farprops", "atlas"]
var _spike_ms := 25.0              # --spike=N: печатать кадры дольше N мс
var _perf_run := false             # --perfmode=run: бег по земле с покачиванием камеры
var _perf_still := false           # --perfmode=still: замер на месте (без пролёта) + статистика рендера
var _perf_mon := PackedFloat64Array()
var _tskip := 0                      # --tskip=N: perf_skip шейдера ландшафта (отладка стоимости)
var _hide := PackedStringArray()    # --hide=terrain,veg,grass,settle,far,farprops,water: спрятать подсистемы (поиск дорогого в рендере)
var _test_bb: BlockBuilding
var _prefab_center := Vector3.ZERO
var _walk_dir := Vector3.ZERO
var _shot_state := 0
var _shot_wait := 0.0
var _nofar := false                # --nofar=1: скрыть дальний ландшафт (отладка стыков)
var _net_client := false           # сетевая игра: этот игрок — клиент (мир и зомби у хоста)
var _net_msg := ""                 # сообщение о сервере (показать, когда игрок появится)
var _aw_t := 0.0


func _ready() -> void:
	var params := WorldParams.new()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"shot": _shot_path = kv[1]
			"view": _shot_view = kv[1]
			"btype": _shot_btype = kv[1]
			"prefab": Game.test_prefab = kv[1]
			"perf": _perf_s = float(kv[1])
			"tod": _tod_arg = float(kv[1])
			"nofar": _nofar = kv[1] == "1"
			"spike": _spike_ms = float(kv[1])
			"perfmode":
				_perf_still = kv[1] == "still"
				_perf_run = kv[1] == "run"
			"hide": _hide = kv[1].split(",")
			"tskip": _tskip = int(kv[1])
			"pitch": _pitch_arg = float(kv[1])
			"alt": _alt_arg = float(kv[1])
			"pos": _pos_arg = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1]))
			"yaw": _yaw_arg = float(kv[1])
			"select": _shot_select = int(kv[1])
			"act": _shot_act = kv[1]
			"day": day = int(kv[1])
			"size": params.size = int(kv[1])
			"seed": params.seed_value = int(kv[1])
			"towns": params.towns = int(kv[1])
			"pois": params.pois = int(kv[1])
			"rivers": params.rivers = int(kv[1])
			"lakes": params.lakes = int(kv[1])
	_boot_ms = Time.get_ticks_msec()
	if _tod_arg >= 0.0:
		time_of_day = _tod_arg

	if OS.get_cmdline_user_args().has("--loadsave"):
		Game.pending_save = SaveGame.read()   # отладка: загрузить сохранение без меню
	world = Game.world
	if world == null:
		# запуск без меню (отладка): генерируем мир по умолчанию
			world = Game.world
	if world == null:
		# запуск без меню (отладка): генерируем мир по умолчанию
		world = WorldMap.new()
		await world.generate(params)
		print("World: ", world.info)
		print("World generated in %.1f s" % ((Time.get_ticks_msec() - _boot_ms) / 1000.0))

	(get_tree().get_first_node_in_group("minimap") as Minimap).setup(world)   # карта сама переезжает в свой слой выше HUD

	_setup_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.gen = WorldGen.new(world)
	terrain.material = _make_terrain_material()
	atlas = RoadAtlas.new()
	atlas.name = "RoadAtlas"
	add_child(atlas)
	atlas.setup(world.roads, terrain.gen)
	atlas.apply_to(terrain.material)
	add_child(terrain)

	veg = Vegetation.new()
	veg.name = "Vegetation"
	veg.terrain = terrain
	add_child(veg)
	terrain.edited.connect(veg.on_edited)

	grass = GrassField.new()
	grass.name = "Grass"
	grass.terrain = terrain
	add_child(grass)
	terrain.edited.connect(grass.on_edited)

	far = FarTerrain.new()
	far.name = "FarTerrain"
	add_child(far)
	var far_mat := _make_far_material()
	far_mat.set_shader_parameter("biome_mask", world.biome.tex)
	far_mat.set_shader_parameter("biome_world", float(world.size))
	far_mat.set_shader_parameter("has_biome", true)
	terrain.material.set_shader_parameter("biome_mask", world.biome.tex)
	terrain.material.set_shader_parameter("biome_world", float(world.size))
	terrain.material.set_shader_parameter("has_biome", true)
	var ov := RoadOverview.build(world.roads, world.size)
	far_mat.set_shader_parameter("road_mask", ov["tex"])
	far_mat.set_shader_parameter("road_ppm", ov["ppm"])
	far_mat.set_shader_parameter("road_px", float(ov["px"]))
	far_mat.set_shader_parameter("has_roads", true)
	far.setup(world, far_mat)
	far.visible = not _nofar

	far_props = FarProps.new()
	far_props.name = "FarProps"
	add_child(far_props)
	far_props.veg = veg
	far_props.setup(terrain.gen)

	settlement = Settlement.new()
	settlement.name = "Settlement"
	add_child(settlement)
	settlement.setup(terrain)
	terrain.edited.connect(settlement.on_edited)

	_spawn_pos = terrain.gen.spawn_point()
	if _shot_view == "forest":
		_spawn_pos = terrain.gen.find_forest_spot(Vector2(_spawn_pos.x + 120.0, _spawn_pos.z), 14)
	elif _shot_view == "lake" and not world.hydro.lakes.is_empty():
		var lk: Dictionary = world.hydro.lakes[0]
		var lc: Vector2 = lk["center"]
		var sx := lc.x + float(lk["R"]) * 1.7
		_spawn_pos = Vector3(sx, terrain.gen.height_at(sx, lc.y) + 2.0, lc.y)
		_street_yaw = PI * 0.5
	elif _shot_view == "burn":
		var bm: BiomeMap = world.biome
		var best_d := 1e18
		var bp := Vector2(world.size * 0.5, world.size * 0.5)
		var cellm := float(world.size) / bm.px
		for j in bm.px:
			for i in bm.px:
				if bm.burn[i + j * bm.px] > 0.995:
					var wp := Vector2((i + 0.5) * cellm, (j + 0.5) * cellm)
					var d := wp.distance_to(Vector2(_spawn_pos.x, _spawn_pos.z))
					if d < best_d:
						best_d = d
						bp = wp
		_spawn_pos = Vector3(bp.x, terrain.gen.height_at(bp.x, bp.y) + 2.0, bp.y)
		_street_yaw = 0.6
		_burn = 1.0
		print("burn view at ", bp, " dist from spawn ", best_d, " coverage ", bm.coverage)
	elif _shot_view == "river" and not world.hydro.rivers.is_empty():
		# самая длинная река: камера над серединой, взгляд вдоль течения
		var best: Dictionary = world.hydro.rivers[0]
		for rv: Dictionary in world.hydro.rivers:
			if (rv["pts"] as PackedVector2Array).size() > (best["pts"] as PackedVector2Array).size():
				best = rv
		var rp: PackedVector2Array = best["pts"]
		var mi := rp.size() / 2
		if _shot_select >= 0:
			mi = clampi(rp.size() * (_shot_select % 10) / 10, 2, rp.size() - 3)
		var rd := (rp[mi + 1] - rp[mi - 1]).normalized()
		var rs := rp[mi] - rd * 40.0
		_spawn_pos = Vector3(rs.x, terrain.gen.height_at(rs.x, rs.y) + 2.0, rs.y)
		_street_yaw = atan2(-rd.x, -rd.y)
	elif _shot_view == "hogweed":
		# заросли борщевика рядом со стартом (тот же шум, что в GrassField._wild_job): стоим в 9 м, смотрим на них
		var g := terrain.gen
		var bd2 := INF
		for iz in range(-80, 81):
			for ix in range(-80, 81):
				var wx := _spawn_pos.x + ix * 4.0
				var wz := _spawn_pos.z + iz * 4.0
				if g._forest.get_noise_2d(wx * 4.0 + 900.0, wz * 4.0 - 300.0) < 0.62 or world.biome.burn_at(wx, wz) > 0.3 \
						or world.road_dist(wx, wz) < 6.0 or world._town_weight(wx, wz) > 0.0 or g.height_at(wx, wz) < WorldGen.WATER_LEVEL + 3.0:
					continue
				var d := Vector2(ix, iz).length()
				if d < bd2:
					bd2 = d
					var p := Vector2(wx - 9.0, wz)
					_spawn_pos = Vector3(p.x, g.height_at(p.x, p.y) + 2.0, p.y)
					_street_yaw = -PI * 0.5      # смотреть на +X
	elif _shot_view == "road":
		# загородная дорога рядом со стартом: стоим на обочине, смотрим вдоль дороги
		var seg := world.roads._seg
		var bd := INF
		for q in range(0, seg.size(), RoadNet.SS):
			if int(seg[q + RoadNet.F_TOWN]) != 0:
				continue
			var a := Vector2(seg[q], seg[q + 1])
			var bb2 := Vector2(seg[q + 3], seg[q + 4])
			var mid := (a + bb2) * 0.5
			var d := mid.distance_to(Vector2(_spawn_pos.x, _spawn_pos.z))
			if d > 250.0 and d < bd and world._town_weight(mid.x, mid.y) < 0.01:
				bd = d
				var dirv := (bb2 - a).normalized()
				var side := Vector2(-dirv.y, dirv.x) * (seg[q + RoadNet.F_HW] + 1.5)
				var p := mid + side
				_spawn_pos = Vector3(p.x, terrain.gen.height_at(p.x, p.y) + 2.0, p.y)
				_street_yaw = atan2(-dirv.x, -dirv.y)
	elif _shot_view == "walk":
		var lot := _find_lot(_shot_btype)
		if not lot.is_empty():
			var lc: Vector2 = lot["pos"]
			var rot: float = lot["rot"]
			var ux := Vector2(cos(rot), sin(rot))
			var fz := Vector2(-ux.y, ux.x)
			var hzz: float = lot["hz"]
			var st := lc + fz * (hzz + 2.5) + ux * 2.0
			_spawn_pos = Vector3(st.x, float(lot["plateau"]) + 0.3, st.y)
			_street_yaw = atan2(fz.x, fz.y)
			_walk_dir = Vector3(-fz.x, 0.0, -fz.y)
	elif _shot_view == "chop":
		var lot := _find_lot(_shot_btype)
		if not lot.is_empty():
			var lc: Vector2 = lot["pos"]
			var rot: float = lot["rot"]
			var fz := Vector2(-sin(rot), cos(rot))
			var hzz: float = lot["hz"]
			var st := lc + fz * (hzz + 0.2)
			_spawn_pos = Vector3(st.x, float(lot["plateau"]) + 0.3, st.y)
			_street_yaw = atan2(fz.x, fz.y)
	elif _shot_view == "house" or _shot_view == "interior":
		var lot := _find_lot(_shot_btype)
		if not lot.is_empty():
			var lc: Vector2 = lot["pos"]
			var rot: float = lot["rot"]
			var ux := Vector2(cos(rot), sin(rot))
			var fz := Vector2(-ux.y, ux.x)   # фасад (+Z здания) смотрит вдоль fz
			var gy := float(lot["plateau"]) + 0.06
			if _shot_view == "house":
				var off := lc + fz * 20.0
				_spawn_pos = Vector3(off.x, gy + 8.0, off.y)
				_street_yaw = atan2(fz.x, fz.y)
			else:
				var off2 := lc + fz * 9.0
				_spawn_pos = Vector3(off2.x, gy + 10.0, off2.y)
				_street_yaw = atan2(fz.x, fz.y)
				_interior_lot = lc
	elif _shot_view == "cross":
		var t := _best_town()
		if not t.is_empty():
			var c: Vector2 = t["center"]
			var a: float = t["angle"]
			var along := Vector2(cos(a), sin(a))
			_street_yaw = atan2(along.x, along.y)
			_spawn_pos = Vector3(c.x + along.x * 22.0, float(t["plateau"]) + 2.0, c.y + along.y * 22.0)
	elif _shot_view == "pile":
		var t := _best_town()
		if not t.is_empty():
			var c: Vector2 = t["center"]
			var ccx := floori(c.x / 16.0)
			var ccz := floori(c.y / 16.0)
			for dz in range(-8, 9):
				for dx in range(-8, 9):
					if _spawn_pos != Vector3.ZERO and _street_yaw != 0.0:
						break
					for lt: Dictionary in terrain.gen.world.roads.litter_in_column(ccx + dx, ccz + dz):
						if lt["kind"] == "pile":
							var pp: Vector2 = lt["pos"]
							_spawn_pos = Vector3(pp.x, terrain.gen.height_at(pp.x, pp.y) + 2.5, pp.y + 1.8)
							_street_yaw = PI
							break
	elif _shot_view == "street" or _shot_view == "roaddig":
		var t := _best_town()
		if not t.is_empty():
			var c: Vector2 = t["center"]
			var a: float = t["angle"]
			var along := Vector2(cos(a), sin(a))
			_street_yaw = atan2(-along.x, -along.y)
			_spawn_pos = Vector3(c.x - along.x * 45.0, float(t["plateau"]) + 2.0, c.y - along.y * 45.0)
	if _pos_arg.x >= 0.0:
		_spawn_pos = Vector3(_pos_arg.x, terrain.gen.height_at(_pos_arg.x, _pos_arg.y) + 2.0, _pos_arg.y)
	# загрузка сохранения: изменения мира — до начала стриминга чанков; новая игра — чистые списки
	var save_d: Dictionary = Game.pending_save
	Game.pending_save = {}
	_net_client = bool(save_d.get("net_client", false))
	if _net_client:
		# сетевая игра, клиент: правки мира от хоста; появляемся рядом с хостом
		SaveGame.apply_world(self, save_d)
		var hp: Vector3 = save_d["spawn"]
		var off := Vector2.from_angle(randf() * TAU) * 2.5
		_spawn_pos = Vector3(hp.x + off.x, hp.y + 1.0, hp.z + off.y)
	elif not save_d.is_empty():
		SaveGame.apply_world(self, save_d)
		_spawn_pos = save_d["player"]["pos"]
	else:
		Vegetation.removed.clear()
		GrassField.cut.clear()
		Gear.reset()
		Loot._looted.clear()
		ZombieDirector.sleepers_killed.clear()
	player = Player.new()
	player.name = "Player"
	player.terrain = terrain
	player.position = _spawn_pos
	add_child(player)
	player.set_physics_process(false)
	player.spawn_point = _spawn_pos
	var inv_ui := InventoryUI.new()
	inv_ui.name = "InventoryUI"
	add_child(inv_ui)
	inv_ui.setup(player.inventory)
	player.UI = inv_ui
	if TouchControls.wanted():
		var tcl := TouchControls.new()
		tcl.name = "TouchControls"
		tcl.player = player
		tcl.main = self
		add_child(tcl)
		tcl.fire_pressed.connect(player._on_touch_fire)
	if DynamicRes.wanted():
		var dr := DynamicRes.new()
		dr.name = "DynamicRes"
		add_child(dr)
	if not save_d.is_empty() and not _net_client:
		SaveGame.apply_player(player, save_d)
	# звуковой фон и зомби (в отладочных снимках/замерах зомби только с --zombies=1)
	var amb := Ambience.new()
	amb.name = "Ambience"
	amb.main = self
	add_child(amb)
	zombies = ZombieDirector.new()
	zombies.name = "Zombies"
	zombies.main = self
	# зомби временно выключены (по просьбе); включить: ZOMBIES_ON = true или аргумент --zombies=1
	zombies.enabled = (ZOMBIES_ON and _shot_path == "" and _perf_s <= 0.0) or OS.get_cmdline_user_args().has("--zombies=1")
	if _net_client:
		zombies.enabled = false     # зомби живут у хоста, здесь — их марионетки (Net._zsnap)
	add_child(zombies)
	# сетевая игра: хост открывает сервер, клиент получает накопленные правки мира
	if Game.net_host and not _net_client:
		Game.net_host = false
		var err := Net.ensure(get_tree()).host(Net.PORT)
		if err == OK:
			_net_msg = "Сервер открыт: порт %d, IP %s" % [Net.PORT, ", ".join(Net.local_ips())]
		else:
			_net_msg = "Не удалось открыть сервер (порт %d занят?)" % Net.PORT
	if Net.active():
		Net.inst.attach(self)
		if _net_client:
			Zombie.preload_model()
	# всё, что иначе грузилось бы с диска посреди игры (разовые фризы): звуки, модель зомби
	Sfx.preload_all()
	if zombies.enabled:
		Zombie.preload_model()
	# графика: в обычной игре — из настроек; в отладочных снимках/замерах — по --gfx=0..3 (иначе как раньше)
	var gfx_arg := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gfx="):
			gfx_arg = int(a.substr(6))
		elif a.begins_with("--pom="):
			GraphicsSettings.load_settings()
			GraphicsSettings.pom = a.substr(6) == "1"
			if gfx_arg < 0:
				gfx_arg = GraphicsSettings.MED
	if gfx_arg >= 0:
		GraphicsSettings.level = gfx_arg
		GraphicsSettings._loaded = true
		GraphicsSettings.apply_world(self)
	elif _shot_path == "" and _perf_s <= 0.0:
		GraphicsSettings.apply_world(self)
	if _shot_path != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_setup_hud()
	if OS.get_cmdline_user_args().has("--noterrain"):
		terrain.visible = false
	terrain.update_view(_spawn_pos)


func _process(delta: float) -> void:
	var tod_new := time_of_day + (0.0 if time_paused else delta / day_length)
	if tod_new >= 1.0:
		day += 1   # полночь — новый день
	time_of_day = fposmod(tod_new, 1.0)
	_update_clock()
	_aw_t -= delta
	if _aw_t <= 0.0 and player != null and player.UI != null:
		_aw_t = 0.15
		player.UI.set_awareness(_awareness())
	if _spawned and _shot_path == "" and _perf_s <= 0.0 and not _net_client:
		_autosave_t -= delta
		if _autosave_t <= 0.0:
			_autosave_t = 180.0
			save_game("Автосохранение")
	if player != null:
		_burn = lerpf(_burn, world.biome.burn_at(player.position.x, player.position.z), 1.0 - exp(-delta * 0.5))
		_update_burn_fx()
	_update_sky()
	FrameBudget.begin()
	var t0 := Time.get_ticks_usec()
	terrain.update_view(player.position)
	var t1 := Time.get_ticks_usec()
	veg.update_view(player.position)
	var t2 := Time.get_ticks_usec()
	grass.update_view(player.position)
	var t3 := Time.get_ticks_usec()
	settlement.update_view(player.position)
	var t4 := Time.get_ticks_usec()
	far.update_view(player.position, delta)
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.2
		far.set_near_radius(maxf(terrain.safe_radius(player.position) - 6.0, 0.0))
	var t5 := Time.get_ticks_usec()
	far_props.update_view(player.position, delta)
	var t6 := Time.get_ticks_usec()
	atlas.update_view(player.position, delta)
	if _perf_s > 0.0:
		_perf_record(delta, [t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4, t6 - t5, Time.get_ticks_usec() - t6])
	water.position = Vector3(player.position.x, WorldGen.WATER_LEVEL, player.position.z)
	var lim := float(world.size) - 6.0
	player.position.x = clampf(player.position.x, 6.0, lim)
	player.position.z = clampf(player.position.z, 6.0, lim)

	if not _spawned and terrain.is_ready_around(_spawn_pos, 1) and atlas.is_ready_around(_spawn_pos, 2):
		_spawned = true
		player.set_physics_process(true)
		if _net_msg != "":
			player._toast(_net_msg, 10.0)
		if Game.test_prefab != "":
			_place_test_prefab(Game.test_prefab)
		print("Spawn ready in %.1f s" % ((Time.get_ticks_msec() - _boot_ms) / 1000.0))
		if OS.get_cmdline_user_args().has("--atmopanel=1"):
			AtmospherePanel.toggle(self)     # отладка: снимок с открытой панелью атмосферы
		if OS.get_cmdline_user_args().has("--blood=1"):
			atmo_force_blood = true
			_blood_k = 1.0
		if OS.get_cmdline_user_args().has("--nettest=1"):
			_net_autotest()
		if OS.get_cmdline_user_args().has("--bmtest=1"):
			_bm_autotest()
		if OS.get_cmdline_user_args().has("--findpark=1"):   # отладка: ближайшие парки к точке старта
			var sp := player.global_position
			var parks: Array = []
			for l: Dictionary in world.roads.lots_in(sp.x - 900.0, sp.x + 900.0, sp.z - 900.0, sp.z + 900.0):
				if String(l["btype"]) == "park":
					parks.append(l["pos"])
			parks.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(Vector2(sp.x, sp.z)) < b.distance_to(Vector2(sp.x, sp.z)))
			print("PARKS ", parks.slice(0, 5))
			# размеры участков по типам (во всём мире): сколько и какие (2hx-1 x 2hz-1 м — место под префаб)
			var sizes := {}
			var wsz := float(world.params.size) + 64.0
			for l: Dictionary in world.roads.lots_in(-64.0, wsz, -64.0, wsz):
				var bt := String(l["btype"])
				var k := "%s %dx%d" % [bt, roundi(2.0 * float(l["hx"]) - 1.0), roundi(2.0 * float(l["hz"]) - 1.0)]
				sizes[k] = int(sizes.get(k, 0)) + 1
			print("LOTSIZES ", sizes)
			# где стоят префабы из редактора (тот же выбор, что у Settlement)
			var placed := {}
			for l: Dictionary in world.roads.lots_in(-64.0, wsz, -64.0, wsz):
				var bt := String(l["btype"])
				if bt == "":
					continue
				var pf := PrefabRegistry.pick(bt, 2.0 * float(l["hx"]) - 1.0, 2.0 * float(l["hz"]) - 1.0, float(int(l["seed"]) % 1000) / 1000.0)
				if not pf.is_empty():
					var nm := String(pf["item"]["data"].get("name", "?"))
					if not placed.has(nm):
						placed[nm] = []
					(placed[nm] as Array).append(l["pos"])
			for nm: String in placed:
				print("PREFAB %s x%d: %s" % [nm, (placed[nm] as Array).size(), str((placed[nm] as Array).slice(0, 4))])

	_hud_t += delta
	if _hud_t > 0.25:
		_hud_t = 0.0
		var p := player.position
		hud.text = "FPS %d   pos %.0f %.0f %.0f   %s  plants %d\nWASD идти · Shift бег · Ctrl пригнуться · Space прыжок · F полёт · ЛКМ действие · ПКМ второе действие · R перезарядка · Q выбросить · E подобрать · Tab инвентарь · 1-8 слоты · F5 сохранить · F7 графика · F8 тест 7-й ночи · F10 меню" % [
			Engine.get_frames_per_second(), p.x, p.y, p.z, terrain.stats(), veg.count()]
		if TouchControls.active():
			hud.text = "FPS %d" % Engine.get_frames_per_second()    # телефон: без подсказок клавиш

	FrameBudget.reap()   # отложенное удаление выгруженных колонок/чанков — понемногу за кадр
	if _shot_path != "":
		_process_shot(delta)


## Автотест сети (--nettest=1, хост: --menu-host, клиент: --menu-join=127.0.0.1). Хост ставит зомби рядом
## с клиентом; клиент копает землю (правка мира) и убивает марионетку этого зомби; оба печатают NET-строки.
func _net_autotest() -> void:
	var spawned_near := false
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		if not Net.active():
			print("NET inactive")
			return
		var puppets := 0
		var dead := 0
		for z: Zombie in zombies.get_children():
			if z.puppet:
				puppets += 1
			if z.dead:
				dead += 1
		print("NET t=%d %s remotes=%d zombies=%d puppets=%d dead=%d edited=%d aw=%.0f kills=%d hp=%.0f" % [i, "host" if Net.is_host() else "client",
			Net.inst.remotes.size(), zombies.get_child_count(), puppets, dead, _edited_count(), _awareness(), Gear.kills, player.health])
		if Net.is_host() and not spawned_near and not Net.inst.remotes.is_empty() and (Net.inst.remotes.values()[0] as Node3D).global_position.y > 1.0:
			spawned_near = true
			await get_tree().create_timer(3.0).timeout
			var rp: Node3D = Net.inst.remotes.values()[0]
			for k in 3:
				var at := rp.global_position + Vector3(6.0 + k, 0.0, 3.0)
				var y := terrain.surface_y(at.x, at.z, terrain.gen.height_at(at.x, at.z))
				var zb := zombies._make("biome", Vector3(at.x, (y if not is_nan(y) else at.y) + 0.3, at.z))
				zb.rotation.y = atan2(rp.global_position.x - at.x, rp.global_position.z - at.z)
			print("NET host spawned 3 zombies near client")
		if Net.is_client() and i == 10:
			var p := player.global_position + Vector3(2.0, -0.5, 0.0)
			terrain.edit_sphere(p, 1.2, false)
			Net.op("terrain", [p, 1.2, false, WorldGen.MAT_DIRT])
			var best: Zombie = null
			for z: Zombie in zombies.get_children():
				if z.puppet and not z.dead and (best == null or z.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
					best = z
			if best != null:
				player._hit_zombie(best, 5000.0, Vector3(0, 0, 1), best.global_position + Vector3.UP, "pistol", 1)
				print("NET client hit puppet %d at %.1f m" % [best.net_id, best.global_position.distance_to(player.global_position)])
			else:
				print("NET client: no puppets to hit")


## Заметность своего игрока (шкала на экране): максимум по зомби, которые «чуют» именно его.
## У клиента — из снимков хоста.
func _awareness() -> float:
	if _net_client:
		return Net.inst.my_aw if Net.active() else 0.0
	var best := 0.0
	if zombies != null:
		for z: Zombie in zombies.get_children():
			if not z.dead and z.aw_target == player:
				best = maxf(best, z.awareness)
	return best


func _find_lot(btype: String) -> Dictionary:
	var best := {}
	var bd := INF
	var sp := Vector2(_spawn_pos.x, _spawn_pos.z)
	for t: Dictionary in world.roads.all_places():
		for l: Dictionary in t["lots"]:
			if String(l["btype"]) == btype:
				var d := (l["pos"] as Vector2).distance_to(sp)
				if d < bd:
					bd = d
					best = l
	return best


func _best_town() -> Dictionary:
	var best := {}
	var bd := INF
	for t: Dictionary in world.roads.towns:
		if int(t["tier"]) < 1:
			continue
		var d := (t["center"] as Vector2).distance_to(Vector2(_spawn_pos.x, _spawn_pos.z))
		if d < bd:
			bd = d
			best = t
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10 and _shot_path == "":
		save_game("")
		if Net.active():
			Net.inst.close()
		Game.back_to_menu()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5 and _shot_path == "":
		save_game("Игра сохранена")
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		AtmospherePanel.toggle(self)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		_toggle_gfx_panel()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8 and _shot_path == "":
		if _net_client:
			player._toast("Тест кровавой луны — только у хоста", 2.5)
		else:
			test_blood_moon()


## Тест 7-й ночи (F8): перемотка на ближайший 7-й день, 21:54 — через несколько секунд начнётся кровавая луна.
## Игроку — пистолет и патроны, зомби включаются.
func test_blood_moon() -> void:
	if zombies.is_blood_moon():
		player.call("_toast", "Кровавая луна уже идёт", 3.0)
		return
	day = maxi(7, ceili(day / 7.0) * 7)
	if day % 7 == 0 and time_of_day > 21.9 / 24.0:
		day += 7
	time_of_day = 21.9 / 24.0
	zombies.enabled = true
	Zombie.preload_model()
	if player.inventory.count("pistol") == 0:
		player.inventory.add("pistol", 1, {"mag": 12})
	player.inventory.add("ammo_9mm", 60)
	player.call("_toast", "Тест: день %d, 21:54 — кровавая луна через пару секунд" % day, 5.0)


## Автотест (--bmtest=1): F8 и выстрелы в голову ближайшему зомби каждые 0.5 с (смотреть вместе с --zlog=1).
func _bm_autotest() -> void:
	await get_tree().create_timer(3.0).timeout
	test_blood_moon()
	for i in Inventory.SIZE:
		var s: Variant = player.inventory.get_slot(i)
		if s != null and s["id"] == "pistol" and i < Inventory.HOTBAR:
			player.inventory.select(i)
	for i in 60:
		await get_tree().create_timer(0.5).timeout
		var best: Zombie = null
		for z: Zombie in zombies.get_children():
			if not z.dead and (best == null or z.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
				best = z
		if best != null and best.global_position.distance_to(player.global_position) < 30.0:
			var dv := best.global_position + Vector3.UP * 1.55 - player.cam.global_position
			player.set_look(atan2(-dv.x, -dv.z), atan2(dv.y, Vector2(dv.x, dv.z).length()))
			if not OS.get_cmdline_user_args().has("--bmnoshoot=1"):
				player._fire()
			var s2: Variant = player.inventory.selected_item()
			print("BM shot t=%.1f dist %.1f zhp %.0f dead %s mag %s ammo %d hp %.0f" % [i * 0.5, dv.length(), best.hp, best.dead,
				s2.get("mag") if s2 != null else "-", player.inventory.count("ammo_9mm"), player.health])


func _edited_count() -> int:
	var n := 0
	for cd: ChunkData in terrain._data.values():
		if cd.edited:
			n += 1
	return n


func _count_item(id: String) -> int:
	var n := 0
	for s: Variant in player.inventory.slots:
		if s != null and s["id"] == id:
			n += int(s["n"])
	return n


## Сохранить игру (слот 1); msg — подсказка игроку ("" — без подсказки).
func save_game(msg: String) -> void:
	if not _spawned or player == null or player._dead_t > 0.0:
		return
	if _net_client:
		if msg != "":
			player._toast("Сетевая игра: мир сохраняет хост", 2.0)
		return
	var ok := SaveGame.save(self)
	if msg != "":
		player._toast(msg if ok else "Ошибка сохранения", 2.0)


func _exit_tree() -> void:
	if Net.active() and Net.inst.main == self:
		Net.inst.detach()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _shot_path == "" and _perf_s <= 0.0:
		save_game("")


## F7: панель настроек графики поверх игры (применяется сразу, сохраняется).
func _toggle_gfx_panel() -> void:
	if _gfx_panel != null:
		_gfx_panel.queue_free()
		_gfx_panel = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_gfx_panel = PanelContainer.new()
	_gfx_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gfx_panel.position = Vector2(-300, -260)
	_gfx_panel.custom_minimum_size = Vector2(600, 0)
	_gfx_panel.tree_exited.connect(layer.queue_free)
	layer.add_child(_gfx_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_gfx_panel.add_child(box)
	var title := Label.new()
	title.text = "Графика"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	box.add_child(GraphicsSettings.make_details(func() -> void: GraphicsSettings.apply_world(self)))
	var hint := Label.new()
	hint.text = "Применяется сразу. F7 — закрыть."
	hint.modulate = Color(0.7, 0.75, 0.8)
	box.add_child(hint)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- скриншот-режим для автопроверки --------------------------------------

## "Проверить в мире": ставит префаб из реестра перед игроком у спавна (фасад к игроку), по высоте земли.
func _place_test_prefab(prefab_name: String) -> void:
	PrefabRegistry.reload()
	var item := PrefabRegistry.find(prefab_name)
	if item.is_empty():
		push_warning("Префаб не найден: " + prefab_name)
		return
	var grid := PrefabRegistry.grid_of(item)
	var sp := player.position
	var cx := sp.x
	var cz := sp.z - 13.0
	var hw := grid.nx * BlockGrid.B * 0.5
	var hd := grid.nz * BlockGrid.B * 0.5
	var top := -INF
	for dx in [-hw, 0.0, hw]:
		for dz in [-hd, 0.0, hd]:
			var h := terrain.gen.height_at(cx + dx, cz + dz)
			var sy := terrain.surface_y(cx + dx, cz + dz, h)
			top = maxf(top, h if is_nan(sy) else sy)
	_test_bb = BlockBuilding.new()
	_test_bb.position = Vector3(cx, top + 0.06 - grid.sink * BlockGrid.B, cz)
	add_child(_test_bb)
	_test_bb.setup(grid, settlement.block_material, settlement.glass_material)
	_prefab_center = _test_bb.position
	print("Prefab '%s' placed at %s" % [prefab_name, _prefab_center])


func _prefab_view() -> void:
	# ракурсы для скриншотов: 0 фасад, 1 сверху без крыши, 2 сбоку, 3 интерьер к задней стене, 4 интерьер к фасаду
	if _test_bb == null:
		return
	var c := _prefab_center
	player.flying = true
	match maxi(int(_shot_act), 0):
		0:
			player.position = c + Vector3(0.0, 2.2, 9.0)
			player.set_look(0.0, -0.12)
		1:
			_cut_roof()
			player.position = c + Vector3(0.0, 9.0, 4.0)
			player.set_look(0.0, -1.2)
		2:
			player.position = c + Vector3(-9.0, 2.4, 6.0)
			player.set_look(-0.95, -0.15)
		3:
			_cut_roof()
			player.position = c + Vector3(-0.8, 3.6, 3.2)
			player.set_look(0.0, -0.55)
		4:
			_cut_roof()
			player.position = c + Vector3(2.0, 3.4, -2.8)
			player.set_look(PI, -0.5)
		6:
			player.position = c + Vector3(0.0, 4.5, 10.0)
			player.set_look(0.0, -0.4)
		7:
			player.position = c + Vector3(-3.0, 1.8, 5.5)
			player.set_look(-0.45, -0.1)
		5:
			player.position = c + Vector3(1.0, 1.6, 2.6)
			player.set_look(0.0, 0.0)


func _cut_roof() -> void:
	var g := _test_bb.grid
	for z in g.nz:
		for y in range(g.ground_cells + 6, g.ny):
			for x in g.nx:
				g.set_cell(x, y, z, 0, 0)
	_test_bb.rebuild_all()


func _process_shot(delta: float) -> void:
	if _shot_state == 0 and _spawned and (_test_bb == null or _test_bb.is_ready()) and terrain.is_idle() and veg.is_idle() and grass.is_idle() and settlement.is_idle() and far.is_idle() and far_props.is_idle() and atlas.is_idle():
		_shot_state = 1
		_shot_wait = 99.0
		print("Terrain idle after %.1f s, %s, prefab buildings %d" % [(Time.get_ticks_msec() - _boot_ms) / 1000.0, terrain.stats(), Settlement.prefab_count])
		time_of_day = _tod_arg if _tod_arg >= 0.0 else 0.36
		match _shot_view:
			"aerial":
				player.flying = true
				player.position.y += 110.0
				player.position.z += 90.0
				player.set_look(0.0, -0.8)
			"town":
				player.flying = true
				player.position.y += 55.0
				player.position.z += 40.0
				player.set_look(0.0, -0.75)
			"map":
				# большая карта (для сравнения с видом сверху): --alt=<метров на экране>
				var pp := Vector2(player.global_position.x, player.global_position.z)
				Minimap.marks = [{"pos": pp + Vector2(60, -40), "color": Color(1.0, 0.25, 0.2), "n": 1}]
				(get_tree().get_first_node_in_group("minimap") as Minimap).debug_open(Vector2.ZERO, _alt_arg if _alt_arg > 0.0 else 700.0)
				_shot_wait = 2.0
			"street", "lake", "burn", "hogweed":
				if _alt_arg > 0.0:
					player.flying = true
					player.position.y += _alt_arg
				player.set_look(_street_yaw if _yaw_arg < -8.0 else _yaw_arg, -0.1 if _pitch_arg < -8.0 else _pitch_arg)
			"prefab":
				_prefab_view()
			"pile":
				player.set_look(_street_yaw, -0.45)
			"river":
				player.flying = true
				player.position.y += 22.0 if _shot_select < 10 else 110.0
				player.set_look(_street_yaw, -0.5 if _shot_select < 10 else -0.95)
			"walk":
				player.position = _spawn_pos
				player.set_look(_street_yaw, -0.05)
				await get_tree().physics_frame
				player.debug_dir = _walk_dir
				for i in 150:
					await get_tree().physics_frame
				player.debug_dir = Vector3.ZERO
				print("walk end ", player.position, " lot ", _spawn_pos)
			"chop":
				player.position = _spawn_pos
				player.set_look(_street_yaw, -0.08)
				player.inventory.select(0)
				await get_tree().physics_frame
				await get_tree().physics_frame
				for i in 90:
					player._melee()
					await get_tree().physics_frame
				player.position += Vector3(0, 0, 0)
				player.set_look(_street_yaw, -0.18)
			"house":
				player.position = _spawn_pos
				player.flying = true
				player.set_look(_street_yaw, -0.4)
			"interior":
				player.position = _spawn_pos
				player.flying = true
				player.set_look(_street_yaw, -1.55 if _shot_select >= 0 else -0.95)
				if _shot_select >= 0:
					player.position = Vector3(_interior_lot.x, _spawn_pos.y + 2.0, _interior_lot.y)
				for col: Node3D in settlement._cols.values():
					for ch in col.get_children():
						if ch is BlockBuilding and Vector2(ch.position.x, ch.position.z).distance_to(_interior_lot) < 2.0:
							(ch as BlockBuilding).debug_open_roof()
							# с --select: камера над туалетом (первым предметом здания)
							var props: Array = (ch as BlockBuilding)._props
							if _shot_select >= 0 and not props.is_empty():
								var tp: Vector3 = (props[0] as Node3D).global_position
								player.position = tp + Vector3(0.0, 5.0, 0.3)
								player.set_look(PI, -1.55)
			"cross":
				player.flying = true
				player.position.y += 5.0
				player.set_look(_street_yaw, -0.45)
			"roaddig":
				player.set_look(_street_yaw, -0.7)
				for i in 4:
					player.dig(2.0)
					await get_tree().physics_frame
				player.set_look(_street_yaw, -0.4)
			"shallowdig":
				# неглубокая пологая яма 7x5 м впереди (проверка дорожного покрытия на склонах и рваного края)
				var g := _spawn_pos.y - 2.0
				var fwd := Vector3(-sin(_yaw_arg if _yaw_arg > -8.0 else 0.0), 0.0, -cos(_yaw_arg if _yaw_arg > -8.0 else 0.0))
				var side := Vector3(fwd.z, 0.0, -fwd.x)
				for a in 4:
					for s in 3:
						var c := _spawn_pos + fwd * (4.0 + a * 1.8) + side * ((s - 1) * 1.8)
						terrain.edit_sphere(Vector3(c.x, g + 0.5, c.z), 1.5, false)
				await get_tree().create_timer(2.5).timeout
				player.flying = true
				player.position.y += _alt_arg if _alt_arg > 0.0 else 3.0
				player.set_look(_yaw_arg if _yaw_arg > -8.0 else 0.0, -0.75 if _pitch_arg < -8.0 else _pitch_arg)
			"pit":
				player.position = _spawn_pos
				for k in 14:
					terrain.edit_sphere(Vector3(_spawn_pos.x, _spawn_pos.y - 2.0 - k * 1.5, _spawn_pos.z), 2.2, false)
				await get_tree().create_timer(2.5).timeout
				player.flying = true
				player.position.y -= 0.0
				player.set_look(0.3, -0.9)
			"dig":
				player.set_look(0.0, -0.75)
				for i in 5:
					player.dig(2.2)
					await get_tree().physics_frame
				player.set_look(0.0, -0.45)
			_:
				player.set_look(0.0, -0.1)
		_shot_wait = 2.0
		if _shot_select >= 0:
			player.inventory.select(_shot_select)
		match _shot_act:
			"hitground":
				# тест прочности ландшафта: бьём в землю перед собой, печатаем hp и подпись под прицелом
				player.set_look(0.0, -0.9)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				await get_tree().physics_frame
				for k in 8:
					player._melee()
					player._update_hp_label(false)
					print("HITGROUND ", k + 1, " cells ", player._ground_hp, " label '", player._hp_label.text, "' visible ", player._hp_label.visible)
					await get_tree().create_timer(0.2).timeout
			"swing":
				player.hand.play("swing")
				_shot_wait = 0.27
			"drink":
				player.hand.play("drink")
				_shot_wait = 1.45
			"throw":
				player.hand.play("throw")
				_shot_wait = 0.9
			"throwlate":
				player.hand.play("throw")
				_shot_wait = 1.15
			"inv":
				player.ui.toggle()
				player.inventory.set_slot(5, {"id": "wood", "n": 12})
				player.inventory.set_slot(10, {"id": "stone", "n": 4})
				_shot_wait = 0.5
			"hold":
				_shot_wait = 0.6
			"hurt":
				for k in 3:
					var t0 := Time.get_ticks_usec()
					player.take_damage(1.0)
					print("HURT #%d take_damage %.1f ms" % [k, (Time.get_ticks_usec() - t0) / 1000.0])
					var f0 := Time.get_ticks_usec()
					await get_tree().process_frame
					await get_tree().process_frame
					print("HURT #%d next 2 frames %.1f ms" % [k, (Time.get_ticks_usec() - f0) / 1000.0])
					await get_tree().create_timer(0.7).timeout
			"savetest1":
				# тест сохранения, шаг 1: изменить мир и игрока, сохранить
				terrain.edit_sphere(player.global_position + Vector3(0, -1.0, 4.0), 1.6, false)
				player.hunger = 42.0
				player.inventory.add("berries", 7)
				day = 3
				time_of_day = 0.61
				Loot.mark_looted(Vector3(10, 20, 30))
				Vegetation.mark_removed(Vector3(100.0, 0.0, 200.0))
				await get_tree().create_timer(0.5).timeout
				print("SAVETEST1 saved ", SaveGame.save(self), " pos ", player.global_position, " edited chunks ", _edited_count())
			"savetest2":
				print("SAVETEST2 day ", day, " tod ", snappedf(time_of_day, 0.01), " hunger ", player.hunger, " berries ", _count_item("berries"),
					" looted ", Loot.is_looted(Vector3(10, 20, 30)), " plant removed ", Vegetation.removed.has(Vegetation.plant_key(100.0, 200.0)),
					" edited chunks ", _edited_count(), " pos ", player.global_position)
			"zwake":
				# тест слуха: громкий шум у игрока будит спящих в ближних зданиях (смотреть --zlog=1)
				_shot_wait = 99.0
				await get_tree().create_timer(12.0).timeout
				print("ZWAKE noise")
				ZombieDirector.noise(player.global_position, 60.0)
			"zombie":
				# тест зомби: один перед игроком в 7 м, удары дубиной
				_shot_wait = 99.0
				zombies.enabled = false
				var fwd := -player.global_basis.z
				var zp := player.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 7.0
				var zb := Zombie.new()
				zb.player = player
				zb.gen = terrain.gen
				zombies.add_child(zb)
				zb.global_position = Vector3(zp.x, terrain.surface_y(zp.x, zp.z, terrain.gen.height_at(zp.x, zp.z)) + 0.2, zp.z)
				player.inventory.select(2)
				await get_tree().create_timer(2.5).timeout
				print("ZOMBIE dist after 2.5s ", snappedf(zb.global_position.distance_to(player.global_position), 0.1), " player hp ", player.health)
				var tgt := zb.global_position + Vector3.UP * 1.2
				var dv := tgt - player.cam.global_position
				player.set_look(atan2(-dv.x, -dv.z), atan2(dv.y, Vector2(dv.x, dv.z).length()))
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				await get_tree().physics_frame
				player._melee()
				print("ZOMBIE hp after club hit ", zb.hp)
				_shot_wait = 0.2
			"hcx", "hcmx", "hcy", "hcmy":
				# крупный план кисти (отладка хвата): камера в системе руки — тыл (+X), ладонь (-X), сверху (+Y), снизу (-Y)
				await get_tree().create_timer(0.6).timeout
				var hc := Camera3D.new()
				hc.near = 0.005
				hc.fov = 40.0
				player.hand.add_child(hc)
				var tgt := Vector3(-0.02, 0.0, -0.07)
				var off: Vector3 = {"hcx": Vector3(0.32, 0.0, 0.0), "hcmx": Vector3(-0.32, 0.0, 0.0), "hcy": Vector3(0.0, 0.32, 0.0), "hcmy": Vector3(0.0, -0.32, 0.0)}[_shot_act]
				hc.position = tgt + off
				hc.look_at(player.hand.to_global(tgt), player.hand.global_basis * (Vector3.BACK if _shot_act in ["hcy", "hcmy"] else Vector3.UP))
				hc.make_current()
				_shot_wait = 0.4
			"loot", "rock":
				# тест: подойти к ближайшему мешку мусора / валуну, обыскать / добыть камень, напечатать результат
				var best: Node3D = null
				var bd := 1e9
				for n in get_tree().root.find_children("*", "Node3D", true, false):
					var ok: bool = n.has_meta("loot") if _shot_act == "loot" else (n.get_meta("kind", "") == "rock")
					if ok:
						var d := (n as Node3D).global_position.distance_to(player.global_position)
						if d < bd:
							bd = d
							best = n
				_shot_wait = 99.0
				if best == null:
					print("ACT ", _shot_act, ": target not found")
				else:
					var tp := best.global_position + Vector3(0, 0.25, 0)
					player.flying = true
					player.position = tp + Vector3(1.4, 0.0, 1.4) - Vector3(0, 1.62 - 0.9, 0)
					var dv := tp - (player.position + Vector3(0, 1.62, 0))
					player.set_look(atan2(-dv.x, -dv.z), atan2(dv.y, Vector2(dv.x, dv.z).length()))
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					await get_tree().physics_frame
					await get_tree().physics_frame
					if _shot_act == "loot":
						print("LOOT aim dot ", (-player.cam.global_basis.z).dot(dv.normalized()), " dist ", dv.length(), " bodies ", best.find_children("*", "StaticBody3D", true, false).size())
						var cf := player.cam.global_position
						var rq := PhysicsRayQueryParameters3D.create(cf, cf - player.cam.global_basis.z * 3.0)
						rq.exclude = [player.get_rid()]
						rq.collision_mask = 3
						var rh := player.get_world_3d().direct_space_state.intersect_ray(rq)
						print("LOOT ray hit ", rh.get("collider"), " path ", (rh["collider"] as Node).get_path() if not rh.is_empty() else "-", " at ", rh.get("position"))
						print("LOOT start ", player._start_loot(), " target ", best.get_meta("loot"))
						for k in 120:
							player._update_loot(1.0 / 60.0, false)
							await get_tree().physics_frame
						print("LOOT label '", player._info_label.text, "' inv ", player.inventory.slots)
						player._start_loot()
						print("LOOT again label '", player._info_label.text, "'")
					else:
						for k in 6:
							player._melee()
							await get_tree().create_timer(0.1).timeout
						print("ROCK after 6 hits: hp ", best.get_meta("hp", -1), "/", best.get_meta("hp_max", -1), " inv ", player.inventory.slots)
				_shot_wait = 0.3
	elif _shot_state == 1:
		_shot_wait -= delta
		if _shot_wait <= 0.0 and terrain.is_idle():
			_shot_state = 2
			print("capturing")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot_path)
			print("Saved ", _shot_path)
			get_tree().quit()
	elif Time.get_ticks_msec() - _boot_ms > 90000:
		print("Shot timeout, ", terrain.stats())
		get_tree().quit()


# --- сцена ------------------------------------------------------------------

func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = not OS.get_cmdline_user_args().has("--noshadow")
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.4
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.directional_shadow_max_distance = 90.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.53, 0.55)
	env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# дневной профиль: бледное небо, рассеянное солнце, мягкие холодные тени, умеренная цветокоррекция
	# (AgX — естественные кирпич и кожа без «HDR»-контраста ACES)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	# SSAO: контактные тени в щелях, под деревьями и у стен (половинное разрешение — дешевле, без заметной потери)
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 3.2
	env.ssao_power = 1.7
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.35
	env.ssao_ao_channel_affect = 0.4
	# постапокалипсис: пасмурно, приглушённые цвета, плотная дымка
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.3
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.9
	env.adjustment_brightness = 1.0
	# туман по глубине: вблизи чисто, дальние дома и холмы постепенно теряют контраст (не серый слой на весь экран)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 0.7      # < 1 — дымка набирает плотность быстро уже на первой сотне метров
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.55
	env.fog_height = 8.0
	env.fog_height_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if not OS.get_cmdline_user_args().has("--nopost"):
		var post := CanvasLayer.new()
		post.layer = 0
		post_layer = post
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = load("res://shaders/postfx.gdshader")
		_post_mat = pm
		rect.material = pm
		post.add_child(rect)
		add_child(post)

	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16000, 16000)
	water.mesh = plane
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# реки и озёра: отдельные поверхности на своих уровнях
	var rivers := MeshInstance3D.new()
	rivers.name = "Rivers"
	rivers.mesh = world.hydro.build_water_mesh()
	rivers.material_override = wm
	rivers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rivers)
	_update_sky()


const GRASS_GROUND_TINT := Vector3(1.0, 1.0, 1.0)   # множитель земли под травой (цвет задаёт GrassField.GRASS_COLOR)


## Атмосфера — профили «День / Сумерки / Ночь / Кровавая луна» (Atmosphere, data/atmosphere.json), смешиваются по
## высоте солнца; правка — отладочная панель F6 (AtmospherePanel). Поверх — выжженная земля (_burn).
var _post_mat: ShaderMaterial
var time_paused := false            # панель F6: время стоит
var atmo_force_blood := false       # панель F6: кровавая луна принудительно
var atmo_preview := ""              # панель F6: показывать только этот профиль ("" — по времени)
var _blood_k := 0.0
var _atmo_ms := 0
var atmo_weights := {}              # текущие веса профилей (для панели)


func _update_sky() -> void:
	var ang := (time_of_day - 0.25) * TAU
	var to_sun := Vector3(cos(ang), sin(ang), 0.35).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	var now_ms := Time.get_ticks_msec()
	var dt := clampf((now_ms - _atmo_ms) / 1000.0, 0.0, 0.5) if _atmo_ms > 0 else 0.0
	_atmo_ms = now_ms
	var blood_on := atmo_force_blood or (zombies != null and zombies.is_blood_moon())
	_blood_k = move_toward(_blood_k, 1.0 if blood_on else 0.0, dt / 6.0)     # переход 6 с
	var w: Dictionary
	if atmo_preview != "":
		w = {atmo_preview: 1.0}
	else:
		w = Atmosphere.time_weights(to_sun.y)
		if _blood_k > 0.0:
			for k: String in w.keys():
				w[k] = float(w[k]) * (1.0 - _blood_k)
			w["blood"] = _blood_k
	atmo_weights = w
	var a := Atmosphere.blend(w)
	var day := clampf(to_sun.y * 3.0 + 0.15, 0.0, 1.0)
	var night := clampf(-to_sun.y * 4.0 + 0.1, 0.0, 1.0)
	var top: Color = a["sky_top"]
	var hor: Color = a["sky_horizon"]
	# выжженная земля: небо в копоти, багровый отсвет у горизонта
	var b := _burn
	if b > 0.001:
		top = top.lerp(Color(0.07, 0.05, 0.05).lerp(Color(0.25, 0.19, 0.16), day), b * 0.9)
		hor = hor.lerp(Color(0.17, 0.10, 0.08).lerp(Color(0.52, 0.34, 0.24), day), b * 0.9)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(float(a["sky_ground_dark"])))
	sky_mat.set_shader_parameter("sky_curve", float(a["sky_curve"]))
	sky_mat.set_shader_parameter("stars", float(a["stars"]))
	sky_mat.set_shader_parameter("sun_size", float(a["sun_size"]))
	sky_mat.set_shader_parameter("sun_glow", float(a["sun_glow"]))
	sky_mat.set_shader_parameter("moon_size", float(a["moon_size"]))
	sky_mat.set_shader_parameter("moon_glow", float(a["moon_glow"]))
	sky_mat.set_shader_parameter("moon_tint", a["moon_color"])
	sky_mat.set_shader_parameter("sun_dir", to_sun)
	if terrain != null:
		terrain.material.set_shader_parameter("pom_sun", to_sun if to_sun.y > 0.0 else (-to_sun + Vector3(0.0, 0.18, 0.0)).normalized())
	sky_mat.set_shader_parameter("moon_dir", -to_sun + Vector3(0.0, 0.18, 0.0))
	sky_mat.set_shader_parameter("night", maxf(night, _blood_k))
	sky_mat.set_shader_parameter("sun_power", clampf(to_sun.y * 6.0 + 0.5, 0.0, 1.0))
	# солнце: яркость профиля, гаснет к горизонту
	sun.light_energy = clampf(to_sun.y * 3.0, 0.0, 1.0) * float(a["sun_energy"]) * (1.0 - 0.4 * b)
	sun.light_color = (a["sun_color"] as Color).lerp(Color(1.0, 0.5, 0.28), b * 0.7)
	# луна: свет против солнца
	var to_moon := (-to_sun + Vector3(0.0, 0.18, 0.0)).normalized()
	moon.global_transform = Transform3D(Basis.looking_at(-to_moon, Vector3.UP), Vector3.ZERO)
	moon.light_energy = clampf(to_moon.y * 3.0 + 0.3, 0.0, 1.0) * float(a["moon_energy"])
	moon.light_color = a["moon_color"]
	for l: DirectionalLight3D in [sun, moon]:
		l.shadow_opacity = float(a["shadow_opacity"])
		l.shadow_blur = float(a["shadow_blur"])
	if shadows_on and not OS.get_cmdline_user_args().has("--noshadow"):
		moon.shadow_enabled = moon.light_energy > 0.03
		sun.shadow_enabled = sun.light_energy > 0.03
	# туман (в выжженной земле — ближе, гуще и дымный)
	var smoke := Color(0.3, 0.21, 0.17) * (0.3 + 0.7 * day)
	env.fog_light_color = (a["fog_color"] as Color).lerp(smoke, b * 0.6)
	env.fog_density = lerpf(float(a["fog_density"]), 0.98, b)
	env.fog_depth_begin = float(a["fog_begin"]) * (1.0 - 0.6 * b)
	env.fog_depth_end = maxf(float(a["fog_end"]) * (1.0 - 0.65 * b), env.fog_depth_begin + 1.0)
	env.fog_depth_curve = float(a["fog_curve"])
	env.fog_sky_affect = lerpf(float(a["fog_sky_affect"]), 0.9, b)
	env.fog_aerial_perspective = float(a["fog_aerial"])
	env.fog_height = float(a["fog_height"])
	env.fog_height_density = lerpf(float(a["fog_height_density"]), 0.03, b)
	# окружающий свет и цвет
	env.ambient_light_color = (a["ambient_color"] as Color).lerp(Color(0.5, 0.4, 0.34), b * 0.5)
	env.ambient_light_energy = float(a["ambient_energy"]) * (1.0 - 0.1 * b)
	env.ssao_intensity = float(a["ssao"])
	env.tonemap_exposure = float(a["exposure"])
	env.adjustment_brightness = float(a["brightness"])
	env.adjustment_contrast = float(a["contrast"])
	env.adjustment_saturation = float(a["saturation"])
	env.glow_intensity = float(a["glow"])
	if _post_mat != null:
		var tn: Color = a["tint"]
		_post_mat.set_shader_parameter("tint", Vector3(tn.r, tn.g, tn.b))
		_post_mat.set_shader_parameter("vignette", float(a["vignette"]))
		_post_mat.set_shader_parameter("grain", float(a["grain"]))


func _make_terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var map := {
		"tex_grass": "grass_a", "tex_grass2": "grass_b", "tex_grass3": "grass_c", "tex_dirt": "dirt_a", "tex_stone": "terrain_stone",
		"tex_sand": "terrain_sand", "tex_gravel": "terrain_gravel", "tex_asph": "road_asphalt",
		"tex_asph2": "road_asphalt_rough", "tex_walk": "sidewalk_slab", "tex_brick": "sidewalk_brick",
		"tex_conc": "road_concrete", "tex_dirtroad": "road_dirt", "tex_decals": "road_decals", "tex_moss": "ground_moss", "tex_tramp": "ground_trampled",
	}
	for u: String in map.keys():
		mat.set_shader_parameter(u, _load_tex(map[u]))
	mat.set_shader_parameter("tex_noise", _make_noise_tex())
	mat.set_shader_parameter("grass_tint", GRASS_GROUND_TINT)
	mat.set_shader_parameter("grass_color", GrassField.GRASS_COLOR)
	mat.set_shader_parameter("grass_recolor", GrassField.TERRAIN_RECOLOR)
	# карты нормалей/высоты (не sRGB)
	var nmap := {"n_grass": "grass_a", "n_grass2": "grass_b", "n_grass3": "grass_c", "n_dirt": "dirt_a",
		"n_stone": "terrain_stone", "n_sand": "terrain_sand", "n_gravel": "terrain_gravel", "n_asph": "road_asphalt",
		"n_walk": "sidewalk_slab", "n_conc": "road_concrete", "n_dirtroad": "road_dirt", "n_moss": "ground_moss"}
	for u: String in nmap.keys():
		mat.set_shader_parameter(u, _load_tex(nmap[u] + "_n"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roaddebug="):
			mat.set_shader_parameter("debug_mode", int(a.substr(12)))
	return mat


## Бесшовная шумовая текстура для шейдера ландшафта: R — фрактальный перлин (3 октавы), G — value-шум.
## Ячейка шума = 4 px, 256 px = 64 ячейки (в шейдере аргумент делится на 64).
static func _make_noise_tex() -> ImageTexture:
	var a := FastNoiseLite.new()
	a.seed = 77
	a.noise_type = FastNoiseLite.TYPE_PERLIN
	a.fractal_type = FastNoiseLite.FRACTAL_FBM
	a.fractal_octaves = 3
	a.frequency = 0.25
	var b := FastNoiseLite.new()
	b.seed = 1234
	b.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	b.fractal_type = FastNoiseLite.FRACTAL_NONE
	b.frequency = 0.25
	var ia := a.get_seamless_image(256, 256)
	var ib := b.get_seamless_image(256, 256)
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			img.set_pixel(x, y, Color(ia.get_pixel(x, y).r, ib.get_pixel(x, y).r, 0.0, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_far_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_far.gdshader")
	var map := {"tex_grass": "grass_a", "tex_grass2": "grass_b", "tex_grass3": "grass_c", "tex_dirt": "dirt_a",
		"tex_stone": "terrain_stone", "tex_sand": "terrain_sand"}
	for u: String in map.keys():
		mat.set_shader_parameter(u, _load_tex(map[u]))
	mat.set_shader_parameter("grass_tint", GRASS_GROUND_TINT)
	mat.set_shader_parameter("grass_color", GrassField.GRASS_COLOR)
	mat.set_shader_parameter("grass_recolor", GrassField.TERRAIN_RECOLOR)
	return mat


func _load_tex(tex_name: String) -> Texture2D:
	# карты нормалей (*_n: RGB нормаль + A высота) — данные, не sRGB; декали — с альфой, без сжатия (тонкие края)
	# дорожные материалы: шероховатость (<имя>_r.png) — в альфе цветовой текстуры (терраин-шейдер читает .a)
	if tex_name in ["road_asphalt", "road_concrete", "sidewalk_slab"]:
		var tr := TexCache.texture_rgb_a("res://assets/textures/%s.png" % tex_name, "res://assets/textures/%s_r.png" % tex_name)
		if tr != null:
			return tr
	var is_data := tex_name.ends_with("_n")
	var t := TexCache.texture("res://assets/textures/%s.png" % tex_name, not is_data, 0, tex_name != "road_decals")
	if t == null:
		push_warning("Нет текстуры %s — запусти tools/gen_textures.gd" % tex_name)
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 0.5))
		t = ImageTexture.create_from_image(img)
	return t


## «День 3   14:25»: время суток из time_of_day (0 — полночь, 0.5 — полдень). Каждый 7-й день — красным (будущая орда).
func _update_clock() -> void:
	if _clock == null:
		return
	var mins := int(time_of_day * 24.0 * 60.0)
	_clock.text = "День %d   %02d:%02d" % [day, mins / 60, mins % 60]
	_clock.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if day % 7 == 0 else Color(0.95, 0.93, 0.88))


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud)
	# часы и номер дня — по центру сверху
	_clock = Label.new()
	_clock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_clock.position = Vector2(-120, 10)
	_clock.size = Vector2(240, 30)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", 22)
	_clock.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock.add_theme_constant_override("outline_size", 6)
	layer.add_child(_clock)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_outline_color", Color.BLACK)
	cross.add_theme_constant_override("outline_size", 4)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(cross)


func _perf_record(delta: float, subs: Array) -> void:
	if not _spawned or player == null:
		return
	if _perf_t == 0.0:
		Prof.enabled = true
		if _perf_run:
			# бег по земле с покачиванием камеры (как играет человек)
			player.flying = false
			player.debug_dir = Vector3(0, 0, -1)
			player.debug_sprint = true
			player.set_look(0.7, -0.1)
		elif not _perf_still:
			player.flying = true
			player.debug_dir = Vector3(0, 0, -1)
			player.set_look(0.7, -0.1)
		else:
			player.set_look(_yaw_arg if _yaw_arg > -8.0 else _street_yaw, _pitch_arg if _pitch_arg > -8.0 else -0.05)
		_perf_sub.resize(_perf_subnames.size() * 2)
		_perf_mon.resize(9)
		_perf_mon.fill(0.0)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var nodes := {"terrain": terrain, "veg": veg, "grass": grass, "settle": settlement, "far": far, "farprops": far_props, "water": water}
		terrain.material.set_shader_parameter("perf_skip", _tskip)
		for h in _hide:
			if nodes.has(h):
				(nodes[h] as Node3D).visible = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # мерить реальную стоимость кадра
	_perf_t += delta
	if _perf_t < 4.0:
		return   # прогрев (стриминг вокруг спавна)
	if _perf_run:
		var yaw := 0.7 + sin(_perf_t * TAU / 7.0) * 0.6
		player.set_look(yaw, -0.1)
		player.debug_dir = Vector3(-sin(yaw), 0, -cos(yaw)).rotated(Vector3.UP, -yaw)   # вперёд в локальных осях
		player.debug_dir = -player.transform.basis.z
	elif not _perf_still:
		var gy := terrain.gen.height_at(player.position.x, player.position.z)
		player.position.y = maxf(gy + 6.0, player.position.y - 0.5)
	elif _pitch_arg < -8.0:
		player.rotation.y += delta * 0.25   # медленно осматриваемся (если наклон не задан явно)
	_perf_frames.append(delta * 1000.0)
	var prof := Prof.take()
	if delta > _spike_ms / 1000.0:
		var vr := get_viewport().get_viewport_rid()
		var parts := ""
		for k: String in prof:
			if int(prof[k]) > 1000:
				parts += " %s=%.1f" % [k, int(prof[k]) / 1000.0]
		for i in subs.size():
			if int(subs[i]) > 1500:
				parts += " %s=%.1f" % [_perf_subnames[i], int(subs[i]) / 1000.0]
		print("PERF FRAME t=%.1f %.0f ms | process %.1f physics %.1f | render cpu %.1f gpu %.1f | nodes %d zombies %d |%s" % [
			_perf_t, delta * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vr), RenderingServer.viewport_get_measured_render_time_gpu(vr),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), zombies.get_child_count() if zombies != null else 0, parts])
	var mons := [Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		Performance.OBJECT_NODE_COUNT, Performance.TIME_PROCESS, Performance.TIME_PHYSICS_PROCESS]
	for i in mons.size():
		_perf_mon[i] += Performance.get_monitor(mons[i])
	var vrid := get_viewport().get_viewport_rid()
	_perf_mon[6] += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
	_perf_mon[7] += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_perf_mon[8] += RenderingServer.get_frame_setup_time_cpu()
	for i in subs.size():
		if int(subs[i]) > 10000:
			print("PERF spike t=%.1f %s %.1f ms" % [_perf_t, _perf_subnames[i], int(subs[i]) / 1000.0])
		_perf_sub[i * 2] += int(subs[i])
		_perf_sub[i * 2 + 1] = maxi(_perf_sub[i * 2 + 1], int(subs[i]))
	if _perf_t > _perf_s + 4.0:
		var f := _perf_frames.duplicate()
		f.sort()
		var n := f.size()
		var sum := 0.0
		var over := 0
		for v in f:
			sum += v
			if v > 33.4:
				over += 1
		print("PERF frames %d  avg %.1f ms (%.0f fps)  p50 %.1f  p95 %.1f  p99 %.1f  max %.1f  >33ms: %d" % [n, sum / n, 1000.0 * n / sum, f[n / 2], f[int(n * 0.95)], f[int(n * 0.99)], f[n - 1], over])
		for i in _perf_subnames.size():
			print("PERF  %-9s avg %.2f ms  max %.2f ms" % [_perf_subnames[i], _perf_sub[i * 2] / 1000.0 / n, _perf_sub[i * 2 + 1] / 1000.0])
		print("PERF render: objects %.0f  draw calls %.0f  primitives %.0f  nodes %.0f  process %.2f ms  physics %.2f ms" % [
			_perf_mon[0] / n, _perf_mon[1] / n, _perf_mon[2] / n, _perf_mon[3] / n, _perf_mon[4] / n * 1000.0, _perf_mon[5] / n * 1000.0])
		print("PERF streaming: chunks built %d (%.1f/s), queue now %d, safe radius %.0f m" % [terrain.built_total, terrain.built_total / _perf_t, terrain._queue.size() + terrain._priority.size(), terrain.safe_radius(player.position)])
		print("PERF render time: viewport cpu %.2f ms  gpu %.2f ms  frame setup cpu %.2f ms" % [_perf_mon[6] / n, _perf_mon[7] / n, _perf_mon[8] / n])
		get_tree().quit()

## Пепел и угольки вокруг игрока в выжженном биоме (интенсивность по _burn).
func _update_burn_fx() -> void:
	if _ash == null:
		_ash = _make_particles(Color(0.28, 0.27, 0.26), 0.05, 380, Vector3(0.25, -0.5, 0.1), false)
		_embers = _make_particles(Color(1.0, 0.45, 0.12), 0.03, 70, Vector3(0.1, 0.35, 0.0), true)
	var on := _burn > 0.08
	_ash.emitting = on
	_embers.emitting = on and _burn > 0.3
	_ash.amount_ratio = clampf(_burn, 0.05, 1.0)
	_embers.amount_ratio = clampf(_burn, 0.05, 1.0)
	_ash.global_position = player.global_position + Vector3(0, 5.0, 0)
	_embers.global_position = player.global_position + Vector3(0, 2.0, 0)


func _make_particles(color: Color, size: float, amount: int, gravity: Vector3, glow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.visibility_aabb = AABB(Vector3(-30, -12, -30), Vector3(60, 24, 60))
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 7, 22)
	pm.gravity = gravity
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.direction = Vector3(0.3, -0.2, 0.1)
	pm.spread = 80.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	add_child(p)
	return p
