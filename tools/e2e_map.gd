extends SceneTree
## Сквозной тест большой карты через настоящее меню: «Продолжить» (или «Играть» после «Сгенерировать») -> M -> тянуть
## карту мышью -> колесо -> ПКМ-метка. Нужно окно (не headless). Снимки: <prefix>_1_open.png, _2_drag.png, _3_zoom.png
## godot --path . --script res://tools/e2e_map.gd -- E:/путь/префикс

var fails := 0
var prefix := "res://shots/e2e"


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		prefix = a[0]
	_run()


func _run() -> void:
	await process_frame
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 5:
		await process_frame
	var btn := _find_button(current_scene, "Продолжить")
	if btn == null:
		btn = _find_button(current_scene, "Сгенерировать")
		print("нет сохранения: «Сгенерировать» -> «Играть»")
		btn.pressed.emit()
		var play := _find_button(current_scene, "Играть")
		var t := Time.get_ticks_msec()
		while play.disabled and Time.get_ticks_msec() - t < 240000:
			await process_frame
		btn = play
	print("нажимаю: ", btn.text)
	btn.pressed.emit()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await process_frame
		if current_scene != null and current_scene.name == "Main" and current_scene.get("_spawned") == true:
			break
	check("игра загружена (сцена Main, игрок появился)", current_scene != null and current_scene.name == "Main")
	await create_timer(8.0).timeout    # дать миру прогрузиться

	var mm: Minimap = get_first_node_in_group("minimap") as Minimap
	check("карта в слое выше HUD", mm.get_parent() is CanvasLayer and (mm.get_parent() as CanvasLayer).layer > 5)
	var vp := root.get_visible_rect().size
	var c := vp * 0.5
	print("режим мыши в игре: ", Input.mouse_mode)
	var mode0 := Input.mouse_mode

	_key(KEY_M)
	for i in 3:
		await process_frame
	check("M открывает большую карту", mm.expanded and Minimap.is_open)
	check("мышь стала видимой", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	await create_timer(0.5).timeout
	_shot("_1_open")

	# перетаскивание ЛКМ
	var before := mm._view_center()
	_mb(c, MOUSE_BUTTON_LEFT, true)
	for i in 10:
		_motion(c + Vector2(-30, -15) * (i + 1), Vector2(-30, -15))
		await process_frame
	_mb(c + Vector2(-300, -150), MOUSE_BUTTON_LEFT, false)
	await process_frame
	var after := mm._view_center()
	check("перетаскивание сдвинуло карту (%.0f м)" % before.distance_to(after), before.distance_to(after) > 20.0)
	check("после перетаскивания карта не следует за игроком", not mm._follow)
	await create_timer(0.3).timeout
	_shot("_2_drag")

	# колесо — приближение к курсору
	var v0 := mm._view_m
	for i in 3:
		_wheel(c, MOUSE_BUTTON_WHEEL_UP)
		await process_frame
	check("колесо приближает (%d -> %d м)" % [int(v0), int(mm._view_m)], mm._view_m < v0)
	var marks0 := Minimap.marks.size()
	_mb(c + Vector2(80, 40), MOUSE_BUTTON_RIGHT, true)
	_mb(c + Vector2(80, 40), MOUSE_BUTTON_RIGHT, false)
	await process_frame
	check("ПКМ ставит метку", Minimap.marks.size() == marks0 + 1)
	# Пробел — к игроку
	await create_timer(0.3).timeout
	_shot("_3_zoom")
	_key(KEY_SPACE)
	await process_frame
	check("Пробел возвращает к игроку", mm._follow)
	_key(KEY_M)
	for i in 3:
		await process_frame
	check("M закрывает карту", not mm.expanded and not Minimap.is_open)
	check("режим мыши возвращён как был", Input.mouse_mode == mode0)

	# сравнение карты с реальным миром: вид строго вниз с высоты и карта на ту же точку
	var pl: Player = current_scene.player
	var spot := Vector2(pl.global_position.x, pl.global_position.z)
	pl.flying = true
	pl.position.y += 420.0
	pl.set_look(0.0, -1.5707)
	await create_timer(10.0).timeout
	_shot("_4_real_top")
	mm.debug_open(spot, 640.0)
	await create_timer(8.0).timeout    # дать чёткому превью достроиться
	_shot("_5_map_same_spot")
	print("чёткое превью: состояние ", mm._hi_state)
	check("чёткое превью построено", mm._hi_state == 2)

	Minimap.marks.clear()
	print("RESULT fails=", fails)
	quit(fails)


func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png(prefix + tag + ".png")


func _find_button(n: Node, starts: String) -> Button:
	if n is Button and (n as Button).text.begins_with(starts):
		return n as Button
	for ch in n.get_children():
		var r := _find_button(ch, starts)
		if r != null:
			return r
	return null


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)


func _mb(pos: Vector2, idx: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = idx
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if (pressed and idx == MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(e)


func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _wheel(pos: Vector2, idx: MouseButton) -> void:
	_mb(pos, idx, true)
	_mb(pos, idx, false)
