extends SceneTree
## Крафт и окно инвентаря: рецепты, списание/выдача, вкладки, кнопка «Создать», обрезка белого фона картинок.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/test_craft.gd

var fails := 0
var _f := 0
var _inv: Inventory
var _ui: InventoryUI


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	_inv = Inventory.new()
	_ui = InventoryUI.new()
	root.add_child(_ui)
	_ui.setup(_inv)


func _process(_d: float) -> bool:
	_f += 1
	if _f != 3:
		return _f > 3
	var rope: Dictionary = CraftDB.recipes()[0]
	var axe: Dictionary = CraftDB.recipes()[1]
	check("рецепты: верёвка и топор", rope["out"] == "grass_rope" and axe["out"] == "stone_axe")
	check("без материалов — нельзя", not CraftDB.can_craft(_inv, rope))
	_inv.add("grass", 16)
	check("верёвка: 5 травы -> 1", CraftDB.craft(_inv, rope) and _inv.count("grass") == 11 and _inv.count("grass_rope") == 1)
	CraftDB.craft(_inv, rope)
	CraftDB.craft(_inv, rope)
	check("3 верёвки, травы 1", _inv.count("grass_rope") == 3 and _inv.count("grass") == 1)
	check("на 4-ю травы не хватает", not CraftDB.can_craft(_inv, rope))
	_inv.add("stone", 2)
	_inv.add("planks", 14)
	check("топор: досок 14 из 15 — нельзя", not CraftDB.can_craft(_inv, axe))
	_inv.add("planks", 1)
	# окно: вкладка «Крафт», топор выбран, кнопка «Создать»
	_ui.toggle(1)
	check("окно открыто на крафте", _ui.is_open() and _ui._tab == 1 and _ui._pages[1].visible and not _ui._pages[0].visible)
	_ui._recipe = 1
	_ui._fill_recipes()
	check("кнопка «Создать» активна", not _ui._d_btn.disabled)
	check("требования показаны (3 строки)", _ui._d_need.get_child_count() >= 3)
	_ui._d_btn.pressed.emit()
	check("топор скрафчен, материалы списаны", _inv.count("stone_axe") == 1 and _inv.count("grass_rope") == 0
		and _inv.count("stone") == 1 and _inv.count("planks") == 0)
	_ui.toggle(0)
	check("Tab на крафте -> вкладка инвентаря", _ui.is_open() and _ui._tab == 0)
	# хотбар внизу — живые ячейки при открытом окне: взять из рюкзака, положить в хотбар
	check("в окне — только рюкзак (%d ячеек)" % _ui._grid.size(), _ui._grid.size() == Inventory.SIZE - Inventory.HOTBAR)
	check("хотбар кликабелен при открытом окне", _ui._hotbar[0].mouse_filter == Control.MOUSE_FILTER_STOP)
	_inv.slots[Inventory.HOTBAR + 3] = {"id": "berries", "n": 5}
	_inv.slots[7] = null
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_ui._grid[3].gui_input.emit(click)
	_ui._hotbar[7].gui_input.emit(click)
	check("ягоды переложены из рюкзака в хотбар (ячейка 8)", _inv.get_slot(7) != null and _inv.get_slot(7)["id"] == "berries"
		and _inv.get_slot(Inventory.HOTBAR + 3) == null)
	# ПКМ — половина стопки в руку, ПКМ с предметом — положить одну
	_inv.slots[Inventory.HOTBAR + 5] = {"id": "nails", "n": 9}
	var rclick := InputEventMouseButton.new()
	rclick.button_index = MOUSE_BUTTON_RIGHT
	rclick.pressed = true
	_ui._grid[5].gui_input.emit(rclick)
	check("ПКМ: в руке 5 из 9, в ячейке 4", _ui._cursor != null and int(_ui._cursor["n"]) == 5 and int(_inv.get_slot(Inventory.HOTBAR + 5)["n"]) == 4)
	_ui._grid[6].gui_input.emit(rclick)
	check("ПКМ с предметом: положена 1, в руке 4", int(_inv.get_slot(Inventory.HOTBAR + 6)["n"]) == 1 and int(_ui._cursor["n"]) == 4)
	_ui._grid[5].gui_input.emit(click)
	check("ЛКМ: стопка объединена (8)", _ui._cursor == null and int(_inv.get_slot(Inventory.HOTBAR + 5)["n"]) == 8)
	# Shift+ЛКМ — в хотбар
	for k in Inventory.HOTBAR:
		_inv.slots[k] = null
	_inv.slots[0] = {"id": "nails", "n": 2}
	var sclick := click.duplicate() as InputEventMouseButton
	sclick.shift_pressed = true
	_ui._grid[5].gui_input.emit(sclick)
	check("Shift+ЛКМ: гвозди ушли в хотбар к своим (10)", int(_inv.get_slot(0)["n"]) == 10 and _inv.get_slot(Inventory.HOTBAR + 5) == null)
	_ui._hotbar[0].gui_input.emit(sclick)
	check("Shift+ЛКМ из хотбара — обратно в рюкзак", _inv.get_slot(0) == null and _inv.count("nails") == 11)
	# переработка (R)
	_inv.slots[Inventory.HOTBAR + 10] = {"id": "stone_axe", "n": 1}
	var wood0 := _inv.count("wood")
	check("R: топор -> 3 дерева", _ui.recycle(Inventory.HOTBAR + 10) and _inv.count("wood") == wood0 + 3 and _inv.count("stone_axe") == 0)
	_inv.slots[Inventory.HOTBAR + 11] = {"id": "water_bottle", "n": 1, "fill": 1.0}
	check("R: бутылка -> разбитое стекло", _ui.recycle(Inventory.HOTBAR + 11) and _inv.count("broken_glass") == 1)
	check("стекло — еда с кровотечением", ItemDB.info("broken_glass")["food"].get("bleed", false))
	_inv.slots[Inventory.HOTBAR + 12] = {"id": "stone", "n": 3}
	check("R: камень не перерабатывается", not _ui.recycle(Inventory.HOTBAR + 12))
	# описание у всех предметов
	var no_desc: Array = []
	for id: String in ItemDB.ITEMS:
		if String(ItemDB.info(id).get("desc", "")) == "":
			no_desc.append(id)
	check("описание у всех предметов (нет: %s)" % str(no_desc), no_desc.is_empty())
	# креатив
	_ui._creative_input(click, "pistol")
	check("креатив: ЛКМ — предмет в руке", _ui._cursor != null and _ui._cursor["id"] == "pistol")
	_ui._creative_input(click, "pistol")
	check("креатив: клик с предметом — выброшен", _ui._cursor == null)
	var c0 := _inv.count("ammo_9mm")
	_ui._creative_input(sclick, "ammo_9mm")
	check("креатив: Shift+ЛКМ — стопка в инвентарь", _inv.count("ammo_9mm") == c0 + ItemDB.stack_size("ammo_9mm"))
	# уровни, прочность, развитие
	Gear.reset()
	var club_r: Dictionary = {}
	var axe2: Dictionary = {}
	for r: Dictionary in CraftDB.recipes():
		if r["out"] == "wooden_club" and int(r.get("lvl", 1)) == 1:
			club_r = r
		if r["out"] == "stone_axe" and int(r.get("lvl", 1)) == 2:
			axe2 = r
	check("бита: 10 дерева", club_r.get("need", {}) == {"wood": 10})
	_inv.add("wood", 10)
	check("бита скрафчена (ур. 1, полная прочность)", CraftDB.craft(_inv, club_r) and _inv.count("wooden_club") == 1)
	check("топор ур. 2 закрыт без развития", not axe2.is_empty() and not CraftDB.is_unlocked(axe2))
	_inv.add("stone_axe", 1, Gear.extra("stone_axe", 1))
	_inv.add("grass_rope", 2)
	_inv.add("stone", 2)
	_inv.add("planks", 10)
	Gear.add_damage("stone_axe", 999.0)
	check("999 урона — ещё закрыт", not CraftDB.is_unlocked(axe2))
	Gear.add_damage("stone_axe", 1.0)
	check("1000 урона — открыт, можно крафтить", CraftDB.is_unlocked(axe2) and CraftDB.can_craft(_inv, axe2))
	check("топор ур. 2 скрафчен", CraftDB.craft(_inv, axe2))
	var axe_item: Variant = null
	for s: Variant in _inv.slots:
		if s != null and s["id"] == "stone_axe":
			axe_item = s
	check("в инвентаре топор ур. 2 с прочностью %d" % int(Gear.dur(axe_item)), axe_item != null and Gear.lvl(axe_item) == 2
		and is_equal_approx(Gear.dur(axe_item), Gear.max_dur("stone_axe", 2)))
	check("пороги: ур.3 — 3000, ур.5 — 10000", is_equal_approx(Gear.need_for(3), 3000.0) and is_equal_approx(Gear.need_for(5), 10000.0))
	check("урон: ур.2 ×1.2, ур.5 ×2.07", is_equal_approx(Gear.dmg_mult(2), 1.2) and absf(Gear.dmg_mult(5) - 2.0736) < 0.001)
	check("бита ур.3: +6% к шансам, топор — 0", is_equal_approx(Gear.chance_bonus("wooden_club", 3), 0.06) and Gear.chance_bonus("stone_axe", 3) == 0.0)
	var w := {"id": "wooden_club", "n": 1, "lvl": 1, "dur": 2.0}
	check("износ: 2 удара -> сломался на втором", not Gear.wear(w) and Gear.wear(w))
	_ui.toggle(3)
	check("вкладка «Развитие» — строки оружия", _ui._dev_box.get_child_count() == Gear.LEVELED.size())
	_ui.toggle(4)
	check("вкладка «Помощь» открыта", _ui._tab == 4 and _ui._pages[4].visible)
	_ui.toggle(4)
	_ui.toggle(0)
	_ui.toggle(0)
	check("повторный Tab — закрыто", not _ui.is_open())
	check("закрыто — хотбар мимо мыши", _ui._hotbar[0].mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check("поиск: «верёв» находит одну", CraftDB.list("Все", "верёв").size() == 1)
	check("категория Инструменты — топор", CraftDB.list("Инструменты")[0]["out"] == "stone_axe")
	# фон картинок
	var S: GDScript = load("res://tools/import_ui_images.gd")
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length()
			if d < 26 and d > 12:
				img.set_pixel(x, y, Color(0.4, 0.45, 0.25))   # кольцо (верёвка) с белой дырой внутри
	var cut: Image = S._cut_bg(img)
	check("фон снаружи прозрачный", cut.get_pixel(2, 2).a == 0.0)
	check("дыра внутри кольца прозрачная", cut.get_pixel(32, 32).a == 0.0)
	check("предмет непрозрачный", cut.get_pixel(32, 12).a == 1.0)
	var fit: Image = S._fit(cut, 128, 6)
	check("иконка 128 px", fit.get_width() == 128 and fit.get_height() == 128)
	check("иконка верёвки есть", InventoryUI.icon("grass_rope") != null)
	print("RESULT fails=%d" % fails)
	return true
