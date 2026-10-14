class_name InventoryUI
extends CanvasLayer
## Панель быстрого доступа (всегда), окно с вкладками «Инвентарь» (Tab) и «Крафт» (C), полоски здоровья, жажды
## и голода, красная вспышка при уроне. Оформление — UiTheme (потёртые панели, ячейки, кнопки-пластины).
## Рюкзак: без него доступны хотбар + 1 ряд (16 ячеек), после крафта — все 32. Флаг рюкзака живёт здесь.

var inv: Inventory
var _hotbar: Array[Panel] = []
var _grid: Array[Panel] = []
var _win: Control
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _tab := 0
var _cursor: Variant = null
var _cursor_icon: TextureRect
var _cursor_lbl: Label
var _hp_bar: Range
var _thirst_bar: Range
var _hunger_bar: Range
var _stam_bar: Range
var _flash: ColorRect
var _sel_name: Label
var _sel_name_t := 0.0
var _last_sel := -1
# крафт
var _cat := "Все"
var _search: LineEdit
var _cat_btns: Array[Button] = []
var _recipe_box: VBoxContainer
var _recipe := -1          # индекс в CraftDB.recipes()
var _d_icon: TextureRect
var _d_name: Label
var _d_desc: Label
var _d_need: VBoxContainer
var _d_btn: Button
var _d_out: Label

const SLOT := 84           # хотбар
const BIG := 96            # ячейки окна
const GAP := 6
const WIN := Vector2(1220, 620)
const INFO_W := 330        # панель описания справа (инвентарь, креатив)

var _hover_i := -1           # ячейка инвентаря под мышью (-1 — нет)
var _hover_id := ""        # предмет креатива под мышью
var _infos: Array = []     # панели описания: {icon, name, desc, stats, keys}
var _info_flash := ""
var _info_flash_t := 0.0

# рюкзак: флаг живёт здесь, потому что в Inventory поле добавлять не нужно
var _backpack: bool:
	get:
		return inv != null and inv.has_backpack
	set(v):
		if inv != null:
			inv.has_backpack = v

# экипировка: что надето (голова, торс, спина, ноги); item — Dictionary или null
var _eq: Dictionary = {"head": null, "torso": null, "back": null, "legs": null}
var _eq_panels := {}       # слот -> Panel (для отрисовки)

# компас и время (сверху по центру)
var _hud: Panel
var _compass: CompassStrip
var _clock_lbl: Label


func setup(inventory: Inventory) -> void:
	inv = inventory
	layer = 5
	UiTheme.apply_cursor()
	_build()
	inv.changed.connect(refresh)
	refresh()


func is_open() -> bool:
	return _win.visible or Minimap.is_open   # большая карта тоже блокирует стрельбу/удары


## Открыть/закрыть окно; tab — вкладка при открытии (0 инвентарь, 1 крафт). Повторно на открытой вкладке — закрыть.
func toggle(tab: int = 0) -> void:
	if _win.visible and tab != _tab:
		_show_tab(tab)
		return
	_win.visible = not _win.visible
	# хотбар внизу экрана: при открытом окне — живые ячейки (перетаскивание прямо в него), иначе мимо мыши
	for p in _hotbar:
		p.mouse_filter = Control.MOUSE_FILTER_STOP if _win.visible else Control.MOUSE_FILTER_IGNORE
	if _win.visible:
		_show_tab(tab)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _cursor != null:
			inv.add(_cursor["id"], int(_cursor["n"]), {"fill": float(_cursor.get("fill", 1.0))})
			_cursor = null
		if not TouchControls.active():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh()


func set_stats(health: float, thirst: float, hunger: float = 100.0, stamina: float = 100.0) -> void:
	_set_bar(_hp_bar, clampf(health, 0.0, 100.0))
	_set_bar(_thirst_bar, clampf(thirst, 0.0, 100.0))
	_set_bar(_hunger_bar, clampf(hunger, 0.0, 100.0))
	_set_bar(_stam_bar, clampf(stamina, 0.0, 100.0))


## Заметность игрока для зомби (максимум по зомби, 0..100): серая — не замечен, жёлтая — насторожились
## (идут проверить), красная — заметили.
var _aw_bar: Range
var _aw_lbl: Label


func set_awareness(v: float) -> void:
	_aw_bar.value = lerpf(_aw_bar.value, clampf(v, 0.0, 100.0), 0.5)
	var col := Color(0.62, 0.62, 0.6)
	var txt := "Заметность"
	if v >= Zombie.AW_NOTICE - 0.5:
		col = Color(1.0, 0.3, 0.25)
		txt = "Заметили!"
	elif v >= Zombie.AW_INVESTIGATE:
		col = Color(1.0, 0.85, 0.35)
		txt = "Насторожились"
	(_aw_bar.get_meta("fill") as StyleBoxFlat).bg_color = col
	_aw_lbl.text = txt
	_aw_lbl.add_theme_color_override("font_color", Color.WHITE.lerp(col, 0.6))


## Время в мире: день и часы (0..24). Вызывается из кода, который ведёт смену дня и ночи.
## temp — температура воздуха (если не передавать, не показывается).
func set_clock(day: int, hours: float, temp: float = -999.0) -> void:
	var t := "ДЕНЬ: %d     ВРЕМЯ: %02d:%02d" % [day, int(hours) % 24, int(fposmod(hours, 1.0) * 60.0)]
	if temp > -100.0:
		t += "     %d°C" % int(round(temp))
	_clock_lbl.text = t


func flash() -> void:
	_flash.modulate.a = 0.55
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, 0.5)


## Иконка предмета (assets/icons/<id>.png: tools/gen_icons.gd или свои картинки — tools/import_ui_images.gd) или null.
static var _icons := {}


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/icons/%s.png" % id
		_icons[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[id]


# --- рюкзак ----------------------------------------------------------------------------------------------------

## Рюкзак надет?
func _has_backpack() -> bool:
	return _backpack


## Сколько ячеек сейчас доступно: без рюкзака — хотбар + 1 ряд (16), с ним — все 32.
func _capacity() -> int:
	return inv.capacity()


## Рюкзак в руке — надеть на спину (если спина свободна).
func _wear_cursor() -> bool:
	if _cursor == null or String(ItemDB.info(String(_cursor["id"])).get("wear", "")) != "back" or _eq["back"] != null:
		return false
	_eq["back"] = _cursor
	_cursor = null
	_backpack = true
	inv.changed.emit()
	return true


## Загрузка сохранения: рюкзак уже был надет — показать его в слоте «Спина» и открыть ячейки.
func wear_backpack_silently() -> void:
	_eq["back"] = {"id": "backpack", "n": 1}
	_backpack = true
	inv.changed.emit()


## Ctrl+ЛКМ по рюкзаку в ячейке — надеть на спину (если спина свободна).
func _wear_from_slot(i: int) -> bool:
	var it: Variant = inv.get_slot(i)
	if it == null or String(ItemDB.info(String(it["id"])).get("wear", "")) != "back" or _eq["back"] != null:
		return false
	_eq["back"] = it
	inv.slots[i] = null
	_backpack = true
	inv.changed.emit()
	return true


## Скрафтили рюкзак — он надевается сразу: попадает в слот «Спина» и открывает все ячейки.
func _equip_backpack() -> void:
	_backpack = true
	_eq["back"] = {"id": "backpack", "n": 1}
	for i in inv.slots.size():
		var s: Variant = inv.get_slot(i)
		if s != null and String(s["id"]) == "backpack":
			inv.slots[i] = null
			break
	_info_flash = "Рюкзак надет: открыты все ячейки"
	_info_flash_t = 4.0
	inv.changed.emit()


# --- построение -----------------------------------------------------------------------------------------------

func _make_slot(parent: Control, pos: Vector2, size: float) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size = Vector2(size, size)
	p.position = pos
	p.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	var sw := ColorRect.new()
	sw.name = "Swatch"
	sw.position = Vector2(size * 0.22, size * 0.22)
	sw.size = Vector2(size * 0.56, size * 0.56)
	sw.color = Color(0, 0, 0, 0)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(sw)
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.position = Vector2(4, 4)
	ic.size = Vector2(size - 8, size - 8)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ic)
	var ct := UiTheme.label("", 15)
	ct.name = "Count"
	ct.position = Vector2(size - 40, size - 24)
	ct.size = Vector2(35, 20)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(ct)
	var num := UiTheme.label("", 12, UiTheme.DIM)
	num.name = "Num"
	num.position = Vector2(6, 2)
	p.add_child(num)
	var lv := UiTheme.label("", 14, UiTheme.GOLD)   # уровень оружия (римская цифра)
	lv.name = "Lvl"
	lv.position = Vector2(size - 34, 2)
	lv.size = Vector2(30, 18)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(lv)
	var back := ColorRect.new()    # жёлоб полоски
	back.name = "FillBack"
	back.color = Color(0, 0, 0, 0.6)
	back.position = Vector2(7, size - 9)
	back.size = Vector2(size - 14, 5)
	back.visible = false
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(back)
	var fill := ColorRect.new()    # полоска: прочность оружия / заполненность бутылки
	fill.name = "Fill"
	fill.position = Vector2(8, size - 8)
	fill.size = Vector2(size - 16, 3)
	fill.visible = false
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(fill)
	p.mouse_entered.connect(func() -> void: _hover(p, true))
	p.mouse_exited.connect(func() -> void: _hover(p, false))
	parent.add_child(p)
	return p


func _hover(p: Panel, on: bool) -> void:
	if p.get_meta("sel", false):
		return
	p.add_theme_stylebox_override("panel", UiTheme.box("slot_hover" if on else "slot"))


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.05, 0.05, 1.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	root.add_child(_flash)

	# хотбар
	var hb := Control.new()
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.position = Vector2(-(Inventory.HOTBAR * (SLOT + GAP)) * 0.5, -SLOT - 18)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)
	for i in Inventory.HOTBAR:
		var p := _make_slot(hb, Vector2(i * (SLOT + GAP), 0), SLOT)
		(p.get_node("Num") as Label).text = str(i + 1)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.gui_input.connect(_slot_input.bind(i))
		_track_hover(p, i)
		_hotbar.append(p)
	_sel_name = UiTheme.label("", 17)
	_sel_name.position = Vector2(0, -30)
	_sel_name.size = Vector2(Inventory.HOTBAR * (SLOT + GAP), 24)
	_sel_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(_sel_name)

	# полоски состояния (бейджи)
	var stats := Control.new()
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stats.position = Vector2(18, -238)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats)
	_hp_bar = _bar(stats, Vector2(0, 0), "red", "heart", Color(0.72, 0.16, 0.14), "Здоровье")
	_thirst_bar = _bar(stats, Vector2(0, 40), "blue", "thirst", Color(0.2, 0.45, 0.8), "Жажда")
	_hunger_bar = _bar(stats, Vector2(0, 80), "yellow", "hunger", Color(0.68, 0.5, 0.14), "Голод")
	_stam_bar = _bar(stats, Vector2(0, 120), "green", "stamina", Color(0.36, 0.62, 0.28), "Выносливость")
	_aw_bar = _bar(stats, Vector2(0, 160), "yellow", "eye", Color(0.7, 0.6, 0.25), "Заметность", false)
	_aw_bar.value = 0.0
	_aw_lbl = _aw_bar.get_meta("lbl") as Label

	# компас и время (сверху по центру)
	_hud = Panel.new()
	_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud.position = Vector2(-280, 8)
	_hud.size = Vector2(560, 74)
	_hud.add_theme_stylebox_override("panel", UiTheme.box("panel"))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	_compass = CompassStrip.new()
	_compass.position = Vector2(10, 4)
	_compass.size = Vector2(540, 34)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_compass)
	_clock_lbl = UiTheme.label("", 17, UiTheme.TEXT)
	_clock_lbl.position = Vector2(0, 44)
	_clock_lbl.size = Vector2(560, 22)
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_clock_lbl)

	# окно с вкладками
	_win = Control.new()
	_win.visible = false
	_win.set_anchors_preset(Control.PRESET_CENTER)
	_win.position = -WIN * 0.5 - Vector2(0, 40)
	_win.size = WIN
	root.add_child(_win)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_win.add_child(tabs)
	for t in [["Инвентарь", "Tab", "backpack"], ["Крафт", "C", "craft"], ["Креатив", "", "star"], ["Развитие", "", "trophy"], ["Помощь", "", "notes"], ["Экипировка", "", "backpack"]]:
		var b := Button.new()
		b.text = (" %s  [%s]" % [String(t[0]).to_upper(), t[1]]) if String(t[1]) != "" else " " + String(t[0]).to_upper()
		b.icon = UiTheme.ui_icon(t[2])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 28)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(172, 46)
		b.add_theme_font_size_override("font_size", 15)
		UiTheme.style_button(b, "tab")
		var idx := _tabs.size()
		b.pressed.connect(func() -> void: _show_tab(idx))
		tabs.add_child(b)
		_tabs.append(b)
	var close := UiTheme.label("Tab / Esc — закрыть", 13, UiTheme.DIM)
	close.position = Vector2(WIN.x - 150, 12)
	_win.add_child(close)
	_pages.append(_build_inventory_page())
	_pages.append(_build_craft_page())
	_pages.append(_build_creative_page())
	_pages.append(_build_dev_page())
	_pages.append(_build_help_page())
	_pages.append(_build_equip_page())

	# предмет «в руке» (перетаскивание)
	_cursor_icon = TextureRect.new()
	_cursor_icon.size = Vector2(56, 56)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	root.add_child(_cursor_icon)
	_cursor_lbl = UiTheme.label("", 14)
	_cursor_lbl.visible = false
	root.add_child(_cursor_lbl)


func _page_panel(title: String, icon_name: String) -> Panel:
	var pg := Panel.new()
	pg.position = Vector2(0, 52)
	pg.size = Vector2(WIN.x, WIN.y - 52)
	pg.add_theme_stylebox_override("panel", UiTheme.box("panel"))
	_win.add_child(pg)
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = UiTheme.ui_icon(icon_name)
	ic.position = Vector2(18, 10)
	ic.size = Vector2(38, 38)
	pg.add_child(ic)
	var t := UiTheme.label(title, 28, UiTheme.TEXT, true)
	t.position = Vector2(64, 11)
	pg.add_child(t)
	return pg


## Рюкзак: ячейки 9–32 (3 ряда); ячейки 1–8 — хотбар внизу экрана, при открытом окне он тоже кликабелен.
## Без рюкзака виден только первый ряд (ячейки 9–16), остальные скрыты до крафта рюкзака.
func _build_inventory_page() -> Control:
	var pg := _page_panel("Инвентарь", "backpack")
	var cols := Inventory.HOTBAR
	var ox := 24.0
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		var k := i - Inventory.HOTBAR
		var p := _make_slot(pg, Vector2(ox + (k % cols) * (BIG + GAP), 68 + (k / cols) * (BIG + GAP)), BIG)
		p.gui_input.connect(_slot_input.bind(i))
		_track_hover(p, i)
		_grid.append(p)
	# страница по высоте сетки (без пустоты под рюкзаком)
	var rows := (Inventory.SIZE - Inventory.HOTBAR + cols - 1) / cols
	pg.size.y = 68 + rows * (BIG + GAP) + 52
	var hint := UiTheme.label("Хотбар (1–8) внизу экрана — тоже ячейки инвентаря   ·   C — крафт   ·   рюкзак открывает все ячейки", 14, UiTheme.DIM)
	hint.position = Vector2(24, pg.size.y - 38)
	pg.add_child(hint)
	_make_info(pg, Vector2(WIN.x - INFO_W - 18, 16), Vector2(INFO_W, pg.size.y - 32))
	return pg


## Креатив: все предметы игры. ЛКМ — стопка в руку, ПКМ — одна штука, Shift+ЛКМ — сразу в инвентарь;
## клик с предметом в руке — выбросить его.
func _build_creative_page() -> Control:
	var pg := _page_panel("Креатив", "star")
	var ids: Array = ItemDB.ITEMS.keys()
	var cols := 8
	var cs := 84.0
	for k in ids.size():
		var p := _make_slot(pg, Vector2(24 + (k % cols) * (cs + GAP), 68 + (k / cols) * (cs + GAP)), cs)
		var id: String = ids[k]
		_fill_slot(p, {"id": id, "n": 1}, false)
		p.gui_input.connect(_creative_input.bind(id))
		p.mouse_entered.connect(func() -> void:
			_hover_id = id
			_update_info())
		p.mouse_exited.connect(func() -> void:
			if _hover_id == id:
				_hover_id = ""
			_update_info())
	var rows := (ids.size() + cols - 1) / cols
	pg.size.y = maxf(68 + rows * (cs + GAP) + 52, 420)
	var hint := UiTheme.label("ЛКМ — стопка в руку  ·  ПКМ — одна штука  ·  Shift+ЛКМ — в инвентарь  ·  клик с предметом в руке — выбросить", 14, UiTheme.DIM)
	hint.position = Vector2(24, pg.size.y - 38)
	pg.add_child(hint)
	_make_info(pg, Vector2(WIN.x - INFO_W - 18, 16), Vector2(INFO_W, pg.size.y - 32))
	return pg


## Развитие и статистика: по каждому оружию/инструменту — нанесённый урон, открытые уровни крафта, прогресс
## до следующего; общая статистика.
var _dev_box: VBoxContainer
var _dev_total: Label


func _build_dev_page() -> Control:
	var pg := _page_panel("Развитие и статистика", "trophy")
	pg.size.y = WIN.y - 52
	_dev_total = UiTheme.label("", 16, UiTheme.TEXT)
	_dev_total.position = Vector2(24, 62)
	pg.add_child(_dev_total)
	var sc := ScrollContainer.new()
	sc.position = Vector2(20, 96)
	sc.size = Vector2(WIN.x - 40, pg.size.y - 150)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pg.add_child(sc)
	_dev_box = VBoxContainer.new()
	_dev_box.custom_minimum_size = Vector2(WIN.x - 60, 0)
	_dev_box.add_theme_constant_override("separation", 8)
	sc.add_child(_dev_box)
	var hint := UiTheme.label("Урон оружием по зомби и блокам (позже — по животным) открывает крафт следующего уровня: 2-й — 1000, 3-й — ещё 2000, 4-й — ещё 3000, 5-й — ещё 4000.", 14, UiTheme.DIM)
	hint.position = Vector2(24, pg.size.y - 44)
	pg.add_child(hint)
	return pg


func _fill_dev() -> void:
	_dev_total.text = "Убито зомби: %d     ·     Всего нанесено урона: %d     ·     Сломано предметов: %d" % [Gear.kills, int(Gear.total_dmg), Gear.broken]
	for c in _dev_box.get_children():
		c.queue_free()
	for id: String in Gear.LEVELED:
		var row := Panel.new()
		row.custom_minimum_size = Vector2(0, 108)
		row.add_theme_stylebox_override("panel", UiTheme.box("slot"))
		var ib := Panel.new()
		ib.position = Vector2(10, 10)
		ib.size = Vector2(88, 88)
		ib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
		row.add_child(ib)
		var ic := _small_icon(id, Vector2(6, 6))
		ic.size = Vector2(76, 76)
		ib.add_child(ic)
		var un := Gear.unlocked(id)
		var dealt := float(Gear.dealt.get(id, 0.0))
		var nm := UiTheme.label("%s — открыт крафт до уровня %s" % [ItemDB.item_name(id), Gear.roman(un)], 20, UiTheme.GOLD)
		nm.position = Vector2(114, 10)
		row.add_child(nm)
		var lv_line := []
		for l in range(1, Gear.MAX_LVL + 1):
			var t := "%s ×%.2f" % [Gear.roman(l), Gear.dmg_mult(l)]
			if Gear.chance_bonus(id, l) > 0.0:
				t += " (+%d%%)" % roundi(Gear.chance_bonus(id, l) * 100.0)
			lv_line.append(t)
		var lv := UiTheme.label("Урон по уровням: " + "  ·  ".join(PackedStringArray(lv_line)), 14, UiTheme.DIM)
		lv.position = Vector2(114, 40)
		row.add_child(lv)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.position = Vector2(114, 70)
		bar.size = Vector2(560, 18)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.05, 0.05, 0.9)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Color(0.82, 0.62, 0.22)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		var txt := ""
		if un >= Gear.MAX_LVL:
			bar.max_value = 1.0
			bar.value = 1.0
			txt = "Все уровни открыты · нанесено %d" % int(dealt)
		else:
			var lo := Gear.need_for(un)
			var hi := Gear.need_for(un + 1)
			bar.max_value = hi - lo
			bar.value = dealt - lo
			txt = "До уровня %s: %d / %d урона (всего нанесено %d)" % [Gear.roman(un + 1), int(dealt - lo), int(hi - lo), int(dealt)]
		row.add_child(bar)
		var pl := UiTheme.label(txt, 15)
		pl.position = Vector2(690, 68)
		row.add_child(pl)
		_dev_box.add_child(row)


## Помощь: бой, шансы, оружие и уровни, прочность, выносливость, управление.
const HELP := """[font_size=22][color=#dcb45c]Бой[/color][/font_size]
[b]Сбить с ног[/b] (при любом попадании): кулак — [b]25%[/b], бита (дубина) — [b]33%[/b], остальное оружие (и огнестрел) — [b]15%[/b].
Сбитый зомби падает (рэгдолл), лежит и встаёт сам. Пока лежит и встаёт — не бьёт. Удар по лежачему роняет снова лишь с шансом [b]10%[/b].
[b]Оглушить[/b] (зомби стоит на месте 1 с, замах сорван): оружием ближнего боя — [b]25%[/b], огнестрелом — [b]20%[/b] (если не сбил с ног).
Удар в голову — двойной урон. У зомби 300 здоровья. Сбитого (лежащего) зомби бей по телу — удар попадает по нему самому.
Обычный удар без оглушения зомби почти не останавливает — только вздрагивает.

[font_size=22][color=#dcb45c]Заметность (шкала с глазом)[/color][/font_size]
Показывает, насколько тебя «почуяли» зомби (по самому насторожившемуся). Растёт, пока зомби тебя [b]видит[/b] (вблизи и на бегу быстрее, пригнувшись — медленнее, ночью видят ближе) и от твоего [b]шума[/b] (шаги, удары, выстрелы, рубка). Сама спадает, когда тихо и тебя не видно.
[b]35+[/b] (жёлтая) — зомби насторожился и идёт проверить. [b]100[/b] (красная) — заметил и гонится.
Если шкала заполнилась [b]от звука[/b] — с шансом [b]50%[/b] зомби всё же не понял, что это ты: шкала откатывается до 70, он только идёт к месту шума.

[font_size=22][color=#dcb45c]Сетевая игра[/color][/font_size]
Хост ставит галочку «Открыть мир для друзей» в меню и играет как обычно; друзья вводят его IP и жмут «Подключиться» (UDP-порт 7777). Мир, зомби и время — у хоста, сохраняет тоже хост. Держитесь недалеко от хоста: зомби и здания «живут» вокруг него.

[font_size=22][color=#dcb45c]Темп ударов и выносливость[/color][/font_size]
Кулак — раз в 0.7 с, каменный топор — раз в 1 с, бита — раз в 0.85 с. Удары, бег и прыжки тратят выносливость (зелёная шкала). Восстанавливается сразу, как перестал бежать или бить (11 в секунду). Без сил нельзя бить и прыгать; выдохся — бег вернётся с 25.

[font_size=22][color=#dcb45c]Уровни оружия и инструментов (1–5)[/color][/font_size]
Каменный топор, бита, пистолет. Урон: 1-й уровень — базовый, каждый следующий [b]+20%[/b] к предыдущему (×1.2, ×1.44, ×1.73, ×2.07).
Бита: шансы сбить с ног и оглушить [b]+3%[/b] за уровень.
Крафт следующего уровня открывается развитием: нанеси этим оружием урон зомби и блокам (позже — животным) — 2-й уровень: 1000, 3-й: ещё 2000, 4-й: ещё 3000, 5-й: ещё 4000. Прогресс — во вкладке «Развитие». Для крафта нужен предмет предыдущего уровня и материалы.

[font_size=22][color=#dcb45c]Прочность[/color][/font_size]
Полоска под предметом: каждый удар/выстрел — минус 1. Кончилась — предмет ломается. Прочность растёт на 15% за уровень (топор 200, бита 160, пистолет 400 на 1-м).

[font_size=22][color=#dcb45c]Инвентарь[/color][/font_size]
Tab — инвентарь, C — крафт. ЛКМ — взять/положить, ПКМ — взять половину / положить одну, Shift+ЛКМ — между рюкзаком и хотбаром, R — переработать (топор → 3 дерева, бутылка → разбитое стекло). Хотбар внизу экрана — тоже ячейки инвентаря.
Скрафти рюкзак (3 верёвки, 6 тряпья) — он наденется сам и откроет все ячейки.

[font_size=22][color=#dcb45c]Экипировка[/color][/font_size]
Вкладка «Экипировка»: слоты Голова, Торс, Спина, Ноги. ЛКМ по слоту — надеть предмет (в руке) или снять его. Подходят предметы с пометкой «экипировка»: каска — в голову, жилет — на торс, обмотки — на ноги, рюкзак — на спину.

[font_size=22][color=#dcb45c]Крафт[/color][/font_size]
Верёвка из травы — 5 травы (трава — удар по траве). Каменный топор — 3 верёвки, камень, 15 досок. Бита (дубина) — 10 дерева. Рюкзак — 3 верёвки, 6 тряпья.
"""


func _build_help_page() -> Control:
	var pg := _page_panel("Помощь", "notes")
	pg.size.y = WIN.y - 52
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.position = Vector2(24, 62)
	rt.size = Vector2(WIN.x - 48, pg.size.y - 80)
	rt.add_theme_font_override("normal_font", UiTheme.font())
	rt.add_theme_font_override("bold_font", UiTheme.font())
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 16)
	rt.add_theme_color_override("default_color", UiTheme.TEXT)
	rt.text = HELP
	pg.add_child(rt)
	return pg


## Экипировка: что в руках, рюкзак, патроны + слоты Голова/Торс/Спина/Ноги.
var _eq_hand_icon: TextureRect
var _eq_hand_name: Label
var _eq_hand_stats: Label
var _eq_bp_lbl: Label
var _eq_ammo_lbl: Label


func _build_equip_page() -> Control:
	var pg := _page_panel("Экипировка", "backpack")
	pg.size.y = WIN.y - 52
	# «В руках»
	var hand := Panel.new()
	hand.position = Vector2(24, 68)
	hand.size = Vector2(560, 128)
	hand.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	pg.add_child(hand)
	var hib := Panel.new()
	hib.position = Vector2(12, 12)
	hib.size = Vector2(104, 104)
	hib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
	hand.add_child(hib)
	_eq_hand_icon = TextureRect.new()
	_eq_hand_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_eq_hand_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_eq_hand_icon.position = Vector2(8, 8)
	_eq_hand_icon.size = Vector2(88, 88)
	hib.add_child(_eq_hand_icon)
	var ht := UiTheme.label("В РУКАХ", 13, UiTheme.DIM, true)
	ht.position = Vector2(132, 12)
	hand.add_child(ht)
	_eq_hand_name = UiTheme.label("Кулаки", 22, UiTheme.GOLD)
	_eq_hand_name.position = Vector2(132, 34)
	_eq_hand_name.size = Vector2(410, 30)
	hand.add_child(_eq_hand_name)
	_eq_hand_stats = UiTheme.label("", 14, UiTheme.DIM)
	_eq_hand_stats.position = Vector2(132, 70)
	_eq_hand_stats.size = Vector2(410, 48)
	_eq_hand_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hand.add_child(_eq_hand_stats)
	# рюкзак (статус)
	var bp := Panel.new()
	bp.position = Vector2(24, 208)
	bp.size = Vector2(560, 92)
	bp.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	pg.add_child(bp)
	var bib := Panel.new()
	bib.position = Vector2(12, 12)
	bib.size = Vector2(68, 68)
	bib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
	bp.add_child(bib)
	var bic := TextureRect.new()
	bic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bic.texture = icon("backpack")
	bic.position = Vector2(6, 6)
	bic.size = Vector2(56, 56)
	bib.add_child(bic)
	var bt := UiTheme.label("РЮКЗАК", 13, UiTheme.DIM, true)
	bt.position = Vector2(96, 12)
	bp.add_child(bt)
	_eq_bp_lbl = UiTheme.label("", 17)
	_eq_bp_lbl.position = Vector2(96, 36)
	_eq_bp_lbl.size = Vector2(440, 44)
	_eq_bp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bp.add_child(_eq_bp_lbl)
	# патроны
	var ammo := Panel.new()
	ammo.position = Vector2(24, 312)
	ammo.size = Vector2(560, 92)
	ammo.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	pg.add_child(ammo)
	var aib := Panel.new()
	aib.position = Vector2(12, 12)
	aib.size = Vector2(68, 68)
	aib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
	ammo.add_child(aib)
	var aic := TextureRect.new()
	aic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aic.texture = icon("ammo_9mm")
	aic.position = Vector2(6, 6)
	aic.size = Vector2(56, 56)
	aib.add_child(aic)
	var at := UiTheme.label("ПАТРОНЫ", 13, UiTheme.DIM, true)
	at.position = Vector2(96, 12)
	ammo.add_child(at)
	_eq_ammo_lbl = UiTheme.label("", 17)
	_eq_ammo_lbl.position = Vector2(96, 36)
	_eq_ammo_lbl.size = Vector2(440, 44)
	_eq_ammo_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ammo.add_child(_eq_ammo_lbl)
	# слоты экипировки: голова, торс, спина, ноги (2×2 справа)
	var et := UiTheme.label("СЛОТЫ ЭКИПИРОВКИ   ·   ЛКМ по слоту — надеть/снять", 13, UiTheme.DIM, true)
	et.position = Vector2(640, 70)
	pg.add_child(et)
	for s: Array in [["head", "ГОЛОВА", Vector2(640, 114)], ["torso", "ТОРС", Vector2(790, 114)], ["back", "СПИНА", Vector2(640, 262)], ["legs", "НОГИ", Vector2(790, 262)]]:
		var pos: Vector2 = s[2]
		var cap := UiTheme.label(String(s[1]), 12, UiTheme.DIM)
		cap.position = pos + Vector2(0, -20)
		pg.add_child(cap)
		var p := _make_slot(pg, pos, BIG)
		p.gui_input.connect(_eq_input.bind(String(s[0])))
		_eq_panels[String(s[0])] = p
	var hint := UiTheme.label("Надеть можно предметы с пометкой «экипировка» (каска, жилет, обмотки, рюкзак). Снятое возвращается в руку — положите его в инвентарь.", 14, UiTheme.DIM)
	hint.position = Vector2(640, 386)
	hint.size = Vector2(556, 60)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pg.add_child(hint)
	return pg


func _fill_equip() -> void:
	var s: Variant = inv.selected_item()
	if s == null:
		_eq_hand_icon.texture = null
		_eq_hand_name.text = "Кулаки"
		var a := ItemDB.HAND_ATTACK
		_eq_hand_stats.text = "Удар раз в %.2f с · выносливость −%.1f" % [float(a["rate"]), float(a["stam"])]
	else:
		var id := String(s["id"])
		_eq_hand_icon.texture = icon(id)
		var nm := ItemDB.item_name(id)
		if Gear.is_leveled(id):
			nm += "  ур. %d" % Gear.lvl(s)
		_eq_hand_name.text = nm
		var lines := ItemDB.stats_lines(id)
		var shown: Array = lines.slice(0, 2)
		_eq_hand_stats.text = "\n".join(PackedStringArray(shown))
	_eq_bp_lbl.text = "Рюкзак надет — открыты все ячейки инвентаря." if _backpack else "Рюкзака нет — доступен только первый ряд ячеек. Скрафти: 3 верёвки, 6 тряпья."
	_eq_ammo_lbl.text = "Патроны 9 мм в инвентаре: %d" % inv.count("ammo_9mm")
	for slot in _eq:
		_fill_slot(_eq_panels[String(slot)], _eq[String(slot)], false)


## ЛКМ по слоту экипировки: пустая рука — снять предмет (в руку); с предметом — надеть, если слот подходит.
func _eq_input(event: InputEvent, slot: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cur: Variant = _eq[slot]
	if _cursor == null:
		if cur == null:
			return
		if slot == "back" and inv.has_extra_items():
			_eq_bp_lbl.text = "Сначала освободи дополнительные ячейки — рюкзак снять нельзя."
			return
		_cursor = cur
		_eq[slot] = null
		if slot == "back":
			_backpack = false   # сняли рюкзак со спины — ячейки снова закрылись
	else:
		var it := ItemDB.info(String(_cursor["id"]))
		if String(it.get("wear", "")) != slot:
			return   # предмет не для этого слота
		_eq[slot] = _cursor
		_cursor = null
		if slot == "back":
			_backpack = true
	inv.changed.emit()


func _creative_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if _cursor != null:
		_cursor = null      # предмет из руки — в «мусорку» креатива
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.shift_pressed:
		inv.add(id, ItemDB.stack_size(id), _new_extra(id))
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		_cursor = _new_item(id, ItemDB.stack_size(id))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_cursor = _new_item(id, 1)
	if id == "backpack" and not _has_backpack():
		_equip_backpack()
	inv.changed.emit()


static func _new_extra(id: String) -> Dictionary:
	if Gear.is_leveled(id):
		return Gear.extra(id, 1)
	if id == "water_bottle":
		return {"fill": 1.0}
	if id == "glass_bottle":
		return {"fill": 0.0}
	return {}


static func _new_item(id: String, n: int) -> Dictionary:
	var d := {"id": id, "n": n}
	d.merge(_new_extra(id))
	return d


# --- панель описания ---------------------------------------------------------------------------------------------

func _make_info(parent: Control, pos: Vector2, size: Vector2) -> void:
	var box := Panel.new()
	box.position = pos
	box.size = size
	box.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	parent.add_child(box)
	var ib := Panel.new()
	ib.position = Vector2(16, 16)
	ib.size = Vector2(104, 104)
	ib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
	box.add_child(ib)
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(8, 8)
	ic.size = Vector2(88, 88)
	ib.add_child(ic)
	var nm := UiTheme.label("", 21, UiTheme.GOLD)
	nm.position = Vector2(132, 18)
	nm.size = Vector2(size.x - 146, 60)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	var desc := UiTheme.label("", 15)
	desc.position = Vector2(16, 132)
	desc.size = Vector2(size.x - 32, 90)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var stats := UiTheme.label("", 14, UiTheme.DIM)
	stats.position = Vector2(16, 224)
	stats.size = Vector2(size.x - 32, 80)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)
	var keys := UiTheme.label("", 13, UiTheme.DIM)
	keys.position = Vector2(16, size.y - 64)
	keys.size = Vector2(size.x - 32, 52)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(keys)
	_infos.append({"icon": ic, "name": nm, "desc": desc, "stats": stats, "keys": keys})


func _track_hover(p: Panel, i: int) -> void:
	p.mouse_entered.connect(func() -> void:
		if not p.visible:
			return
		_hover_i = i
		_update_info())
	p.mouse_exited.connect(func() -> void:
		if _hover_i == i:
			_hover_i = -1
		_update_info())


func _update_info() -> void:
	var id := _hover_id
	var item: Variant = null
	if id == "" and _hover_i >= 0:
		item = inv.get_slot(_hover_i)
		if item != null:
			id = String(item["id"])
	for f: Dictionary in _infos:
		if id == "":
			(f["icon"] as TextureRect).texture = null
			(f["name"] as Label).text = "Наведи на предмет"
			(f["desc"] as Label).text = ""
			(f["stats"] as Label).text = _info_flash if _info_flash_t > 0.0 else ""
			(f["keys"] as Label).text = "ЛКМ — взять/положить · ПКМ — разделить · Shift+ЛКМ — в хотбар/рюкзак · R — переработать"
			continue
		var it := ItemDB.info(id)
		(f["icon"] as TextureRect).texture = icon(id)
		var nline := String(it["name"])
		if item != null and int(item["n"]) > 1:
			nline += "  ×%d" % int(item["n"])
		var st: Array = []
		if Gear.is_leveled(id):
			var lv := Gear.lvl(item)
			nline += "  ур. %d" % lv
			var g: Variant = item if item != null else Gear.extra(id, 1).merged({"id": id, "n": 1})
			st.append("Уровень %d · урон ×%.2f · прочность %d / %d" % [lv, Gear.dmg_mult(lv), int(Gear.dur(g)), int(Gear.max_dur(id, lv))])
			if Gear.chance_bonus(id, lv) > 0.0:
				st.append("Сбить с ног / оглушить: +%d%%" % roundi(Gear.chance_bonus(id, lv) * 100.0))
		(f["name"] as Label).text = nline
		(f["desc"] as Label).text = String(it.get("desc", ""))
		st.append_array(ItemDB.stats_lines(id))
		if _info_flash_t > 0.0:
			st.push_front(_info_flash)
		(f["stats"] as Label).text = "\n".join(PackedStringArray(st))
		var keys: Array = ["ЛКМ — взять/положить", "ПКМ — разделить", "Shift+ЛКМ — в хотбар/рюкзак"]
		if it.has("recycle"):
			keys.append("R — переработать")
		if it.has("wear"):
			keys.append("Экипировка: слот «%s»" % String(it["wear"]))
		(f["keys"] as Label).text = " · ".join(PackedStringArray(keys))


func _build_craft_page() -> Control:
	var pg := _page_panel("Крафт", "craft")
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск…"
	_search.position = Vector2(170, 14)
	_search.size = Vector2(300, 34)
	_search.add_theme_font_override("font", UiTheme.font())
	_search.add_theme_stylebox_override("normal", UiTheme.box("slot"))
	_search.add_theme_stylebox_override("focus", UiTheme.box("slot_hover"))
	_search.text_changed.connect(func(_t: String) -> void: _fill_recipes())
	pg.add_child(_search)
	# категории
	var cats := VBoxContainer.new()
	cats.position = Vector2(18, 64)
	cats.size = Vector2(150, 300)
	cats.add_theme_constant_override("separation", 4)
	pg.add_child(cats)
	for c: String in CraftDB.CATEGORIES:
		var b := Button.new()
		b.text = " " + c
		b.icon = UiTheme.ui_icon({"Все": "notes", "Инструменты": "craft", "Оружие": "pistol", "Ресурсы": "plant"}.get(c, "notes"))
		b.add_theme_constant_override("icon_max_width", 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 38)
		b.add_theme_font_size_override("font_size", 16)
		UiTheme.style_button(b, "row")
		b.pressed.connect(func() -> void:
			_cat = c
			_fill_recipes())
		cats.add_child(b)
		_cat_btns.append(b)
	# список рецептов
	var sc := ScrollContainer.new()
	sc.position = Vector2(180, 64)
	sc.size = Vector2(380, WIN.y - 52 - 84)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pg.add_child(sc)
	_recipe_box = VBoxContainer.new()
	_recipe_box.custom_minimum_size = Vector2(368, 0)
	_recipe_box.add_theme_constant_override("separation", 5)
	sc.add_child(_recipe_box)
	# подробности рецепта
	var det := Panel.new()
	det.position = Vector2(576, 14)
	det.size = Vector2(WIN.x - 576 - 18, WIN.y - 52 - 32)
	det.add_theme_stylebox_override("panel", UiTheme.box("slot"))
	pg.add_child(det)
	var ib := Panel.new()
	ib.position = Vector2(18, 18)
	ib.size = Vector2(128, 128)
	ib.add_theme_stylebox_override("panel", UiTheme.box("slot_sel"))
	det.add_child(ib)
	_d_icon = TextureRect.new()
	_d_icon.position = Vector2(8, 8)
	_d_icon.size = Vector2(112, 112)
	_d_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ib.add_child(_d_icon)
	_d_name = UiTheme.label("", 24, UiTheme.GOLD)
	_d_name.position = Vector2(162, 20)
	_d_name.size = Vector2(det.size.x - 180, 30)
	det.add_child(_d_name)
	_d_out = UiTheme.label("", 14, UiTheme.DIM)
	_d_out.position = Vector2(162, 52)
	det.add_child(_d_out)
	_d_desc = UiTheme.label("", 15, UiTheme.TEXT)
	_d_desc.position = Vector2(162, 76)
	_d_desc.size = Vector2(det.size.x - 180, 70)
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_d_desc)
	var nl := UiTheme.label("Требуется", 17, UiTheme.DIM, true)
	nl.position = Vector2(20, 162)
	det.add_child(nl)
	_d_need = VBoxContainer.new()
	_d_need.position = Vector2(18, 192)
	_d_need.size = Vector2(det.size.x - 36, 200)
	_d_need.add_theme_constant_override("separation", 6)
	det.add_child(_d_need)
	_d_btn = Button.new()
	_d_btn.text = " СОЗДАТЬ"
	_d_btn.icon = UiTheme.ui_icon("craft")
	_d_btn.add_theme_constant_override("icon_max_width", 34)
	_d_btn.size = Vector2(det.size.x - 36, 54)
	_d_btn.position = Vector2(18, det.size.y - 72)
	_d_btn.add_theme_font_size_override("font_size", 22)
	UiTheme.style_button(_d_btn)
	_d_btn.pressed.connect(_do_craft)
	det.add_child(_d_btn)
	return pg


## Полоска состояния — компактный бейдж: значок слева, тёмная скруглённая плашка,
## цветная заливка по значению, внутри — «100/100» (или текст для заметности).
func _bar(parent: Control, pos: Vector2, fill_name: String, icon_name: String, col: Color, label: String, numeric := true) -> Range:
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = UiTheme.ui_icon(icon_name)
	ic.position = pos + Vector2(0, 4)
	ic.size = Vector2(26, 26)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ic)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 100.0
	pb.value = 100.0
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.position = pos + Vector2(34, 0)
	pb.size = Vector2(206, 32)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.04, 0.04, 0.78)
	bg.set_corner_radius_all(9)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.9, 0.86, 0.78, 0.3)
	pb.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(8)
	pb.add_theme_stylebox_override("fill", fill)
	pb.set_meta("fill", fill)
	parent.add_child(pb)
	var lb := UiTheme.label("Заметность" if not numeric else "100/100", 15)
	lb.position = Vector2(0, 5)
	lb.size = Vector2(206, 22)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_color_override("font_color", Color.WHITE)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("outline_size", 5)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(lb)
	pb.set_meta("lbl", lb)
	pb.set_meta("numeric", numeric)
	pb.tooltip_text = label
	return pb


## Обновить бейдж: значение и текст «49/100».
func _set_bar(bar: Range, v: float) -> void:
	bar.value = v
	if bool(bar.get_meta("numeric")):
		(bar.get_meta("lbl") as Label).text = "%d/100" % int(round(v))


# --- вкладки и крафт -------------------------------------------------------------------------------------------

func _show_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
		_tabs[k].button_pressed = k == i
	if i == 1:
		_fill_recipes()
	elif i == 3:
		_fill_dev()
	elif i == 5:
		_fill_equip()


func _fill_recipes() -> void:
	for c in _recipe_box.get_children():
		c.queue_free()
	for k in _cat_btns.size():
		_cat_btns[k].button_pressed = CraftDB.CATEGORIES[k] == _cat
	var list := CraftDB.list(_cat, _search.text)
	var all := CraftDB.recipes()
	if _recipe < 0 or not all[_recipe] in list:
		_recipe = all.find(list[0]) if not list.is_empty() else -1
	for r: Dictionary in list:
		var idx := all.find(r)
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = idx == _recipe
		b.custom_minimum_size = Vector2(368, 52)
		var locked := not CraftDB.is_unlocked(r)
		b.text = "            " + CraftDB.title(r) + ("   [закрыто]" if locked else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		UiTheme.style_button(b, "row")
		if not CraftDB.can_craft(inv, r):
			b.add_theme_color_override("font_color", UiTheme.DIM)
		var ic := _small_icon(r["out"], Vector2(8, 4))
		if locked:
			ic.modulate = Color(0.45, 0.45, 0.45)
		b.add_child(ic)
		b.pressed.connect(func() -> void:
			_recipe = idx
			_fill_recipes())
		_recipe_box.add_child(b)
	_fill_details()


func _fill_details() -> void:
	for c in _d_need.get_children():
		c.queue_free()
	if _recipe < 0:
		_d_icon.texture = null
		_d_name.text = "Нет рецептов"
		_d_desc.text = ""
		_d_out.text = ""
		_d_btn.disabled = true
		return
	var r: Dictionary = CraftDB.recipes()[_recipe]
	var out := String(r["out"])
	var lv := int(r.get("lvl", 1))
	_d_icon.texture = icon(out)
	_d_name.text = CraftDB.title(r)
	_d_out.text = "Результат: ×%d   ·   %s" % [int(r["n"]), String(r["cat"])]
	var desc := String(ItemDB.info(out).get("desc", ""))
	if Gear.is_leveled(out):
		desc += "\nУровень %d: урон ×%.2f, прочность %d%s" % [lv, Gear.dmg_mult(lv), int(Gear.max_dur(out, lv)),
			("  · сбить/оглушить +%d%%" % roundi(Gear.chance_bonus(out, lv) * 100.0)) if Gear.chance_bonus(out, lv) > 0.0 else ""]
	if not CraftDB.is_unlocked(r):
		desc += "\nЗакрыто. Откроется: нанеси этим оружием %d урона зомби/блокам (сейчас %d)" % [int(Gear.need_for(lv)), int(Gear.dealt.get(out, 0.0))]
	_d_desc.text = desc
	for key: String in r["need"]:
		var need := int(r["need"][key])
		var have := CraftDB.have(inv, key)
		var row := Panel.new()
		row.custom_minimum_size = Vector2(0, 54)
		row.add_theme_stylebox_override("panel", UiTheme.box("row" if have >= need else "slot_bad"))
		row.add_child(_small_icon(CraftDB.need_id(key), Vector2(6, 5)))
		var nm := UiTheme.label(CraftDB.need_name(key), 17)
		nm.position = Vector2(62, 14)
		row.add_child(nm)
		var cnt := UiTheme.label("%d / %d" % [have, need], 18, UiTheme.OK if have >= need else UiTheme.BAD)
		cnt.position = Vector2(_d_need.size.x - 100, 14)
		cnt.size = Vector2(88, 24)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cnt)
		_d_need.add_child(row)
	_d_btn.disabled = not CraftDB.can_craft(inv, r)


## Иконка 44 px в строке списка (режим растяжения — до размера, иначе размер = размер текстуры).
func _small_icon(id: String, pos: Vector2) -> TextureRect:
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.texture = icon(id)
	ic.position = pos
	ic.size = Vector2(44, 44)
	return ic


func _do_craft() -> void:
	if _recipe < 0:
		return
	var r: Dictionary = CraftDB.recipes()[_recipe]
	if CraftDB.craft(inv, r):
		if String(r["out"]) == "backpack" and not _has_backpack():
			_equip_backpack()
		Sfx.play_ui(self, Sfx.pick("craft", "rustle"), -6.0)
	_fill_recipes()


# --- ячейки ----------------------------------------------------------------------------------------------------

func _slot_input(event: InputEvent, i: int) -> void:
	if i >= _capacity():
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_split(i)
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.ctrl_pressed and _cursor == null and _wear_from_slot(i):
		return
	# двойное нажатие (и на телефоне, где нет Ctrl): первое взяло предмет в руку, второе — надеть рюкзак
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and _wear_cursor():
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.shift_pressed and _cursor == null:
		_quick_move(i)
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var cur: Variant = inv.get_slot(i)
		if _cursor == null:
			if cur != null:
				_cursor = cur
				inv.slots[i] = null
		else:
			if cur != null and cur["id"] == _cursor["id"] and ItemDB.stack_size(cur["id"]) > 1:
				var room := ItemDB.stack_size(cur["id"]) - int(cur["n"])
				var mv := mini(room, int(_cursor["n"]))
				cur["n"] = int(cur["n"]) + mv
				_cursor["n"] = int(_cursor["n"]) - mv
				if int(_cursor["n"]) <= 0:
					_cursor = null
			else:
				inv.slots[i] = _cursor
				_cursor = cur
		inv.changed.emit()


## ПКМ: пустая рука — взять половину стопки; с предметом в руке — положить одну штуку (в пустую или ту же стопку).
func _split(i: int) -> void:
	var cur: Variant = inv.get_slot(i)
	if _cursor == null:
		if cur == null:
			return
		var n := int(cur["n"])
		if n <= 1:
			_cursor = cur
			inv.slots[i] = null
		else:
			var half := ceili(n / 2.0)
			_cursor = (cur as Dictionary).duplicate()
			_cursor["n"] = half
			cur["n"] = n - half
	else:
		if cur == null:
			var one: Dictionary = (_cursor as Dictionary).duplicate()
			one["n"] = 1
			inv.slots[i] = one
		elif cur["id"] == _cursor["id"] and int(cur["n"]) < ItemDB.stack_size(cur["id"]):
			cur["n"] = int(cur["n"]) + 1
		else:
			return
		_cursor["n"] = int(_cursor["n"]) - 1
		if int(_cursor["n"]) <= 0:
			_cursor = null
	inv.changed.emit()


## Shift+ЛКМ: из рюкзака — в хотбар, из хотбара — в рюкзак (сначала в такие же стопки, потом в пустые ячейки).
func _quick_move(i: int) -> void:
	var it: Variant = inv.get_slot(i)
	if it == null:
		return
	var to: Array = range(Inventory.HOTBAR, Inventory.SIZE) if i < Inventory.HOTBAR else range(0, Inventory.HOTBAR)
	var n := int(it["n"])
	var stack := ItemDB.stack_size(it["id"])
	for j: int in to:
		if j >= _capacity():
			continue
		var s: Variant = inv.get_slot(j)
		if n > 0 and s != null and s["id"] == it["id"] and stack > 1:
			var mv := mini(stack - int(s["n"]), n)
			s["n"] = int(s["n"]) + mv
			n -= mv
	for j: int in to:
		if n > 0 and j < _capacity() and inv.get_slot(j) == null:
			var d: Dictionary = (it as Dictionary).duplicate()
			d["n"] = n
			inv.slots[j] = d
			n = 0
	if n <= 0:
		inv.slots[i] = null
	else:
		it["n"] = n
	inv.changed.emit()


## R над предметом: переработать одну штуку (ItemDB recycle), продукт — в инвентарь.
func recycle(i: int) -> bool:
	var it: Variant = inv.get_slot(i)
	if it == null or not ItemDB.info(it["id"]).has("recycle"):
		return false
	var out: Dictionary = ItemDB.info(it["id"])["recycle"]
	var name := ItemDB.item_name(it["id"])
	var n := int(it["n"]) - 1
	inv.slots[i] = null if n <= 0 else it
	if n > 0:
		it["n"] = n
	var got: Array = []
	for id: String in out:
		var left := inv.add(id, int(out[id]))
		got.append("+%d %s" % [int(out[id]) - left, ItemDB.item_name(id)])
	_info_flash = "%s переработан: %s" % [name, ", ".join(PackedStringArray(got))]
	_info_flash_t = 3.0
	Sfx.play_ui(self, Sfx.pick("craft", "rustle"), -6.0)
	inv.changed.emit()
	return true


func _input(event: InputEvent) -> void:
	if not _win.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_R:
		if _hover_i >= 0 and recycle(_hover_i):
			get_viewport().set_input_as_handled()


func _fill_slot(p: Panel, item: Variant, selected: bool) -> void:
	p.set_meta("sel", selected)
	p.add_theme_stylebox_override("panel", UiTheme.box("slot_sel" if selected else "slot"))
	var sw: ColorRect = p.get_node("Swatch")
	var ic: TextureRect = p.get_node("Icon")
	var ct: Label = p.get_node("Count")
	var fill: ColorRect = p.get_node("Fill")
	var back: ColorRect = p.get_node("FillBack")
	var lvl: Label = p.get_node("Lvl")
	if item == null:
		sw.color = Color(0, 0, 0, 0)
		ic.texture = null
		ct.text = ""
		fill.visible = false
		back.visible = false
		lvl.text = ""
		p.tooltip_text = ""
		return
	var id := String(item["id"])
	var info := ItemDB.info(id)
	ic.texture = icon(id)
	sw.color = Color(0, 0, 0, 0) if ic.texture != null else info["color"]   # без иконки — цветная плашка
	ct.text = str(item["n"]) if int(item["n"]) > 1 else ""
	p.tooltip_text = String(info["name"])
	var f := -1.0
	if Gear.is_leveled(id):
		f = Gear.dur_frac(item)
		fill.color = Color(0.86, 0.22, 0.16).lerp(Color(0.86, 0.72, 0.2), clampf(f * 2.0, 0.0, 1.0)).lerp(Color(0.38, 0.72, 0.3), clampf(f * 2.0 - 1.0, 0.0, 1.0))
		lvl.text = Gear.roman(Gear.lvl(item))
	else:
		lvl.text = ""
		if item.has("fill") and info.has("bottle"):
			f = clampf(float(item["fill"]), 0.0, 1.0)
			fill.color = Color(0.3, 0.6, 0.9)
	fill.visible = f >= 0.0
	back.visible = f >= 0.0
	if f >= 0.0:
		fill.size.x = maxf((p.size.x - 16) * f, 1.0)


func refresh() -> void:
	for i in Inventory.HOTBAR:
		_fill_slot(_hotbar[i], inv.get_slot(i), i == inv.selected)
	for k in _grid.size():
		var p := _grid[k]
		p.visible = Inventory.HOTBAR + k < _capacity()   # без рюкзака — только первый ряд
		_fill_slot(p, inv.get_slot(Inventory.HOTBAR + k), false)
	if inv.selected != _last_sel:
		_last_sel = inv.selected
		var s: Variant = inv.selected_item()
		_sel_name.text = ItemDB.item_name(s["id"]) if s != null else ""
		_sel_name_t = 2.0
	_cursor_lbl.visible = _cursor != null
	_cursor_icon.visible = _cursor != null
	if _cursor != null:
		_cursor_icon.texture = icon(String(_cursor["id"]))
		_cursor_lbl.text = "×%d" % int(_cursor["n"]) if int(_cursor["n"]) > 1 else ""
	if _win.visible and _tab == 1:
		_fill_recipes()
	if _win.visible and _tab == 5:
		_fill_equip()
	_update_info()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _compass != null:
		var f := -cam.global_basis.z
		_compass.heading = fposmod(-rad_to_deg(atan2(-f.x, -f.z)), 360.0)
		_compass.queue_redraw()
	if _cursor != null:
		var mp := get_viewport().get_mouse_position()
		_cursor_icon.position = mp + Vector2(8, 8)
		_cursor_lbl.position = mp + Vector2(44, 44)
	if _info_flash_t > 0.0:
		_info_flash_t -= delta
		if _info_flash_t <= 0.0:
			_update_info()
	if _sel_name_t > 0.0:
		_sel_name_t -= delta
		_sel_name.modulate.a = clampf(_sel_name_t, 0.0, 1.0)


## Полоса компаса: деления каждые 15°, буквы С/В/Ю/З каждые 90°, плавное затухание у краёв.
## heading — курс камеры в градусах (0 — север), обновляется извне каждый кадр.
class CompassStrip:
	extends Control

	var heading := 0.0
	var px := 3.0   # пикселей на градус

	func _draw() -> void:
		var cx := size.x * 0.5
		var font := get_theme_default_font()
		var fs := 15
		var t := ceilf((heading - 75.0) / 15.0) * 15.0
		while t <= heading + 75.0:
			var off := wrapf(t - heading, -180.0, 180.0)
			var x := cx + off * px
			if x >= 8.0 and x <= size.x - 8.0:
				var a := clampf(1.0 - absf(off) / 75.0, 0.0, 1.0)
				var n := int(roundi(t / 15.0)) % 24
				if n % 6 == 0:
					var s: String = ["С", "В", "Ю", "З"][n / 6]
					var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(font, Vector2(x - tw * 0.5, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.88, 0.66, a))
					draw_line(Vector2(x, 24), Vector2(x, 30), Color(0.9, 0.86, 0.76, 0.55 * a), 2.0)
				else:
					var h := 8.0 if n % 2 == 0 else 5.0
					draw_line(Vector2(x, 30.0 - h), Vector2(x, 30.0), Color(0.85, 0.82, 0.74, 0.5 * a), 2.0)
			t += 15.0
		# золотая метка курса по центру
		draw_polygon(PackedVector2Array([Vector2(cx - 5, 32), Vector2(cx + 5, 32), Vector2(cx, 25)]),
			PackedColorArray([Color(1, 0.82, 0.35), Color(1, 0.82, 0.35), Color(1, 0.82, 0.35)]))
