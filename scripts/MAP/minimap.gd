extends Control
class_name Minimap
## Миникарта. Маленькая — в углу, следует за игроком. M — большая карта: ЛКМ-перетаскивание двигает, колесо — масштаб
## (вокруг курсора), ПКМ — поставить метку (на существующей — убрать), 1–6 — цвет метки, Пробел — к игроку,
## Del — убрать все метки, M — закрыть. Метки видны на обеих картах; вне экрана — стрелка по краю с расстоянием.

@export var map_size := Vector2(220, 220)
@export var preview_px := 1024        # быстрое превью (строится при старте)
@export var hi_preview_px := 2048     # чёткое превью (строится в фоне при первом открытии большой карты)
@export var small_view_m := 420.0     # сколько метров видно на маленькой карте
@export var min_view_m := 60.0        # максимальное приближение большой карты
@export var big_margin := 40.0

const PALETTE: Array[Color] = [
	Color(1.0, 0.25, 0.2), Color(1.0, 0.8, 0.1), Color(0.3, 0.85, 0.3),
	Color(0.2, 0.7, 1.0), Color(0.85, 0.35, 1.0), Color(1.0, 1.0, 1.0),
]
const MARK_HIT_PX := 20.0

## Метки игрока: [{pos: Vector2 (м, x/z), color: Color, n: int}] — общие для карт, сохраняются в сохранении.
static var marks: Array = []
## Большая карта открыта (игрок не должен стрелять/бить, мышь видна).
static var is_open := false

var world: WorldMap
var markers: Dictionary = {}
var map_texture: ImageTexture
var world_size := 2048.0
var expanded := false

var _center_m := Vector2.ZERO
var _view_m := 700.0
var _follow := true
var _drag := false
var _color_i := 0
var _next_n := 1
var _hover_m := Vector2.ZERO
var _prev_mouse := Input.MOUSE_MODE_CAPTURED   # режим мыши до открытия большой карты
var _hi_state := 0                              # чёткое превью: 0 не строилось, 1 строится, 2 готово
var _road_cols := {}
var _road_w := {}
var _river_boxes: Array[Rect2] = []             # габариты рек/дорог: быстро отсекать невидимые
var _road_boxes: Array[Rect2] = []
var _river_w := PackedFloat32Array()

const RIVER_COL := Color(0.2, 0.45, 0.85)
const TOWN_COLS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.55, 0.1), Color(1.0, 0.25, 0.2)]
const TOWN_NAMES: Array[String] = ["Деревня", "Посёлок", "Город"]
const POI_NAMES := {"farm": "Ферма", "cabin": "Хижина", "gas": "Заправка"}
const POI_COL := Color(0.75, 0.2, 0.9)


func _ready() -> void:
	add_to_group("minimap")
	custom_minimum_size = map_size
	size = map_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	get_viewport().size_changed.connect(_apply_layout)
	_road_cols = {RoadNet.ASPHALT: Color(0.1, 0.1, 0.11), RoadNet.CONCRETE: Color(0.85, 0.85, 0.85),
		RoadNet.GRAVEL: Color(0.66, 0.55, 0.38), RoadNet.ROADSAND: Color(0.93, 0.83, 0.5)}
	_road_w = {RoadNet.ASPHALT: 8.0, RoadNet.CONCRETE: 7.0, RoadNet.GRAVEL: 5.0, RoadNet.ROADSAND: 4.0}
	_apply_layout()
	for m: Dictionary in marks:
		_next_n = maxi(_next_n, int(m["n"]) + 1)
	_lift_to_layer.call_deferred()


## Карта — в своём слое выше HUD (здоровье, хотбар, компас не рисуются поверх неё).
func _lift_to_layer() -> void:
	var par := get_parent()
	if par == null or par is CanvasLayer:
		return
	var cl := CanvasLayer.new()
	cl.name = "MapLayer"
	cl.layer = 30
	par.add_child(cl)
	reparent(cl, false)
	_apply_layout()


func setup(w: WorldMap) -> void:
	world = w
	world_size = float(w.size)
	_river_boxes.clear()
	_road_boxes.clear()
	_build()


func _build() -> void:
	if world == null:
		return
	var img: Image = await world.render_preview(preview_px, get_tree(), false)
	if _hi_state != 2:
		map_texture = ImageTexture.create_from_image(img)
	queue_redraw()


## Чёткое превью в фоне (без зависания кадров): подменяет быстрое, когда готово.
func _build_hi() -> void:
	_hi_state = 1
	var img: Image = await world.render_preview(hi_preview_px, get_tree(), false)
	map_texture = ImageTexture.create_from_image(img)
	_hi_state = 2
	queue_redraw()


func _exit_tree() -> void:
	is_open = false


# --- ввод --------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_M:
		_set_expanded(not expanded)
	elif expanded:
		if k == KEY_SPACE:
			_follow = true
		elif k == KEY_DELETE:
			marks.clear()
			_next_n = 1
		elif k >= KEY_1 and k <= KEY_6:
			_color_i = k - KEY_1
		else:
			return
		get_viewport().set_input_as_handled()


func _set_expanded(on: bool) -> void:
	if on == expanded:
		return
	var pl := _get_player()
	if on and pl is Player and (pl as Player).UI != null and (pl as Player).UI.is_open():
		return   # открыто окно инвентаря — карту поверх него не открываем
	expanded = on
	is_open = on
	_drag = false
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		_center_m = Vector2(pl.global_position.x, pl.global_position.z) if pl != null else Vector2.ONE * world_size * 0.5
		_follow = true
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _hi_state == 0 and map_texture != null and world != null:
			_build_hi()
	elif not TouchControls.active():
		Input.mouse_mode = _prev_mouse   # как было до открытия (захвачена или освобождена по Esc)
	_apply_layout()


## Мышь большой карты ловим в _input (до интерфейса): другие Control поверх экрана не перехватывают перетаскивание.
func _input(event: InputEvent) -> void:
	if not expanded:
		return
	var inv_xf := get_global_transform().affine_inverse()
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var lp := inv_xf * mm.position
		if Rect2(Vector2.ZERO, size).has_point(lp):
			_hover_m = _local_to_world(lp)
		if _drag:
			_center_m -= mm.relative / _scale()
			_follow = false
			_clamp_center()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var lp := inv_xf * mb.position
		var inside := Rect2(Vector2.ZERO, size).has_point(lp)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and inside:
				_drag = true
				_center_m = _view_center()
			elif not mb.pressed:
				_drag = false
		elif inside and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_toggle_mark(lp)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(0.8 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25, lp)
		if inside:
			get_viewport().set_input_as_handled()


## Отладка (снимки): открыть большую карту без проверки мыши.
func debug_open(center: Vector2 = Vector2.ZERO, view: float = 700.0) -> void:
	expanded = true
	is_open = true
	_view_m = view
	_follow = center == Vector2.ZERO
	_center_m = center
	_apply_layout()


func _zoom(factor: float, at: Vector2) -> void:
	var before := _local_to_world(at)
	_view_m = clampf(_view_m * factor, min_view_m, world_size)
	# точка под курсором остаётся на месте
	_center_m = before - (at - size * 0.5) / _scale()
	_follow = false
	_clamp_center()


func _toggle_mark(at: Vector2) -> void:
	for i in range(marks.size() - 1, -1, -1):
		var sp := _world_to_local(marks[i]["pos"])
		if sp.distance_to(at) <= MARK_HIT_PX:
			marks.remove_at(i)
			return
	marks.append({"pos": _local_to_world(at), "color": PALETTE[_color_i], "n": _next_n})
	_next_n += 1


# --- геометрия ---------------------------------------------------------------------------------------------------

func _apply_layout() -> void:
	var vp := get_viewport_rect().size
	if expanded:
		position = Vector2.ONE * big_margin
		size = vp - Vector2.ONE * big_margin * 2.0
		_clamp_center()
	else:
		size = map_size
		position = Vector2(15, 15)
	queue_redraw()


## Метров на экране для текущего режима по ширине карты (для большой — по меньшей стороне, чтобы вид был квадратным).
func _cur_view() -> float:
	return _view_m if expanded else small_view_m


## Пикселей на метр.
func _scale() -> float:
	return minf(size.x, size.y) / _cur_view()


func _clamp_center() -> void:
	var half := size * 0.5 / _scale()
	for a in 2:
		var lo := half[a]
		var hi := world_size - half[a]
		_center_m[a] = clampf(_center_m[a], lo, hi) if lo < hi else world_size * 0.5


func _view_center() -> Vector2:
	if expanded and not _follow:
		return _center_m
	var p := _get_player()
	var c := Vector2(p.global_position.x, p.global_position.z) if p != null else _center_m
	var half := size * 0.5 / _scale()
	for a in 2:
		var lo := half[a]
		var hi := world_size - half[a]
		c[a] = clampf(c[a], lo, hi) if lo < hi else world_size * 0.5
	return c


func _origin() -> Vector2:
	return _view_center() - size * 0.5 / _scale()


func _world_to_local(m: Vector2) -> Vector2:
	return (m - _origin()) * _scale()


func _local_to_world(p: Vector2) -> Vector2:
	return _origin() + p / _scale()


func add_marker(node: Node3D, color: Color) -> void:
	markers[node] = color


func remove_marker(node: Node3D) -> void:
	markers.erase(node)


func _get_player() -> Node3D:
	for n in get_tree().get_nodes_in_group("survivors"):
		if n is Player:
			return n as Player
	return get_tree().get_first_node_in_group("player") as Node3D


func _process(_delta: float) -> void:
	for node in markers.keys():
		if not is_instance_valid(node):
			markers.erase(node)
	if expanded and _follow:
		var p := _get_player()
		if p != null:
			_center_m = Vector2(p.global_position.x, p.global_position.z)
	queue_redraw()


# --- рисование ---------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.15, 0.92 if expanded else 0.75))
	if map_texture != null:
		var tpm := map_texture.get_width() / world_size
		var o := _origin()
		var vis := size / _scale()
		var src := Rect2(o * tpm, vis * tpm)
		draw_texture_rect_region(map_texture, Rect2(Vector2.ZERO, size), src)
	else:
		draw_string(get_theme_default_font(), Vector2(10, 24), "Карта строится…", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var player := _get_player()
	var ppos := Vector2(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO
	var rect := Rect2(Vector2.ZERO, size)
	if world != null and world.roads != null:
		_draw_world_overlays()

	for node in markers:
		if is_instance_valid(node):
			var sp := _world_to_local(Vector2(node.global_position.x, node.global_position.z))
			if rect.has_point(sp):
				draw_circle(sp, 6.0 if expanded else 4.5, Color.BLACK)
				draw_circle(sp, 4.5 if expanded else 3.0, markers[node])

	for m: Dictionary in marks:
		_draw_mark(m, rect, ppos, player != null)

	if player != null:
		_draw_player(player, rect)

	_draw_frame()


## Реки, дороги, города и точки интереса — векторно поверх рельефа (чёткие при любом приближении).
func _draw_world_overlays() -> void:
	var s := _scale()
	var o := _origin()
	var vis := Rect2(o, size / s).grow(30.0)
	if _river_boxes.is_empty():
		_build_boxes()
	var rivers: Array = world.hydro.rivers
	for i in rivers.size():
		var pts: PackedVector2Array = rivers[i]["pts"]
		if pts.size() < 2 or not vis.intersects(_river_boxes[i]):
			continue
		var w := clampf(_river_w[i] * 2.0 * s, 1.5, 16.0)
		draw_polyline(_to_screen(pts, o, s), RIVER_COL, w, true)
	var paths: Array = world.roads.link_paths
	for pass_i in 2:   # сначала тёмный контур всех дорог, потом заливка — перекрёстки читаются чище
		for i in paths.size():
			var lp: Dictionary = paths[i]
			var pts: PackedVector2Array = lp["pts"]
			if pts.size() < 2 or not vis.intersects(_road_boxes[i]):
				continue
			var mat: Variant = lp["mat"]
			var w := clampf(float(_road_w.get(mat, 5.0)) * s, 1.8, 11.0)
			var sp := _to_screen(pts, o, s)
			if pass_i == 0:
				draw_polyline(sp, Color(0, 0, 0, 0.75), w + 2.5, true)
			else:
				draw_polyline(sp, _road_cols.get(mat, Color.GRAY), w, true)
	var expanded_close := expanded and _view_m <= 1800.0
	for t: Dictionary in world.roads.towns:
		var tier := clampi(int(t["tier"]), 0, 2)
		var c := _world_to_local(t["center"])
		var rr := float(t["radius"]) * s
		if not Rect2(Vector2.ZERO, size).grow(rr + 30.0).has_point(c):
			continue
		var col := TOWN_COLS[tier]
		draw_circle(c, rr, Color(col.r, col.g, col.b, 0.16))
		draw_arc(c, rr, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.7), 1.5, true)
		var half := (5.0 + tier * 2.0) * (1.4 if expanded else 1.0)
		draw_rect(Rect2(c - Vector2.ONE * (half + 2.0), Vector2.ONE * (half + 2.0) * 2.0), Color.BLACK)
		draw_rect(Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0), col)
		if expanded_close:
			_label(c + Vector2(0, half + 18.0), TOWN_NAMES[tier], 16, true)
	for t: Dictionary in world.roads.pois:
		var c := _world_to_local(t["center"])
		if not Rect2(Vector2.ZERO, size).grow(20.0).has_point(c):
			continue
		var half := 5.0 if expanded else 3.5
		draw_rect(Rect2(c - Vector2.ONE * (half + 1.5), Vector2.ONE * (half + 1.5) * 2.0), Color.BLACK)
		draw_rect(Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0), POI_COL)
		if expanded and _view_m <= 900.0:
			_label(c + Vector2(0, half + 15.0), POI_NAMES.get(String(t["poi_type"]), "Склад"), 13, true)


## Габариты каждой реки и дороги (один раз): невидимые в текущем окне пропускаются без обхода точек.
func _build_boxes() -> void:
	_river_boxes.clear()
	_road_boxes.clear()
	_river_w.clear()
	for rv: Dictionary in world.hydro.rivers:
		_river_boxes.append(_box_of(rv["pts"]))
		var hw: PackedFloat32Array = rv["hw"]
		var sum := 0.0
		for v in hw:
			sum += v
		_river_w.append(sum / maxf(hw.size(), 1.0))   # средняя полуширина русла, м
	for lp: Dictionary in world.roads.link_paths:
		_road_boxes.append(_box_of(lp["pts"]))


func _box_of(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO) if pts.size() > 0 else Rect2()
	for p in pts:
		r = r.expand(p)
	return r


func _to_screen(pts: PackedVector2Array, o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = (pts[i] - o) * s
	return out


func _draw_mark(m: Dictionary, rect: Rect2, ppos: Vector2, has_player: bool) -> void:
	var f := get_theme_default_font()
	var col: Color = m["color"]
	var sp := _world_to_local(m["pos"])
	var dist := int(ppos.distance_to(m["pos"])) if has_player else -1
	var r := 16.0 if expanded else 9.0
	if rect.grow(-r - 2.0).has_point(sp):
		# столбик + крупный круг с обводкой и номером — виден на любом фоне
		draw_line(sp, sp + Vector2(0, r + 6.0), Color.BLACK, 4.0)
		draw_line(sp, sp + Vector2(0, r + 6.0), col, 2.0)
		draw_circle(sp, r + 3.0, Color.BLACK)
		draw_circle(sp, r + 1.0, Color.WHITE)
		draw_circle(sp, r - 1.5, col)
		var txt := str(int(m["n"]))
		var fs := 20 if expanded else 12
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tcol := Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE
		draw_string(f, sp + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)
		if dist >= 0:
			_label(sp + Vector2(0, -r - 8.0), _fmt_dist(dist), 15 if expanded else 10, true)
	else:
		# вне карты: стрелка на краю в сторону метки + расстояние
		var c := size * 0.5
		var dir := (sp - c).normalized()
		var edge := _edge_point(c, dir, rect.grow(-16.0))
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([edge + dir * 11.0, edge - dir * 7.0 + perp * 9.0, edge - dir * 7.0 - perp * 9.0])
		draw_colored_polygon(tri, col)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 2.0)
		if dist >= 0:
			var pos := edge - dir * 22.0
			pos = pos.clamp(Vector2(24, 18), size - Vector2(24, 12))
			_label(pos, _fmt_dist(dist), 12 if expanded else 10, true)


func _edge_point(c: Vector2, dir: Vector2, r: Rect2) -> Vector2:
	var t := INF
	if dir.x > 0.0001:
		t = minf(t, (r.end.x - c.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (r.position.x - c.x) / dir.x)
	if dir.y > 0.0001:
		t = minf(t, (r.end.y - c.y) / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, (r.position.y - c.y) / dir.y)
	return c + dir * (t if t != INF else 0.0)


func _fmt_dist(d: int) -> String:
	return "%d м" % d if d < 1000 else "%.1f км" % (d / 1000.0)


## Подпись с тёмной обводкой, по центру точки.
func _label(at: Vector2, txt: String, fs: int, center: bool) -> void:
	var f := get_theme_default_font()
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(tw * 0.5 if center else 0.0, 0.0)
	draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
	draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_player(player: Node3D, rect: Rect2) -> void:
	var p := _world_to_local(Vector2(player.global_position.x, player.global_position.z))
	if not rect.has_point(p):
		return
	var fwd := -player.global_transform.basis.z
	var dir := Vector2(fwd.x, fwd.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var perp := Vector2(-dir.y, dir.x)
	var k := 1.0 if expanded else 0.75
	var tri := PackedVector2Array([p + dir * 13.0 * k, p - dir * 8.0 * k + perp * 8.0 * k, p - dir * 4.0 * k, p - dir * 8.0 * k - perp * 8.0 * k])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color.BLACK, 2.0)


func _draw_frame() -> void:
	var f := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.85, 0.85, 0.6), false, 2.0)
	_label(Vector2(size.x - 14.0, 16.0), "С", 13 if expanded else 11, true)
	if not expanded:
		return
	# линейка масштаба
	var nice := 10.0
	for v: float in [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]:
		if v * _scale() <= 160.0:
			nice = v
	var bar := nice * _scale()
	var bp := Vector2(18.0, size.y - 52.0)
	draw_line(bp, bp + Vector2(bar, 0), Color.BLACK, 5.0)
	draw_line(bp, bp + Vector2(bar, 0), Color.WHITE, 2.0)
	_label(bp + Vector2(bar + 8.0, 5.0), _fmt_dist(int(nice)), 12, false)
	# выбранный цвет метки и координаты под курсором
	for i in PALETTE.size():
		var c := Vector2(size.x - 24.0 - (PALETTE.size() - 1 - i) * 26.0, size.y - 60.0)
		draw_circle(c, 11.0 if i == _color_i else 8.0, Color.WHITE if i == _color_i else Color.BLACK)
		draw_circle(c, 9.0 if i == _color_i else 6.5, PALETTE[i])
		_label(c + Vector2(0, 22.0), str(i + 1), 11, true)
	_label(Vector2(18.0, 24.0), "Карта   (%d, %d)" % [int(_hover_m.x), int(_hover_m.y)], 14, false)
	var hint := "ЛКМ — двигать · колесо — масштаб · ПКМ — метка (на метке — убрать) · 1–6 — цвет · Пробел — к игроку · Del — убрать все · M — закрыть"
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_label(Vector2(maxf(size.x * 0.5 - hw * 0.5, 10.0), size.y - 14.0), hint, 12, false)
