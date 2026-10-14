extends SceneTree
## Тест миникарты: метки (поставить/убрать по клику), зум вокруг курсора, границы, перетаскивание.
## godot --headless --path . --script res://tools/test_minimap.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _touch(idx: int, pos: Vector2, down: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = down
	return e


func _sdrag(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	return e


func _init() -> void:
	var mm := Minimap.new()
	root.add_child(mm)
	await process_frame
	mm.world_size = 2048.0
	mm.expanded = true
	mm.size = Vector2(800, 600)
	mm._view_m = 600.0
	mm._center_m = Vector2(1000, 1000)
	mm._follow = false
	mm.queue_redraw()

	var c := mm.size * 0.5
	check("центр экрана = центр вида", mm._local_to_world(c).is_equal_approx(Vector2(1000, 1000)))
	check("туда-обратно", mm._world_to_local(mm._local_to_world(Vector2(123, 321))).is_equal_approx(Vector2(123, 321)))

	Minimap.marks.clear()
	mm._toggle_mark(c)
	check("ПКМ в пустом месте ставит метку", Minimap.marks.size() == 1)
	check("метка в точке клика", (Minimap.marks[0]["pos"] as Vector2).is_equal_approx(Vector2(1000, 1000)))
	mm._toggle_mark(c + Vector2(5, 5))
	check("ПКМ по метке убирает её", Minimap.marks.is_empty())
	mm._toggle_mark(c)
	mm._toggle_mark(c + Vector2(100, 0))
	check("две разные метки", Minimap.marks.size() == 2)

	var p := Vector2(600, 200)
	var before := mm._local_to_world(p)
	mm._zoom(0.8, p)
	check("зум приближает", mm._view_m < 600.0)
	check("точка под курсором не сдвинулась", mm._local_to_world(p).distance_to(before) < 0.01)
	for i in 30:
		mm._zoom(0.8, p)
	check("приближение ограничено (%d м)" % int(mm._view_m), is_equal_approx(mm._view_m, mm.min_view_m))
	for i in 60:
		mm._zoom(1.25, p)
	check("отдаление ограничено миром", is_equal_approx(mm._view_m, mm.world_size))

	mm._view_m = 600.0
	mm._center_m = Vector2(50, 50)
	mm._clamp_center()
	var o := mm._origin()
	check("вид не выходит за край мира", o.x >= -0.01 and o.y >= -0.01)

	# сенсорный экран: щипок двумя пальцами и долгое нажатие
	mm.expanded = true
	mm.position = Vector2.ZERO
	mm.size = Vector2(800, 600)
	mm._view_m = 600.0
	mm._center_m = Vector2(1000, 1000)
	mm._follow = false
	Minimap.marks.clear()
	mm._input(_touch(0, Vector2(300, 300), true))
	mm._input(_touch(1, Vector2(500, 300), true))
	mm._input(_sdrag(1, Vector2(700, 300)))          # расстояние между пальцами 200 -> 400
	check("щипок: пальцы врозь — приближение (%d м)" % int(mm._view_m), absf(mm._view_m - 300.0) < 1.0)
	mm._input(_sdrag(1, Vector2(500, 300)))          # назад: 400 -> 200
	check("щипок: пальцы вместе — отдаление (%d м)" % int(mm._view_m), absf(mm._view_m - 600.0) < 1.0)
	mm._input(_touch(1, Vector2(500, 300), false))
	mm._input(_touch(0, Vector2(300, 300), false))
	mm._input(_touch(0, Vector2(400, 300), true))
	mm._long_press_tick(0.3)
	check("короткое касание: метки нет", Minimap.marks.is_empty())
	mm._long_press_tick(0.4)
	check("долгое нажатие ставит метку", Minimap.marks.size() == 1)
	mm._input(_touch(0, Vector2(400, 300), false))
	mm._input(_touch(0, Vector2(400, 300), true))
	mm._input(_sdrag(0, Vector2(480, 300)))          # палец сдвинулся — это перетаскивание, не метка
	mm._long_press_tick(1.0)
	check("сдвинутый палец метку не ставит", Minimap.marks.size() == 1)
	mm._input(_touch(0, Vector2(480, 300), false))
	var v0 := mm._view_m
	mm.zoom_step(0.7)
	check("кнопка «+» приближает", mm._view_m < v0)
	mm.follow_player()
	check("кнопка «Я» возвращает к игроку", mm._follow)
	var c0 := mm._color_i
	mm.next_color()
	check("кнопка «Цвет» меняет цвет метки", mm._color_i == (c0 + 1) % Minimap.PALETTE.size())

	mm.expanded = false
	mm.size = mm.map_size
	check("маленькая карта: масштаб = размер / small_view", is_equal_approx(mm._scale(), 220.0 / mm.small_view_m))

	Minimap.marks.clear()
	print("RESULT fails=", fails)
	quit(fails)
