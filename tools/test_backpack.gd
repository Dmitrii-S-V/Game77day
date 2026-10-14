extends SceneTree
## Тест рюкзака: ёмкость инвентаря, запрет снять рюкзак с вещами в доп. ячейках, модель на спине аватара.
## godot --headless --path . --script res://tools/test_backpack.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var inv := Inventory.new()
	check("без рюкзака — %d ячеек" % inv.capacity(), inv.capacity() == Inventory.BASE)
	var left := inv.add("nails", 40 * 100)   # заведомо больше, чем влезет
	var filled := 0
	for i in Inventory.SIZE:
		if inv.slots[i] != null:
			filled += 1
	check("без рюкзака заполнено только %d ячеек" % filled, filled == Inventory.BASE and left > 0)
	check("доп. ячейки пусты", not inv.has_extra_items())

	inv.has_backpack = true
	check("с рюкзаком — %d ячеек" % inv.capacity(), inv.capacity() == Inventory.SIZE)
	inv.add("nails", 40 * 100)
	check("с рюкзаком заполнены все ячейки", inv.slots[Inventory.SIZE - 1] != null and inv.has_extra_items())

	# UI: рюкзак в слот «Спина» и обратно
	var ui := InventoryUI.new()
	root.add_child(ui)
	var inv2 := Inventory.new()
	ui.inv = inv2
	check("слот спины пуст — рюкзака нет", not inv2.has_backpack)
	inv2.slots[10] = {"id": "backpack", "n": 1}
	check("Ctrl+ЛКМ надевает рюкзак", ui._wear_from_slot(10) and inv2.has_backpack and inv2.slots[10] == null)
	check("второй рюкзак на спину не надеть", not ui._wear_from_slot(11))
	inv2.slots[20] = {"id": "stone", "n": 1}
	check("с вещью в доп. ячейке снять нельзя", inv2.has_extra_items())

	# двойное нажатие (телефон): рюкзак в руке уходит на спину
	var inv3 := Inventory.new()
	ui.inv = inv3
	ui._eq["back"] = null
	ui._cursor = {"id": "backpack", "n": 1}
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	ui._slot_input(dbl, 10)
	check("двойное нажатие надевает рюкзак из руки", inv3.has_backpack and ui._cursor == null and ui._eq["back"] != null)
	ui._cursor = {"id": "stone", "n": 1}
	ui._eq["back"] = null
	inv3.has_backpack = false
	ui._slot_input(dbl, 10)
	check("двойное нажатие с камнем рюкзак не надевает", not inv3.has_backpack)

	# аватар: рюкзак виден только когда надет
	var av := PlayerAvatar.new()
	root.add_child(av)
	av.build(Color(0.3, 0.4, 0.3))
	var pack := av.find_child("Pack", true, false) as Node3D
	check("модель рюкзака есть и скрыта", pack != null and not pack.visible)
	av.set_backpack(true)
	check("надет — виден", pack.visible)
	av.set_backpack(false)
	check("снят — скрыт", not pack.visible)

	print("RESULT fails=", fails)
	quit(fails)
