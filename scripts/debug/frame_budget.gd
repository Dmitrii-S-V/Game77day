class_name FrameBudget
extends RefCounted
## Общий бюджет времени кадра на подгрузку мира (применение готовых чанков, растений, зданий, текстур).
## main.gd вызывает begin() в начале кадра; подсистемы перед каждой порцией работы проверяют ok(): пока
## потрачено меньше LIMIT_MS — можно ещё. Остаток работы переносится на следующие кадры: кадр не «раздувается».

const LIMIT_MS := 3.0

static var _start := 0
static var _frame := -1


static func begin() -> void:
	_start = Time.get_ticks_usec()
	_frame = Engine.get_process_frames()


static func used_ms() -> float:
	return (Time.get_ticks_usec() - _start) / 1000.0


## Без активного бюджета в этом кадре (редактор структур, тесты, сцены без main.gd) — ограничений нет.
static func ok(limit_ms: float = LIMIT_MS) -> bool:
	if _frame != Engine.get_process_frames():
		return true
	return used_ms() < limit_ms


# --- отложенное удаление ------------------------------------------------------------
# Выгружаемые узлы (колонки растений, чанки, плитки) сразу скрываются, а удаляются по нескольку за кадр:
# при движении за радиус уходит целый ряд колонок — сотни узлов с коллизией, удаление разом давало пики.
static var _trash: Array[Node] = []


static func free_later(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is Node3D:
		(n as Node3D).visible = false   # не рисуется сразу; коллизия (далеко от игрока) уйдёт при удалении
	_trash.append(n)


## Вызывается в конце кадра: удалить часть накопленного (не больше ~1 мс, минимум один узел).
static func reap() -> void:
	var t0 := Time.get_ticks_usec()
	while not _trash.is_empty():
		var n: Node = _trash.pop_front()
		if is_instance_valid(n):
			n.free()
		if Time.get_ticks_usec() - t0 > 1000 and _trash.size() < 40:
			break
