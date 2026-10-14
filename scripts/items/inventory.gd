class_name Inventory
extends RefCounted
## Инвентарь: 8 слотов быстрого доступа + рюкзак. Слот — null или {id, n, fill}.

signal changed

const HOTBAR := 8
const SIZE := 32
const BASE := HOTBAR + 8     # ячеек без рюкзака: хотбар + 1 ряд

var slots: Array = []
var selected := 0
var has_backpack := false    # рюкзак на спине — открыты все SIZE ячеек


func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = null


## Сколько ячеек сейчас доступно.
func capacity() -> int:
	return SIZE if has_backpack else BASE


## Есть ли предметы в ячейках, которые откроет только рюкзак (без него снять его нельзя).
func has_extra_items() -> bool:
	for i in range(BASE, SIZE):
		if slots[i] != null:
			return true
	return false


func get_slot(i: int) -> Variant:
	return slots[i]


func set_slot(i: int, v: Variant) -> void:
	slots[i] = v
	changed.emit()


func selected_item() -> Variant:
	return slots[selected]


func select(i: int) -> void:
	selected = posmod(i, HOTBAR)
	changed.emit()


func swap(a: int, b: int) -> void:
	var t: Variant = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()


## Добавляет предмет; возвращает, сколько не поместилось.
func add(id: String, n: int = 1, extra: Dictionary = {}) -> int:
	var stack := ItemDB.stack_size(id)
	var left := n
	var cap := capacity()
	if stack > 1:
		for i in cap:
			var s: Variant = slots[i]
			if s != null and s["id"] == id and int(s["n"]) < stack:
				var take := mini(left, stack - int(s["n"]))
				s["n"] = int(s["n"]) + take
				left -= take
				if left == 0:
					changed.emit()
					return 0
	for i in cap:
		if slots[i] == null:
			var take2 := mini(left, stack)
			var item := {"id": id, "n": take2}
			item.merge(extra)
			slots[i] = item
			left -= take2
			if left == 0:
				break
	changed.emit()
	return left


func count(id: String) -> int:
	var n := 0
	for s: Variant in slots:
		if s != null and s["id"] == id:
			n += int(s["n"])
	return n


## Забрать до n штук (с конца рюкзака); возвращает, сколько забрано.
func take(id: String, n: int) -> int:
	var got := 0
	for i in range(SIZE - 1, -1, -1):
		var s: Variant = slots[i]
		if got >= n:
			break
		if s != null and s["id"] == id:
			var k := mini(n - got, int(s["n"]))
			s["n"] = int(s["n"]) - k
			got += k
			if int(s["n"]) <= 0:
				slots[i] = null
	if got > 0:
		changed.emit()
	return got


func remove_selected_one() -> void:
	var s: Variant = slots[selected]
	if s == null:
		return
	s["n"] = int(s["n"]) - 1
	if int(s["n"]) <= 0:
		slots[selected] = null
	changed.emit()
