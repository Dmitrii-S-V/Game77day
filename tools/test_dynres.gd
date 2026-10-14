extends SceneTree
## Тест автоподстройки разрешения: низкий FPS понижает масштаб до минимума, запас по FPS возвращает к потолку пресета.
## godot --headless --path . --script res://tools/test_dynres.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _feed(dr: DynamicRes, fps: float, seconds: float) -> void:
	var delta := 1.0 / fps
	var t := 0.0
	while t < seconds:
		dr._process(delta)
		t += delta


func _init() -> void:
	GraphicsSettings.level = GraphicsSettings.MIN
	GraphicsSettings._loaded = true
	GraphicsSettings.custom = {}
	var dr := DynamicRes.new()
	root.add_child(dr)
	await process_frame     # узел входит в дерево: _ready и окно доступны
	var top := float(GraphicsSettings.preset()["scale"])
	check("старт — потолок пресета (%.2f)" % dr.current, is_equal_approx(dr.current, top))
	_feed(dr, 10.0, 3.0)
	check("10 FPS: масштаб падает (%.2f)" % dr.current, dr.current < top - 0.05)
	_feed(dr, 10.0, 20.0)
	check("не ниже минимума (%.2f)" % dr.current, is_equal_approx(dr.current, DynamicRes.MIN_SCALE))
	_feed(dr, 30.0, 6.0)
	check("30 FPS (в цели): масштаб не меняется", is_equal_approx(dr.current, DynamicRes.MIN_SCALE))
	_feed(dr, 120.0, 60.0)
	check("120 FPS: масштаб вернулся к потолку пресета (%.2f)" % dr.current, is_equal_approx(dr.current, top))
	check("окно получило масштаб", is_equal_approx(root.scaling_3d_scale, top))
	print("RESULT fails=", fails)
	quit(fails)
