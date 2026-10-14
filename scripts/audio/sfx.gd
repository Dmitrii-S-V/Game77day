class_name Sfx
extends RefCounted
## Звуки: assets/sounds/<имя>_<вариант>.wav (вариант выбирается случайно, высота ±7%) или <имя>.wav.
## play_at — 3D-звук в точке (узел удаляется сам), play_ui — без позиции. Фон (ветер, сверчки, птицы) — Ambience.

const DIR := "res://assets/sounds/"
static var _cache := {}   # имя -> Array[AudioStream]


static func streams(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var out: Array = []
	for v in 16:
		var s := _find(DIR + "%s_%d" % [name, v])
		if s != null:
			out.append(s)
		elif v > 0:
			break
	if out.is_empty():
		var s1 := _find(DIR + name)
		if s1 != null:
			out.append(s1)
	_cache[name] = out
	return out


## Имя звука, если он есть, иначе запасное (новые записанные звуки — с откатом на прежние).
static func pick(name: String, fallback: String) -> String:
	return name if not streams(name).is_empty() else fallback


## Загрузить все звуки заранее (при загрузке мира): первая загрузка файла посреди игры давала разовые фризы ~50 мс.
static func preload_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	var names := {}
	for f in d.get_files():
		var ext := f.get_extension()
		if ext == "import":
			f = f.get_basename()
			ext = f.get_extension()
		if not ext in ["ogg", "mp3", "wav"]:
			continue
		var base := f.get_basename()
		var us := base.rfind("_")
		if us > 0 and base.substr(us + 1).is_valid_int():
			base = base.substr(0, us)
		names[base] = true
	for n: String in names:
		streams(n)


## Записи (ogg, mp3) приоритетнее синтезированных wav с тем же именем.
static func _find(base: String) -> AudioStream:
	for ext in ["ogg", "mp3", "wav"]:
		if ResourceLoader.exists(base + "." + ext):
			return load(base + "." + ext)
	return null


static func play_at(ctx: Node, name: String, pos: Vector3, volume_db: float = 0.0, max_dist: float = 40.0, pitch_var: float = 0.07) -> void:
	var list := streams(name)
	if list.is_empty() or ctx == null or not ctx.is_inside_tree() or ctx.get_tree().current_scene == null:
		return     # нет сцены (тесты из --script) — тихо пропустить
	Net.echo_sfx(ctx, name, pos, volume_db, max_dist, pitch_var)   # сетевая игра: услышат и другие игроки
	var p := AudioStreamPlayer3D.new()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.max_distance = max_dist
	p.unit_size = 4.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	ctx.get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func play_ui(ctx: Node, name: String, volume_db: float = 0.0) -> void:
	var list := streams(name)
	if list.is_empty() or ctx == null or not ctx.is_inside_tree() or ctx.get_tree().current_scene == null:
		return
	# звуки рук своего игрока другие слышат в 3D у его модели
	if ctx is Player and name in ["swing", "gun_reload", "gun_dry", "drink"]:
		Net.echo_sfx(ctx, name, (ctx as Node3D).global_position + Vector3.UP * 1.4, volume_db + 4.0, 20.0, 0.06)
	var p := AudioStreamPlayer.new()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-0.06, 0.06)
	ctx.get_tree().current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Зацикленный фоновый поток (WAV из save_to_wav не хранит петлю — включаем её здесь).
static func loop_stream(name: String) -> AudioStream:
	var list := streams(name)
	if list.is_empty():
		return null
	var s: AudioStream = (list[0] as AudioStream).duplicate()
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	return s
