class_name Ambience
extends Node
## Фон: ветер всегда (сильнее на высоте и в выжженном биоме), птицы днём, сверчки ночью (петли записей CC0),
## изредка — вороны в стороне.

var main: Node              # main.gd (time_of_day, player, _burn)
var _wind: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _crow_t := 20.0


func _ready() -> void:
	_wind = _loop("wind_loop")
	_crickets = _loop("crickets_loop")
	_birds = _loop("birds_loop")


func _loop(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.loop_stream(name)
	p.volume_db = -80.0
	add_child(p)
	if p.stream != null:
		p.play(randf() * maxf(p.stream.get_length() - 1.0, 0.0))   # с разных мест петли — меньше узнаваемых повторов
	return p


func _fade(p: AudioStreamPlayer, lin: float, delta: float, speed: float) -> void:
	p.volume_db = lerpf(p.volume_db, linear_to_db(maxf(lin, 0.0001)), 1.0 - exp(-delta * speed))


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var tod: float = main.time_of_day
	var night := clampf((absf(tod - 0.5) - 0.27) / 0.06, 0.0, 1.0)   # 0 днём, 1 ночью (переход на закате/рассвете)
	var pos: Vector3 = main.player.global_position
	var ground: float = main.terrain.gen.height_at(pos.x, pos.z)
	var height := clampf((pos.y - ground) / 40.0, 0.0, 1.0)
	var burn: float = main._burn
	_fade(_wind, 0.16 + 0.35 * height + 0.25 * burn, delta, 2.0)
	_fade(_crickets, night * (1.0 - burn) * (1.0 - height) * 0.45, delta, 1.5)
	_fade(_birds, (1.0 - night) * (1.0 - burn) * (1.0 - height) * 0.3, delta, 1.0)
	_crow_t -= delta
	if _crow_t <= 0.0:
		_crow_t = randf_range(40.0, 120.0)
		if night < 0.5:
			var a := randf() * TAU
			Sfx.play_at(self, "crow", pos + Vector3(cos(a) * 40.0, 12.0, sin(a) * 40.0), -6.0, 120.0, 0.05)
