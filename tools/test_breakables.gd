extends SceneTree
## Разрушаемость без игрока: срезание травы (кустики, запоминание срезанного), поиск реквизита по коллайдеру,
## добыча, иконки, частицы. C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_breakables.gd

var fails := 0
var _f := 0
var _tuft: MultiMeshInstance3D


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	GrassField.cut.clear()
	var holder := Node3D.new()
	root.add_child(holder)
	_tuft = PropFactory.tuft(1234, 6)
	_tuft.position = Vector3(10, 0, 10)
	holder.add_child(_tuft)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		var before := _tuft.multimesh.instance_count
		var n := GrassField.cut_around(self, Vector3(10, 0, 10), 0.7)
		check("кустик срезан (%d из %d)" % [n, before], n > 0 and _tuft.multimesh.instance_count == before - n)
		check("срезанные клетки запомнены (%d)" % GrassField.cut.size(), GrassField.cut.size() > 0)
		var t2 := PropFactory.tuft(1234, 6)
		t2.position = Vector3(10, 0, 10)
		root.add_child(t2)
		check("новый кустик на срезанном месте пуст (%d)" % t2.multimesh.instance_count, t2.multimesh.instance_count == 0)
		var far := PropFactory.tuft(99, 6)
		far.position = Vector3(40, 0, 40)
		root.add_child(far)
		check("в другом месте трава цела", far.multimesh.instance_count == 6)
		# реквизит: поиск по коллайдеру, добыча
		var pack := PropFactory.backpack(2)
		root.add_child(pack)
		var body: Node = pack.find_children("*", "StaticBody3D", true, false)[0]
		check("рюкзак находится по коллайдеру", Breakables.find(body) == pack)
		var d := Breakables.def(pack)
		check("описание рюкзака", d.get("loot", false) and float(d["hp"]) > 0.0)
		var drop := Breakables.roll_drop(Breakables.DEFS["pole_metal"])
		check("со столба — металлолом (%s)" % str(drop), int(drop.get("scrap_metal", 0)) >= 3)
		check("сломанное не ставится снова", not Breakables.is_broken(Vector3(5, 0, 5)))
		Vegetation.mark_removed(Vector3(5, 0, 5))
		check("…а после поломки — помечено", Breakables.is_broken(Vector3(5.05, 1, 4.98)))
		# предметы и иконки
		for id in ["grass", "rubber"]:
			check("предмет %s есть" % id, ItemDB.ITEMS.has(id))
		var missing: Array = []
		for id: String in ItemDB.ITEMS:
			if InventoryUI.icon(id) == null:
				missing.append(id)
		check("иконки у всех предметов (нет: %s)" % str(missing), missing.is_empty())
		check("удар кулаком — урон руки", ItemDB.damage("grass", "zombie") == ItemDB.HAND_DMG["zombie"])
		# частицы создаются и удаляются сами
		Debris.burst(root, Vector3.ZERO, Color.GRAY, 5, 2.0, 0.1, 3.0, Debris.file_tex("dirt_a"))
		Debris.dust(root, Vector3.ZERO, Color.GRAY)
		check("частицы запущены (%d)" % Debris.active, Debris.active == 2)
	if _f == 3 + 60 * 3:
		check("частицы удалились (%d)" % Debris.active, Debris.active == 0)
		print("RESULT fails=%d" % fails)
		return true
	return false
