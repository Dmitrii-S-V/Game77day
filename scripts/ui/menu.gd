extends Control
## Меню "Новый мир": сид, размер (кратно 1024), количество городов / POI / рек / озёр,
## соотношение гор / холмов / равнин, предпросмотр карты, кнопки "Сгенерировать" и "Играть".

var _seed_edit: LineEdit
var _size_spin: SpinBox
var _towns: HSlider
var _pois: HSlider
var _rivers: HSlider
var _lakes: HSlider
var _mount: HSlider
var _hill: HSlider
var _plain: HSlider
var _burn: HSlider
var _gen_btn: Button
var _play_btn: Button
var _status: Label
var _progress: ProgressBar
var _info: Label
var _preview: TextureRect
var _world: WorldMap
var _busy := false
var _lock := false


func _ready() -> void:
	if Net.active():
		Net.inst.close()      # вернулись в меню из сетевой игры
	UiTheme.apply_cursor()
	var th := Theme.new()
	th.default_font_size = 18
	theme = th
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 28)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	var title := Label.new()
	title.text = "77Days — новый мир"
	title.add_theme_font_size_override("font_size", 30)
	left.add_child(title)

	var seed_row := HBoxContainer.new()
	left.add_child(seed_row)
	var seed_lbl := Label.new()
	seed_lbl.text = "Сид"
	seed_lbl.custom_minimum_size = Vector2(150, 0)
	seed_row.add_child(seed_lbl)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(Game.params.seed_value)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var rnd := Button.new()
	rnd.text = "Случайный"
	rnd.pressed.connect(func() -> void: _seed_edit.text = str(randi() % 1000000000))
	seed_row.add_child(rnd)

	var size_row := HBoxContainer.new()
	left.add_child(size_row)
	var size_lbl := Label.new()
	size_lbl.text = "Размер карты, м"
	size_lbl.custom_minimum_size = Vector2(150, 0)
	size_row.add_child(size_lbl)
	_size_spin = SpinBox.new()
	_size_spin.min_value = 1024
	_size_spin.max_value = 8192
	_size_spin.step = 1024
	_size_spin.value = Game.params.size
	_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_size_spin)

	_towns = _slider(left, "Города", 0, 40, Game.params.towns)
	_pois = _slider(left, "POI", 0, 80, Game.params.pois)
	_rivers = _slider(left, "Реки", 0, 12, Game.params.rivers)
	_lakes = _slider(left, "Озёра", 0, 20, Game.params.lakes)
	_mount = _slider(left, "Горы, %", 0, 100, Game.params.pct_mountain)
	_hill = _slider(left, "Холмы, %", 0, 100, Game.params.pct_hill)
	_plain = _slider(left, "Равнины, %", 0, 100, Game.params.pct_plain)
	_burn = _slider(left, "Выжженная земля, %", 0, 60, Game.params.pct_burn)
	_mount.value_changed.connect(func(_v: float) -> void: _balance(_mount))
	_hill.value_changed.connect(func(_v: float) -> void: _balance(_hill))
	_plain.value_changed.connect(func(_v: float) -> void: _balance(_plain))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	left.add_child(btns)
	_gen_btn = Button.new()
	_gen_btn.text = "Сгенерировать"
	_gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gen_btn.custom_minimum_size = Vector2(0, 46)
	_gen_btn.pressed.connect(_on_generate)
	btns.add_child(_gen_btn)
	_play_btn = Button.new()
	_play_btn.text = "Играть"
	_play_btn.disabled = true
	_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_btn.custom_minimum_size = Vector2(0, 46)
	_play_btn.pressed.connect(_on_play)
	btns.add_child(_play_btn)
	if SaveGame.exists():
		var cont := Button.new()
		cont.text = "Продолжить  (" + SaveGame.describe() + ")"
		cont.custom_minimum_size = Vector2(0, 46)
		cont.clip_text = true
		cont.pressed.connect(_on_continue)
		left.add_child(cont)
	var gfx_row := HBoxContainer.new()
	left.add_child(gfx_row)
	var gfx_lbl := Label.new()
	gfx_lbl.text = "Графика"
	gfx_lbl.custom_minimum_size = Vector2(150, 0)
	gfx_row.add_child(gfx_lbl)
	var gfx := Button.new()
	gfx.text = "Настройки графики…"
	gfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx.pressed.connect(_open_gfx)
	gfx_row.add_child(gfx)
	_build_net(left)
	var ed_btn := Button.new()
	ed_btn.text = "Редактор структур"
	ed_btn.custom_minimum_size = Vector2(0, 38)
	ed_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/editor.tscn"))
	left.add_child(ed_btn)

	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(0, 20)
	left.add_child(_progress)
	_status = Label.new()
	_status.text = "Задайте параметры и нажмите «Сгенерировать»"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.modulate = Color(0.7, 0.85, 1.0)
	left.add_child(_info)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var pv_title := Label.new()
	pv_title.text = "Предпросмотр карты  (красный — мегаполис, оранжевый — город, жёлтый — деревня, фиолетовый — POI, белый — старт)"
	pv_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(pv_title)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)

	# отладка: godot --path . -- --menu-shot=C:/path/menu.png
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menu-shot="):
			_menu_shot(a.substr(12))
		elif a == "--menu-play":
			_menu_play()
		elif a == "--menu-host":     # отладка сети: сгенерировать мир и открыть сервер
			_net_host.button_pressed = true
			_menu_play()
		elif a.begins_with("--menu-join="):
			_net_ip.text = a.substr(12)
			_net_name.text = "Клиент"
			_on_join.call_deferred()      # не из _ready: корень сцены ещё занят


## Сетевая игра (кооператив по ENet, порт UDP 7777): имя игрока; галочка «открыть мир» — «Играть»/«Продолжить»
## запускают игру как хост (сервер — сама игра, отдельный не нужен); «Подключиться» — к хосту по IP.
var _net_name: LineEdit
var _net_ip: LineEdit
var _net_host: CheckBox
var _join_btn: Button
const NET_CFG := "user://net.cfg"


func _build_net(left: Control) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NET_CFG)
	var t := Label.new()
	t.text = "Сетевая игра (кооператив, UDP-порт %d)" % Net.PORT
	t.modulate = Color(0.75, 0.85, 1.0)
	left.add_child(t)
	var r1 := HBoxContainer.new()
	left.add_child(r1)
	var l1 := Label.new()
	l1.text = "Имя"
	l1.custom_minimum_size = Vector2(150, 0)
	r1.add_child(l1)
	_net_name = LineEdit.new()
	_net_name.text = String(cfg.get_value("net", "name", "Выживший %d" % (randi() % 100)))
	_net_name.max_length = 24
	_net_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_net_name)
	_net_host = CheckBox.new()
	_net_host.text = "Открыть мир для друзей (я — хост)"
	_net_host.button_pressed = bool(cfg.get_value("net", "host", false))
	left.add_child(_net_host)
	var r2 := HBoxContainer.new()
	left.add_child(r2)
	var l2 := Label.new()
	l2.text = "IP хоста"
	l2.custom_minimum_size = Vector2(150, 0)
	r2.add_child(l2)
	_net_ip = LineEdit.new()
	_net_ip.text = String(cfg.get_value("net", "ip", "127.0.0.1"))
	_net_ip.placeholder_text = "192.168.1.5 или 26.x.x.x (Radmin VPN)"
	_net_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_net_ip)
	_join_btn = Button.new()
	_join_btn.text = "Подключиться"
	_join_btn.pressed.connect(_on_join)
	r2.add_child(_join_btn)


func _save_net_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "name", _net_name.text.strip_edges())
	cfg.set_value("net", "ip", _net_ip.text.strip_edges())
	cfg.set_value("net", "host", _net_host.button_pressed)
	cfg.save(NET_CFG)
	Net.my_name = _net_name.text.strip_edges() if _net_name.text.strip_edges() != "" else "Игрок"


## Перед запуском игры: хост — открыть сервер в игровой сцене (main.gd), иначе одиночная.
func _prepare_host() -> void:
	_save_net_cfg()
	Game.net_host = _net_host.button_pressed
	if Game.net_host:
		Net.ensure(get_tree())


func _on_join() -> void:
	if _busy:
		return
	_save_net_cfg()
	var addr := _net_ip.text.strip_edges()
	var port := Net.PORT
	if addr.contains(":"):
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	if addr == "":
		_status.text = "Введите IP хоста"
		return
	var net := Net.ensure(get_tree())
	if not net.status.is_connected(_on_net_status):
		net.status.connect(_on_net_status)
		net.failed.connect(_on_net_failed)
		net.welcome_received.connect(_on_welcome)
	_busy = true
	_join_btn.disabled = true
	_gen_btn.disabled = true
	_play_btn.disabled = true
	if net.join(addr, port) != OK:
		_on_net_failed("Не удалось начать подключение")


func _on_net_status(text: String) -> void:
	_status.text = text


func _on_net_failed(reason: String) -> void:
	_status.text = "Сеть: " + reason
	_busy = false
	_join_btn.disabled = false
	_gen_btn.disabled = false
	_play_btn.disabled = _world == null


## Хост прислал мир: генерируем его у себя по тем же параметрам (детерминирован), правки — поверх, в игровой сцене.
func _on_welcome(d: Dictionary) -> void:
	var p := SaveGame.params_from_dict(d["params"])
	Game.params = p
	_status.text = "Генерация мира хоста…"
	var w := WorldMap.new()
	await w.generate(p, get_tree(), _on_progress)
	if not Net.active():
		_on_net_failed("Соединение потеряно во время загрузки")
		return
	Game.pending_save = d
	Game.net_host = false
	Game.start_world(w)


## Подробные настройки графики (те же, что F7 в игре) — окно поверх меню.
func _open_gfx() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Графика"
	dlg.ok_button_text = "Готово"
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var details := GraphicsSettings.make_details(func() -> void: GraphicsSettings.apply_viewport(get_viewport()))
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(details)
	dlg.add_child(sc)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _menu_play() -> void:
	await _on_generate()
	_on_play()


func _menu_shot(path: String) -> void:
	await _on_generate()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Menu shot saved ", path)
	get_tree().quit()


func _slider(parent: Control, label: String, lo: int, hi: int, value: int) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = str(value)
	row.add_child(val)
	s.value_changed.connect(func(v: float) -> void: val.text = str(int(v)))
	return s


## Три процента всегда в сумме 100: остальные ползунки перераспределяются пропорционально.
func _balance(src: HSlider) -> void:
	if _lock:
		return
	_lock = true
	var others: Array[HSlider] = []
	for s: HSlider in [_mount, _hill, _plain]:
		if s != src:
			others.append(s)
	var remain := 100.0 - src.value
	var total := others[0].value + others[1].value
	var a := remain * 0.5
	if total > 0.0:
		a = remain * others[0].value / total
	others[0].value = roundf(a)
	others[1].value = remain - roundf(a)
	_lock = false


func _on_generate() -> void:
	if _busy:
		return
	_busy = true
	_gen_btn.disabled = true
	_play_btn.disabled = true
	var p := WorldParams.new()
	p.seed_value = WorldParams.seed_from_text(_seed_edit.text)
	p.size = int(_size_spin.value)
	p.towns = int(_towns.value)
	p.pois = int(_pois.value)
	p.rivers = int(_rivers.value)
	p.lakes = int(_lakes.value)
	p.pct_mountain = int(_mount.value)
	p.pct_hill = int(_hill.value)
	p.pct_plain = int(_plain.value)
	p.pct_burn = int(_burn.value)
	Game.params = p
	_info.text = ""
	var w := WorldMap.new()
	await w.generate(p, get_tree(), _on_progress)
	_on_progress(0.95, "Предпросмотр")
	var img: Image = await w.render_preview(768, get_tree())
	_preview.texture = ImageTexture.create_from_image(img)
	_world = w
	_progress.value = 1.0
	_status.text = "Готово. Можно играть или изменить параметры."
	_info.text = p.summary() + "\n" + w.info
	_gen_btn.disabled = false
	_play_btn.disabled = false
	_busy = false


func _on_progress(frac: float, text: String) -> void:
	_progress.value = frac
	_status.text = text + "…"


## Загрузка сохранения: мир заново генерируется по сохранённым параметрам (он детерминирован), изменения игрока —
## поверх него в игровой сцене.
func _on_continue() -> void:
	if _busy:
		return
	var d := SaveGame.read()
	if d.is_empty():
		_status.text = "Не удалось прочитать сохранение"
		return
	_busy = true
	_gen_btn.disabled = true
	_play_btn.disabled = true
	var p := SaveGame.params_from_dict(d["params"])
	Game.params = p
	var w := WorldMap.new()
	await w.generate(p, get_tree(), _on_progress)
	Game.pending_save = d
	_prepare_host()
	Game.start_world(w)


func _on_play() -> void:
	if _world != null and _world.ready:
		_prepare_host()
		Game.start_world(_world)
