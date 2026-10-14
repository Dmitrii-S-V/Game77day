extends SceneTree
## Снимки окна инвентаря и крафта (проверка оформления): -- <prefix>  ->  <prefix>_inv.png, <prefix>_craft.png

var _f := 0
var _ui: InventoryUI
var _out := ""


func _init() -> void:
	_out = OS.get_cmdline_user_args()[0]
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.36, 0.3)
	bg.size = Vector2(4000, 3000)
	root.add_child(bg)
	var inv := Inventory.new()
	for it in [["stone_axe", 1], ["water_bottle", 1], ["grass", 14], ["stone", 3], ["planks", 18], ["canned_food", 2],
			["pistol", 1], ["ammo_9mm", 24], ["grass_rope", 1], ["wood", 6], ["cloth", 4], ["nails", 30], ["berries", 7]]:
		inv.add(it[0], it[1])
	_ui = InventoryUI.new()
	root.add_child(_ui)
	_ui.setup(inv)
	var cur := TextureRect.new()   # курсор на снимке (системный не попадает в кадр)
	cur.texture = ImageTexture.create_from_image(UiTheme._draw_cursor())
	cur.position = Vector2(760, 360)
	cur.z_index = 100
	_ui.add_child(cur)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_ui.toggle(0)
		_ui._hover_i = 0          # как будто мышь над топором в хотбаре
		_ui._update_info()
	if _f == 8:
		root.get_viewport().get_texture().get_image().save_png(_out + "_inv.png")
		_ui.toggle(1)
		_ui._recipe = 1
		_ui._fill_recipes()
	if _f == 14:
		root.get_viewport().get_texture().get_image().save_png(_out + "_craft.png")
		_ui.toggle(2)
		_ui._hover_i = -1
		_ui._hover_id = "broken_glass"
		_ui._update_info()
	if _f == 20:
		root.get_viewport().get_texture().get_image().save_png(_out + "_creative.png")
		Gear.add_damage("stone_axe", 1450.0)
		Gear.add_damage("wooden_club", 380.0)
		Gear.kills = 7
		_ui.toggle(3)
	if _f == 26:
		root.get_viewport().get_texture().get_image().save_png(_out + "_dev.png")
		_ui.toggle(4)
	if _f == 32:
		root.get_viewport().get_texture().get_image().save_png(_out + "_help.png")
		return true
	return false
