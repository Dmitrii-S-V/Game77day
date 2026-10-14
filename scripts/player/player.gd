class_name Player
extends CharacterBody3D
## Игрок от первого лица: движение со ступеньками, инвентарь с быстрым доступом, рука с предметами
## (удар топором, бросок и питьё из бутылки), здоровье и жажда.
## ЛКМ — основное действие предмета, ПКМ — дополнительное, Q — выбросить, E — подобрать, Tab — инвентарь.

const REACH := 7.0
const MELEE_REACH := 2.9
const STEP_H := 0.55

var terrain: Terrain
var cam: Camera3D
var hand: HandRig
var inventory := Inventory.new()
var UI: InventoryUI
var health := 100.0
var thirst := 100.0
var hunger := 100.0                # сытость: 100 — сыт, 0 — голодание (урон)
var flying := false
var spawn_point := Vector3.ZERO
var debug_dir := Vector3.ZERO   # для автотестов: принудительное направление ходьбы
var debug_sprint := false       # для автотестов: бег
var crouching := false          # Ctrl: пригнулся (тише и незаметнее для зомби)
var walk_speed := 5.0
var sprint_speed := 8.5
var jump_velocity := 5.5
var fly_speed := 30.0
var mouse_sens := 0.0025

var _slows: Array[float] = []   # зоны замедления (паутина): множители скорости
var _ground_hp := {}              # Vector3i (воксель) -> оставшаяся прочность повреждённого блока ландшафта
var _hp_label: Label
var _info_label: Label             # подсказка «E — обыскать», прогресс обыска, сообщение о найденном
var _ammo_label: Label             # патроны: магазин / запас
var _toast_t := 0.0
var _loot_node: Node3D = null      # контейнер, который сейчас обыскивается
var _loot_t := 0.0
var _hp_t := 0.0
var _step_dist := 0.0
var _pitch := 0.0
# камера отвязана от физического такта (60 Гц): позиция интерполируется между двумя последними тактами,
# поворот мышью применяется сразу — без рывков при любой частоте кадров
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _step_off := 0.0               # сглаживание подъёма на ступеньку (камера догоняет тело)
var _crouch_off := 0.0             # камера ниже, когда пригнулся
const EYE_H := 1.62
var _use_cd := 0.0
var bleeding := false     # внутреннее кровотечение (разбитое стекло): −10 HP/с до смерти
var _bleed_t := 0.0

## Выносливость: бег, прыжки и удары тратят, восстанавливается после короткой паузы.
const STAM_SPRINT := 6.5    # в секунду бега (выносливости хватает вдвое дольше)
const STAM_JUMP := 6.0
const STAM_REGEN := 11.0    # в секунду (стоя/шагом) — сразу, как перестал бежать/бить
const STAM_DELAY := 0.0     # без паузы: пока бежишь или идёт замах — не восстанавливается (_regen_stamina)
const STAM_RESUME := 25.0   # выдохся — бег снова с этого уровня
var stamina := 100.0
var _stam_rest := 0.0
var _exhausted := false
var _sprinting := false


func _use_stamina(v: float) -> void:
	stamina = maxf(0.0, stamina - v)
	_stam_rest = STAM_DELAY
	if stamina <= 0.0:
		_exhausted = true


func _regen_stamina(delta: float) -> void:
	if _sprinting or (hand != null and hand.busy()):
		return      # бежит или замахивается — без восстановления
	if _stam_rest > 0.0:
		_stam_rest -= delta
	elif stamina < 100.0:
		stamina = minf(100.0, stamina + STAM_REGEN * delta * (0.6 if hunger <= 0.0 or thirst <= 0.0 else 1.0))
var _dead_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var peer_id := 1                 # id в сетевой игре (Net.attach); 1 — хост / одиночная игра
var display_name := ""
var avatar: PlayerAvatar         # модель от третьего лица: у своего игрока — только тень


func _ready() -> void:
	add_to_group("survivors")    # цели зомби (свой игрок и игроки по сети)
	avatar = PlayerAvatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	avatar.build(PlayerAvatar.tint_for(peer_id))
	avatar.set_shadow_only(true)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	cam = Camera3D.new()
	cam.position.y = EYE_H
	cam.top_level = true
	cam.far = 5000.0
	cam.fov = 75.0
	add_child(cam)
	cam.make_current()
	hand = HandRig.new()
	hand.name = "Hand"
	cam.add_child(hand)
	hand.hit_moment.connect(_on_hit_moment)
	hand.release_moment.connect(_on_release_moment)
	hand.drink_progress.connect(_on_drink_progress)
	hand.drink_done.connect(_on_drink_done)
	hand.eat_done.connect(_on_eat_done)
	hand.reload_done.connect(_on_reload_done)
	hand.action_started.connect(_on_hand_action)
	var pose_dbg := ItemPoseDebug.new()   # F9: подгонка положения предмета и руки (сохраняется в data/item_poses.json)
	pose_dbg.hand = hand
	add_child(pose_dbg)
	var hp_layer := CanvasLayer.new()
	add_child(hp_layer)
	_hp_label = Label.new()
	_hp_label.set_anchors_preset(Control.PRESET_CENTER)
	_hp_label.position = Vector2(-60, 22)
	_hp_label.size = Vector2(120, 24)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 6)
	_hp_label.visible = false
	hp_layer.add_child(_hp_label)
	_info_label = _hp_label.duplicate() as Label
	_info_label.position = Vector2(-220, 48)
	_info_label.size = Vector2(440, 24)
	hp_layer.add_child(_info_label)
	_ammo_label = _hp_label.duplicate() as Label
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.position = Vector2(-170, -110)
	_ammo_label.size = Vector2(140, 30)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 22)
	hp_layer.add_child(_ammo_label)
	collision_layer = 4   # игрок: его видят только осколки (и сам игрок для лучей)
	collision_mask = 3 | Zombie.LAYER    # ландшафт/дороги (1) + растения, здания, предметы (2) + зомби
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4
	inventory.changed.connect(_sync_hand)
	inventory.add("stone_axe")
	inventory.add("water_bottle", 1, {"fill": 1.0})
	inventory.add("wooden_club")
	inventory.add("canned_food", 2)
	inventory.add("pistol", 1, {"mag": 12})
	inventory.add("ammo_9mm", 36)
	inventory.select(0)
	_sync_hand()
	if DisplayServer.get_name() != "headless" and not TouchControls.wanted():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Рука начала действие: то же — модели от третьего лица (тень) и другим игрокам по сети.
func _on_hand_action(action: String) -> void:
	avatar.play_action(action)
	if Net.active():
		Net.inst.local_action(action)


func add_slow(f: float) -> void:
	_slows.append(f)


func remove_slow(f: float) -> void:
	_slows.erase(f)


func set_look(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	_pitch = clampf(pitch, -1.55, 1.55)
	_update_cam()


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	_step_off = lerpf(_step_off, 0.0, 1.0 - exp(-delta * 14.0))
	_crouch_off = lerpf(_crouch_off, -0.6 if crouching else 0.0, 1.0 - exp(-delta * 10.0))
	if TouchControls.active():
		var d := TouchControls.inst.take_look()
		if d != Vector2.ZERO and not (UI != null and UI.is_open()):
			rotation.y -= d.x * TouchControls.LOOK_SENS
			_pitch = clampf(_pitch - d.y * TouchControls.LOOK_SENS, -1.55, 1.55)
			hand.look_delta += d
	_update_cam()


## Камера: интерполированная позиция тела + глаза, поворот — текущие yaw/pitch.
func _update_cam() -> void:
	if not is_inside_tree():
		return
	if global_position.distance_squared_to(_cur_pos) > 1e-8:
		# тело переставили вне физики (телепорт, респаун, отладка) — без интерполяции
		_prev_pos = global_position
		_cur_pos = global_position
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var p := _prev_pos.lerp(_cur_pos, f)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, rotation.y, 0.0)), p + Vector3.UP * (EYE_H + _step_off + _crouch_off))


func _sync_hand() -> void:
	var s: Variant = inventory.selected_item()
	if s == null:
		hand.set_item("")
	else:
		hand.set_item(s["id"], float(s.get("fill", 1.0)))
	var g: Variant = _gun()
	hand.slide_locked = g != null and int(g.get("mag", 0)) <= 0


## Экранное управление (TouchControls): касание выбранного «Удар» с пистолетом — выстрел.
func _on_touch_fire() -> void:
	if _gun() != null and not (UI != null and UI.is_open()):
		_fire()


## Можно ли действовать предметом: мышь захвачена (ПК) или экранное управление (телефон).
func _can_act() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or TouchControls.active()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and TouchControls.active():
		return    # на телефоне мышь — эмуляция касаний (ими управляет TouchControls)
	var open := UI != null and UI.is_open()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sens
		_pitch = clampf(_pitch - event.relative.y * mouse_sens, -1.55, 1.55)
		_update_cam()
		hand.look_delta += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not open and event.button_index == MOUSE_BUTTON_LEFT and _gun() != null:
			_fire()   # пистолет: один выстрел на нажатие (не очередью при удержании)
		elif not open and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.select(inventory.selected - 1)
		elif not open and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.select(inventory.selected + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_8 and not open:
			inventory.select(k - KEY_1)
			return
		match k:
			KEY_ESCAPE:
				if open:
					UI.toggle()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_TAB:
				if UI != null:
					UI.toggle(0)
			KEY_C:
				if UI != null:
					UI.toggle(1)   # окно сразу на вкладке «Крафт»
			KEY_F:
				flying = not flying
				velocity = Vector3.ZERO
			KEY_Q:
				if not open:
					_drop_selected()
			KEY_R:
				if not open:
					_reload()
			KEY_E:
				if not open and not _use_block() and not _start_loot():
					_pickup()


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_prev_pos = global_position
	_cur_pos = global_position
	_physics_move(delta)
	_cur_pos = global_position
	var s: Variant = inventory.selected_item()
	avatar.set_item("" if s == null else String(s["id"]))
	avatar.set_backpack(inventory.has_backpack)
	avatar.animate(delta, 0.0 if flying else Vector2(velocity.x, velocity.z).length(), crouching, _pitch, _dead_t > 0.0)
	Prof.add("player", Time.get_ticks_usec() - t0)


func _physics_move(delta: float) -> void:
	if _dead_t > 0.0:
		_dead_t -= delta
		if _dead_t <= 0.0:
			_respawn()
		return
	var open := UI != null and UI.is_open()
	var dir := Vector3.ZERO
	if debug_dir != Vector3.ZERO:
		dir = debug_dir
	elif not open:
		if Input.is_physical_key_pressed(KEY_W): dir -= transform.basis.z
		if Input.is_physical_key_pressed(KEY_S): dir += transform.basis.z
		if Input.is_physical_key_pressed(KEY_A): dir -= transform.basis.x
		if Input.is_physical_key_pressed(KEY_D): dir += transform.basis.x
	var tc := TouchControls.inst if TouchControls.active() else null
	if tc != null and not open and debug_dir == Vector3.ZERO:
		dir += -transform.basis.z * tc.move.y + transform.basis.x * tc.move.x
	# Ctrl — пригнуться: медленно, тихо, зомби замечают ближе (в полёте Ctrl — вниз)
	crouching = not open and not flying and (Input.is_physical_key_pressed(KEY_CTRL) or (tc != null and tc.crouch))
	var sprint := (Input.is_physical_key_pressed(KEY_SHIFT) or debug_sprint or (tc != null and tc.sprint)) and not open and not crouching
	# выносливость: бег тратит (если выдохся — бег недоступен, пока не восстановится STAM_RESUME)
	if not flying:
		if _exhausted and stamina >= STAM_RESUME:
			_exhausted = false
		var moving := dir != Vector3.ZERO
		if sprint and (_exhausted or stamina <= 0.0):
			sprint = false
		_sprinting = sprint and moving
		if _sprinting:
			_use_stamina(STAM_SPRINT * delta)
	else:
		_sprinting = false
	_regen_stamina(delta)

	if flying:
		var fdir := dir
		if dir != Vector3.ZERO:
			fdir = (cam.global_basis * Vector3(dir.dot(transform.basis.x), 0.0, dir.dot(transform.basis.z))).normalized()
		if not open and Input.is_physical_key_pressed(KEY_SPACE): fdir += Vector3.UP
		if not open and Input.is_physical_key_pressed(KEY_CTRL): fdir += Vector3.DOWN
		velocity = fdir * fly_speed * (3.0 if sprint else 1.0)
		move_and_slide()
	else:
		dir.y = 0.0
		dir = dir.normalized()
		var speed := sprint_speed if sprint else (walk_speed * 0.45 if crouching else walk_speed)
		var slow_f := 1.0
		for sf in _slows:
			slow_f = minf(slow_f, sf)   # несколько паутин сразу не складываются, действует самая сильная
		speed *= slow_f
		velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
		if is_on_floor():
			if not open and (Input.is_physical_key_pressed(KEY_SPACE) or (tc != null and tc.jump)) and stamina >= STAM_JUMP:
				velocity.y = jump_velocity
				_use_stamina(STAM_JUMP)
		else:
			velocity.y -= _gravity * delta
		var was_floor := is_on_floor()
		move_and_slide()
		# ступенька — только при упоре в стенку по направлению движения (пол тоже даёт столкновение:
		# раньше при развороте скорость падала, и игрока каждый такт дёргало вперёд-вверх на 0.22 м)
		if was_floor and dir != Vector3.ZERO:
			var d2 := Vector2(dir.x, dir.z).normalized()
			for i in get_slide_collision_count():
				var nrm := get_slide_collision(i).get_normal()
				if nrm.y < 0.6 and Vector2(nrm.x, nrm.z).normalized().dot(d2) < -0.5:
					_try_step(dir * speed * delta)
					break
	hand.speed = clampf(Vector2(velocity.x, velocity.z).length() / walk_speed, 0.0, 1.4) if is_on_floor() and not flying else 0.0
	# шаги: по пройденному пути, звук — по покрытию под ногами
	if is_on_floor() and not flying:
		_step_dist += Vector2(velocity.x, velocity.z).length() * delta
		var stride := 2.6 if sprint else (1.4 if crouching else 1.9)
		if _step_dist >= stride:
			_step_dist = 0.0
			Sfx.play_at(self, "step_" + _surface(), global_position, -2.0 if sprint else (-14.0 if crouching else -6.0), 25.0)
			# шум шагов для зомби: бег слышно далеко, крадущегося — почти нет
			ZombieDirector.noise(global_position, 24.0 if sprint else (3.0 if crouching else 11.0), self)
	else:
		_step_dist = 1.2

	_hp_t -= delta
	if _hp_t <= 0.0:
		_hp_t = 0.1
		_update_hp_label(open)
		_update_ammo_label()
	_update_loot(delta, open)
	# основное / дополнительное действие предмета
	_use_cd = maxf(0.0, _use_cd - delta)
	if _can_act() and not open and not hand.busy() and _use_cd <= 0.0:
		var lmb := tc.attack if tc != null else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var rmb := tc.alt if tc != null else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if lmb:
			_primary()
		elif rmb:
			_secondary()

	# жажда и здоровье
	# голод медленнее жажды (~50 мин до нуля), бег и удары расходуют силы быстрее
	thirst = maxf(0.0, thirst - delta / 22.0)
	var exertion := 1.6 if (Input.is_physical_key_pressed(KEY_SHIFT) and not flying) else 1.0
	hunger = maxf(0.0, hunger - delta / 30.0 * exertion)
	if thirst <= 0.0:
		health -= delta * 1.5
	if hunger <= 0.0:
		health -= delta * 1.0
	if thirst > 50.0 and hunger > 40.0 and health < 100.0 and not bleeding:
		health = minf(100.0, health + delta * 0.4)
	if bleeding:
		# внутреннее кровотечение (съел разбитое стекло): −10 HP/с, пока не кончится здоровье
		_bleed_t -= delta
		health -= delta * 10.0
		if _bleed_t <= 0.0:
			_bleed_t = 1.0
			if UI != null:
				UI.flash()
	if health <= 0.0:
		_die()
	if UI != null:
		UI.set_stats(health, thirst, hunger, stamina)


## Покрытие под ногами для звука шагов: grass / gravel / hard (асфальт, бетон) / wood (постройки).
func _surface() -> String:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.6)
	q.exclude = [get_rid()]
	q.collision_mask = 3
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit["collider"] as Node).has_meta("block_building"):
		return "wood"
	if terrain == null:
		return "grass"
	var x := floori(global_position.x)
	var z := floori(global_position.z)
	var col := terrain.gen.column(floori(x / float(WorldGen.CHUNK)), floori(z / float(WorldGen.CHUNK)))
	match int(col.mat[posmod(x, WorldGen.CHUNK) + WorldGen.CHUNK * posmod(z, WorldGen.CHUNK)]):
		WorldGen.MAT_ASPHALT, WorldGen.MAT_CONCRETE:
			return "hard"
		WorldGen.MAT_GRAVEL, WorldGen.MAT_ROADSAND:
			return "gravel"
	return "grass"


## Шаг через ступеньку/бордюр высотой до STEP_H.
func _try_step(motion: Vector3) -> void:
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP_H):
		return
	var up := xf.translated(Vector3.UP * STEP_H)
	var fwd := motion.normalized() * 0.22
	if test_move(up, fwd):
		return
	var y0 := global_position.y
	global_position = up.origin + fwd
	move_and_collide(Vector3.DOWN * (STEP_H + 0.05))
	velocity.y = 0.0
	_step_off -= global_position.y - y0   # камера поднимается плавно, а не скачком
	_cur_pos = global_position


# --- здоровье ----------------------------------------------------------------------------

func take_damage(amount: float) -> void:
	if _dead_t > 0.0:
		return
	health -= amount
	if UI != null:
		UI.flash()
	Sfx.play_ui(self, "player_hurt", -4.0)


func _die() -> void:
	_dead_t = 2.5
	health = 0.0


func _respawn() -> void:
	bleeding = false
	stamina = 100.0
	_exhausted = false
	health = 100.0
	thirst = 70.0
	hunger = maxf(hunger, 60.0)
	velocity = Vector3.ZERO
	global_position = spawn_point + Vector3.UP * 1.0


# --- действия ----------------------------------------------------------------------------

func _primary() -> void:
	var s: Variant = inventory.selected_item()
	if s != null and ItemDB.info(s["id"]).has("gun"):   # пистолет стреляет по нажатию (_unhandled_input)
		return
	if s != null and ItemDB.info(s["id"]).has("food"):
		hand.play("eat")
		return
	if s != null and s["id"] in ["water_bottle", "glass_bottle"]:
		hand.play("throw")
		return
	# удар: инструмент/оружие — взмах, иначе (пустая рука, материалы…) — кулак; темп и выносливость — ItemDB.attack
	var a := ItemDB.attack("" if s == null else String(s["id"]))
	if stamina < float(a["stam"]):
		return   # нет сил на удар
	_use_stamina(float(a["stam"]))
	_use_cd = float(a["rate"])
	if s != null and ItemDB.info(s["id"]).has("dmg"):
		hand.play("swing")
		Sfx.play_ui(self, "swing", -10.0)
	else:
		hand.play("punch")
		Sfx.play_ui(self, "swing", -16.0)


func _secondary() -> void:
	var s: Variant = inventory.selected_item()
	if s == null:
		return
	if ItemDB.info(s["id"]).has("food"):
		hand.play("eat")
		return
	match s["id"]:
		"water_bottle":
			if float(s.get("fill", 1.0)) > 0.0:
				hand.play("drink")
		"stone_axe":
			place()
			_use_cd = 0.25


func _on_hit_moment() -> void:
	_melee()


# --- пистолет ----------------------------------------------------------------------------

## Выбранное оружие ({id, n, mag}) или null.
func _gun() -> Variant:
	var s: Variant = inventory.selected_item()
	if s != null and ItemDB.info(s["id"]).has("gun"):
		return s
	return null


func _fire() -> void:
	var s: Variant = _gun()
	if s == null or hand.busy() or _dead_t > 0.0 or flying:
		return
	var g: Dictionary = ItemDB.info(s["id"])["gun"]
	if int(s.get("mag", 0)) <= 0:
		Sfx.play_ui(self, "gun_dry", -4.0)
		if inventory.count(String(g["ammo"])) > 0:
			_reload()
		else:
			_toast("Нет патронов")
		return
	s["mag"] = int(s["mag"]) - 1
	hand.slide_locked = int(s["mag"]) <= 0     # последний патрон — затвор на задержке
	var gl := Gear.lvl(s)
	var gm := Gear.dmg_mult(gl)
	_wear_selected()
	hand.play("shoot")
	_pitch = clampf(_pitch + 0.018, -1.55, 1.55)   # отдача
	_update_cam()
	var dbg := OS.get_cmdline_user_args()   # отладка рывков: --nofx=sound,noise,flash,hit
	var nofx := ""
	for a in dbg:
		if a.begins_with("--nofx="):
			nofx = a.substr(7)
	if not "sound" in nofx:
		Sfx.play_at(self, "gun_shot", cam.global_position, 4.0, 120.0, 0.04)
	if not "noise" in nofx:
		ZombieDirector.noise(global_position, float(g["noise"]), self)   # выстрел слышно далеко (как в 7DTD)
	if not "flash" in nofx:
		_muzzle_flash()
	if "hit" in nofx:
		return
	# пуля — мгновенный луч из центра экрана с небольшим разбросом (на бегу больше)
	var spread := float(g["spread"]) * (3.0 if Vector2(velocity.x, velocity.z).length() > walk_speed + 0.5 else 1.0)
	var dir := (-cam.global_basis.z + cam.global_basis.x * randf_range(-spread, spread) + cam.global_basis.y * randf_range(-spread, spread)).normalized()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * float(g["range"]))
	q.exclude = [get_rid()]
	q.collision_mask = 3 | Zombie.LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var zc := Zombie.of(col)
	if zc != null and not zc.dead:
		_hit_zombie(zc, float(g["dmg"]) * gm, dir, pos, "pistol", gl)
		Sfx.play_at(self, "hit_flesh", pos, -4.0, 30.0)
		Blood.spray(get_tree().current_scene, pos, dir, 1.3)
		_impact(pos, -dir, Color(0.32, 0.03, 0.03))
		return
	if col.has_meta("block_building"):
		var bb: Variant = col.get_meta("block_building")
		if bb is BlockBuilding:
			(bb as BlockBuilding).hit(pos, hit["normal"], float(g["block"]) * gm, "pickaxe", col)
			Gear.add_damage("pistol", float(g["block"]) * gm)
	_impact(pos, hit["normal"], Color(0.45, 0.41, 0.36))


## Вспышка выстрела: одна постоянная лампа, включается на 50 мс (создавать свет на каждый выстрел — рывки кадра).
var _flash: OmniLight3D
var _flash_t := 0.0


func _muzzle_flash() -> void:
	if _flash == null:
		_flash = OmniLight3D.new()
		_flash.light_color = Color(1.0, 0.75, 0.4)
		_flash.light_energy = 4.0
		_flash.omni_range = 5.0
		_flash.shadow_enabled = false
		_flash.visible = false
		_flash.top_level = true
		add_child(_flash)
	_flash.global_position = hand.muzzle_global()
	_flash.visible = true
	_flash_t = 0.05


## Брызги от попадания пули: частицы из готового запаса (без физических тел).
var _impacts: Array[CPUParticles3D] = []
var _impact_i := 0


func _impact(pos: Vector3, nrm: Vector3, color: Color) -> void:
	if _impacts.is_empty():
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.025
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		bm.material = m
		for i in 6:
			var p := CPUParticles3D.new()
			p.emitting = false
			p.one_shot = true
			p.explosiveness = 1.0
			p.amount = 7
			p.lifetime = 0.6
			p.mesh = bm
			p.spread = 40.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
			p.top_level = true
			p.local_coords = false
			add_child(p)
			_impacts.append(p)
	var e := _impacts[_impact_i]
	_impact_i = (_impact_i + 1) % _impacts.size()
	e.global_position = pos + nrm * 0.03
	e.direction = Vector3.UP
	e.global_basis = Basis(Quaternion(Vector3.UP, nrm.normalized())) if absf(nrm.normalized().dot(Vector3.UP)) < 0.999 else Basis()
	e.color = color
	e.restart()


func _reload() -> void:
	var s: Variant = _gun()
	if s == null or hand.busy():
		return
	var g: Dictionary = ItemDB.info(s["id"])["gun"]
	if int(s.get("mag", 0)) >= int(g["mag"]):
		return
	if inventory.count(String(g["ammo"])) <= 0:
		_toast("Нет патронов")
		return
	hand.play("reload")
	Sfx.play_ui(self, "gun_reload", -4.0)


func _on_reload_done() -> void:
	var s: Variant = _gun()
	if s == null:
		return
	var g: Dictionary = ItemDB.info(s["id"])["gun"]
	var need := int(g["mag"]) - int(s.get("mag", 0))
	s["mag"] = int(s.get("mag", 0)) + inventory.take(String(g["ammo"]), need)
	hand.slide_locked = int(s["mag"]) <= 0


## Патроны на экране: «магазин / запас» (только с оружием в руке).
func _update_ammo_label() -> void:
	var s: Variant = _gun()
	_ammo_label.visible = s != null
	if s != null:
		_ammo_label.text = "%d / %d" % [int(s.get("mag", 0)), inventory.count(String(ItemDB.info(s["id"])["gun"]["ammo"]))]


func _on_release_moment() -> void:
	var s: Variant = inventory.selected_item()
	if s == null:
		return
	var b := ThrownBottle.new()
	get_tree().current_scene.add_child(b)
	b.setup(s["id"], float(s.get("fill", 1.0)))
	var fwd := -cam.global_basis.z
	b.global_position = cam.global_position + fwd * 0.6 + cam.global_basis.x * 0.12 + Vector3.DOWN * 0.08
	b.linear_velocity = fwd * 13.0 + Vector3.UP * 1.8 + velocity * 0.6
	b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(8, 14))
	inventory.set_slot(inventory.selected, null)


func _on_drink_progress(f: float) -> void:
	var s: Variant = inventory.selected_item()
	if s != null:
		s["fill"] = f


## Съедена порция выбранной еды: сытость, немного воды/здоровья (из ItemDB.food), минус одна штука.
func _on_eat_done() -> void:
	var s: Variant = inventory.selected_item()
	if s == null:
		return
	var f: Dictionary = ItemDB.info(s["id"]).get("food", {})
	if f.is_empty():
		return
	hunger = minf(100.0, hunger + float(f.get("hunger", 0.0)))
	thirst = clampf(thirst + float(f.get("thirst", 0.0)), 0.0, 100.0)
	health = clampf(health + float(f.get("health", 0.0)), 0.0, 100.0)
	if f.get("bleed", false):
		bleeding = true
		_bleed_t = 0.0
		_toast("Внутреннее кровотечение!", 4.0)
	var n := int(s["n"]) - 1
	inventory.set_slot(inventory.selected, null if n <= 0 else {"id": s["id"], "n": n})
	Sfx.play_at(self, "eat", global_position + Vector3.UP * 1.5)


func _on_drink_done() -> void:
	Sfx.play_ui(self, "drink", -6.0)
	thirst = minf(100.0, thirst + 45.0)
	health = minf(100.0, health + 4.0)
	inventory.set_slot(inventory.selected, {"id": "glass_bottle", "n": 1, "fill": 0.0})


func _drop_selected() -> void:
	var s: Variant = inventory.selected_item()
	if s == null:
		return
	var fwd := -cam.global_basis.z
	var pos := cam.global_position + fwd * 0.7 + Vector3.DOWN * 0.3
	if ItemDB.info(s["id"]).get("bottle", false):
		var b := ThrownBottle.new()
		get_tree().current_scene.add_child(b)
		b.setup(s["id"], float(s.get("fill", 1.0)))
		b.global_position = pos
		b.linear_velocity = fwd * 2.5 + velocity * 0.5
	else:
		var ip := ItemPickup.spawn(get_tree().current_scene, pos, s.duplicate(), fwd * 2.5 + velocity * 0.5)
		if Net.active():
			ip.set_meta("uid", Net.inst.next_uid())
			Net.op("drop", [ip.get_meta("uid"), pos, s.duplicate(), fwd * 2.5 + velocity * 0.5])
	inventory.set_slot(inventory.selected, null)


## E по двери здания (в досягаемости): открыть/закрыть. true, если блок обработан (в т.ч. заколоченная дверь не открылась).
func _use_block() -> bool:
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 3.2)
	q.exclude = [get_rid()]
	q.collision_mask = 3 | 8
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var collider: Object = hit["collider"]
	if not (collider is Node and (collider as Node).has_meta("block_building")):
		return false
	var bb: Variant = (collider as Node).get_meta("block_building")
	if not (bb is BlockBuilding):
		return false
	var c: Vector3i = (bb as BlockBuilding).cell_at_hit(hit["position"], hit["normal"], collider)
	var a := (bb as BlockBuilding).grid.anchor_of(c)
	var id := (bb as BlockBuilding).grid.get_cell(a.x, a.y, a.z)
	if id != 0 and BlockRegistry.is_new(id) and BlockRegistry.shape_of(id) == "door":
		var was_open := ((bb as BlockBuilding).grid.get_meta_at(a.x, a.y, a.z) & (1 << 10)) != 0
		if (bb as BlockBuilding).toggle_door(a):
			Sfx.play_at(self, "door_close" if was_open else "door_open", hit["position"], 0.0, 30.0)
			ZombieDirector.noise(hit["position"], 12.0, self)
		return true
	return false


## Обыскиваемый контейнер под прицелом (мешок/куча мусора с метой "loot") или null.
func _loot_target() -> Node3D:
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 3.0)
	q.exclude = [get_rid()]
	q.collision_mask = 3 | Zombie.CORPSE_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col := hit["collider"] as Node
	if col.has_meta("loot") and col is Node3D:   # труп зомби
		return col as Node3D
	var p := col.get_parent()
	if p is Node3D and p.has_meta("loot"):
		return p as Node3D
	return null


## E по мешку мусора: начать обыск. true, если под прицелом контейнер.
func _start_loot() -> bool:
	var n := _loot_target()
	if n == null:
		return false
	if Loot.is_looted(n.global_position):
		_toast("Здесь уже пусто")
	elif _loot_node == null:
		_loot_node = n
		_loot_t = 0.0
		Sfx.play_at(self, Sfx.pick("loot_open", "rustle"), n.global_position, -4.0, 20.0)
	return true


func _toast(text: String, t: float = 2.5) -> void:
	_info_label.text = text
	_info_label.visible = true
	_toast_t = t


func _update_loot(delta: float, ui_open: bool) -> void:
	if _loot_node != null:
		if not is_instance_valid(_loot_node) or ui_open or _loot_target() != _loot_node:
			_loot_node = null
			_toast("Обыск прерван", 1.2)
			return
		_loot_t += delta
		var need := Loot.search_time(String(_loot_node.get_meta("loot")))
		_info_label.text = "Обыскиваю… %d%%" % int(minf(_loot_t / need, 1.0) * 100.0)
		_info_label.visible = true
		if _loot_t >= need:
			_finish_loot(_loot_node)
			_loot_node = null
		return
	if _toast_t > 0.0:
		_toast_t -= delta
		return
	# подсказка при наведении (не каждый кадр: тот же такт, что и у метки прочности)
	if _hp_t >= 0.095:
		var n: Node3D = null if ui_open else _loot_target()
		_info_label.visible = n != null
		if n != null:
			_info_label.text = "Пусто" if Loot.is_looted(n.global_position) else "E — обыскать"


func _finish_loot(n: Node3D) -> void:
	var table := String(n.get_meta("loot"))
	var items := Loot.roll(table, n.global_position)
	Loot.mark_looted(n.global_position)
	Net.op("looted", [n.global_position])
	if items.is_empty():
		_toast("Ничего полезного")
		return
	var parts: Array[String] = []
	var full := false
	for it: Array in items:
		var left := inventory.add(String(it[0]), int(it[1]))
		var got := int(it[1]) - left
		if got > 0:
			parts.append("+%d %s" % [got, ItemDB.item_name(String(it[0]))])
		if left > 0:
			full = true
	var text := ", ".join(parts)
	if full:
		text += ("  " if text != "" else "") + "(инвентарь полон)"
	_toast(text, 3.5)


func _pickup() -> void:
	var best: Node3D = null
	var bd := 2.8
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	for n: Node3D in get_tree().get_nodes_in_group("pickups"):
		var d := n.global_position.distance_to(from)
		var facing := (n.global_position - from).normalized().dot(fwd)
		if d < bd and facing > 0.3:
			bd = d
			best = n
	if best == null:
		return
	var item: Dictionary = best.get_meta("item")
	var extra := {}
	if item.has("fill"):
		extra["fill"] = item["fill"]
	if inventory.add(item["id"], int(item["n"]), extra) == 0:
		Sfx.play_at(self, "pickup", best.global_position, -6.0, 12.0)
		if best.has_meta("decor"):
			Vegetation.mark_removed(best.global_position)   # камешек на территории не появится снова
			Net.op("removed", [best.global_position])
		Net.op("take", [String(best.get_meta("uid", "")), best.global_position])
		best.queue_free()


func _melee() -> void:
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * MELEE_REACH)
	q.exclude = [get_rid()]
	q.collision_mask = 3 | 8 | Zombie.LAYER   # + «мягкие» блоки построек (ковёр, паутина, свеча) + зомби
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	var sel: Variant = inventory.selected_item()
	var sid := "" if sel == null else String(sel["id"])
	_wear_selected()      # удар инструментом изнашивает его (по чему угодно)
	var zh := Zombie.of(collider)    # зомби или кость его ragdoll (сбит с ног)
	if zh != null:
		if not zh.dead:
			_hit_zombie(zh, _tool_dmg("zombie"), -cam.global_basis.z, pos, sid, Gear.lvl(sel))
			Sfx.play_at(self, "hit_flesh", pos, 0.0, 30.0)
			Blood.spray(get_tree().current_scene, pos, -cam.global_basis.z, 1.0)
		ZombieDirector.noise(pos, 14.0, self)
		return
	if collider.has_meta("block_building"):
		var bb: Variant = collider.get_meta("block_building")
		if bb is BlockBuilding:
			# звук — по материалу блока (до удара: после него блока может уже не быть)
			var bk: String = (bb as BlockBuilding).kind_at_hit(pos, nrm, collider)
			bb.hit(pos, nrm, _tool_dmg("block"), "axe", collider)
			Gear.add_damage(sid, _tool_dmg("block"))     # развитие: урон по блокам
			var snd := "hit_wood"
			if bk == "stone":
				snd = "hit_stone"
			elif bk == "metal":
				snd = Sfx.pick("hit_metal", "hit_stone")
			elif bk == "cloth":
				snd = "rustle"
			Sfx.play_at(self, snd, pos, -2.0, 30.0)
			ZombieDirector.noise(pos, 22.0, self)
			return
	var parent := (collider as Node).get_parent()
	if parent != null and parent.has_meta("resource"):
		var k: String = parent.get_meta("kind", "tree")
		Sfx.play_at(self, "hit_stone" if k == "rock" else ("rustle" if k == "bush" else "hit_wood"), pos, 0.0, 35.0)
		ZombieDirector.noise(pos, 8.0 if k == "bush" else 30.0, self)   # рубка и добыча камня слышны далеко
		_hit_plant(parent, pos)
		return
	var brk := Breakables.find(collider)
	if brk != null:
		_hit_breakable(brk, pos)
		return
	# земля с травой: сначала срезается трава (в инвентарь), копать — следующими ударами
	if nrm.y > 0.5:
		var cut := GrassField.cut_around(get_tree(), pos, GRASS_CUT_R)
		if cut > 0:
			Net.op("grass", [pos, GRASS_CUT_R])
			Sfx.play_at(self, "rustle", pos, -4.0, 15.0)
			Debris.burst(get_tree().current_scene, pos + Vector3.UP * 0.15, Color(0.36, 0.5, 0.2), 6, 1.8, 0.07, 2.0, null, 0.15)
			var gn := clampi(ceili(cut / 3.0), 1, 4)
			if inventory.add("grass", gn) == 0:
				_toast("+%d %s" % [gn, ItemDB.item_name("grass")], 1.2)
			ZombieDirector.noise(pos, 5.0, self)
			return
	Sfx.play_at(self, "hit_dirt", pos, -2.0, 25.0)
	ZombieDirector.noise(pos, 14.0, self)
	_hit_ground(pos, nrm)


const GRASS_CUT_R := 0.7


## Удар по разрушаемому реквизиту (Breakables): прочность, звук и осколки по материалу; при поломке — добыча
## (и лут пакета/кучи/рюкзака, если не обыскан), пыль; на этом месте больше не появится.
func _hit_breakable(node: Node3D, pos: Vector3) -> void:
	var d := Breakables.def(node)
	if d.is_empty():
		return
	var mat := String(d["mat"])
	var col: Color = Breakables.MAT_COLOR.get(mat, Color(0.4, 0.4, 0.4))
	var tex := Debris.node_tex(node)
	Sfx.play_at(self, Breakables.hit_sound(mat), pos, -2.0, 30.0)
	ZombieDirector.noise(pos, 20.0 if mat in ["metal", "wood"] else 8.0, self)
	var mx := float(d["hp"])
	var hp := float(node.get_meta("bhp", mx)) - _tool_dmg(String(d["dmg"]))
	Debris.burst(get_tree().current_scene, pos, col, 3, 2.0, 0.06, 2.5, tex, 0.4 if mat in ["cloth", "plastic", "cardboard"] else 1.0)
	if hp > 0.0:
		node.set_meta("bhp", hp)
		return
	var center := node.global_position + Vector3.UP * 0.3
	Debris.burst(get_tree().current_scene, center, col, 10, 3.0, 0.1, 4.0, tex)
	Debris.dust(get_tree().current_scene, center, col)
	var got: Array[String] = []
	var drop := Breakables.roll_drop(d)
	if d.get("loot", false) and node.has_meta("loot") and not Loot.is_looted(node.global_position):
		for it: Array in Loot.roll(String(node.get_meta("loot")), node.global_position):
			drop[it[0]] = int(drop.get(it[0], 0)) + int(it[1])
		Loot.mark_looted(node.global_position)
		Net.op("looted", [node.global_position])
	for id: String in drop:
		var n := int(drop[id])
		var left := inventory.add(id, n)
		if left < n:
			got.append("+%d %s" % [n - left, ItemDB.item_name(id)])
	if not got.is_empty():
		_toast(", ".join(got), 2.5)
	_removed(node)


## Прочность цели под прицелом: показывается, только если по ней уже били (формат «осталось/всего»).
func _update_hp_label(ui_open: bool) -> void:
	var show := false
	if not ui_open and _can_act() and _dead_t <= 0.0:
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * MELEE_REACH)
		q.exclude = [get_rid()]
		q.collision_mask = 3 | 8
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var collider: Object = hit["collider"]
			var left := -1.0
			var mx := 0.0
			if collider.has_meta("block_building"):
				var bb: Variant = collider.get_meta("block_building")
				if bb is BlockBuilding:
					var r: Array = (bb as BlockBuilding).hp_at_hit(hit["position"], hit["normal"], collider)
					if not r.is_empty():
						left = r[0]
						mx = r[1]
			else:
				var parent := (collider as Node).get_parent()
				var brk := Breakables.find(collider)
				if brk != null:
					if brk.has_meta("bhp"):
						left = float(brk.get_meta("bhp"))
						mx = float(Breakables.def(brk).get("hp", left))
				elif parent != null and parent.has_meta("resource"):
					if parent.has_meta("hp"):
						left = float(parent.get_meta("hp"))
						mx = float(parent.get_meta("hp_max", left))
				else:
					var b := terrain.block_at(hit["position"], hit["normal"])
					if not b.is_empty() and _ground_hp.has(b["cell"]):
						left = float(_ground_hp[b["cell"]])
						mx = Terrain.block_max_hp(int(b["mat"]))
			if left >= 0.0 and left < mx - 0.01:
				show = true
				_hp_label.text = "%d / %d" % [ceili(left), int(mx)]
	_hp_label.visible = show


## Урон предмета в руке по классу цели (ItemDB.ITEMS[..].dmg) с учётом уровня (Gear: +20% за уровень).
func _tool_dmg(target: String) -> float:
	var s: Variant = inventory.selected_item()
	return ItemDB.damage("" if s == null else String(s["id"]), target) * Gear.dmg_mult(Gear.lvl(s))


## Попадание по зомби: шансы сбить/оглушить — по классу оружия (кулак/бита/прочее/огнестрел), бита — +3% за уровень;
## урон идёт в развитие (открытие уровней), убийства — в статистику.
## По сети: марионетка зомби — удар уходит хосту (убийство засчитает его событие), кровь видят и остальные.
func _hit_zombie(z: Zombie, dmg: float, dir: Vector3, pos: Vector3, id: String, level: int) -> void:
	Gear.add_damage(id, dmg)
	if Net.active():
		Net.inst.fx_blood(pos, dir, 1.3 if Gear.kind_of(id) == "gun" else 1.0)
	if z.puppet:
		Net.inst.zombie_hit(z, dmg, dir, pos, Gear.kind_of(id), Gear.chance_bonus(id, level))
		return
	var was_dead := z.dead
	z.take_hit(dmg, dir, pos, Gear.kind_of(id), Gear.chance_bonus(id, level), self, peer_id)
	if z.dead and not was_dead:
		Gear.kills += 1


## Износ выбранного оружия/инструмента на 1 удар/выстрел; сломалось — пропадает в конце кадра (удар засчитан).
func _wear_selected() -> void:
	var s: Variant = inventory.selected_item()
	if Gear.wear(s):
		call_deferred("_break_item", inventory.selected, s)
	elif s != null and Gear.is_leveled(String(s["id"])):
		inventory.changed.emit()    # полоска прочности


func _break_item(slot: int, item: Variant) -> void:
	if inventory.get_slot(slot) == item:
		inventory.set_slot(slot, null)
	_toast("%s сломался!" % ItemDB.item_name(item["id"]), 2.5)
	Sfx.play_ui(self, Sfx.pick("block_break", "hit_wood"), -4.0)


## Текстура осколков земли по материалу вокселя (трава при ударе — земля под дёрном).
static func _ground_tex(mat: int) -> String:
	match mat:
		WorldGen.MAT_STONE:
			return "terrain_stone"
		WorldGen.MAT_SAND:
			return "terrain_sand"
		WorldGen.MAT_ASPHALT:
			return "road_asphalt"
		WorldGen.MAT_CONCRETE:
			return "road_concrete"
		WorldGen.MAT_GRAVEL, WorldGen.MAT_BASE:
			return "terrain_gravel"
		WorldGen.MAT_ROADSAND:
			return "road_dirt"
	return "dirt_a"


## Удар по ландшафту: у каждого вокселя (блока 1 м) своя прочность по материалу; разрушенный блок выкапывается.
func _hit_ground(pos: Vector3, nrm: Vector3) -> void:
	var b := terrain.block_at(pos, nrm)
	if b.is_empty():
		return
	var cell: Vector3i = b["cell"]
	var mx := Terrain.block_max_hp(int(b["mat"]))
	var left: float = float(_ground_hp.get(cell, mx)) - _tool_dmg("ground")
	if left > 0.0:
		_ground_hp[cell] = left
		Debris.burst(get_tree().current_scene, pos, Color(0.4, 0.32, 0.22), 3, 2.0, 0.06, 2.5, Debris.file_tex(_ground_tex(int(b["mat"]))))
		if _ground_hp.size() > 600:
			_ground_hp.clear()
			_ground_hp[cell] = left
		return
	_ground_hp.erase(cell)
	terrain.edit_sphere(Vector3(cell) + Vector3(0.5, 0.5, 0.5), 0.95, false)
	Net.op("terrain", [Vector3(cell) + Vector3(0.5, 0.5, 0.5), 0.95, false, WorldGen.MAT_DIRT])
	# каменные блоки дают камень, щебень и дорожное покрытие — немного
	match int(b["mat"]):
		WorldGen.MAT_STONE:
			inventory.add("stone", 6)
		WorldGen.MAT_GRAVEL, WorldGen.MAT_ASPHALT, WorldGen.MAT_CONCRETE:
			inventory.add("stone", 2)


func _hit_plant(inst: Node, pos: Vector3) -> void:
	var kind: String = inst.get_meta("kind", "tree")
	var target := "tree"
	var base_hp := 200.0
	var drop := "planks"
	var drop_n := 47
	var col := Color(0.5, 0.35, 0.2)
	if kind == "rock":
		# валун: прочность и выход камня растут с размером (масштаб 0.7..1.5); камень выдаётся с каждым ударом
		var rt := clampf((float((inst as Node3D).scale.x) - 0.7) / 0.8, 0.0, 1.0)
		var rhp := snappedf(lerpf(160.0, 480.0, rt), 1.0)
		var total := roundi(rhp / 6.0)
		inst.set_meta("hp_max", rhp)
		var before: float = float(inst.get_meta("hp", rhp))
		var after := before - _tool_dmg("rock")
		inst.set_meta("hp", after)
		# сколько камня положено за снятую прочность (без потерь на округлении)
		var given := roundi(total * (1.0 - clampf(before, 0.0, rhp) / rhp))
		var due := roundi(total * (1.0 - clampf(after, 0.0, rhp) / rhp))
		if due > given:
			inventory.add("stone", due - given)
		var gray := Color(0.5, 0.5, 0.48)
		var rtex := Debris.node_tex(inst)   # порода валуна
		Debris.burst(get_tree().current_scene, pos, gray, 4, 2.4, 0.07, 3.0, rtex)
		if after <= 0.0:
			Debris.burst(get_tree().current_scene, (inst as Node3D).global_position + Vector3.UP * 0.5, gray, 10, 3.0, 0.12, 4.0, rtex)
			Debris.dust(get_tree().current_scene, (inst as Node3D).global_position + Vector3.UP * 0.5, gray, 1.2)
			_removed(inst)
		return
	elif kind == "bush":
		target = "bush"
		base_hp = 30.0
		drop = "fiber"
		drop_n = 2
		if randf() < 0.45:
			inventory.add("berries", randi_range(2, 5))   # кусты иногда с ягодами
		col = Color(0.3, 0.5, 0.2)
	elif kind == "bench":
		# скамейка в парке: ломается быстро, немного дерева
		base_hp = 60.0
		drop = "wood"
		drop_n = 3 + absi(hash((inst as Node3D).global_position)) % 3
		col = Color(0.35, 0.5, 0.5)
	elif kind == "grass_tuft":
		_removed(inst)
		inventory.add("fiber", 1)
		return
	else:
		# дерево: прочность и доски растут с размером (масштаб 0.8..1.25): мелкое 200 хп / 47 досок, крупное 500 хп / ~118 досок
		var t := clampf((float((inst as Node3D).scale.x) - 0.8) / 0.45, 0.0, 1.0)
		base_hp = snappedf(lerpf(200.0, 500.0, t), 0.01)
		drop_n = int(floor(47.0 * base_hp / 200.0 + 0.5))
	inst.set_meta("hp_max", base_hp)
	var hp: float = float(inst.get_meta("hp", base_hp)) - _tool_dmg(target)
	inst.set_meta("hp", hp)
	# щепки коры/дерева текстурой модели; куст — плоские листочки цветом (текстура листвы с прозрачностью)
	var ptex: Texture2D = null if kind == "bush" else Debris.node_tex(inst)
	var pflat := 0.15 if kind == "bush" else 0.5
	var ptint := Debris.node_tint(inst)
	Debris.burst(get_tree().current_scene, pos, col, 3, 2.0, 0.06, 2.5, ptex, pflat, ptint)
	if hp <= 0.0:
		Debris.burst(get_tree().current_scene, (inst as Node3D).global_position + Vector3.UP, col, 8, 3.0, 0.1, 4.0, ptex, pflat, ptint)
		if not kind in ["bush", "bench"]:   # дерево (oak/pine/dead_tree)
			Sfx.play_at(self, "tree_fall", (inst as Node3D).global_position + Vector3.UP * 2.0, 2.0, 60.0)
		if kind != "bush":
			Debris.dust(get_tree().current_scene, (inst as Node3D).global_position + Vector3.UP * 0.4, col, 1.4)
		inventory.add(drop, drop_n)
		# дерево, поражённое лишаем: с шансом 17% — 1-2 пенициллина
		if inst.get_meta("lichen", false) and randf() < 0.17:
			var pn := randi_range(1, 2)
			inventory.add("penicillin", pn)
			_toast("+%d %s (лишай)" % [pn, ItemDB.item_name("penicillin")], 3.5)
		_removed(inst)


## Срублено/сломано: не появится снова (Vegetation.removed), у других игроков по сети — тоже пропадёт.
func _removed(n: Node) -> void:
	var pos := (n as Node3D).global_position
	Vegetation.mark_removed(pos)
	Net.op("removed", [pos])
	n.queue_free()


func _raycast() -> Dictionary:
	var from := cam.global_position
	var to := from - cam.global_basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1   # землю/дороги копаем, остальное — нет
	return get_world_3d().direct_space_state.intersect_ray(q)


func dig(radius: float = 0.9) -> bool:
	var hit := _raycast()
	if hit.is_empty():
		return false
	terrain.edit_sphere(hit["position"] - hit["normal"] * 0.4, radius, false)
	Net.op("terrain", [hit["position"] - hit["normal"] * 0.4, radius, false, WorldGen.MAT_DIRT])
	return true


func place(radius: float = 0.8) -> bool:
	var hit := _raycast()
	if hit.is_empty():
		return false
	var c: Vector3 = hit["position"] + hit["normal"] * 0.9
	if (c - (global_position + Vector3.UP * 0.9)).length() < radius + 0.9:
		return false
	terrain.edit_sphere(c, radius, true, WorldGen.MAT_DIRT)
	Net.op("terrain", [c, radius, true, WorldGen.MAT_DIRT])
	return true
