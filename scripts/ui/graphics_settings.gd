class_name GraphicsSettings
extends RefCounted
## Настройки графики: пресеты качества (минимальные / низкие / средние / ультра), сохранение в user://settings.cfg,
## применение к окну и к игровой сцене (main.gd) — на лету, без перезапуска.

const PATH := "user://settings.cfg"
const NAMES := ["Минимальные", "Низкие", "Средние", "Ультра"]
const MIN := 0
const LOW := 1
const MED := 2
const ULTRA := 3

# scale — разрешение 3D (FSR 1 ниже 1.0); shadow — дальность теней (0 — без теней), splits — каскады;
# ssao 0/1/2 — нет / обычное / высокое; aa 0 нет, 1 FXAA, 2 SMAA; terrain — радиус ближнего ландшафта (чанки 16 м);
# grass — радиус травы (колонки 16 м, 0 — нет); detail — до какой дистанции рельеф карт нормалей (м);
# roads — плавные стыки покрытий; far — дальность камеры (м); post — свечение и плёночный постэффект
const PRESETS := [
	{"scale": 0.67, "shadow": 0.0, "splits": 2, "ssao": 0, "aa": 0, "terrain": 4, "grass": 0, "detail": 0.0, "roads": false, "far": 1800.0, "post": false},
	{"scale": 0.8, "shadow": 100.0, "splits": 2, "ssao": 0, "aa": 1, "terrain": 5, "grass": 2, "detail": 30.0, "roads": true, "far": 2600.0, "post": true},
	{"scale": 1.0, "shadow": 170.0, "splits": 4, "ssao": 1, "aa": 1, "terrain": 6, "grass": 3, "detail": 85.0, "roads": true, "far": 4000.0, "post": true},
	{"scale": 1.0, "shadow": 240.0, "splits": 4, "ssao": 2, "aa": 2, "terrain": 7, "grass": 4, "detail": 120.0, "roads": true, "far": 5000.0, "post": true},
]

static var level := MED
static var pom := false        # объёмный рельеф покрытий (Parallax Occlusion Mapping) — отдельная галочка
## Ручные настройки поверх пресета (ключи как в PRESETS + fov): выбор пресета их сбрасывает.
static var custom := {}
const FOV_DEFAULT := 70.0   # чуть уже прежних 75° — сильнее погружение
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var def := MIN if OS.has_feature("mobile") else MED     # телефон — по умолчанию минимальные
	level = def
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		level = clampi(int(cf.get_value("graphics", "preset", def)), 0, PRESETS.size() - 1)
		pom = bool(cf.get_value("graphics", "pom", false))
		custom = cf.get_value("graphics", "custom", {})


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("graphics", "preset", level)
	cf.set_value("graphics", "pom", pom)
	cf.set_value("graphics", "custom", custom)
	cf.save(PATH)


static func preset() -> Dictionary:
	load_settings()
	var p: Dictionary = (PRESETS[level] as Dictionary).duplicate()
	p["fov"] = FOV_DEFAULT
	p.merge(custom, true)
	return p


## Выбор пресета: ручные настройки сбрасываются, кроме поля зрения (это не качество, а вкус).
static func set_level(l: int) -> void:
	level = clampi(l, 0, PRESETS.size() - 1)
	_loaded = true
	var fov: Variant = custom.get("fov")
	custom = {}
	if fov != null:
		custom["fov"] = fov
	save_settings()


## Одна ручная настройка (key — как в PRESETS, или "fov").
static func set_value(key: String, v: Variant) -> void:
	load_settings()
	custom[key] = v
	save_settings()


static func is_custom() -> bool:
	load_settings()
	for k: String in custom:
		if k != "fov":
			return true
	return false


## Окно: разрешение 3D и сглаживание (действует и в меню, и в игре).
static func apply_viewport(vp: Viewport) -> void:
	var p := preset()
	var s: float = p["scale"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s
	vp.fsr_sharpness = 1.0   # мягче стандартной 0.2: иначе листва и трава при апскейле рябят
	match int(p["aa"]):
		0: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA


## Игровая сцена (main.gd): свет, окружение, дальности, шейдеры.
static func apply_world(m: Node) -> void:
	var p := preset()
	apply_viewport(m.get_viewport())
	var sh: float = p["shadow"]
	m.shadows_on = sh > 0.0
	for l: DirectionalLight3D in [m.sun, m.moon]:
		l.directional_shadow_max_distance = maxf(sh, 30.0)
		l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p["splits"]) >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		if sh <= 0.0:
			l.shadow_enabled = false
	RenderingServer.directional_shadow_atlas_set_size(4096 if sh > 120.0 else 2048, true)   # дальние тени — шире атлас
	var env: Environment = m.env
	env.ssao_enabled = int(p["ssao"]) > 0
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_HIGH if int(p["ssao"]) >= 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, int(p["ssao"]) < 2, 0.5, 2, 50.0, 300.0)
	env.glow_enabled = bool(p["post"])
	if m.post_layer != null:
		m.post_layer.visible = bool(p["post"])
	if m.player != null:
		m.player.cam.far = float(p["far"])
		m.player.cam.fov = float(p["fov"])
	# ландшафт, трава, дальний ландшафт
	var tr := int(p["terrain"])
	m.terrain.set_view_radius(tr)
	# растительность и постройки появляются только на построенном ландшафте: их радиус — не больше его;
	# граница передачи деревьев дальним моделям (FarProps) сдвигается вместе с радиусом
	var vr := mini(6, tr)
	# граница эстафеты — внутри гарантированно загруженной зоны колонок (на (vr-1.5) колонки): иначе на краю
	# радиуса ближнее дерево ещё не создано, а дальняя модель уже растворилась — дерево «пропадало» при подходе
	var ne := (vr - 1.5) * 16.0
	m.veg.set_range(vr, ne)
	m.far_props.set_near_end(ne)
	m.settlement.set_radius(mini(5, tr))
	m.far.set_level0_sink(minf(86.0, int(p["terrain"]) * 16.0 - 10.0))
	m.grass.set_radius(int(p["grass"]), tr)   # полная плотность — в «grass», дальше редкие кусты до радиуса ландшафта
	var tm: ShaderMaterial = m.terrain.material
	tm.set_shader_parameter("detail_far", maxf(float(p["detail"]), 0.01))
	tm.set_shader_parameter("use_pom", pom)
	var cur: Variant = tm.get_shader_parameter("perf_skip")   # null, если ещё не задавался
	var skip := (int(cur) if cur != null else 0) & ~2
	if not bool(p["roads"]):
		skip |= 2
	tm.set_shader_parameter("perf_skip", skip)


## Галочка «Объёмный рельеф (POM)». on_change() вызывается после сохранения.
static func make_pom_checkbox(on_change: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = "Объёмный рельеф дорог (POM)"
	cb.tooltip_text = "Камешки асфальта и плитка тротуара выглядят объёмными вблизи (до ~15 м). Стоит около 1-2 мс кадра."
	load_settings()
	cb.button_pressed = pom
	cb.toggled.connect(func(on: bool) -> void:
		pom = on
		_loaded = true
		save_settings()
		on_change.call())
	return cb


## Выпадающий список пресетов (для меню и внутриигровой панели). on_change(level) вызывается после сохранения.
static func make_selector(on_change: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for i in NAMES.size():
		ob.add_item(NAMES[i], i)
	load_settings()
	ob.select(level)
	ob.item_selected.connect(func(i: int) -> void:
		set_level(i)
		on_change.call(i))
	return ob


## Подробные настройки: ползунки и списки, применяются сразу (on_change — например apply_world), сохраняются.
## Пресет сверху выставляет всё разом; ручная правка любого пункта — «Свои».
static func make_details(on_change: Callable) -> VBoxContainer:
	load_settings()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var rows: Array = []        # [Callable обновления]
	var head := HBoxContainer.new()
	box.add_child(head)
	var hl := Label.new()
	hl.text = "Пресет"
	hl.custom_minimum_size = Vector2(265, 0)
	head.add_child(hl)
	var ob := OptionButton.new()
	for i in NAMES.size():
		ob.add_item(NAMES[i], i)
	ob.add_item("Свои", NAMES.size())
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ob)
	var sync_preset := func() -> void:
		ob.select(NAMES.size() if is_custom() else level)
	sync_preset.call()
	var refresh := func() -> void:
		sync_preset.call()
		for r: Callable in rows:
			r.call()
	ob.item_selected.connect(func(i: int) -> void:
		if i < NAMES.size():
			set_level(i)
		refresh.call()
		on_change.call())
	# слайдер: [ключ, подпись, мин, макс, шаг, формат]
	for s: Array in [
			["fov", "Поле зрения (FOV)", 55.0, 100.0, 1.0, "%d°"],
			["scale", "Разрешение 3D", 0.5, 1.0, 0.05, "%d%%"],
			["shadow", "Дальность теней, м", 0.0, 300.0, 10.0, "%d"],
			["terrain", "Дальность ландшафта (×16 м)", 3.0, 8.0, 1.0, "%d"],
			["grass", "Дальность травы (×16 м)", 0.0, 5.0, 1.0, "%d"],
			["far", "Дальность прорисовки, м", 1000.0, 5000.0, 100.0, "%d"],
			["detail", "Рельеф текстур до, м", 0.0, 150.0, 5.0, "%d"]]:
		var key: String = s[0]
		var row := HBoxContainer.new()
		box.add_child(row)
		var lb := Label.new()
		lb.text = s[1]
		lb.custom_minimum_size = Vector2(265, 0)
		row.add_child(lb)
		var sl := HSlider.new()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = s[4]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size = Vector2(200, 0)
		row.add_child(sl)
		var val := Label.new()
		val.custom_minimum_size = Vector2(56, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		var fmt: String = s[5]
		var show_v := func(v: float) -> void:
			val.text = fmt % (v * 100.0 if key == "scale" else v)
		var upd := func() -> void:
			sl.set_value_no_signal(float(preset()[key]))
			show_v.call(sl.value)
		upd.call()
		rows.append(upd)
		sl.value_changed.connect(func(v: float) -> void:
			show_v.call(v)
			set_value(key, int(v) if key in ["terrain", "grass"] else v)
			sync_preset.call()
			on_change.call())
	# списки: [ключ, подпись, варианты]
	for o: Array in [
			["ssao", "Затенение (SSAO)", ["Нет", "Обычное", "Высокое"]],
			["aa", "Сглаживание", ["Нет", "FXAA", "SMAA"]],
			["splits", "Каскады теней", ["2 (быстрее)", "4 (чётче вблизи)"]]]:
		var key2: String = o[0]
		var row2 := HBoxContainer.new()
		box.add_child(row2)
		var lb2 := Label.new()
		lb2.text = o[1]
		lb2.custom_minimum_size = Vector2(265, 0)
		row2.add_child(lb2)
		var opt := OptionButton.new()
		for item: String in o[2]:
			opt.add_item(item)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(opt)
		var upd2 := func() -> void:
			var v := int(preset()[key2])
			opt.select((1 if v >= 4 else 0) if key2 == "splits" else v)
		upd2.call()
		rows.append(upd2)
		opt.item_selected.connect(func(i: int) -> void:
			set_value(key2, (4 if i == 1 else 2) if key2 == "splits" else i)
			sync_preset.call()
			on_change.call())
	# галочки
	for c: Array in [["post", "Свечение и плёночный эффект"], ["roads", "Плавные стыки дорог"]]:
		var key3: String = c[0]
		var cb := CheckBox.new()
		cb.text = c[1]
		box.add_child(cb)
		var upd3 := func() -> void: cb.set_pressed_no_signal(bool(preset()[key3]))
		upd3.call()
		rows.append(upd3)
		cb.toggled.connect(func(on: bool) -> void:
			set_value(key3, on)
			sync_preset.call()
			on_change.call())
	box.add_child(make_pom_checkbox(on_change))
	return box
