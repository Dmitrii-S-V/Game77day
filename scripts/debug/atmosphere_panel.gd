class_name AtmospherePanel
extends CanvasLayer
## Отладочная настройка атмосферы (F6): время суток (ползунок, пауза, быстрые кнопки), кровавая луна принудительно,
## редактор профилей Atmosphere («День / Сумерки / Ночь / Кровавая луна») — небо, солнце и луна, свет и тени,
## туман, цвет. «Показывать только этот профиль» — видеть правку без смешивания. Сохранение — data/atmosphere.json.

static var _inst: AtmospherePanel

var main: Node
var _profile := "day"
var _rows: Array = []          # Callable — обновить значения из профиля
var _time_sl: HSlider
var _time_lbl: Label
var _weights_lbl: Label
var _status: Label
var _box: VBoxContainer


static func toggle(m: Node) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
		_inst = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var p := AtmospherePanel.new()
	p.main = m
	m.add_child(p)
	_inst = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 61
	Atmosphere.ensure()
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 60)
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.88)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, minf(get_viewport().get_visible_rect().size.y - 90.0, 900.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 4)
	sc.add_child(_box)
	var title := Label.new()
	title.text = "Атмосфера (F6 — закрыть)"
	title.add_theme_font_size_override("font_size", 20)
	_box.add_child(title)

	# --- время суток ---
	var tr := HBoxContainer.new()
	_box.add_child(tr)
	_time_lbl = Label.new()
	_time_lbl.custom_minimum_size = Vector2(110, 0)
	tr.add_child(_time_lbl)
	_time_sl = HSlider.new()
	_time_sl.min_value = 0.0
	_time_sl.max_value = 24.0
	_time_sl.step = 0.05
	_time_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_sl.value_changed.connect(func(v: float) -> void: main.time_of_day = fposmod(v / 24.0, 1.0))
	tr.add_child(_time_sl)
	var qr := HBoxContainer.new()
	_box.add_child(qr)
	for q: Array in [["Рассвет", 6.0], ["Утро", 8.0], ["День", 13.0], ["Закат", 18.0], ["Ночь", 23.5]]:
		var b := Button.new()
		b.text = q[0]
		var hh: float = q[1]
		b.pressed.connect(func() -> void: main.time_of_day = hh / 24.0)
		qr.add_child(b)
	var pause := CheckBox.new()
	pause.text = "Остановить время"
	pause.button_pressed = main.time_paused
	pause.toggled.connect(func(on: bool) -> void: main.time_paused = on)
	_box.add_child(pause)
	var blood := CheckBox.new()
	blood.text = "Кровавая луна (принудительно)"
	blood.button_pressed = main.atmo_force_blood
	blood.toggled.connect(func(on: bool) -> void: main.atmo_force_blood = on)
	_box.add_child(blood)
	_weights_lbl = Label.new()
	_weights_lbl.modulate = Color(0.7, 0.8, 0.9)
	_box.add_child(_weights_lbl)

	# --- профиль ---
	var pr := HBoxContainer.new()
	_box.add_child(pr)
	var pl := Label.new()
	pl.text = "Профиль"
	pl.custom_minimum_size = Vector2(110, 0)
	pr.add_child(pl)
	var ob := OptionButton.new()
	for k: String in Atmosphere.PROFILES:
		ob.add_item(Atmosphere.PROFILE_NAMES[k])
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(ob)
	var prev := CheckBox.new()
	prev.text = "Показывать только этот профиль"
	prev.toggled.connect(func(on: bool) -> void: main.atmo_preview = _profile if on else "")
	_box.add_child(prev)
	ob.item_selected.connect(func(i: int) -> void:
		_profile = Atmosphere.PROFILES[i]
		if prev.button_pressed:
			main.atmo_preview = _profile
		_refresh())
	var br := HBoxContainer.new()
	_box.add_child(br)
	var save := Button.new()
	save.text = "Сохранить все профили"
	save.pressed.connect(func() -> void:
		var path := Atmosphere.save()
		_status.text = ("Сохранено: " + path) if path != "" else "Не удалось сохранить")
	br.add_child(save)
	var reset := Button.new()
	reset.text = "Сбросить профиль"
	reset.pressed.connect(func() -> void:
		Atmosphere.reset(_profile)
		_refresh()
		_status.text = "Профиль сброшен (не сохранён)")
	br.add_child(reset)
	_status = Label.new()
	_status.modulate = Color(0.6, 0.9, 0.6)
	_box.add_child(_status)

	# --- параметры по группам ---
	var group := ""
	for prm: Array in Atmosphere.PARAMS:
		if prm[2] != group:
			group = prm[2]
			var gl := Label.new()
			gl.text = "— " + group + " —"
			gl.add_theme_font_size_override("font_size", 17)
			gl.modulate = Color(0.95, 0.85, 0.55)
			_box.add_child(gl)
		_add_param(prm)
	_refresh()


func _add_param(prm: Array) -> void:
	var key: String = prm[0]
	var row := HBoxContainer.new()
	_box.add_child(row)
	var lb := Label.new()
	lb.text = prm[1]
	lb.custom_minimum_size = Vector2(250, 0)
	lb.clip_text = true
	row.add_child(lb)
	if prm[3] == "c":
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(120, 26)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.edit_alpha = false
		cp.color_changed.connect(func(c: Color) -> void: Atmosphere.profiles[_profile][key] = c)
		row.add_child(cp)
		_rows.append(func() -> void: cp.color = Atmosphere.profiles[_profile][key])
	else:
		var sl := HSlider.new()
		sl.min_value = prm[4]
		sl.max_value = prm[5]
		sl.step = (float(prm[5]) - float(prm[4])) / 400.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sl)
		var val := Label.new()
		val.custom_minimum_size = Vector2(62, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		sl.value_changed.connect(func(v: float) -> void:
			Atmosphere.profiles[_profile][key] = v
			val.text = _fmt(v))
		_rows.append(func() -> void:
			var v := float(Atmosphere.profiles[_profile][key])
			sl.set_value_no_signal(v)
			val.text = _fmt(v))


static func _fmt(v: float) -> String:
	return "%.0f" % v if absf(v) >= 100.0 else ("%.2f" % v if absf(v) >= 0.1 or v == 0.0 else "%.4f" % v)


func _refresh() -> void:
	for r: Callable in _rows:
		r.call()


func _process(_d: float) -> void:
	var h: float = main.time_of_day * 24.0
	_time_sl.set_value_no_signal(h)
	_time_lbl.text = "Время %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
	var parts: Array[String] = []
	for k: String in main.atmo_weights:
		var w := float(main.atmo_weights[k])
		if w > 0.005:
			parts.append("%s %d%%" % [Atmosphere.PROFILE_NAMES[k].get_slice(" ", 0), roundi(w * 100.0)])
	_weights_lbl.text = "Сейчас действует: " + ", ".join(parts)
