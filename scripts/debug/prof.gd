class_name Prof
extends RefCounted
## Лёгкий профайлер кадра: подсистемы добавляют время (мкс) под своим именем, main.gd в начале кадра забирает
## накопленное за прошлый кадр (для отчёта о пиках в режиме --perf). Вне замера enabled = false — ничего не считает.

static var enabled := false
static var _acc := {}


static func add(name: String, usec: int) -> void:
	if enabled:
		_acc[name] = int(_acc.get(name, 0)) + usec


static func take() -> Dictionary:
	var d := _acc
	_acc = {}
	return d
