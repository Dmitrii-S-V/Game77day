extends SceneTree
## Подробные настройки графики: ручная правка поверх пресета, выбор пресета сбрасывает ручные (кроме FOV),
## сохранение/загрузка. С аргументом -- <файл.png> (окно) — снимок панели.
## C:\Godot\godot.exe --path D:\77Days --script res://tools/test_gfx_settings.gd -- shot.png

var fails := 0
var _f := 0
var _shot := ""
var _saved := ""


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_shot = a[0] if a.size() > 0 else ""
	# не портить настройки игрока: сохранить файл и вернуть в конце
	if FileAccess.file_exists(GraphicsSettings.PATH):
		_saved = FileAccess.get_file_as_string(GraphicsSettings.PATH)
	GraphicsSettings._loaded = false
	GraphicsSettings.load_settings()
	GraphicsSettings.set_level(GraphicsSettings.MED)
	check("средние: тени 170", float(GraphicsSettings.preset()["shadow"]) == 170.0)
	check("FOV по умолчанию 70", float(GraphicsSettings.preset()["fov"]) == 70.0)
	GraphicsSettings.set_value("fov", 62.0)
	GraphicsSettings.set_value("shadow", 90.0)
	check("ручные значения поверх пресета", float(GraphicsSettings.preset()["shadow"]) == 90.0 and float(GraphicsSettings.preset()["fov"]) == 62.0)
	check("режим «Свои»", GraphicsSettings.is_custom())
	GraphicsSettings._loaded = false
	GraphicsSettings.custom = {}
	GraphicsSettings.load_settings()
	check("сохранилось и загрузилось", float(GraphicsSettings.preset()["shadow"]) == 90.0 and float(GraphicsSettings.preset()["fov"]) == 62.0)
	GraphicsSettings.set_level(GraphicsSettings.ULTRA)
	check("пресет сбросил ручные, FOV остался", float(GraphicsSettings.preset()["shadow"]) == 240.0 and float(GraphicsSettings.preset()["fov"]) == 62.0 and not GraphicsSettings.is_custom())
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.22, 0.25)
	bg.size = Vector2(1400, 900)
	root.add_child(bg)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 30)
	panel.custom_minimum_size = Vector2(620, 0)
	root.add_child(panel)
	panel.add_child(GraphicsSettings.make_details(func() -> void: pass))


func _process(_d: float) -> bool:
	_f += 1
	if _f == 6:
		if _shot != "":
			root.get_viewport().get_texture().get_image().save_png(_shot)
		if _saved != "":
			var f := FileAccess.open(GraphicsSettings.PATH, FileAccess.WRITE)
			f.store_string(_saved)
			f.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GraphicsSettings.PATH))
		print("RESULT fails=%d" % fails)
		return true
	return false
