class_name RoadAtlas
extends Node
## Скользящее окно карты дорог вокруг игрока (текстуры-атласы для шейдера ландшафта).
## Окно 640x640 узлов (256 м) с тороидальной адресацией: колонка (cx, cz) занимает блок
## 41x41 узел в позиции ((cx mod 16) * 40, (cz mod 16) * 40). Блоки считаются в потоках.
##   A (RGBAF): Fp, Fo, lat, along      — линейная фильтрация, чёткие края по знаку расстояния
##   B (RGBA8): тип*20, износ, разметка, бордюр
##   C (RGBA8): полуширина/12, признак "посчитано", исходная высота поверхности (B — старший, A — младший байт; см (h+50)*100)

const N := 640
const SLOTS := 16
const NODE := 41
const RADIUS := 7

var roads: RoadNet
var tex_a: ImageTexture
var tex_b: ImageTexture
var tex_c: ImageTexture
var tex_k1: ImageTexture   # веса основы покрытия (шейдер размывает билинейными выборками — плавные стыки)
var tex_k2: ImageTexture   # площадка, тротуар, износ, «есть дорога»

var _img_a: Image
var _img_b: Image
var _img_c: Image
var _img_k1: Image
var _img_k2: Image
var _slot := {}          # Vector2i(слот) -> Vector2i(колонка)
var _pending: Array[Vector2i] = []
var _inflight := {}
var _results: Array = []
var _results_mutex := Mutex.new()
var _center := Vector2i(1 << 30, 0)
var _dirty := false
var _upload_stage := -1   # >=0 — идёт поэтапная загрузка текстур (см. update_view)
var _flush_t := 0.0


var gen: WorldGen   # исходная высота поверхности -> road_c.ba (шейдер по ней узнаёт выкопанную/засыпанную дорогу)


func setup(r: RoadNet, g: WorldGen = null) -> void:
	roads = r
	gen = g
	_img_a = Image.create(N, N, false, Image.FORMAT_RGBAF)
	_img_a.fill(Color(1000.0, 1000.0, 0.0, 0.0))
	_img_b = Image.create(N, N, false, Image.FORMAT_RGBA8)
	_img_c = Image.create(N, N, false, Image.FORMAT_RGBA8)
	tex_a = ImageTexture.create_from_image(_img_a)
	tex_b = ImageTexture.create_from_image(_img_b)
	tex_c = ImageTexture.create_from_image(_img_c)
	_img_k1 = Image.create(N, N, false, Image.FORMAT_RGBA8)
	_img_k2 = Image.create(N, N, false, Image.FORMAT_RGBA8)
	tex_k1 = ImageTexture.create_from_image(_img_k1)
	tex_k2 = ImageTexture.create_from_image(_img_k2)


func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("road_a", tex_a)
	mat.set_shader_parameter("road_b", tex_b)
	mat.set_shader_parameter("road_c", tex_c)
	mat.set_shader_parameter("road_k1", tex_k1)
	mat.set_shader_parameter("road_k2", tex_k2)


func is_idle() -> bool:
	return _pending.is_empty() and _inflight.is_empty() and _results.is_empty() and _upload_stage < 0 and not _dirty


func is_ready_around(pos: Vector3, rad: int = 2) -> bool:
	var cx := floori(pos.x / 16.0)
	var cz := floori(pos.z / 16.0)
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if not is_ready(Vector2i(cx + dx, cz + dz)):
				return false
	return true


func is_ready(key: Vector2i) -> bool:
	return _slot.get(Vector2i(posmod(key.x, SLOTS), posmod(key.y, SLOTS))) == key


func update_view(pos: Vector3, delta: float) -> void:
	var c := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if c != _center:
		_center = c
		_pending.clear()
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				if dx * dx + dz * dz <= RADIUS * RADIUS:
					var key := Vector2i(c.x + dx, c.y + dz)
					if not is_ready(key) and not _inflight.has(key):
						_pending.append(key)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - c).length_squared() < (b - c).length_squared())
	while _inflight.size() < 4 and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if _inflight.has(key) or is_ready(key):
			continue
		_inflight[key] = true
		WorkerThreadPool.add_task(_job.bind(key))
	_apply()
	# загрузка в видеокарту — по одной текстуре за кадр (все пять разом давали пик 3-4 мс); «посчитано» (C) — последней,
	# поэтому шейдер не увидит новую колонку, пока не загружены её данные
	_flush_t -= delta
	if _upload_stage < 0 and _dirty and _flush_t <= 0.0:
		_flush_t = 0.12
		_dirty = false
		_upload_stage = 0
	if _upload_stage >= 0:
		var tu := Time.get_ticks_usec()
		match _upload_stage:
			0: tex_a.update(_img_a)
			1: tex_b.update(_img_b)
			2: tex_k1.update(_img_k1)
			3: tex_k2.update(_img_k2)
			_: tex_c.update(_img_c)
		_upload_stage = -1 if _upload_stage >= 4 else _upload_stage + 1
		Prof.add("atlas_upload", Time.get_ticks_usec() - tu)


func _job(key: Vector2i) -> void:
	var blk := RoadField.build_block(roads, key.x, key.y, gen)
	blk["key"] = key
	_results_mutex.lock()
	_results.append(blk)
	_results_mutex.unlock()


func _apply() -> void:
	_results_mutex.lock()
	var take := mini(4, _results.size())
	var batch := _results.slice(0, take)
	_results = _results.slice(take)
	_results_mutex.unlock()
	for r: Dictionary in batch:
		var key: Vector2i = r["key"]
		_inflight.erase(key)
		var sx := posmod(key.x, SLOTS) * 40
		var sz := posmod(key.y, SLOTS) * 40
		_blit(_img_a, r["a"], sx, sz)
		_blit(_img_b, r["b"], sx, sz)
		_blit(_img_c, r["c"], sx, sz)
		_blit(_img_k1, r["k1"], sx, sz)
		_blit(_img_k2, r["k2"], sx, sz)
		_slot[Vector2i(posmod(key.x, SLOTS), posmod(key.y, SLOTS))] = key
		_dirty = true


## Блок 41x41 с заворачиванием через край окна (до 4 частей).
func _blit(dst: Image, src: Image, sx: int, sz: int) -> void:
	var w1 := mini(NODE, N - sx)
	var h1 := mini(NODE, N - sz)
	dst.blit_rect(src, Rect2i(0, 0, w1, h1), Vector2i(sx, sz))
	if w1 < NODE:
		dst.blit_rect(src, Rect2i(w1, 0, NODE - w1, h1), Vector2i(0, sz))
	if h1 < NODE:
		dst.blit_rect(src, Rect2i(0, h1, w1, NODE - h1), Vector2i(sx, 0))
		if w1 < NODE:
			dst.blit_rect(src, Rect2i(w1, h1, NODE - w1, NODE - h1), Vector2i(0, 0))
