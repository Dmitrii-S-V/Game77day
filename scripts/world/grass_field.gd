class_name GrassField
extends Node3D
## Осока вокруг игрока: колонки 16x16 м, в каждой MultiMesh из перекрёстных карточек.
## Позиции считаются в рабочем потоке по плану мира и реальной поверхности вокселей
## (где копали — травы нет). Исключены дороги, здания, вода, песок, склоны и скалы.

const CHUNK := WorldGen.CHUNK
const CANDIDATES := 1300
const LAYER_NODES := ["node", "fnode", "pnode", "wnode", "hnode"]
## Общий цвет травы (линейный, как у 7DTD — насыщенный зелёный): в него перекрашиваются и земля под травой
## (terrain/terrain_far), и кусты травы — со своей светотенью; GRASS_RECOLOR — доля перекраски.
const GRASS_COLOR := Vector3(0.07, 0.115, 0.022)   # средний цвет текстуры земли grass_a (сгенерированной)
const TERRAIN_RECOLOR := 0.0      # земля: свои цвета (текстуры assets/src/terrain_gen — уже в тон), кусты — в её цвет
const GRASS_RECOLOR := 0.92
## Кусты травы под текстуры земли: атлас tools/cut_tufts.gd (4x4, квадратные ячейки) + data/blocks/tufts.json —
## у каждого куста своя земля (main — основная трава, pine — хвоя и мох, meadow — луг), выбирается по тому же шуму,
## которым ландшафт смешивает текстуры (_ground_pool).
const TUFTS_TEX := "res://assets/textures/grass_tufts_v2.png"
const TUFTS_JSON := "res://data/blocks/tufts.json"
const TUFTS_GRID := Vector2(4, 4)
const TUFTS_ASPECT := 1.0
const TUFTS_WIDEN := 1.4         # кусты шире (по сторонам), высота не меняется
const MOSS_AMOUNT := 0.35         # как moss_amount в terrain.gdshader
const TUFTS_BRIGHT := 0.9         # кусты чуть светлее (как текстуры земли — make_ground_tex.GAIN)
var _tuft_pools := {}             # pool -> [{cell, hf}]
var _tufts := false               # основная трава — кусты из атласа (карточка шире: куст в квадратной ячейке)

var terrain: Terrain
var radius := 4

var _mat: ShaderMaterial
var _mesh: ArrayMesh
var _flora_mat: ShaderMaterial
var _patch_mat: ShaderMaterial
var _flat_mesh: ArrayMesh
var _flora_items: Array = []     # из data/blocks/flora.json: {cell, kind, aspect, size, weight}
var _flora_cards: Array = []     # plant + rock
var _flora_patches: Array = []   # ground
const FLORA_ENABLED := false   # карточки/пятна из декалей природы отключены (выглядели нелепо)
const FLORA_CANDIDATES := 520
const FLORA_CHANCE := 0.11      # доля кандидатов с карточкой растения/камня (в пределах пятна травы)
const PATCH_CHANCE := 0.035     # доля кандидатов с пятном на земле
## Дикие растения (атласы tools/cut_flora.gd, data/blocks/flora_wild.json): трава разных видов, цветы, сухие кусты
## и трава — в поле среди осоки и густо вплотную вдоль загородных дорог; борщевик — поодиночке и зарослями.
const WILD_CANDIDATES := 150    # поле: кандидатов на колонку
const WILD_ACCEPT := 0.16       # доля принятых (в пятне травы)
const ROAD_CANDIDATES := 1800   # обочины: кандидаты по всей колонке, принимаются только у края дороги
const ROAD_BAND := 4.0          # полоса от края дороги, м
const ROAD_ACCEPT := 0.48
const HOG_CANDIDATES := 40      # борщевик
const HOG_GROUP := 0.5          # порог шума зарослей
const HOG_GROUP_ACCEPT := 0.25
const HOG_SINGLE := 0.002       # одиночный — где угодно в траве
var _wild_mat: ShaderMaterial
var _hog_mat: ShaderMaterial
var _wild_pools := {}           # вид -> [item]
var _hog_items: Array = []
var _cols := {}              # Vector2i -> {"node": MultiMeshInstance3D, "data": PackedFloat32Array}
var _pending: Array[Vector2i] = []
var _inflight := {}
var _results: Array = []
var _mutex := Mutex.new()
var _center := Vector2i(1 << 30, 0)

## Срезанная трава (удар по земле с травой): клетки 0.5 м; на них трава и кустики не растут (сохраняется в сейв).
const CUT_CELL := 0.5
static var cut := {}


static func cut_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CUT_CELL), floori(z / CUT_CELL))


## Срезать траву в радиусе r вокруг точки: поле травы и кустики (группа grass_mm). Возвращает число срезанных пучков.
static func cut_around(tree: SceneTree, center: Vector3, r: float) -> int:
	var n := 0
	for f in tree.get_nodes_in_group("grass_field"):
		n += (f as GrassField)._cut_columns(center, r)
	for mm in tree.get_nodes_in_group("grass_mm"):
		n += cut_mmi(mm as MultiMeshInstance3D, center, r)
	if n > 0:
		var lo := cut_key(center.x - r, center.z - r)
		var hi := cut_key(center.x + r, center.z + r)
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var c := Vector2((cx + 0.5) * CUT_CELL, (cz + 0.5) * CUT_CELL)
				if c.distance_to(Vector2(center.x, center.z)) <= r + CUT_CELL * 0.5:
					cut[Vector2i(cx, cz)] = true
	return n


## Убрать экземпляры MultiMesh (кустики травы) в радиусе; r < 0 — все, что стоят на срезанных клетках.
static func cut_mmi(mmi: MultiMeshInstance3D, center: Vector3, r: float) -> int:
	if mmi == null or mmi.multimesh == null or not mmi.is_inside_tree():
		return 0
	var mm := mmi.multimesh
	var gt := mmi.global_transform
	var keep_t: Array[Transform3D] = []
	var keep_c: Array[Color] = []
	var removed := 0
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		var wp := gt * t.origin
		var gone := cut.has(cut_key(wp.x, wp.z)) if r < 0.0 else \
			(Vector2(wp.x - center.x, wp.z - center.z).length() < r and absf(wp.y - center.y) < 1.5)
		if gone:
			removed += 1
		else:
			keep_t.append(t)
			keep_c.append(mm.get_instance_custom_data(i) if mm.use_custom_data else Color.WHITE)
	if removed > 0:
		mm.instance_count = keep_t.size()
		for i in keep_t.size():
			mm.set_instance_transform(i, keep_t[i])
			if mm.use_custom_data:
				mm.set_instance_custom_data(i, keep_c[i])
	return removed


## Кустик/полоса кустиков травы: в группу срезаемых; при появлении в мире — без уже срезанного.
static func register_mmi(mmi: MultiMeshInstance3D) -> void:
	mmi.add_to_group("grass_mm")
	mmi.ready.connect(func() -> void: cut_mmi(mmi, Vector3.ZERO, -1.0), CONNECT_ONE_SHOT)


func _cut_columns(center: Vector3, r: float) -> int:
	var n := 0
	var lo := Vector2i(floori((center.x - r) / CHUNK), floori((center.z - r) / CHUNK))
	var hi := Vector2i(floori((center.x + r) / CHUNK), floori((center.z + r) / CHUNK))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cz)
			if not _cols.has(key):
				continue
			for layer in [["node", "data"], ["wnode", "wdata"], ["hnode", "hdata"]]:
				if not _cols[key].has(layer[0]):
					continue
				var data: PackedFloat32Array = _cols[key][layer[1]]
				var keep := PackedFloat32Array()
				var removed := 0
				for i in range(0, data.size(), 16):
					var dx := data[i + 3] - center.x
					var dz := data[i + 11] - center.z
					if dx * dx + dz * dz < r * r and absf(data[i + 7] - center.y) < 1.5:
						removed += 1
					else:
						keep.append_array(data.slice(i, i + 16))
				if removed > 0:
					_cols[key][layer[1]] = keep
					_set_buffer(_cols[key][layer[0]], keep, null if layer[0] == "node" else _mesh)
					if layer[0] == "node":
						_update_density(key, _view_pos)
					n += removed
	return n


func _ready() -> void:
	add_to_group("grass_field")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	# основная трава — чёткие кусты с собственным цветом (assets/textures/grass_tufts.png, tools/cut_grass.gd);
	# нет атласа — прежняя осока, перекрашенная под землю
	var st := TexCache.texture(TUFTS_TEX, true, 0, false)
	if st != null:
		_mat.set_shader_parameter("tex_sedge", st)
		_mat.set_shader_parameter("grid", TUFTS_GRID)
		_mat.set_shader_parameter("true_color", 1.0)
		_mat.set_shader_parameter("mip_alpha", 0.3)
		_mat.set_shader_parameter("use_shapes", true)
		_mat.set_shader_parameter("grass_color", GRASS_COLOR)
		_mat.set_shader_parameter("grass_recolor", 0.0)   # кусты сгенерированы под землю — свои цвета
		_mat.set_shader_parameter("bright", TUFTS_BRIGHT)
		_tufts = true
		var jf := FileAccess.open(TUFTS_JSON, FileAccess.READ)
		if jf != null:
			var jd: Variant = JSON.parse_string(jf.get_as_text())
			if jd is Dictionary:
				for it: Dictionary in jd.get("items", []):
					var pk := String(it["pool"])
					if not _tuft_pools.has(pk):
						_tuft_pools[pk] = []
					(_tuft_pools[pk] as Array).append(it)
	else:
		st = TexCache.texture("res://assets/textures/sedge.png", true, 0, false)
		if st != null:
			_mat.set_shader_parameter("tex_sedge", st)
	for pair in [["tex_g1", "grass_a"], ["tex_g2", "grass_b"], ["tex_g3", "grass_c"]]:
		# те же объекты, что у ландшафта (TexCache держит их в памяти) — без повторного декодирования
		var gt := TexCache.texture("res://assets/textures/%s.png" % pair[1], true, 0, true)
		if gt != null:
			_mat.set_shader_parameter(pair[0], gt)
	var mb := MeshBuilder.new()
	var up := Vector3.UP
	var w := Color.WHITE
	var a0 := mb.vert_full(Vector3(-0.5, 0, 0), w, Vector2(0, 1), up)
	var a1 := mb.vert_full(Vector3(0.5, 0, 0), w, Vector2(1, 1), up)
	var a2 := mb.vert_full(Vector3(0.5, 1, 0), w, Vector2(1, 0), up)
	var a3 := mb.vert_full(Vector3(-0.5, 1, 0), w, Vector2(0, 0), up)
	mb.quad(a0, a1, a2, a3)
	var b0 := mb.vert_full(Vector3(0, 0, -0.5), w, Vector2(0, 1), up)
	var b1 := mb.vert_full(Vector3(0, 0, 0.5), w, Vector2(1, 1), up)
	var b2 := mb.vert_full(Vector3(0, 1, 0.5), w, Vector2(1, 0), up)
	var b3 := mb.vert_full(Vector3(0, 1, -0.5), w, Vector2(0, 0), up)
	mb.quad(b0, b1, b2, b3)
	_mesh = mb.to_mesh()
	_tuft_mesh = _build_shape_mesh()
	_setup_flora()
	_setup_wild()


## Какая земля в точке (как смешивает terrain.gdshader): main / pine / meadow; мох — кусты хвои.
## r — случайное число 0..1 для выбора по весам на стыке текстур.
static func _ground_pool(x: float, z: float, slope: float, r: float) -> String:
	var w := Vector2(x, z)
	var m1 := smoothstep(0.25, 0.75, _gnoise(w * 0.06 + Vector2(2.0, 2.0)))
	var m2 := smoothstep(0.45, 0.95, _gnoise(w * 0.031 + Vector2(17.0, 17.0)))
	var up := 1.0 / sqrt(1.0 + slope * slope)
	var mm := smoothstep(1.0 - MOSS_AMOUNT, 1.0 - MOSS_AMOUNT + 0.12, _gnoise(w * 0.045 + Vector2(51.0, 51.0)) + (1.0 - smoothstep(0.86, 0.97, up)) * 0.15)
	if r < mm:
		return "pine"
	var r2 := (r - mm) / maxf(1.0 - mm, 1e-4)
	var wm := m2 * 0.85
	if r2 < wm:
		return "meadow"
	return "pine" if (r2 - wm) / maxf(1.0 - wm, 1e-4) < m1 else "main"


## Порт gnoise/hash из terrain.gdshader (тот же шум на CPU).
static func _hash(p: Vector2) -> float:
	var p3 := Vector3(p.x, p.y, p.x) * 0.1031
	p3 = Vector3(p3.x - floorf(p3.x), p3.y - floorf(p3.y), p3.z - floorf(p3.z))
	var dd := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(dd, dd, dd)
	var v := (p3.x + p3.y) * p3.z
	return v - floorf(v)


static func _ghash(p: Vector2) -> Vector2:
	var a := _hash(p) * 6.2831853
	return Vector2(cos(a), sin(a))


static func _gnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * f * (f * (f * 6.0 - Vector2(15.0, 15.0)) + Vector2(10.0, 10.0))
	var a := _ghash(i).dot(f)
	var b := _ghash(i + Vector2(1, 0)).dot(f - Vector2(1, 0))
	var c := _ghash(i + Vector2(0, 1)).dot(f - Vector2(0, 1))
	var d := _ghash(i + Vector2(1, 1)).dot(f - Vector2(1, 1))
	return clampf(lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y) * 0.75 + 0.5, 0.0, 1.0)


func _setup_wild() -> void:
	var f := FileAccess.open("res://data/blocks/flora_wild.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	for it: Dictionary in d.get("items", []):
		if bool(it.get("white", false)):
			continue     # белёсые, плохо вырезанные (tools/flora_lum.gd)
		if String(it["atlas"]) == "hogweed":
			_hog_items.append(it)
		else:
			var k := String(it["kind"])
			if not _wild_pools.has(k):
				_wild_pools[k] = []
			(_wild_pools[k] as Array).append(it)
	var wt := TexCache.texture("res://assets/textures/flora_wild.png", true, 0, true)
	var ht := TexCache.texture("res://assets/textures/flora_hogweed.png", true, 0, true)
	if wt == null or ht == null:
		_wild_pools.clear()
		_hog_items.clear()
		return
	_wild_mat = ShaderMaterial.new()
	_wild_mat.shader = load("res://shaders/wild.gdshader")
	_wild_mat.set_shader_parameter("tex_atlas", wt)
	_wild_mat.set_shader_parameter("grid", Vector2(9, 8))
	_hog_mat = ShaderMaterial.new()
	_hog_mat.shader = load("res://shaders/wild.gdshader")
	_hog_mat.set_shader_parameter("tex_atlas", ht)
	_hog_mat.set_shader_parameter("grid", Vector2(4, 2))
	_hog_mat.set_shader_parameter("sway", 0.06)


func _setup_flora() -> void:
	if not FLORA_ENABLED:
		return
	var f := FileAccess.open("res://data/blocks/flora.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	_flora_items = d.get("items", [])
	for it: Dictionary in _flora_items:
		if it["kind"] == "ground":
			_flora_patches.append(it)
		else:
			_flora_cards.append(it)
	var fimg := TexCache.load_image("res://assets/textures/flora.png")
	if fimg == null:
		_flora_items = []
		return
	fimg.generate_mipmaps()
	var ftex := ImageTexture.create_from_image(fimg)
	_flora_mat = ShaderMaterial.new()
	_flora_mat.shader = load("res://shaders/flora.gdshader")
	_flora_mat.set_shader_parameter("tex_flora", ftex)
	_patch_mat = ShaderMaterial.new()
	_patch_mat.shader = load("res://shaders/flora.gdshader")
	_patch_mat.set_shader_parameter("tex_flora", ftex)
	_patch_mat.set_shader_parameter("sway", 0.0)
	_patch_mat.set_shader_parameter("fade_start", 48.0)
	_patch_mat.set_shader_parameter("fade_end", 62.0)
	var pb := MeshBuilder.new()
	var up2 := Vector3.UP
	var w2 := Color.WHITE
	var p0 := pb.vert_full(Vector3(-0.5, 0.012, 0.5), w2, Vector2(0, 1), up2)
	var p1 := pb.vert_full(Vector3(0.5, 0.012, 0.5), w2, Vector2(1, 1), up2)
	var p2 := pb.vert_full(Vector3(0.5, 0.012, -0.5), w2, Vector2(1, 0), up2)
	var p3 := pb.vert_full(Vector3(-0.5, 0.012, -0.5), w2, Vector2(0, 0), up2)
	pb.quad(p0, p1, p2, p3)
	_flat_mesh = pb.to_mesh()


func is_idle() -> bool:
	if radius <= 0:
		return true
	return _pending.is_empty() and _inflight.is_empty() and _results.is_empty()


## Радиус травы в колонках (настройки графики); 0 — трава выключена. Дистанция растворения — под радиус.
## Радиус травы: r — полная плотность (настройки графики, колонки 16 м); дальше, до r * FAR_MULT (но не дальше
## построенного ближнего ландшафта max_r — иначе трава повиснет над упрощённым дальним), — всё реже: кусты в буфере
## колонки отсортированы по «рангу», рисуется только начало списка (visible_instance_count), а шейдер плавно
## «выращивает» куст, когда плотность в его точке становится больше его ранга (без выскакивания). Как в 7DTD/UE.
const FAR_MULT := 3
const FAR_DENSITY := 0.14       # доля кустов у дальнего края
var near_radius := 0            # колонок с полной плотностью
var _view_pos := Vector2.ZERO


func set_radius(r: int, max_r: int = 1 << 20) -> void:
	near_radius = r
	radius = mini(r * FAR_MULT, max_r - 1) if r > 0 else 0   # край ландшафта достраивается не всегда
	visible = r > 0
	_center = Vector2i(1 << 30, 0)
	if _mat != null and r > 0:
		var near := r * float(CHUNK)
		var edge := radius * float(CHUNK)
		_mat.set_shader_parameter("dens_near", near * 0.8)
		_mat.set_shader_parameter("dens_far", edge * 0.95)
		_mat.set_shader_parameter("dens_min", FAR_DENSITY)
		_mat.set_shader_parameter("fade_start", edge * 0.85)
		_mat.set_shader_parameter("fade_end", edge * 0.97)
		# дикие растения (мелочь) — до прежней границы, борщевик (высокий) — до дальней
		if _wild_mat != null:
			_wild_mat.set_shader_parameter("fade_start", near * 0.72)
			_wild_mat.set_shader_parameter("fade_end", near * 0.95)
		if _hog_mat != null:
			_hog_mat.set_shader_parameter("fade_start", edge * 0.8)
			_hog_mat.set_shader_parameter("fade_end", edge * 0.95)


## Плотность травы на расстоянии d (как density() в grass.gdshader).
func _density(d: float) -> float:
	var near := near_radius * float(CHUNK) * 0.8
	var far := radius * float(CHUNK) * 0.95
	return lerpf(1.0, FAR_DENSITY, smoothstep(near, far, d))


## Сколько кустов колонки рисовать: все с рангом ниже плотности в ближайшей точке колонки (с запасом на колонку —
## шейдер уже сам плавно выращивает их по точному расстоянию).
func _update_density(key: Vector2i, pos: Vector2) -> void:
	var e: Dictionary = _cols.get(key, {})
	if e.is_empty() or not e.has("node") or near_radius <= 0:
		return     # set_radius ещё не вызывался (отладочные снимки) — шейдер рисует все кусты, и здесь все
	var mmi: MultiMeshInstance3D = e["node"]
	if mmi.multimesh == null:
		return
	var lo := Vector2(key.x * CHUNK, key.y * CHUNK)
	var near_p := pos.clamp(lo, lo + Vector2(CHUNK, CHUNK))
	var dens := _density(maxf(near_p.distance_to(pos) - CHUNK, 0.0))
	var data: PackedFloat32Array = e["data"]
	var n := data.size() / 16
	# ранги отсортированы по возрастанию — двоичный поиск
	var a := 0
	var b := n
	while a < b:
		var m := (a + b) / 2
		if data[m * 16 + 14] < dens:
			a = m + 1
		else:
			b = m
	mmi.multimesh.visible_instance_count = a if a < n else -1


func update_view(pos: Vector3) -> void:
	if radius <= 0:
		_pending.clear()
		_apply()   # дочитать результаты уже запущенных задач (они отбросятся — колонки вне радиуса)
		if not _cols.is_empty():
			for key: Vector2i in _cols.keys():
				for nk in LAYER_NODES:
					if _cols[key].has(nk):
						(_cols[key][nk] as Node).queue_free()
			_cols.clear()
		return
	var c := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	if c != _center:
		_center = c
		_pending.clear()
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var key := Vector2i(c.x + dx, c.y + dz)
				if dx * dx + dz * dz <= radius * radius + 1 and not _cols.has(key) and not _inflight.has(key) \
						and terrain.gen.in_map(key.x, key.y):
					_pending.append(key)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - c).length_squared() < (b - c).length_squared())
		for key: Vector2i in _cols.keys():
			if (key - c).length_squared() > (radius + 1) * (radius + 1):
				for nk in LAYER_NODES:
					if _cols[key].has(nk):
						FrameBudget.free_later(_cols[key][nk])
				_cols.erase(key)
		_view_pos = Vector2(pos.x, pos.z)
		for key: Vector2i in _cols.keys():
			_update_density(key, _view_pos)
	var i := 0
	while i < _pending.size() and i < 12 and _inflight.size() < 2:
		var key := _pending[i]
		if terrain.is_column_done(key.x, key.y):
			_pending.remove_at(i)
			_inflight[key] = true
			WorkerThreadPool.add_task(_job.bind(key, cut.duplicate()))   # копия: задача читает её в потоке
		else:
			i += 1
	_apply()


func _job(key: Vector2i, cut_cells: Dictionary) -> void:
	var gen := terrain.gen
	var col := gen.column(key.x, key.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.world.params.seed_value, key.x, key.y, 4242])
	var buf := PackedFloat32Array()
	var fbuf := PackedFloat32Array()
	var pbuf := PackedFloat32Array()
	# деревья, кусты и камни рядом (эта и соседние колонки): у них трава гуще
	var anchors := PackedVector2Array()
	if _tufts:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if gen.in_map(key.x + dx, key.y + dz):
					for pl: Dictionary in gen.vegetation_plan(key.x + dx, key.y + dz):
						anchors.append(Vector2(float(pl["x"]), float(pl["z"])))
	for n in CANDIDATES:
		var lx := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var lz := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var accept := rng.randf()
		var hs := rng.randf()
		var ws := rng.randf()
		var yaw := rng.randf() * TAU
		var pick := rng.randf()
		var pick2 := rng.randf()
		var rank := rng.randf()          # порядок появления вдали (плотность травы по расстоянию)
		var shape_r := rng.randf()       # форма куста (TUFT_SHAPES)
		var k := int(lx) + CHUNK * int(lz)
		if col.blocked[k] != 0 or col.mat[k] != 0:
			continue
		var h := col.h[k]
		if h < WorldGen.WATER_LEVEL + 1.8 or h > 62.0:
			continue
		var wx := key.x * CHUNK + lx
		var wz := key.y * CHUNK + lz
		if not cut_cells.is_empty() and cut_cells.has(cut_key(wx, wz)):
			continue   # срезано игроком
		if accept < gen.world.biome.burn_at(wx, wz) * 1.05:
			continue   # в выжженном биоме трава не растёт
		var patch := clampf(0.75 + gen._forest.get_noise_2d(wx * 2.6 + 50.0, wz * 2.6) * 1.1, 0.2, 1.0)
		if _tufts:
			if accept > _tuft_density(wx, wz, anchors):
				continue
		elif accept > patch:
			continue
		if gen.slope_at(wx, wz) > 0.7:
			continue
		var y := terrain.surface_y(wx, wz, h)
		if is_nan(y) or y < h - 0.4 or y > h + 1.0:
			continue
		var hg := lerpf(0.6, 1.25, hs) * lerpf(0.8, 1.15, patch)
		var wg := hg * 0.5 * lerpf(1.0, 1.35, ws)
		var cell := int(pick * 8.0)
		if _tufts and not _tuft_pools.is_empty():
			var pool: Array = _tuft_pools.get(_ground_pool(wx, wz, gen.slope_at(wx, wz), pick), _tuft_pools.values()[0])
			var it: Dictionary = pool[mini(int(pick2 * pool.size()), pool.size() - 1)]
			cell = int(it["cell"]) + 16 * _pick_shape(shape_r)
			var plant_h := lerpf(0.30, 0.70, hs) * lerpf(0.85, 1.15, patch)  # высота самого куста, м (прежняя 0.35–0.8, ниже в 1.15 раза)
			hg = plant_h / maxf(float(it["hf"]), 0.3)                        # высота ячейки
			wg = hg * TUFTS_ASPECT * TUFTS_WIDEN * lerpf(0.95, 1.15, ws)   # шире, высота прежняя
		var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(wg, hg, wg))
		var green := smoothstep(-0.55, 0.15, gen._forest.get_noise_2d(wx * 0.9 + 200.0, wz * 0.9))
		buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, wx, b.x.y, b.y.y, b.z.y, y - 0.03, b.x.z, b.y.z, b.z.z, wz,
			green, gen.world.biome.burn_at(wx, wz), rank, float(cell) / 255.0]))
	if FLORA_ENABLED and not _flora_items.is_empty():
		var frng := RandomNumberGenerator.new()
		frng.seed = hash([gen.world.params.seed_value, key.x, key.y, 9191])
		for n in FLORA_CANDIDATES:
			var lx := minf(frng.randf() * CHUNK, CHUNK - 0.01)
			var lz := minf(frng.randf() * CHUNK, CHUNK - 0.01)
			var roll := frng.randf()
			var pick := frng.randf()
			var yaw := frng.randf() * TAU
			var jitter := frng.randf()
			var tint := frng.randf_range(0.88, 1.12)
			var k := int(lx) + CHUNK * int(lz)
			if col.blocked[k] != 0 or col.mat[k] != 0:
				continue
			var h := col.h[k]
			if h < WorldGen.WATER_LEVEL + 1.4 or h > 70.0:
				continue
			var wx := key.x * CHUNK + lx
			var wz := key.y * CHUNK + lz
			var patchn := clampf(0.5 + gen._forest.get_noise_2d(wx * 1.7 + 90.0, wz * 1.7) * 1.4, 0.0, 1.0)
			var is_patch := roll < PATCH_CHANCE
			if not is_patch and (roll > PATCH_CHANCE + FLORA_CHANCE * patchn or _flora_cards.is_empty()):
				continue
			if gen.slope_at(wx, wz) > (0.9 if is_patch else 0.7):
				continue
			var y := terrain.surface_y(wx, wz, h)
			if is_nan(y) or y < h - 0.4 or y > h + 1.0:
				continue
			var pool: Array = _flora_patches if is_patch else _flora_cards
			if pool.is_empty():
				continue
			var tw := 0.0
			for it: Dictionary in pool:
				tw += float(it["weight"])
			var r := pick * tw
			var chosen: Dictionary = pool[pool.size() - 1]
			for it: Dictionary in pool:
				r -= float(it["weight"])
				if r <= 0.0:
					chosen = it
					break
			var sz := float(chosen["size"]) * lerpf(0.8, 1.2, jitter)
			var asp := float(chosen["aspect"])
			var bs: Basis
			if is_patch:
				bs = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sz, 1.0, sz / maxf(asp, 0.2)))
				pbuf.append_array(PackedFloat32Array([bs.x.x, bs.y.x, bs.z.x, wx, bs.x.y, bs.y.y, bs.z.y, y, bs.x.z, bs.y.z, bs.z.z, wz,
					tint, 0.0, 0.0, float(chosen["cell"]) / 31.0]))
			else:
				var hh := sz
				var ww := sz * asp
				bs = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(ww, hh, ww))
				fbuf.append_array(PackedFloat32Array([bs.x.x, bs.y.x, bs.z.x, wx, bs.x.y, bs.y.y, bs.z.y, y - 0.03, bs.x.z, bs.y.z, bs.z.z, wz,
					tint, 0.0, 0.0, float(chosen["cell"]) / 31.0]))
	buf = _sort_by_rank(buf)
	var wbuf := PackedFloat32Array()
	var hbuf := PackedFloat32Array()
	if not _wild_pools.is_empty():
		_wild_job(key, col, cut_cells, wbuf, hbuf)
	_mutex.lock()
	_results.append({"key": key, "buf": buf, "fbuf": fbuf, "pbuf": pbuf, "wbuf": wbuf, "hbuf": hbuf})
	_mutex.unlock()


## Плотность кустов травы (0..1 — доля кандидатов): редкие одиночные кусты, группы и куртины по шуму, проплешины;
## гуще там, где трава логична — у деревьев, кустов и камней (anchors), у обочин, на пологих склонах.
const TUFT_SINGLE := 0.05       # одиночные — где угодно
const TUFT_GROUP := 0.55        # прибавка в группах (пятна ~2 м)
const TUFT_CLUMP := 0.8         # прибавка в куртинах (пятна ~8 м)
const TUFT_NEAR := 0.7          # прибавка у деревьев, кустов, камней (до 3 м)
const TUFT_ROADSIDE := 0.45     # прибавка у края загородной дороги (до 6 м)


func _tuft_density(x: float, z: float, anchors: PackedVector2Array) -> float:
	var gen := terrain.gen
	var w := Vector2(x, z)
	var clump := smoothstep(0.58, 0.78, _gnoise(w * 0.12 + Vector2(310.0, 7.0)))
	var group := smoothstep(0.62, 0.8, _gnoise(w * 0.5 + Vector2(-93.0, 211.0)))
	var d := TUFT_SINGLE + TUFT_GROUP * group + TUFT_CLUMP * clump
	var near := 1e9
	for a in anchors:
		near = minf(near, a.distance_squared_to(w))
	if near < 9.0:
		d += TUFT_NEAR * (1.0 - sqrt(near) / 3.0)
	var rd := gen.world.road_dist(x, z)
	if rd < 6.0:
		d += TUFT_ROADSIDE * (1.0 - rd / 6.0)
	# проплешины: крупные пятна голой (только текстурной) травы
	var bald := smoothstep(0.32, 0.22, _gnoise(w * 0.035 + Vector2(-500.0, 133.0)))
	return clampf(d, 0.0, 1.0) * (1.0 - 0.9 * bald)


## Формы 2D-кустов травы (набор плоскостей-карточек): одна общая сетка со всеми плоскостями, у вершины в COLOR.r —
## маска форм, к которым относится плоскость; у куста форма в INSTANCE_CUSTOM.w (ячейка + 16 * форма), лишние
## плоскости шейдер схлопывает. Веса — доля кустов этой формы.
const TUFT_SHAPES := [
	["крест", 0.25], ["звезда (3 плоскости)", 0.2], ["гексагон (6 лучей)", 0.1],
	["решётка #", 0.15], ["сетка 3x3", 0.1], ["треугольник", 0.2],
]
var _tuft_mesh: ArrayMesh


static func _pick_shape(r: float) -> int:
	var acc := 0.0
	for i in TUFT_SHAPES.size():
		acc += float(TUFT_SHAPES[i][1])
		if r < acc:
			return i
	return 0


func _build_shape_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var r3 := 0.22                      # треугольник: расстояние сторон от центра
	var side := 2.0 * sqrt(3.0) * r3    # длина стороны
	# [угол плоскости, сдвиг по нормали, ширина, маска форм]
	var planes := [
		[0.0, 0.0, 1.0, 1 | 2 | 4 | 16], [90.0, 0.0, 1.0, 1 | 4 | 16],
		[60.0, 0.0, 1.0, 2 | 4], [120.0, 0.0, 1.0, 2 | 4],
		[30.0, 0.0, 0.9, 4], [150.0, 0.0, 0.9, 4],
		[0.0, 0.3, 0.9, 8 | 16], [0.0, -0.3, 0.9, 8 | 16], [90.0, 0.3, 0.9, 8 | 16], [90.0, -0.3, 0.9, 8 | 16],
		[0.0, r3, side, 32], [120.0, r3, side, 32], [240.0, r3, side, 32],
	]
	for i in planes.size():
		var pl: Array = planes[i]
		var ang := deg_to_rad(float(pl[0]))
		var tg := Vector3(cos(ang), 0.0, sin(ang))
		var nrm := Vector3(-sin(ang), 0.0, cos(ang))
		var c := nrm * float(pl[1])
		var hw := float(pl[2]) * 0.5
		var col := Color(float(pl[3]) / 255.0, 0.0, 0.0, 1.0)
		var u0 := 0.0 if i % 2 == 0 else 1.0     # соседние плоскости — зеркально (меньше повторов)
		var u1 := 1.0 - u0
		var v0 := mb.vert_full(c - tg * hw, col, Vector2(u0, 1), Vector3.UP)
		var v1 := mb.vert_full(c + tg * hw, col, Vector2(u1, 1), Vector3.UP)
		var v2 := mb.vert_full(c + tg * hw + Vector3.UP, col, Vector2(u1, 0), Vector3.UP)
		var v3 := mb.vert_full(c - tg * hw + Vector3.UP, col, Vector2(u0, 0), Vector3.UP)
		mb.quad(v0, v1, v2, v3)
	return mb.to_mesh()


## Кусты по возрастанию ранга (custom.z): вдали рисуется только начало буфера.
static func _sort_by_rank(buf: PackedFloat32Array) -> PackedFloat32Array:
	var n := buf.size() / 16
	var idx: Array = range(n)
	idx.sort_custom(func(i: int, j: int) -> bool: return buf[i * 16 + 14] < buf[j * 16 + 14])
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for k in n:
		var s: int = idx[k] * 16
		for q in 16:
			out[k * 16 + q] = buf[s + q]
	return out


## Место для растения в колонке: высота поверхности или NAN (дорога, здание, вода, склон, срезано, копали).
func _wild_spot(col: ColumnInfo, lx: float, lz: float, wx: float, wz: float, cut_cells: Dictionary, max_slope: float) -> float:
	var k := int(lx) + CHUNK * int(lz)
	if col.blocked[k] != 0 or col.mat[k] != 0:
		return NAN
	var h := col.h[k]
	if h < WorldGen.WATER_LEVEL + 1.6 or h > 70.0:
		return NAN
	if not cut_cells.is_empty() and cut_cells.has(cut_key(wx, wz)):
		return NAN
	if terrain.gen.slope_at(wx, wz) > max_slope:
		return NAN
	var y := terrain.surface_y(wx, wz, h)
	if is_nan(y) or y < h - 0.4 or y > h + 1.0:
		return NAN
	return y


func _pick(pool: Array, r: float) -> Dictionary:
	return pool[mini(int(r * pool.size()), pool.size() - 1)]


## Карточка: высота растения hgt (м), ширина — по ячейке атласа (cell_aspect = ширина/высота ячейки).
func _put(buf: PackedFloat32Array, it: Dictionary, x: float, y: float, z: float, hgt: float, yaw: float, tint: float,
		dry: float, cell_aspect: float, burn: float = 0.0) -> void:
	var ch := hgt / maxf(float(it["hf"]), 0.2)
	var cw := ch * cell_aspect
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(cw, ch, cw))
	buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y - 0.05, b.x.z, b.y.z, b.z.z, z,
		tint, dry, burn, float(it["cell"]) / 255.0]))


func _wild_job(key: Vector2i, col: ColumnInfo, cut_cells: Dictionary, wbuf: PackedFloat32Array, hbuf: PackedFloat32Array) -> void:
	var gen := terrain.gen
	var world := gen.world
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.params.seed_value, key.x, key.y, 7373])
	var green_pool: Array = _wild_pools.get("grass", []) + _wild_pools.get("flower", [])
	var dry_pool: Array = _wild_pools.get("dry_grass", []) + _wild_pools.get("dry_weed", []) + _wild_pools.get("dry_bush", [])
	# поле: среди осоки — разные виды трав и цветов, местами (и в выжженном) — сухие
	for n in WILD_CANDIDATES:
		var lx := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var lz := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var acc := rng.randf()
		var pick := rng.randf()
		var r2 := rng.randf()
		var yaw := rng.randf() * TAU
		var js := rng.randf()
		var wx := key.x * CHUNK + lx
		var wz := key.y * CHUNK + lz
		var patch := clampf(0.75 + gen._forest.get_noise_2d(wx * 2.6 + 50.0, wz * 2.6) * 1.1, 0.0, 1.0)
		if acc > WILD_ACCEPT * patch:
			continue
		var y := _wild_spot(col, lx, lz, wx, wz, cut_cells, 0.7)
		if is_nan(y):
			continue
		var burn := world.biome.burn_at(wx, wz)
		var dryness := clampf(0.2 + gen._forest.get_noise_2d(wx * 1.3 + 400.0, wz * 1.3) * 0.9 + burn, 0.0, 1.0)
		var it := _pick(dry_pool if (pick < dryness or burn > 0.45) else green_pool, r2)
		var fs := 0.87 if String(it["kind"]) == "grass" else 1.0      # травы в поле ниже в 1.15 раза (как основная трава)
		_put(wbuf, it, wx, y, wz, float(it["size"]) * fs * lerpf(0.75, 1.3, js), yaw, rng.randf_range(0.85, 1.1), dryness * 0.4, 1.0, burn)
	# обочины загородных дорог: густо, вплотную к краю, разной высоты (кроме борщевика)
	for n in ROAD_CANDIDATES:
		var lx := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var lz := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var acc := rng.randf()
		var pick := rng.randf()
		var r2 := rng.randf()
		var yaw := rng.randf() * TAU
		var js := rng.randf()
		var wx := key.x * CHUNK + lx
		var wz := key.y * CHUNK + lz
		var rd := world.road_dist(wx, wz)
		# прерывистая полоса: куски по несколько метров с промежутками (не сплошная стена вдоль дороги)
		var seg := smoothstep(0.4, 0.62, gen._forest.get_noise_2d(wx * 9.0 + 77.0, wz * 9.0 - 41.0) * 0.5 + 0.5)
		if rd > ROAD_BAND or acc > ROAD_ACCEPT * seg * (1.0 - 0.35 * rd / ROAD_BAND):
			continue
		var y := _wild_spot(col, lx, lz, wx, wz, cut_cells, 0.9)
		if is_nan(y):
			continue
		var burn := world.biome.burn_at(wx, wz)
		var pool: Array = dry_pool if (pick < 0.3 + burn) else green_pool
		var it := _pick(pool, r2)
		_put(wbuf, it, wx, y, wz, float(it["size"]) * lerpf(0.7, 1.7, js), yaw, rng.randf_range(0.82, 1.08), 0.25, 1.0, burn)
	# борщевик: заросли (по шуму) и одиночные
	if _hog_items.is_empty():
		return
	for n in HOG_CANDIDATES:
		var lx := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var lz := minf(rng.randf() * CHUNK, CHUNK - 0.01)
		var acc := rng.randf()
		var r2 := rng.randf()
		var yaw := rng.randf() * TAU
		var js := rng.randf()
		var wx := key.x * CHUNK + lx
		var wz := key.y * CHUNK + lz
		var grp := gen._forest.get_noise_2d(wx * 4.0 + 900.0, wz * 4.0 - 300.0)
		var p := HOG_GROUP_ACCEPT * smoothstep(HOG_GROUP, HOG_GROUP + 0.15, grp) + HOG_SINGLE
		if acc > p:
			continue
		if world.biome.burn_at(wx, wz) > 0.45 or world.road_dist(wx, wz) < 1.5:
			continue
		var y := _wild_spot(col, lx, lz, wx, wz, cut_cells, 0.5)
		if is_nan(y):
			continue
		var it := _pick(_hog_items, r2)
		_put(hbuf, it, wx, y, wz, lerpf(1.9, 3.2, js), yaw, rng.randf_range(0.88, 1.08), 0.0, 0.5)


func _apply() -> void:
	_mutex.lock()
	var take := mini(2, _results.size())
	var batch := _results.slice(0, take)
	_results = _results.slice(take)
	_mutex.unlock()
	for r: Dictionary in batch:
		var key: Vector2i = r["key"]
		_inflight.erase(key)
		if _cols.has(key) or (key - _center).length_squared() > (radius + 1) * (radius + 1):
			continue
		var buf: PackedFloat32Array = r["buf"]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d" % [key.x, key.y]
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_set_buffer(mmi, buf)
		var entry := {"node": mmi, "data": buf}
		if _flora_mat != null:
			var fm := MultiMeshInstance3D.new()
			fm.material_override = _flora_mat
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(fm)
			_set_buffer(fm, r["fbuf"], _mesh)
			var pm := MultiMeshInstance3D.new()
			pm.material_override = _patch_mat
			pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(pm)
			_set_buffer(pm, r["pbuf"], _flat_mesh)
			entry["fnode"] = fm
			entry["fdata"] = r["fbuf"]
			entry["pnode"] = pm
			entry["pdata"] = r["pbuf"]
		if _wild_mat != null:
			for layer in [["wnode", "wdata", "wbuf", _wild_mat, false], ["hnode", "hdata", "hbuf", _hog_mat, true]]:
				var lm := MultiMeshInstance3D.new()
				lm.material_override = layer[3]
				# борщевик высокий — с тенью (иначе «висит»), мелочь — без
				lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if layer[4] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(lm)
				_set_buffer(lm, r[layer[2]], _mesh)
				entry[layer[0]] = lm
				entry[layer[1]] = r[layer[2]]
		_cols[key] = entry
		_update_density(key, _view_pos)


func _set_buffer(mmi: MultiMeshInstance3D, buf: PackedFloat32Array, mesh: ArrayMesh = null) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh if mesh != null else (_tuft_mesh if _tufts and _tuft_mesh != null else _mesh)
	mm.instance_count = buf.size() / 16
	if buf.size() > 0:
		mm.buffer = buf
	mmi.multimesh = mm


## Ландшафт изменён: убираем траву, флору и пятна в радиусе правки.
func on_edited(center: Vector3, edit_radius: float) -> void:
	var reach := edit_radius + 0.9
	var lo := Vector2i(floori((center.x - reach) / CHUNK), floori((center.z - reach) / CHUNK))
	var hi := Vector2i(floori((center.x + reach) / CHUNK), floori((center.z + reach) / CHUNK))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cz)
			if not _cols.has(key):
				continue
			for pair in [["node", "data", null], ["fnode", "fdata", _mesh], ["pnode", "pdata", _flat_mesh], ["wnode", "wdata", _mesh], ["hnode", "hdata", _mesh]]:
				if not _cols[key].has(pair[0]):
					continue
				var data: PackedFloat32Array = _cols[key][pair[1]]
				var keep := PackedFloat32Array()
				var removed := false
				for i in range(0, data.size(), 16):
					var dx := data[i + 3] - center.x
					var dz := data[i + 11] - center.z
					var dy := data[i + 7] - center.y
					if dx * dx + dz * dz < reach * reach and absf(dy) < reach + 1.5:
						removed = true
					else:
						keep.append_array(data.slice(i, i + 16))
				if removed:
					_cols[key][pair[1]] = keep
					_set_buffer(_cols[key][pair[0]], keep, pair[2])
					if pair[0] == "node":
						_update_density(key, _view_pos)