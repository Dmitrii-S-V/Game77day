class_name TouchControls
extends CanvasLayer
## Экранное управление (Android / сенсорный экран; на ПК — аргумент --touch):
## слева — плавающий джойстик ходьбы (касание в левой части экрана), справа — обзор перетаскиванием пальца,
## кнопки: Удар (ЛКМ; с пистолетом — выстрел), Действие (ПКМ), Прыжок, Присед и Бег (переключатели), E — взять/открыть/
## обыскать, R — перезарядка, Выбросить, Инвентарь, Меню (сохранить, графика, выход). Касание ячейки хотбара — выбрать.
## Мультитач обрабатывается здесь (у каждого пальца своя роль); при открытом инвентаре касания уходят интерфейсу.

signal fire_pressed

static var inst: TouchControls

var player: Player
var main: Node
var move := Vector2.ZERO          # x — вправо, y — вперёд (длина до 1)
var sprint := false
var crouch := false
var jump := false
var attack := false
var alt := false

const LOOK_SENS := 0.0055         # рад на пиксель (в единицах интерфейса)
const JOY_R := 110.0

var _pad: Control
var _menu: PanelContainer
var _fingers := {}                # индекс касания -> {role, start, pos}
var _look := Vector2.ZERO
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_on := false


## Нужно ли экранное управление (телефон/планшет или отладка --touch).
static func wanted() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")


static func active() -> bool:
	return inst != null and is_instance_valid(inst)


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	layer = 6
	if not OS.has_feature("mobile"):
		Input.emulate_touch_from_mouse = true     # проверка на ПК (--touch): мышь даёт касания
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	_build_menu()


## Поворот камеры за кадр (накопленный перетаскиванием) — забирает игрок.
func take_look() -> Vector2:
	var d := _look
	_look = Vector2.ZERO
	return d


# --- кнопки ---------------------------------------------------------------------------------

## [id, подпись, центр (от правого/левого края), радиус]; x < 0 — от правого края, y < 0 — от нижнего.
func _buttons() -> Array:
	var open := _ui_open()
	if open:
		return [["close", "Закрыть", Vector2(-90, 70), 52.0]]
	if _menu.visible:
		return []
	return [
		["attack", "Удар", Vector2(-140, -230), 85.0],
		["alt", "Действие", Vector2(-320, -200), 55.0],
		["jump", "Прыжок", Vector2(-140, -420), 55.0],
		["crouch", "Присед", Vector2(-300, -360), 48.0],
		["reload", "R", Vector2(-430, -290), 40.0],
		["use", "E", Vector2(-450, -420), 45.0],
		["sprint", "Бег", Vector2(110, -540), 48.0],
		["inv", "Инв.", Vector2(-90, 70), 46.0],
		["menu", "Меню", Vector2(-200, 70), 46.0],
		["drop", "Выбр.", Vector2(-310, 70), 40.0],
	]


func _btn_center(b: Array) -> Vector2:
	var sz := _pad.size
	var c: Vector2 = b[2]
	return Vector2(c.x if c.x >= 0.0 else sz.x + c.x, c.y if c.y >= 0.0 else sz.y + c.y)


func _btn_at(p: Vector2) -> String:
	for b: Array in _buttons():
		if p.distance_to(_btn_center(b)) <= float(b[3]) * 1.15:
			return b[0]
	return ""


func _ui_open() -> bool:
	return player != null and player.ui != null and player.ui.is_open()


func _hotbar_at(p: Vector2) -> int:
	if player == null or player.ui == null:
		return -1
	var hb: Array = player.ui._hotbar
	for i in hb.size():
		if (hb[i] as Control).get_global_rect().has_point(p):
			return i
	return -1


# --- касания --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _fingers.has(d.index):
			return
		var f: Dictionary = _fingers[d.index]
		match String(f["role"]):
			"joy":
				_joy_pos = d.position
				var v := (_joy_pos - _joy_origin) / JOY_R
				if v.length() > 1.0:
					v = v.normalized()
				move = Vector2(v.x, -v.y)
				_pad.queue_redraw()
			"look":
				_look += d.relative
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, p: Vector2) -> void:
	var b := _btn_at(p)
	if b != "":
		_fingers[idx] = {"role": "btn", "btn": b}
		_press(b, true)
		get_viewport().set_input_as_handled()
		_pad.queue_redraw()
		return
	if _ui_open() or _menu.visible:
		return      # касание — интерфейсу (эмуляция мыши)
	var hb := _hotbar_at(p)
	if hb >= 0:
		player.inventory.select(hb)
		_fingers[idx] = {"role": "none"}
		get_viewport().set_input_as_handled()
		return
	var sz := _pad.size
	if p.x < sz.x * 0.42 and p.y > sz.y * 0.25 and not _joy_on:
		_fingers[idx] = {"role": "joy"}
		_joy_on = true
		_joy_origin = p
		_joy_pos = p
	else:
		_fingers[idx] = {"role": "look"}
	get_viewport().set_input_as_handled()
	_pad.queue_redraw()


func _touch_up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	_fingers.erase(idx)
	match String(f["role"]):
		"joy":
			_joy_on = false
			move = Vector2.ZERO
		"btn":
			_press(String(f["btn"]), false)
	get_viewport().set_input_as_handled()
	_pad.queue_redraw()


func _press(b: String, down: bool) -> void:
	match b:
		"attack":
			attack = down
			if down:
				fire_pressed.emit()
		"alt":
			alt = down
		"jump":
			jump = down
	if not down:
		return
	match b:
		"crouch":
			crouch = not crouch
			if crouch:
				sprint = false
		"sprint":
			sprint = not sprint
			if sprint:
				crouch = false
		"reload":
			player._reload()
		"use":
			if not player._use_block() and not player._start_loot():
				player._pickup()
		"drop":
			player._drop_selected()
		"inv", "close":
			_release_all()
			player.ui.toggle(0)
		"menu":
			_release_all()
			_menu.visible = true


## Открылось окно — отпустить всё (иначе бег/удар «залипнут»).
func _release_all() -> void:
	for idx in _fingers.keys():
		if String(_fingers[idx]["role"]) != "btn" or not String(_fingers[idx]["btn"]) in ["inv", "close", "menu"]:
			_fingers.erase(idx)
	move = Vector2.ZERO
	_joy_on = false
	attack = false
	alt = false
	jump = false


func _process(_d: float) -> void:
	_pad.queue_redraw()


# --- отрисовка ------------------------------------------------------------------------------

func _draw_pad() -> void:
	var font := UiTheme.font()
	var pressed := {}
	for f: Dictionary in _fingers.values():
		if String(f["role"]) == "btn":
			pressed[f["btn"]] = true
	for b: Array in _buttons():
		var c := _btn_center(b)
		var r: float = b[3]
		var on: bool = pressed.has(b[0]) or (b[0] == "sprint" and sprint) or (b[0] == "crouch" and crouch)
		_pad.draw_circle(c, r, Color(0.08, 0.08, 0.07, 0.55 if on else 0.32))
		_pad.draw_arc(c, r, 0.0, TAU, 40, Color(0.86, 0.78, 0.55, 0.9 if on else 0.55), 3.0, true)
		var txt: String = b[1]
		var fs := 22 if r >= 60.0 else 17
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_pad.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.92, 0.85, 0.95))
	if _ui_open() or _menu.visible:
		return
	# джойстик: где коснулись — там центр
	var sz := _pad.size
	var o := _joy_origin if _joy_on else Vector2(220, sz.y - 330)
	_pad.draw_circle(o, JOY_R, Color(0.08, 0.08, 0.07, 0.28))
	_pad.draw_arc(o, JOY_R, 0.0, TAU, 48, Color(0.86, 0.78, 0.55, 0.45), 3.0, true)
	var k := o + (Vector2(move.x, -move.y) * JOY_R if _joy_on else Vector2.ZERO)
	_pad.draw_circle(k, 44.0, Color(0.86, 0.78, 0.55, 0.55 if _joy_on else 0.3))


# --- меню паузы -----------------------------------------------------------------------------

func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", UiTheme.box("panel"))
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(420, 0)
	_menu.position = Vector2(-210, -200)
	add_child(_menu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_menu.add_child(vb)
	var t := UiTheme.label("Меню", 28, UiTheme.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for it in [["Продолжить", "resume"], ["Сохранить", "save"], ["Графика", "gfx"], ["Выйти в меню", "quit"]]:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(380, 70)
		b.add_theme_font_size_override("font_size", 24)
		UiTheme.style_button(b, "tab")
		var act: String = it[1]
		b.pressed.connect(func() -> void: _menu_action(act))
		vb.add_child(b)


func _menu_action(act: String) -> void:
	match act:
		"resume":
			_menu.visible = false
		"save":
			main.save_game("Игра сохранена")
			_menu.visible = false
		"gfx":
			main._toggle_gfx_panel()
			_menu.visible = false
		"quit":
			main.save_game("")
			if Net.active():
				Net.inst.close()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")   # как Game.back_to_menu (без автозагрузки — тесты)
