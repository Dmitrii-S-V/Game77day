class_name DynamicRes
extends Node
## Автоподстройка разрешения 3D под нагрузку (телефон): FPS ниже цели — разрешение (FSR) ступенчато падает,
## запас по FPS — возвращается к значению из настроек графики. Включается на мобильных и с аргументом --dynres.
## Меняет только scaling_3d_scale окна; пресет графики задаёт потолок.

const TARGET_FPS := 30.0
const MIN_SCALE := 0.45
const STEP := 0.05
const WINDOW := 1.0          # секунд на одно решение
const UP_AFTER := 4          # окон подряд с запасом, прежде чем поднять разрешение

var _acc := 0.0
var _frames := 0
var _good := 0
var current := 1.0           # текущий масштаб (для отладки/теста)


static func wanted() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--dynres")


func _ready() -> void:
	current = _ceiling()


## Потолок — масштаб из пресета графики (на «Минимальных» 0.67).
func _ceiling() -> float:
	return float(GraphicsSettings.preset()["scale"])


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	if _acc < WINDOW:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	var ceil_s := _ceiling()
	var s := minf(current, ceil_s)    # пресет могли понизить в меню графики
	if fps < TARGET_FPS * 0.9:
		_good = 0
		s = maxf(MIN_SCALE, s - STEP * (2.0 if fps < TARGET_FPS * 0.6 else 1.0))
	elif fps > TARGET_FPS * 1.6:
		_good += 1
		if _good >= UP_AFTER:
			_good = 0
			s = minf(ceil_s, s + STEP)
	else:
		_good = 0
	if not is_equal_approx(s, current):
		current = s
		_apply(s)


func _apply(s: float) -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s
