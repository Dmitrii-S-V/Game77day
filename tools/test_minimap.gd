extends SceneTree
## Тест миникарты: метки (поставить/убрать по клику), зум вокруг курсора, границы, перетаскивание.
## godot --headless --path . --script res://tools/test_minimap.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


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

	mm.expanded = false
	mm.size = mm.map_size
	check("маленькая карта: масштаб = размер / small_view", is_equal_approx(mm._scale(), 220.0 / mm.small_view_m))

	Minimap.marks.clear()
	print("RESULT fails=", fails)
	quit(fails)
