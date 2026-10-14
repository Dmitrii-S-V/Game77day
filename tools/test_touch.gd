extends SceneTree
## Экранное управление: джойстик двигает игрока, перетаскивание справа поворачивает камеру, кнопки (удар, прыжок,
## присед-переключатель, инвентарь), касание хотбара выбирает ячейку; мультитач — джойстик + удар одновременно.
## C:\Godot\godot.exe --headless --fixed-fps 60 --path D:\77Days --script res://tools/test_touch.gd -- --touch

var fails := 0
var _f := 0
var _p: Player
var _tc: TouchControls
var _y0 := 0.0
var _pos0 := Vector3.ZERO


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos    # координаты окна (у headless-окна свой масштаб)
	e.pressed = down
	Input.parse_input_event(e)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func _btn(id: String) -> Vector2:
	for b: Array in _tc._buttons():
		if b[0] == id:
			return _tc._btn_center(b)
	return Vector2(-1, -1)


func _init() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(200, 1, 200)
	cs.shape = sh
	cs.position.y = -0.5
	ground.add_child(cs)
	root.add_child(ground)
	_p = Player.new()
	_p.position = Vector3(0, 0.1, 0)
	root.add_child(_p)
	var ui := InventoryUI.new()
	root.add_child(ui)
	ui.setup(_p.inventory)
	_p.ui = ui
	_tc = TouchControls.new()
	_tc.player = _p
	root.add_child(_tc)
	_tc.fire_pressed.connect(_p._on_touch_fire)


func _process(_d: float) -> bool:
	_f += 1
	var sz := _tc._pad.size
	match _f:
		20:
			_pos0 = _p.global_position
			_touch(0, Vector2(250, sz.y - 300), true)          # джойстик
			_drag(0, Vector2(250, sz.y - 400), Vector2(0, -100))  # вперёд до упора
		80:
			check("джойстик: вперёд (move %s)" % _tc.move, _tc.move.y > 0.9)
			var moved := _p.global_position - _pos0
			check("игрок пошёл вперёд (-Z) на %.1f м" % -moved.z, moved.z < -2.0)
			_touch(1, _btn("attack"), true)                     # второй палец — удар
		84:
			check("мультитач: удар при ходьбе (рука занята)", _p.hand.busy() and _tc.attack and _tc.move.y > 0.9)
			_touch(1, Vector2.ZERO, false)
			_touch(0, Vector2.ZERO, false)
		90:
			check("отпустил — стоит", _tc.move == Vector2.ZERO and not _tc.attack)
			_y0 = _p.rotation.y
			_touch(2, Vector2(sz.x * 0.6, sz.y * 0.45), true)  # обзор
			_drag(2, Vector2(sz.x * 0.6 + 100, sz.y * 0.45), Vector2(100, 0))
		92:
			check("перетаскивание справа поворачивает камеру (%.2f рад)" % (_y0 - _p.rotation.y), _y0 - _p.rotation.y > 0.4)
			_touch(2, Vector2.ZERO, false)
			_touch(3, _btn("crouch"), true)
			_touch(3, Vector2.ZERO, false)
		96:
			check("присед — переключатель", _tc.crouch and _p.crouching)
			_touch(3, _btn("crouch"), true)
			_touch(3, Vector2.ZERO, false)
			var hb: Control = _p.ui._hotbar[2]
			_touch(4, hb.get_global_rect().get_center(), true)
			_touch(4, Vector2.ZERO, false)
		100:
			check("присед выключен", not _tc.crouch)
			check("касание хотбара: выбрана 3-я ячейка", _p.inventory.selected == 2)
			_touch(5, _btn("jump"), true)
		104:
			check("прыжок", _p.velocity.y > 1.0)
			_touch(5, Vector2.ZERO, false)
			_touch(6, _btn("inv"), true)
			_touch(6, Vector2.ZERO, false)
		108:
			check("кнопка «Инв.» открыла инвентарь", _p.ui.is_open())
			check("при открытом инвентаре — только кнопка «Закрыть»", _tc._buttons().size() == 1)
			_touch(7, _btn("close"), true)
			_touch(7, Vector2.ZERO, false)
		112:
			check("«Закрыть» — инвентарь закрыт", not _p.ui.is_open())
			print("RESULT fails=%d" % fails)
			return true
	return false
