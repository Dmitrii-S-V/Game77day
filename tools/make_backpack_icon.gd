# Разовый генератор иконки рюкзака: в редакторе открыть файл и «Файл → Запустить» (Ctrl+Shift+X)
extends SceneTree

const BODY := Color(0.55, 0.38, 0.2)
const DARK := Color(0.35, 0.24, 0.12)
const FLAP := Color(0.62, 0.45, 0.26)
const GOLD := Color(0.85, 0.7, 0.3)

func _init() -> void:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_fill(img, Rect2i(12, 18, 40, 38), BODY)      # корпус
	_fill(img, Rect2i(12, 14, 40, 14), FLAP)      # клапан
	_fill(img, Rect2i(22, 32, 5, 24), DARK)       # ремни
	_fill(img, Rect2i(37, 32, 5, 24), DARK)
	_fill(img, Rect2i(28, 34, 8, 6), GOLD)        # пряжка
	_fill(img, Rect2i(26, 8, 12, 6), DARK)        # ручка сверху
	_frame(img, Rect2i(11, 13, 42, 44), DARK)     # обводка
	DirAccess.make_dir_recursive_absolute("res://assets/icons")
	img.save_png("res://assets/icons/backpack.png")
	print("Иконка сохранена: assets/icons/backpack.png")
	quit()


func _fill(img: Image, r: Rect2i, col: Color) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			img.set_pixel(x, y, col)


func _frame(img: Image, r: Rect2i, col: Color) -> void:
	for x in range(r.position.x, r.end.x):
		img.set_pixel(x, r.position.y, col)
		img.set_pixel(x, r.end.y - 1, col)
	for y in range(r.position.y, r.end.y):
		img.set_pixel(r.position.x, y, col)
		img.set_pixel(r.end.x - 1, y, col)
