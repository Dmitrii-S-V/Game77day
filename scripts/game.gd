extends Node
## Глобальное состояние (автозагрузка "Game"): параметры нового мира и сгенерированная карта,
## которую меню передаёт игровой сцене.

var params := WorldParams.new()
var world: WorldMap
var pending_save := {}   # сохранение для загрузки в следующей игровой сцене (меню «Продолжить»)
var net_host := false   # следующая игровая сцена открывает сервер для сетевой игры (галочка в меню)
var test_prefab := ""   # имя префаба, который поставить рядом со спавном ("Проверить в мире" из редактора)


func _ready() -> void:
	# телефон: интерфейс масштабируется под экран (рассчитан на 1600x900; база ниже — крупнее кнопки и шрифт)
	if OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch"):
		var w := get_tree().root
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_size = Vector2i(1422, 800)


func start_world(w: WorldMap) -> void:
	world = w
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func back_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
