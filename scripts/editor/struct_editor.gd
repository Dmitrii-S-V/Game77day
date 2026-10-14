extends Node3D
## Режим строительства структур: плоская местность, свободная камера, сетка, подсветка ячейки,
## палитра блоков, инструменты (поставить / удалить / выделение / улучшить / текстура / прочность),
## копирование, поворот и зеркало выделения, undo/redo, сохранение и загрузка префабов (JSON).
## Запуск: C:\Godot\godot.exe --path D:\77Days res://scenes/editor.tscn   (или из меню игры)
##
## Палитра слева — две вкладки: «Формы» (куб, колонны, балки, стены…: материал выбирается кнопкой «Материал»,
## от него зависят вид и прочность) и «Объекты» (двери, окна, мебель, свет, ограждения — материал у них свой).
## «Текстура» — вариант текстуры материала. Кисть (4) — перекрасить уже поставленные блоки текущим материалом и текстурой.
##
## Управление: RMB (зажать) — осмотр мышью, WASD — полёт, Space/Q — вверх/вниз, Shift — быстрее.
## LMB — действие инструмента, колёсико — вариант текстуры, E — открыть/закрыть дверь.
## R — поворот вокруг вертикали, Shift+R — вокруг X, Alt+R — вокруг Z (по всем осям — блоки 1x1x1; поворот
## запоминается для следующих блоков). 1..5 — инструменты; F — заливка выделения; Del — очистить выделение;
## T — повернуть, M/Shift+M — зеркало; Ctrl+C / Ctrl+V — копировать / вставить; Ctrl+Z / Ctrl+Y — undo / redo; G — сетка.

const NX := 48
const NY := 32
const NZ := 48
const B := BlockGrid.B
const REACH := 90.0

enum Mode { PLACE, REMOVE, SELECT, BRUSH, INSPECT, GROUND, PLANT }
const MODE_NAMES := ["Поставить (1)", "Удалить (2)", "Выделение (3)", "Кисть (4)", "Прочность (5)", "Земля (6)", "Растения (7)"]
const CATEGORY_CHOICES := ["house", "shop", "gas_station", "warehouse", "barn", "office", "apartment", "cabin", "shed", "dump", "park", "other"]
const CATEGORY_TITLES := {"house": "дом", "shop": "магазин", "gas_station": "заправка", "warehouse": "склад", "barn": "амбар", "office": "офис", "apartment": "многоэтажка", "cabin": "хижина", "shed": "сарай", "dump": "свалка", "park": "парк", "other": "другое"}

var grid: BlockGrid
var bb: BlockBuilding
var cam: Camera3D
var mode := Mode.PLACE
var item: Dictionary = {}              # выбранный пункт палитры {id, tier, ...}
var cur_rot := 0
var cur_up := 0                         # «верх» (поворот по всем осям, BlockRegistry.up_basis)
var cur_variant := 0
var cur_mat := "concrete_smooth"        # материал форм (ключ tier блока «wall»)
var cur_ground := "asphalt"             # покрытие земли (GroundTypes), инструмент «Земля»
var ground_brush := 1                   # размер кисти земли, ячеек ([ и ])
var _ground_node: Node3D
var _ground_cell := Vector2i(-1, -1)
var _ground_dirty := false
var cur_plant := "oak_0"                # что сажаем (PlantTypes), инструмент «Растения»
var _plants_node: Node3D
var _plants_dirty := false
var _ground_point := Vector3.INF        # точка на земле под курсором (локально к сетке, м)
var has_sel := false
var sel_lo := Vector3i.ZERO
var sel_hi := Vector3i.ZERO
var clipboard: StructClip = null
var info := {"name": "", "category": "house", "tags": "", "weight": 1.0, "biomes": "any", "margin": 2, "fx": 0, "fz": 0, "sink": 0}

var _yaw := 0.0
var _pitch := -0.3
var _looking := false
var _hit := {}
var _target := Vector3i(-1, -1, -1)      # пустая ячейка для постановки
var _hover := Vector3i(-1, -1, -1)       # ячейка с блоком под прицелом
var _drag_a := Vector3i(-1, -1, -1)
var _undo: Array = []
var _redo: Array = []
var _op: Dictionary = {}
var _shown: Array = []
var _status: Label
var _hint: Label
var _search: LineEdit
var _cat: OptionButton
var _cat_keys: Array = []               # ключи категорий в _cat (после «Все категории»)
var _tabs: TabContainer
var _list: ItemList                     # список текущей вкладки
var _lists: Array[ItemList] = []        # [формы, объекты]
var _mat_btn: Button
var _tex_btn: Button
var _rot_lbl: Label
var _mat_popup: PopupPanel
var _tex_popup: PopupPanel
var _brush_last := Vector3i(-1, -1, -1)
var _ghost_key := ""
var _pal_info: Label
var _mode_buttons: Array[Button] = []
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _selbox: MeshInstance3D
var _hoverbox: MeshInstance3D
var _grid_plane: MeshInstance3D
var _save_dlg: ConfirmationDialog
var _load_dlg: ConfirmationDialog
var _load_list: ItemList
var _save_fields := {}
var _msg_t := 0.0
var _shot_path := ""
var _shot_frames := 0


func _ready() -> void:
	BlockRegistry.ensure()
	PrefabRegistry.ensure()
	_build_world()
	_build_ui()
	_refresh_palette()
	var cam_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--load="):
			_load_prefab(a.substr(7))
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--cam="):
			cam_arg = a.substr(6)
	if cam_arg != "":
		var v := cam_arg.split(",")
		cam.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		_yaw = float(v[3])
		_pitch = float(v[4])
		cam.rotation = Vector3(_pitch, _yaw, 0)
	_say("Редактор структур. Выберите блок слева, LMB — поставить. Подсказки внизу.")


# --- мир редактора ---------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.5, 0.8)
	sm.sky_horizon_color = Color(0.7, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# земля
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.28)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.001
	add_child(ground)
	# сетка на уровне земли
	_grid_plane = MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(NX * B, NZ * B)
	_grid_plane.mesh = gp
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 f = abs(fract(wp.xz + 0.5) - 0.5);
	float w = fwidth(wp.x) * 0.9;
	float line = 1.0 - smoothstep(0.0, w, min(f.x, f.y));
	vec2 g = abs(fract(wp.xz / 4.0 + 0.5) - 0.5) * 4.0;
	float major = 1.0 - smoothstep(0.0, w * 1.6, min(g.x, g.y));
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(18.0, 34.0, d);
	ALBEDO = mix(vec3(0.15, 0.18, 0.15), vec3(1.0), major * 0.6);
	ALPHA = clamp(line * 0.35 + major * 0.5, 0.0, 0.85) * fade;
}"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	_grid_plane.material_override = smat
	_grid_plane.position.y = 0.004
	add_child(_grid_plane)
	# контур рамки построек
	add_child(_outline(Vector3(-NX * B * 0.5, -B, -NZ * B * 0.5), Vector3(NX * B, NY * B, NZ * B), Color(1, 1, 1, 0.5)))
	var lbl := Label3D.new()
	lbl.text = "ФАСАД (+Z)"
	lbl.font_size = 96
	lbl.pixel_size = 0.01
	lbl.rotation_degrees.x = -90
	lbl.position = Vector3(0, 0.02, NZ * B * 0.5 + 0.8)
	lbl.modulate = Color(1, 1, 1, 0.6)
	add_child(lbl)
	# материалы деревьев/камней для вкладки «Растения» (те же, что в лесу)
	var veg := Vegetation.new()
	veg.name = "VegMaterials"
	add_child(veg)
	# холст
	grid = BlockGrid.new(NX, NY, NZ)
	grid.ground_cells = 1
	bb = BlockBuilding.new()
	add_child(bb)
	bb.setup(grid, BlockRegistry.make_block_material(), BlockRegistry.make_glass_material(), true)
	# камера
	cam = Camera3D.new()
	cam.far = 500.0
	cam.fov = 70.0
	cam.position = Vector3(0, 5, 16)
	add_child(cam)
	cam.make_current()
	_yaw = 0.0
	_pitch = -0.3
	cam.rotation = Vector3(_pitch, _yaw, 0)
	# призрак блока, подсветка ячейки, рамка выделения
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1.0, 1.0, 0.2, 0.22)
	_hoverbox = MeshInstance3D.new()
	_hoverbox.mesh = BoxMesh.new()
	_hoverbox.material_override = hm
	_hoverbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hoverbox)
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
	_selbox = MeshInstance3D.new()
	_selbox.mesh = BoxMesh.new()
	_selbox.material_override = sm2
	_selbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selbox.visible = false
	add_child(_selbox)


func _outline(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var v := PackedVector3Array()
	var c := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		v.append(pos + (c[e[0]] as Vector3) * size)
		v.append(pos + (c[e[1]] as Vector3) * size)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = col
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mt
	return mi


# --- интерфейс --------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# верхняя панель
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 70
	layer.add_child(top)
	var hb := HFlowContainer.new()
	top.add_child(hb)
	for entry in [["← В меню", func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file("res://scenes/menu.tscn")], ["Новая", _on_new], ["Загрузить", _on_load_pressed], ["Сохранить", _on_save_pressed], ["Проверить в мире", _on_test_world]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		hb.add_child(b)
	hb.add_child(VSeparator.new())
	for i in MODE_NAMES.size():
		var mb := Button.new()
		mb.text = MODE_NAMES[i]
		mb.toggle_mode = true
		mb.pressed.connect(_set_mode.bind(i))
		hb.add_child(mb)
		_mode_buttons.append(mb)
	hb.add_child(VSeparator.new())
	for entry in [["Заливка (F)", _fill_selection], ["Очистить (Del)", _clear_selection], ["Копир. (Ctrl+C)", _copy_selection], ["Встав. (Ctrl+V)", _paste], ["Повернуть (T)", _rotate_selection], ["Зерк. (M)", _mirror_selection.bind(false)], ["Undo", _do_undo], ["Redo", _do_redo]]:
		var b2 := Button.new()
		b2.text = entry[0]
		b2.pressed.connect(entry[1])
		hb.add_child(b2)
	# палитра слева
	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_top = 80
	left.offset_bottom = -60
	left.offset_right = 330
	layer.add_child(left)
	var vb := VBoxContainer.new()
	left.add_child(vb)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по названию…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _refresh_palette())
	vb.add_child(_search)
	_cat = OptionButton.new()
	_cat.item_selected.connect(func(_i: int) -> void: _refresh_palette(false))
	vb.add_child(_cat)
	# вкладки: формы (материал выбирается отдельно) и объекты (свой материал)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	for tab_name in ["Формы", "Объекты", "Земля", "Растения"]:
		var il := ItemList.new()
		il.name = tab_name
		il.fixed_icon_size = Vector2i(40, 40)
		il.icon_mode = ItemList.ICON_MODE_LEFT
		il.item_selected.connect(_on_palette_selected)
		_tabs.add_child(il)
		_lists.append(il)
	_list = _lists[0]
	_tabs.tab_changed.connect(func(t: int) -> void:
		_list = _lists[t]
		item = {}
		if t == 2:
			_set_mode(Mode.GROUND)
		elif t == 3:
			_set_mode(Mode.PLANT)
		elif mode == Mode.GROUND or mode == Mode.PLANT:
			_set_mode(Mode.PLACE)
		_refresh_palette())
	# материал и текстура
	var mrow := HBoxContainer.new()
	vb.add_child(mrow)
	_mat_btn = Button.new()
	_mat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mat_btn.expand_icon = false
	_mat_btn.tooltip_text = "Материал формы: вид и прочность"
	_mat_btn.pressed.connect(_open_mat_popup)
	mrow.add_child(_mat_btn)
	_tex_btn = Button.new()
	_tex_btn.tooltip_text = "Вариант текстуры материала (или колёсико мыши)"
	_tex_btn.pressed.connect(_open_tex_popup)
	mrow.add_child(_tex_btn)
	# поворот (запоминается для следующих блоков)
	var rrow := HBoxContainer.new()
	vb.add_child(rrow)
	_rot_lbl = Label.new()
	_rot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(_rot_lbl)
	for rb: Array in [["⟳Y", Vector3.UP, "Вокруг вертикали (R)"], ["⟳X", Vector3.RIGHT, "Вокруг X (Shift+R)"], ["⟳Z", Vector3.BACK, "Вокруг Z (Alt+R)"]]:
		var b := Button.new()
		b.text = rb[0]
		b.tooltip_text = rb[2]
		b.pressed.connect(_rotate_cur.bind(rb[1]))
		rrow.add_child(b)
	var r0 := Button.new()
	r0.text = "0"
	r0.tooltip_text = "Сбросить поворот"
	r0.pressed.connect(func() -> void:
		cur_rot = 0
		cur_up = 0
		_update_pal_info())
	rrow.add_child(r0)
	_build_popups(layer)
	_pal_info = Label.new()
	_pal_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_pal_info)
	# нижняя панель
	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -56
	layer.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_status = Label.new()
	bv.add_child(_status)
	_hint = Label.new()
	_hint.modulate = Color(1, 1, 1, 0.65)
	_hint.text = "RMB-зажать: камера · WASD/Space/Q: полёт · LMB: действие · колёсико: текстура · R / Shift+R / Alt+R: поворот по Y/X/Z · 4: кисть · 6: земля ([ ] — кисть) · 7: растения · E: дверь · F/Del/T/M: выделение · Ctrl+C/V/Z/Y · G: сетка"
	bv.add_child(_hint)
	_build_dialogs(layer)
	_set_mode(Mode.PLACE)


func _build_dialogs(layer: CanvasLayer) -> void:
	_save_dlg = ConfirmationDialog.new()
	_save_dlg.title = "Сохранить структуру"
	_save_dlg.ok_button_text = "Сохранить"
	_save_dlg.cancel_button_text = "Отмена"
	_save_dlg.min_size = Vector2i(460, 0)
	layer.add_child(_save_dlg)
	var gc := GridContainer.new()
	gc.columns = 2
	_save_dlg.add_child(gc)
	var rows := [
		["name", "Имя", "line"], ["category", "Категория", "cat"], ["custom_cat", "или своя категория", "line"], ["tags", "Теги (через запятую)", "line"],
		["weight", "Вес появления", "spin"], ["biomes", "Допустимые биомы", "line"], ["margin", "Отступ футпринта (ячеек)", "spin_i"],
		["fx", "Футпринт X (ячеек, 0 = авто)", "spin_i"], ["fz", "Футпринт Z (ячеек, 0 = авто)", "spin_i"], ["sink", "Погружение в землю (слоёв, 0 — как здесь)", "spin_i"],
	]
	for r in rows:
		var l := Label.new()
		l.text = r[1]
		gc.add_child(l)
		var w: Control
		match r[2]:
			"line":
				w = LineEdit.new()
				(w as LineEdit).custom_minimum_size.x = 240
			"cat":
				var ob := OptionButton.new()
				for c in CATEGORY_CHOICES:
					ob.add_item("%s (%s)" % [CATEGORY_TITLES[c], c])
				w = ob
			"spin":
				var sp := SpinBox.new()
				sp.min_value = 0.0
				sp.max_value = 100.0
				sp.step = 0.1
				sp.value = 1.0
				w = sp
			_:
				var si := SpinBox.new()
				si.min_value = 0
				si.max_value = 64
				si.step = 1
				w = si
		gc.add_child(w)
		_save_fields[r[0]] = w
	_save_dlg.confirmed.connect(_on_save_confirmed)
	_load_dlg = ConfirmationDialog.new()
	_load_dlg.title = "Загрузить структуру"
	_load_dlg.ok_button_text = "Загрузить"
	_load_dlg.cancel_button_text = "Отмена"
	_load_dlg.min_size = Vector2i(420, 360)
	layer.add_child(_load_dlg)
	_load_list = ItemList.new()
	_load_list.custom_minimum_size = Vector2(380, 280)
	_load_dlg.add_child(_load_list)
	_load_dlg.confirmed.connect(func() -> void:
		var sel := _load_list.get_selected_items()
		if not sel.is_empty():
			_load_prefab(_load_list.get_item_text(sel[0]).split("  ")[0]))


## Формы — блоки с выбираемым материалом (tiers: куб и все формы), объекты — со своим материалом.
func _is_shape(id: int) -> bool:
	return BlockRegistry.tier_count(id) > 0


## Номер tier блока для текущего материала форм (-1 — у блока такого нет).
func _tier_for(id: int) -> int:
	var tiers: Array = BlockRegistry.block(id).get("tiers", [])
	for t in tiers.size():
		if String(tiers[t]["key"]) == cur_mat:
			return t
	return -1


## Пункт палитры для блока: формам — tier текущего материала.
func _item_for(id: int) -> Dictionary:
	var b := BlockRegistry.block(id)
	var tier := maxi(0, _tier_for(id)) if _is_shape(id) else 0
	return {"id": id, "tier": tier, "key": b["key"], "name": b["name"], "category": b.get("category", "")}


func _refresh_palette(rebuild_cats: bool = true) -> void:
	if _tabs != null and _tabs.current_tab == 3:
		# вкладка «Растения»: деревья, кусты, валуны, трава, камешки, скамейки
		_cat.clear()
		_cat.add_item("Растения и предметы")
		_list.clear()
		for k: String in PlantTypes.ORDER:
			var pi := _list.add_item(String(PlantTypes.TYPES[k]["name"]))
			if k == cur_plant:
				_list.select(pi)
		_update_pal_info()
		return
	if _tabs != null and _tabs.current_tab == 2:
		# вкладка «Земля»: типы покрытия
		_cat.clear()
		_cat.add_item("Покрытие земли")
		_list.clear()
		for k: String in GroundTypes.ORDER:
			var gi := _list.add_item(String(GroundTypes.TYPES[k]["name"]), GroundTypes.icon(k))
			if k == cur_ground:
				_list.select(gi)
		_update_pal_info()
		return
	var shapes_tab := _tabs == null or _tabs.current_tab == 0
	# категории текущей вкладки
	if rebuild_cats:
		var keep: String = _cat_keys[_cat.selected - 1] if _cat.selected > 0 and _cat.selected - 1 < _cat_keys.size() else ""
		_cat.clear()
		_cat.add_item("Все категории")
		_cat_keys = []
		var used := {}
		for id: int in BlockRegistry.all_ids():
			if _is_shape(id) == shapes_tab:
				used[String(BlockRegistry.block(id).get("category", ""))] = true
		for c: Dictionary in BlockRegistry.categories():
			if used.has(String(c["key"])):
				_cat.add_item(String(c["name"]))
				_cat_keys.append(String(c["key"]))
				if String(c["key"]) == keep:
					_cat.select(_cat.item_count - 1)
	var cat_key: String = _cat_keys[_cat.selected - 1] if _cat.selected > 0 and _cat.selected - 1 < _cat_keys.size() else ""
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	_shown = []
	_list.clear()
	for id: int in BlockRegistry.all_ids():
		if _is_shape(id) != shapes_tab:
			continue
		var p := _item_for(id)
		if cat_key != "" and String(p["category"]) != cat_key:
			continue
		var nm := String(p["name"])
		if q != "" and not (q in nm.to_lower() or q in String(p["key"]).to_lower()):
			continue
		_shown.append(p)
		var ic: Texture2D = ShapeIcons.icon(id, int(p["tier"])) if shapes_tab or BlockRegistry.shape_of(id) != "cube" else BlockRegistry.icon(id, 0)
		var idx := _list.add_item(nm, ic)
		_list.set_item_tooltip(idx, "%s — hp %d, %s" % [nm, int(BlockRegistry.hp(id, int(p["tier"]))), BlockRegistry.kind(id, int(p["tier"]))])
		if not item.is_empty() and int(item["id"]) == id:
			_list.select(idx)
	if item.is_empty() and not _shown.is_empty():
		_select_palette(0)
	_update_pal_info()


## Выбрать пункт палитры по ключу (например "wall:planks_fresh", "column" или "candle"); для скриптов и тестов.
func select_key(key: String) -> bool:
	var parts := key.split(":")
	var id := BlockRegistry.id_by_key(parts[0])
	if id == 0:
		return false
	if parts.size() > 1:
		cur_mat = parts[1]
	if _tabs != null:
		_tabs.current_tab = 0 if _is_shape(id) else 1
	item = _item_for(id)
	cur_variant = 0
	_update_pal_info()
	return true


func _select_palette(i: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	item = _shown[i]
	_list.select(i)
	_update_pal_info()


func _on_palette_selected(i: int) -> void:
	if _tabs.current_tab == 3:
		cur_plant = PlantTypes.ORDER[i]
		_set_mode(Mode.PLANT)
		_update_pal_info()
		return
	if _tabs.current_tab == 2:
		cur_ground = GroundTypes.ORDER[i]
		_set_mode(Mode.GROUND)
		_update_pal_info()
		return
	_select_palette(i)
	if mode != Mode.BRUSH and mode != Mode.PLACE:
		_set_mode(Mode.PLACE)


func _mat_name(key: String) -> String:
	return String(BlockRegistry.material_by_key(key).get("name", key))


func _update_pal_info() -> void:
	_rot_lbl.text = "Поворот: %d°%s" % [cur_rot * 90, ["", " · верх вниз", " · верх →+X", " · верх →−X", " · верх →+Z", " · верх →−Z"][cur_up]]
	if _tabs != null and _tabs.current_tab == 3:
		_mat_btn.disabled = true
		_mat_btn.icon = null
		_mat_btn.text = "Ставим: %s" % PlantTypes.TYPES[cur_plant]["name"]
		_tex_btn.disabled = true
		_tex_btn.text = "—"
		_pal_info.text = "Растения: ЛКМ по земле — посадить/поставить, Ctrl+ЛКМ — убрать ближайшее\nскамейка — по повороту R (оттенок случайный от синего до зелёного), деревья — случайный поворот и размер\nсохраняется в префаб; в мире рубятся как в лесу (лишай — шанс на пенициллин)"
		return
	if _tabs != null and _tabs.current_tab == 2:
		_mat_btn.disabled = true
		_mat_btn.icon = GroundTypes.icon(cur_ground)
		_mat_btn.text = "Покрытие: %s" % GroundTypes.TYPES[cur_ground]["name"]
		_tex_btn.disabled = true
		_tex_btn.text = "Кисть %d×%d" % [ground_brush, ground_brush]
		_pal_info.text = "Земля: ЛКМ — красить (можно вести), Ctrl+ЛКМ — стереть (вернуть как в мире)\n[ / ] — размер кисти: %d×%d\nПокрытие сохраняется в префаб и кладётся на землю под зданием" % [ground_brush, ground_brush]
		return
	if item.is_empty():
		_pal_info.text = ""
		return
	var id := int(item["id"])
	if _is_shape(id):
		var t := _tier_for(id)
		item["tier"] = maxi(t, 0)
		_mat_btn.disabled = false
		_mat_btn.text = "Материал: %s" % _mat_name(cur_mat)
		_mat_btn.icon = BlockRegistry.icon(BlockRegistry.id_by_key("wall"), maxi(0, _wall_tier(cur_mat)))
		if t < 0:
			_mat_btn.text += " (нет у формы)"
	else:
		_mat_btn.disabled = true
		_mat_btn.icon = null
		_mat_btn.text = "Материал: %s (свой)" % _mat_name(BlockRegistry.material_key(id, 0))
	var tier := int(item["tier"])
	var n := BlockRegistry.variant_count(id, tier)
	cur_variant = cur_variant % n
	_tex_btn.text = "Текстура %d/%d" % [cur_variant + 1, n]
	_tex_btn.disabled = n < 2
	var f := BlockRegistry.footprint(id, cur_rot)
	_pal_info.text = "%s\nhp %d · %s\nфутпринт %d×%d×%d ячеек%s%s" % [
		item["name"], int(BlockRegistry.hp(id, tier)), BlockRegistry.kind(id, tier), f.x, f.y, f.z,
		("\nкрепление: " + {"below": "снизу", "above": "сверху", "any": "к грани"}.get(BlockRegistry.support_mode(id), "")) if BlockRegistry.support_mode(id) != "" else "",
		"\nповорот по X/Z — только у блоков 1×1×1" if cur_up != 0 and BlockRegistry.footprint(id, 0) != Vector3i.ONE else ""]


func _wall_tier(mat_key: String) -> int:
	var tiers: Array = BlockRegistry.block(BlockRegistry.id_by_key("wall")).get("tiers", [])
	for t in tiers.size():
		if String(tiers[t]["key"]) == mat_key:
			return t
	return -1


## Поворот текущей ориентации на 90° вокруг оси (мировой); сохраняется для следующих блоков.
func _rotate_cur(axis: Vector3) -> void:
	var nm := BlockRegistry.rotate_meta(BlockRegistry.make_meta(cur_rot, 0, 0, 0, cur_up), Basis(axis, PI * 0.5))
	cur_rot = BlockRegistry.rot_of(nm)
	cur_up = BlockRegistry.up_of(nm)
	_update_pal_info()


# --- всплывающие окна: материал и текстура -------------------------------------------------

func _build_popups(layer: CanvasLayer) -> void:
	_mat_popup = PopupPanel.new()
	layer.add_child(_mat_popup)
	_tex_popup = PopupPanel.new()
	layer.add_child(_tex_popup)


func _popup_grid(popup: PopupPanel, title: String) -> GridContainer:
	for ch in popup.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	popup.add_child(vb)
	var l := Label.new()
	l.text = title
	vb.add_child(l)
	var g := GridContainer.new()
	g.columns = 3
	vb.add_child(g)
	return g


func _open_mat_popup() -> void:
	var g := _popup_grid(_mat_popup, "Материал формы")
	var wall := BlockRegistry.id_by_key("wall")
	var tiers: Array = BlockRegistry.block(wall).get("tiers", [])
	for t in tiers.size():
		var key := String(tiers[t]["key"])
		var b := Button.new()
		b.text = "%s\nhp %d" % [String(tiers[t]["name"]), int(BlockRegistry.hp(wall, t))]
		b.icon = BlockRegistry.icon(wall, t)
		b.custom_minimum_size = Vector2(170, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = key == cur_mat
		b.pressed.connect(func() -> void:
			cur_mat = key
			cur_variant = 0
			_mat_popup.hide()
			if not item.is_empty() and _is_shape(int(item["id"])) and _tier_for(int(item["id"])) < 0:
				_say("У формы «%s» нет материала «%s» (например, каркас — только у куба)" % [item["name"], _mat_name(key)])
			_refresh_palette(false))
		g.add_child(b)
	_mat_popup.popup(Rect2i(Vector2i(340, 200), Vector2i(560, 0)))


func _open_tex_popup() -> void:
	if item.is_empty():
		return
	var id := int(item["id"])
	var tier := int(item["tier"])
	var list: Array = BlockRegistry.material(id, tier).get("tex", [])
	var g := _popup_grid(_tex_popup, "Текстура: %s" % _mat_name(BlockRegistry.material_key(id, tier)))
	g.columns = 4
	for v in list.size():
		var img := BlockRegistry.texture_image(String(list[v]))
		img.resize(96, 96, Image.INTERPOLATE_BILINEAR)
		var b := Button.new()
		b.icon = ImageTexture.create_from_image(img)
		b.text = str(v + 1)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.toggle_mode = true
		b.button_pressed = v == cur_variant
		b.pressed.connect(func() -> void:
			cur_variant = v
			_tex_popup.hide()
			_update_pal_info())
		g.add_child(b)
	_tex_popup.popup(Rect2i(Vector2i(340, 260), Vector2i(0, 0)))


func _set_mode(m: int) -> void:
	mode = m as Mode
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == m
	_ghost.visible = false
	# инструмент «Земля» и вкладка «Земля» переключаются вместе
	if _tabs != null:
		if m == Mode.GROUND and _tabs.current_tab != 2:
			_tabs.current_tab = 2
		elif m == Mode.PLANT and _tabs.current_tab != 3:
			_tabs.current_tab = 3
		elif m != Mode.GROUND and m != Mode.PLANT and _tabs.current_tab >= 2:
			_tabs.current_tab = 0


func _say(t: String) -> void:
	_msg_t = 6.0
	_status.text = t


# --- ввод --------------------------------------------------------------------------------

func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is SpinBox or f is TextEdit


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and get_viewport().gui_get_hovered_control() == null:
			get_viewport().gui_release_focus()   # иначе после ввода в поиск горячие клавиши (E, R, T…) молчат
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_LEFT and not _looking:
			if mb.pressed:
				_on_lmb_down()
			else:
				_on_lmb_up()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var d := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if not item.is_empty():
				cur_variant = posmod(cur_variant + d, BlockRegistry.variant_count(int(item["id"]), int(item["tier"])))
				_update_pal_info()
	elif event is InputEventMouseMotion and _looking:
		_yaw -= (event as InputEventMouseMotion).relative.x * 0.003
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * 0.003, -1.5, 1.5)
		cam.rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventKey and event.pressed and not event.echo and not _text_focus():
		_on_key(event as InputEventKey)


func _on_key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.physical_keycode:
		KEY_1: _set_mode(Mode.PLACE)
		KEY_2: _set_mode(Mode.REMOVE)
		KEY_3: _set_mode(Mode.SELECT)
		KEY_4: _set_mode(Mode.BRUSH)
		KEY_5: _set_mode(Mode.INSPECT)
		KEY_6: _set_mode(Mode.GROUND)
		KEY_7: _set_mode(Mode.PLANT)
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if mode == Mode.GROUND:
				ground_brush = clampi(ground_brush + (2 if e.physical_keycode == KEY_BRACKETRIGHT else -2), 1, 9)
				_update_pal_info()
		KEY_R:
			if not ctrl:
				_rotate_cur(Vector3.RIGHT if e.shift_pressed else (Vector3.BACK if e.alt_pressed else Vector3.UP))
		KEY_F: _fill_selection()
		KEY_DELETE: _clear_selection()
		KEY_T: _rotate_selection()
		KEY_M: _mirror_selection(e.shift_pressed)
		KEY_G: _grid_plane.visible = not _grid_plane.visible
		KEY_ESCAPE:
			has_sel = false
			_selbox.visible = false
		KEY_E:
			if _hover.x >= 0 and bb.toggle_door(_hover):
				_say("Дверь переключена")
		KEY_C:
			if ctrl:
				_copy_selection()
		KEY_V:
			if ctrl:
				_paste()
		KEY_Z:
			if ctrl:
				_do_undo()
		KEY_Y:
			if ctrl:
				_do_redo()


func _process(delta: float) -> void:
	if _shot_path != "":
		_shot_frames += 1
		if _shot_frames == 40:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			print("editor shot saved ", _shot_path)
			get_tree().quit()
	if _msg_t > 0.0:
		_msg_t -= delta
	# полёт камеры
	if not _text_focus():
		var dir := Vector3.ZERO
		var b := cam.global_basis
		if Input.is_physical_key_pressed(KEY_W): dir -= b.z
		if Input.is_physical_key_pressed(KEY_S): dir += b.z
		if Input.is_physical_key_pressed(KEY_A): dir -= b.x
		if Input.is_physical_key_pressed(KEY_D): dir += b.x
		if Input.is_physical_key_pressed(KEY_SPACE): dir += Vector3.UP
		if Input.is_physical_key_pressed(KEY_Q): dir += Vector3.DOWN
		var spd := 14.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 5.0
		if not Input.is_physical_key_pressed(KEY_CTRL):
			cam.position += dir.normalized() * spd * delta
		cam.position.y = maxf(cam.position.y, 0.3)
	_pick()
	if mode == Mode.PLANT:
		_ground_cell = _pick_ground()
	if _plants_dirty:
		_rebuild_plants()
	# земля: ячейка под курсором, рисование с зажатой ЛКМ
	if mode == Mode.GROUND:
		var gc := _pick_ground()
		if gc != _ground_cell:
			_ground_cell = gc
			if gc.x >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _op.is_empty():
				_paint_ground(gc)
	if _ground_dirty:
		_rebuild_ground()
	# кисть: зажать ЛКМ и вести по блокам
	if mode == Mode.BRUSH and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _looking and _hover.x >= 0 \
			and grid.anchor_of(_hover) != grid.anchor_of(_brush_last if _brush_last.x >= 0 else _hover) and get_viewport().gui_get_hovered_control() == null:
		_brush_at(_hover)
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_brush_last = Vector3i(-1, -1, -1)
	_update_cursor()
	_update_status()


# --- выбор ячейки под прицелом -----------------------------------------------------------

func _to_grid(p: Vector3) -> Vector3:
	return p - bb.global_position - bb.origin


func _pick() -> void:
	_hit = {}
	_hover = Vector3i(-1, -1, -1)
	_target = Vector3i(-1, -1, -1)
	if _looking or get_viewport().gui_get_hovered_control() != null:
		return
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	_hit = grid.raycast(_to_grid(o), d, REACH)
	if _hit.is_empty():
		return
	var c: Vector3i = _hit["cell"]
	if _hit["ground"]:
		_target = c
	else:
		_hover = c
		_target = c + (_hit["normal"] as Vector3i)


func _cell_box(lo: Vector3i, size: Vector3i) -> Transform3D:
	var center := bb.global_position + bb.origin + (Vector3(lo) + Vector3(size) * 0.5) * B
	return Transform3D(Basis.from_scale(Vector3(size) * B * 1.002), center)


func _update_cursor() -> void:
	_hoverbox.visible = false
	_ghost.visible = false
	if mode == Mode.PLANT:
		if _ground_cell.x >= 0:
			var gp := bb.global_position + bb.origin + Vector3(snappedf(_ground_point.x, 0.25), -bb.origin.y + 0.05, snappedf(_ground_point.z, 0.25))
			_hoverbox.global_transform = Transform3D(Basis.from_scale(Vector3(0.5, 0.1, 0.5)), gp)
			_hoverbox.visible = true
	elif mode == Mode.GROUND:
		if _ground_cell.x >= 0:
			var r := ground_brush / 2
			var lo := Vector3i(_ground_cell.x - r, grid.ground_cells, _ground_cell.y - r)
			var tb := _cell_box(lo, Vector3i(ground_brush, 1, ground_brush))
			tb.basis = tb.basis.scaled(Vector3(1.0, 0.04, 1.0))
			tb.origin.y = bb.global_position.y + 0.02
			_hoverbox.global_transform = tb
			_hoverbox.visible = true
	elif _hover.x >= 0 and mode != Mode.PLACE:
		var a := grid.anchor_of(_hover)
		var id := grid.get_cell(a.x, a.y, a.z)
		var f := BlockRegistry.footprint(id, BlockRegistry.rot_of(grid.get_meta_at(a.x, a.y, a.z))) if BlockRegistry.is_new(id) else Vector3i.ONE
		_hoverbox.global_transform = _cell_box(a, f)
		_hoverbox.visible = true
	elif mode == Mode.PLACE and _target.x >= 0 and not item.is_empty():
		var id2 := int(item["id"])
		var m := _place_meta(id2, int(item["tier"]))
		var ok := grid.can_place(_target, id2, cur_rot) and (BlockRegistry.support_mode(id2) == "" or grid.is_supported(_target, id2, m))
		_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.3, 0.45)
		# призрак — сама форма блока в текущем повороте (видно, куда смотрит после поворота по X/Z)
		var gk := "%d:%d:%d" % [id2, BlockRegistry.rot_of(m), BlockRegistry.up_of(m)]
		if gk != _ghost_key:
			_ghost_key = gk
			_ghost.mesh = _shape_mesh(id2, m)
		_ghost.global_transform = Transform3D(Basis(), bb.global_position + bb.origin + Vector3(_target) * B)
		_ghost.visible = true
	# выделение
	if has_sel:
		_selbox.global_transform = _cell_box(sel_lo, sel_hi - sel_lo + Vector3i.ONE)
		_selbox.visible = true
	if _drag_a.x >= 0:
		var cc := _sel_cell()
		if cc.x >= 0:
			var lo := Vector3i(mini(_drag_a.x, cc.x), mini(_drag_a.y, cc.y), mini(_drag_a.z, cc.z))
			var hi := Vector3i(maxi(_drag_a.x, cc.x), maxi(_drag_a.y, cc.y), maxi(_drag_a.z, cc.z))
			_selbox.global_transform = _cell_box(lo, hi - lo + Vector3i.ONE)
			_selbox.visible = true


## Меш формы блока для призрака (треугольники граней; у моделей — коробки столкновений).
func _shape_mesh(id: int, m: int) -> Mesh:
	var parts := BlockShapes.build(id, m)
	var faces: Array = []
	var hidden: Array = []
	for b: Dictionary in parts["boxes"]:
		(hidden if b.get("hidden", false) else faces).append_array(ShapeIcons._box_faces(b["a"], b["b"]))
	for pl: Dictionary in parts.get("polys", []):
		faces.append(pl["p"])
	for q: Dictionary in parts.get("quads", []):
		faces.append(q["p"])
	if BlockRegistry.is_cube(id):
		faces = ShapeIcons._box_faces(Vector3.ZERO, Vector3(BlockRegistry.footprint(id, BlockRegistry.rot_of(m))) * B)
	if faces.is_empty():
		faces = hidden
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		for i in range(1, f.size() - 1):
			st.add_vertex(f[0])
			st.add_vertex(f[i])
			st.add_vertex(f[i + 1])
	return st.commit()


func _update_status() -> void:
	if _msg_t > 0.0:
		return
	var s := "Режим: %s" % MODE_NAMES[mode]
	if _hover.x >= 0:
		var a := grid.anchor_of(_hover)
		var ins := BlockOps.inspect(grid, a)
		s += "  ·  ячейка (%d,%d,%d)" % [_hover.x, _hover.y - grid.ground_cells, _hover.z]
		if not ins.is_empty():
			s += "  ·  %s  hp %d/%d  [%s]  tier %d  вариант %d" % [ins["name"], int(ins["hp"]), int(ins["hp_max"]), ins["kind"], ins["tier"], int(ins["variant"]) + 1]
	elif _target.x >= 0:
		s += "  ·  ячейка (%d,%d,%d)" % [_target.x, _target.y - grid.ground_cells, _target.z]
	if has_sel:
		s += "  ·  выделено %d×%d×%d" % [sel_hi.x - sel_lo.x + 1, sel_hi.y - sel_lo.y + 1, sel_hi.z - sel_lo.z + 1]
	_status.text = s


# --- действия мышью ---------------------------------------------------------------------

func _sel_cell() -> Vector3i:
	if _hover.x >= 0:
		return _hover
	return _target


func _on_lmb_down() -> void:
	if get_viewport().gui_get_hovered_control() != null:
		return
	match mode:
		Mode.PLACE:
			if Input.is_key_pressed(KEY_CTRL) and _hover.x >= 0:
				_remove_at(_hover)
			elif _target.x >= 0:
				_place_at(_target)
		Mode.REMOVE:
			if _hover.x >= 0:
				_remove_at(_hover)
		Mode.SELECT:
			var c := _sel_cell()
			if c.x >= 0:
				_drag_a = c
		Mode.BRUSH:
			if _hover.x >= 0:
				_brush_at(_hover)
		Mode.GROUND:
			if _ground_cell.x >= 0:
				_begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
				_paint_ground(_ground_cell)
		Mode.PLANT:
			if _ground_cell.x >= 0:
				_begin_op(Vector3i.ZERO, Vector3i.ZERO, 0)
				_plant_at(_ground_point, Input.is_key_pressed(KEY_CTRL))
				_end_op()
		Mode.INSPECT:
			if _hover.x >= 0:
				var ins := BlockOps.inspect(grid, _hover)
				if not ins.is_empty():
					_say("%s · материал %s · тип %s · hp %d из %d · tier %d" % [ins["name"], ins["material"], ins["kind"], int(ins["hp"]), int(ins["hp_max"]), ins["tier"]])


## Покрытие земли кистью ground_brush x ground_brush вокруг ячейки; Ctrl — стереть (как в мире).
func _paint_ground(c: Vector2i) -> void:
	var r := ground_brush / 2
	var erase := Input.is_key_pressed(KEY_CTRL)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dz)
			if q.x < 0 or q.y < 0 or q.x >= NX or q.y >= NZ:
				continue
			if erase:
				grid.ground.erase(q)
			else:
				grid.ground[q] = cur_ground
	_ground_dirty = true


## Ячейка земли под курсором (пересечение луча с плоскостью земли), или (-1, -1).
func _pick_ground() -> Vector2i:
	if _looking or get_viewport().gui_get_hovered_control() != null:
		return Vector2i(-1, -1)
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if d.y > -0.001:
		return Vector2i(-1, -1)
	var p := o + d * (-o.y / d.y)
	var lp := p - bb.global_position - bb.origin
	_ground_point = lp
	var c := Vector2i(floori(lp.x / B), floori(lp.z / B))
	if c.x < 0 or c.y < 0 or c.x >= NX or c.y >= NZ:
		return Vector2i(-1, -1)
	return c


## Посадить текущее растение/предмет в точке (м от угла сетки) или убрать ближайшее (remove).
func _plant_at(p: Vector3, remove: bool) -> void:
	if remove:
		var bi := -1
		var bd := 1.3
		for i in grid.plants.size():
			var q: Dictionary = grid.plants[i]
			var dd := Vector2(float(q["x"]) - p.x, float(q["z"]) - p.z).length()
			if dd < bd:
				bd = dd
				bi = i
		if bi >= 0:
			grid.plants.remove_at(bi)
			_plants_dirty = true
		return
	var t: Dictionary = PlantTypes.TYPES[cur_plant]
	var is_tree := not String(t["kind"]) in ["bench", "pebble", "grass_tuft"]
	var e := {"type": cur_plant, "x": snappedf(p.x, 0.25), "z": snappedf(p.z, 0.25),
		"rot": cur_rot * PI * 0.5 if t["kind"] == "bench" else randf() * TAU,
		"scale": randf_range(0.85, 1.15) if is_tree else 1.0, "hue": randf_range(0.33, 0.6)}
	grid.plants.append(e)
	_plants_dirty = true
	_say("%s: %d" % [t["name"], grid.plants.size()])


func _rebuild_plants() -> void:
	_plants_dirty = false
	if _plants_node != null:
		_plants_node.queue_free()
	_plants_node = Node3D.new()
	_plants_node.position = bb.global_position + Vector3(bb.origin.x, 0.0, bb.origin.z)
	add_child(_plants_node)
	for p: Dictionary in grid.plants:
		var lp := Vector3(float(p["x"]), 0.0, float(p["z"]))
		var n := PlantTypes.make(p, lp, _plants_node.position + lp)
		if n != null:
			_plants_node.add_child(n)


func _rebuild_ground() -> void:
	_ground_dirty = false
	if _ground_node != null:
		_ground_node.queue_free()
	_ground_node = GroundTypes.make_node(grid.ground, B)
	_ground_node.position = bb.global_position + Vector3(bb.origin.x, 0.002, bb.origin.z)
	add_child(_ground_node)


func _on_lmb_up() -> void:
	if mode == Mode.GROUND and not _op.is_empty():
		_end_op()
	if mode == Mode.SELECT and _drag_a.x >= 0:
		var c := _sel_cell()
		if c.x < 0:
			c = _drag_a
		sel_lo = Vector3i(mini(_drag_a.x, c.x), mini(_drag_a.y, c.y), mini(_drag_a.z, c.z))
		sel_hi = Vector3i(maxi(_drag_a.x, c.x), maxi(_drag_a.y, c.y), maxi(_drag_a.z, c.z))
		has_sel = true
		_drag_a = Vector3i(-1, -1, -1)


# --- undo / redo ------------------------------------------------------------------------

func _snapshot(lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ids := PackedByteArray()
	var metas := PackedInt32Array()
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := grid.idx(x, y, z)
				ids.append(grid.cells[i])
				metas.append(grid.meta[i])
	return {"lo": lo, "hi": hi, "ids": ids, "metas": metas, "ground": grid.ground.duplicate(), "plants": grid.plants.duplicate(true)}


func _restore(s: Dictionary) -> void:
	var lo: Vector3i = s["lo"]
	var hi: Vector3i = s["hi"]
	var k := 0
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := grid.idx(x, y, z)
				grid.cells[i] = (s["ids"] as PackedByteArray)[k]
				grid.meta[i] = (s["metas"] as PackedInt32Array)[k]
				k += 1
	grid.has_new = true
	bb.refresh_region(lo, hi)
	if s.has("ground") and s["ground"] != grid.ground:
		grid.ground = (s["ground"] as Dictionary).duplicate()
		_ground_dirty = true
	if s.has("plants") and s["plants"] != grid.plants:
		grid.plants = (s["plants"] as Array).duplicate(true)
		_plants_dirty = true


func _begin_op(lo: Vector3i, hi: Vector3i, pad: int = 5) -> void:
	lo = Vector3i(maxi(lo.x - pad, 0), maxi(lo.y - pad, 0), maxi(lo.z - pad, 0))
	hi = Vector3i(mini(hi.x + pad, NX - 1), mini(hi.y + pad, NY - 1), mini(hi.z + pad, NZ - 1))
	_op = {"before": _snapshot(lo, hi), "lo": lo, "hi": hi}


func _end_op() -> void:
	if _op.is_empty():
		return
	var after := _snapshot(_op["lo"], _op["hi"])
	if (after["ids"] as PackedByteArray) == ((_op["before"] as Dictionary)["ids"] as PackedByteArray) and (after["metas"] as PackedInt32Array) == ((_op["before"] as Dictionary)["metas"] as PackedInt32Array) \
			and after["ground"] == (_op["before"] as Dictionary)["ground"] and after["plants"] == (_op["before"] as Dictionary)["plants"]:
		_op = {}
		return
	_undo.append({"before": _op["before"], "after": after})
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()
	_op = {}


func _do_undo() -> void:
	if _undo.is_empty():
		_say("Нечего отменять")
		return
	var e: Dictionary = _undo.pop_back()
	_restore(e["before"])
	_redo.append(e)
	_say("Отмена (осталось %d)" % _undo.size())


func _do_redo() -> void:
	if _redo.is_empty():
		_say("Нечего повторять")
		return
	var e: Dictionary = _redo.pop_back()
	_restore(e["after"])
	_undo.append(e)
	_say("Повтор")


# --- операции ---------------------------------------------------------------------------

func _place_at(target: Vector3i) -> void:
	var id := int(item["id"])
	var tier := int(item["tier"])
	if _is_shape(id) and _tier_for(id) < 0:
		_say("У «%s» нет материала «%s» — выберите другой" % [item["name"], _mat_name(cur_mat)])
		return
	var m := _place_meta(id, tier)
	if not grid.can_place(target, id, cur_rot):
		_say("Занято или за пределами рамки")
		return
	if BlockRegistry.support_mode(id) != "" and not grid.is_supported(target, id, m):
		_say("Нет опоры: этот блок крепится %s" % {"below": "на твёрдый блок снизу", "above": "к блоку сверху", "any": "к грани соседнего блока"}[BlockRegistry.support_mode(id)])
		return
	var f := BlockRegistry.footprint(id, cur_rot)
	_begin_op(target, target + f - Vector3i.ONE, 1)
	var cells := grid.place_block(target, id, m)
	bb.refresh_cells(cells)
	_end_op()


func _remove_at(c: Vector3i) -> void:
	_begin_op(c, c)
	var rec := grid.remove_block(c)
	if not rec.is_empty():
		bb.refresh_cells(rec["cells"])
		bb._check_attachments(rec["cells"])
	_end_op()


## Метаданные нового блока: текущий поворот (по всем осям — только у блоков 1x1x1), материал, текстура.
func _place_meta(id: int, tier: int) -> int:
	var up := cur_up if BlockRegistry.footprint(id, 0) == Vector3i.ONE else 0
	return BlockRegistry.make_meta(cur_rot, tier, cur_variant % BlockRegistry.variant_count(id, tier), 0, up)


## Кисть: перекрасить блок текущим материалом (у форм) и вариантом текстуры. Объектам — только текстура.
func _brush_at(c: Vector3i) -> void:
	_brush_last = c
	var a := grid.anchor_of(c)
	var id := grid.get_cell(a.x, a.y, a.z)
	if not BlockRegistry.is_new(id):
		return
	var m := grid.get_meta_at(a.x, a.y, a.z)
	var tier := BlockRegistry.tier_of(m)
	if _is_shape(id):
		var t := _tier_for(id)
		if t < 0:
			_say("У «%s» нет материала «%s»" % [BlockRegistry.block(id)["name"], _mat_name(cur_mat)])
			return
		tier = t
	var nm := BlockRegistry.with_tier_variant(m, tier, cur_variant % BlockRegistry.variant_count(id, tier))
	if nm == m:
		return
	_begin_op(a, a, 0)
	grid.set_cell(a.x, a.y, a.z, id, nm)
	grid.hp.erase(grid.idx(a.x, a.y, a.z))
	bb.refresh_cells(grid.footprint_cells(a, id, BlockRegistry.rot_of(m)))
	_end_op()


func _require_sel() -> bool:
	if not has_sel:
		_say("Сначала выделите область (режим 3, потянуть мышью)")
	return has_sel


func _fill_selection() -> void:
	if not _require_sel() or item.is_empty():
		return
	var id := int(item["id"])
	if not BlockRegistry.is_cube(id):
		_say("Заливка работает с блоками-кубами")
		return
	var tier := int(item["tier"])
	_begin_op(sel_lo, sel_hi)
	var all: Array[Vector3i] = []
	for z in range(sel_lo.z, sel_hi.z + 1):
		for y in range(sel_lo.y, sel_hi.y + 1):
			for x in range(sel_lo.x, sel_hi.x + 1):
				var c := Vector3i(x, y, z)
				if grid.get_cell(x, y, z) != 0:
					var rec := grid.remove_block(c)
					if not rec.is_empty():
						all.append_array(rec["cells"])
				grid.place_block(c, id, BlockRegistry.make_meta(0, tier, cur_variant % BlockRegistry.variant_count(id, tier)))
				all.append(c)
	bb.refresh_cells(all)
	bb._check_attachments(all)
	_end_op()
	_say("Залито %d ячеек" % all.size())


func _clear_selection() -> void:
	if not _require_sel():
		return
	_begin_op(sel_lo, sel_hi)
	var all: Array[Vector3i] = []
	for z in range(sel_lo.z, sel_hi.z + 1):
		for y in range(sel_lo.y, sel_hi.y + 1):
			for x in range(sel_lo.x, sel_hi.x + 1):
				if grid.get_cell(x, y, z) != 0:
					var rec := grid.remove_block(Vector3i(x, y, z))
					if not rec.is_empty():
						all.append_array(rec["cells"])
	bb.refresh_cells(all)
	bb._check_attachments(all)
	_end_op()
	_say("Очищено")


func _copy_selection() -> void:
	if not _require_sel():
		return
	clipboard = StructClip.capture(grid, sel_lo, sel_hi)
	_say("Скопировано блоков: %d (вставка — Ctrl+V в ячейку под прицелом)" % clipboard.inst.size())


func _paste() -> void:
	if clipboard == null or clipboard.inst.is_empty():
		_say("Буфер пуст")
		return
	var at := _target
	if at.x < 0:
		_say("Наведите на место вставки")
		return
	at = Vector3i(clampi(at.x, 0, NX - clipboard.dims.x), maxi(at.y, 0), clampi(at.z, 0, NZ - clipboard.dims.z))
	_begin_op(at, at + clipboard.dims - Vector3i.ONE, 1)
	var cells := clipboard.place(grid, at)
	bb.refresh_cells(cells)
	_end_op()
	_say("Вставлено блоков: %d" % clipboard.inst.size())


func _rotate_selection() -> void:
	_transform_selection(func(c: StructClip) -> StructClip: return c.rotated(), "Повёрнуто на 90°")


func _mirror_selection(z_axis: bool) -> void:
	_transform_selection(func(c: StructClip) -> StructClip: return c.mirrored_z() if z_axis else c.mirrored_x(), "Отражено по %s" % ("Z" if z_axis else "X"))


func _transform_selection(fn: Callable, msg: String) -> void:
	if not has_sel:
		if clipboard != null:
			clipboard = fn.call(clipboard)
			_say(msg + " (буфер обмена)")
		else:
			_say("Нет выделения")
		return
	var clip := StructClip.capture(grid, sel_lo, sel_hi)
	var res: StructClip = fn.call(clip)
	var new_hi := sel_lo + res.dims - Vector3i.ONE
	if new_hi.x >= NX or new_hi.z >= NZ or new_hi.y >= NY:
		_say("Не помещается в рамку")
		return
	var lo2 := Vector3i(sel_lo.x, sel_lo.y, sel_lo.z)
	var hi2 := Vector3i(maxi(sel_hi.x, new_hi.x), maxi(sel_hi.y, new_hi.y), maxi(sel_hi.z, new_hi.z))
	_begin_op(lo2, hi2)
	var all: Array[Vector3i] = []
	for z in range(sel_lo.z, sel_hi.z + 1):
		for y in range(sel_lo.y, sel_hi.y + 1):
			for x in range(sel_lo.x, sel_hi.x + 1):
				if grid.get_cell(x, y, z) != 0:
					var rec := grid.remove_block(Vector3i(x, y, z))
					if not rec.is_empty():
						all.append_array(rec["cells"])
	all.append_array(res.place(grid, sel_lo, false))
	bb.refresh_cells(all)
	bb._check_attachments(all)
	_end_op()
	sel_hi = new_hi
	_say(msg)


# --- сохранение / загрузка ------------------------------------------------------------------

func _on_new() -> void:
	_begin_op(Vector3i.ZERO, Vector3i(NX - 1, NY - 1, NZ - 1), 0)
	for i in grid.cells.size():
		grid.cells[i] = 0
		grid.meta[i] = 0
	grid.hp.clear()
	grid.ground.clear()
	grid.plants.clear()
	_ground_dirty = true
	_plants_dirty = true
	bb.refresh_region(Vector3i.ZERO, Vector3i(NX - 1, NY - 1, NZ - 1))
	_end_op()
	has_sel = false
	_selbox.visible = false
	_say("Холст очищен (Ctrl+Z вернёт)")


func _on_save_pressed() -> void:
	(_save_fields["name"] as LineEdit).text = String(info["name"])
	(_save_fields["tags"] as LineEdit).text = String(info["tags"])
	(_save_fields["biomes"] as LineEdit).text = String(info["biomes"])
	(_save_fields["weight"] as SpinBox).value = float(info["weight"])
	(_save_fields["margin"] as SpinBox).value = int(info["margin"])
	(_save_fields["fx"] as SpinBox).value = int(info["fx"])
	(_save_fields["fz"] as SpinBox).value = int(info["fz"])
	(_save_fields["sink"] as SpinBox).value = int(info.get("sink", 0))
	var ci := CATEGORY_CHOICES.find(String(info["category"]))
	(_save_fields["category"] as OptionButton).select(maxi(ci, 0))
	(_save_fields["custom_cat"] as LineEdit).text = "" if ci >= 0 else String(info["category"])
	_save_dlg.popup_centered()


func _collect_info() -> Dictionary:
	var cat := String(CATEGORY_CHOICES[(_save_fields["category"] as OptionButton).selected])
	var custom := (_save_fields["custom_cat"] as LineEdit).text.strip_edges()
	if custom != "":
		cat = custom
	var tags: Array = []
	for t in (_save_fields["tags"] as LineEdit).text.split(","):
		if t.strip_edges() != "":
			tags.append(t.strip_edges())
	var biomes: Array = []
	for b in (_save_fields["biomes"] as LineEdit).text.split(","):
		if b.strip_edges() != "":
			biomes.append(b.strip_edges())
	if biomes.is_empty():
		biomes = ["any"]
	var d := {
		"name": (_save_fields["name"] as LineEdit).text.strip_edges().replace(" ", "_"),
		"category": cat, "tags": tags, "weight": (_save_fields["weight"] as SpinBox).value, "biomes": biomes,
		"margin": int((_save_fields["margin"] as SpinBox).value),
	}
	var fx := int((_save_fields["fx"] as SpinBox).value)
	var fz := int((_save_fields["fz"] as SpinBox).value)
	if fx > 0 and fz > 0:
		d["footprint"] = [fx, fz]
	d["sink"] = int((_save_fields["sink"] as SpinBox).value)
	return d


func _on_save_confirmed() -> void:
	var d := _collect_info()
	if String(d["name"]) == "":
		_say("Введите имя структуры")
		return
	info["name"] = d["name"]
	info["category"] = d["category"]
	info["tags"] = ", ".join(d["tags"])
	info["weight"] = d["weight"]
	info["biomes"] = ", ".join(d["biomes"])
	info["margin"] = d["margin"]
	info["fx"] = (d["footprint"][0] if d.has("footprint") else 0)
	info["fz"] = (d["footprint"][1] if d.has("footprint") else 0)
	info["sink"] = int(d.get("sink", 0))
	var data := PrefabIO.to_dict(grid, d)
	if data.is_empty():
		_say("Нечего сохранять: на холсте нет блоков")
		return
	var path := PrefabIO.DIR_RES + String(d["name"]) + ".json"
	if not PrefabIO.save_dict(data, path):
		path = PrefabIO.DIR_USER + String(d["name"]) + ".json"
		PrefabIO.save_dict(data, path)
	PrefabRegistry.reload()
	# влезет ли в участки мира: обычные — до 17x13 и 15x15 м, крупные кварталы городов-сеток — 27x27 и 33x33
	var fw := float(data["footprint"][0])
	var fd := float(data["footprint"][1])
	var fits := func(w: float, d: float) -> bool: return (fw <= w and fd <= d) or (fd <= w and fw <= d)
	var warn := ""
	if not (fits.call(17.0, 13.0) or fits.call(15.0, 15.0) or fits.call(12.0, 12.0)):
		warn = "  ⚠ больше обычных участков: появится только на крупных участках (кварталы городов 27×27 / 33×33)" if fits.call(33.0, 33.0) \
			else "  ⚠ НЕ ПОМЕСТИТСЯ ни в один участок мира (максимум 33×33 с отступом) — уменьшите постройку или отступ"
	_say("Сохранено: %s (блоков %d, футпринт %s, категория %s, вес %.1f)%s" % [path, data["blocks"].size(), str(data["footprint"]), data["category"], data["weight"], warn])


func _on_load_pressed() -> void:
	PrefabRegistry.reload()
	_load_list.clear()
	for it: Dictionary in PrefabRegistry.all():
		var dd: Dictionary = it["data"]
		_load_list.add_item("%s  [%s, вес %.1f, %d блоков]" % [dd.get("name", "?"), dd.get("category", "?"), float(dd.get("weight", 1)), (dd["blocks"] as Array).size()])
	_load_dlg.popup_centered()


func _load_prefab(prefab_name: String) -> void:
	PrefabRegistry.reload()
	var it := PrefabRegistry.find(prefab_name)
	if it.is_empty():
		_say("Структура не найдена: " + prefab_name)
		return
	var d: Dictionary = it["data"]
	var src := PrefabIO.from_dict(d)
	_begin_op(Vector3i.ZERO, Vector3i(NX - 1, NY - 1, NZ - 1), 0)
	for i in grid.cells.size():
		grid.cells[i] = 0
		grid.meta[i] = 0
	grid.hp.clear()
	var off := Vector3i((NX - src.nx) / 2, 0, (NZ - src.nz) / 2)
	for i in src.cells.size():
		var id := src.cells[i]
		if id == 0:
			continue
		var c := src.cell_of(i) + off
		grid.set_cell(c.x, c.y, c.z, id, src.meta[i])
	grid.ground.clear()
	for gc: Vector2i in src.ground:
		grid.ground[gc + Vector2i(off.x, off.z)] = src.ground[gc]
	_ground_dirty = true
	grid.plants.clear()
	for pl: Dictionary in src.plants:
		var np := pl.duplicate()
		np["x"] = float(pl["x"]) + off.x
		np["z"] = float(pl["z"]) + off.z
		grid.plants.append(np)
	_plants_dirty = true
	grid.has_new = true
	bb.refresh_region(Vector3i.ZERO, Vector3i(NX - 1, NY - 1, NZ - 1))
	_end_op()
	info["name"] = d.get("name", "")
	info["category"] = d.get("category", "house")
	info["tags"] = ", ".join(d.get("tags", []))
	info["weight"] = float(d.get("weight", 1.0))
	info["biomes"] = ", ".join(d.get("biomes", ["any"]))
	var fp: Array = d.get("footprint", [0, 0])
	info["fx"] = int(fp[0])
	info["fz"] = int(fp[1])
	info["sink"] = int(d.get("sink", 0))
	has_sel = false
	_selbox.visible = false
	_say("Загружено: %s (%d блоков)" % [info["name"], (d["blocks"] as Array).size()])


## «Проверить в мире»: сохраняем временный префаб (категория _test — в генерацию не попадает) и открываем игру.
func _on_test_world() -> void:
	var d := PrefabIO.to_dict(grid, {"name": "_preview", "category": "_test", "weight": 1.0, "margin": int(info["margin"])})
	if d.is_empty():
		_say("На холсте нет блоков")
		return
	PrefabIO.save_dict(d, PrefabIO.DIR_USER + "_preview.json")
	PrefabRegistry.reload()
	Game.test_prefab = "_preview"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main.tscn")
