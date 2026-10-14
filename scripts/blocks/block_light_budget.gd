extends Node
## Бюджет источников света построек: активны только ближайшие к камере (max_active), остальные выключены.
## Тени у этих источников выключены, дальше fade_begin свет гаснет сам (distance_fade).
## Мерцание: энергия свечи колеблется по шуму от времени.

var _t := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.frequency = 1.0
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


func _process(delta: float) -> void:
	_t += delta
	var lights := BlockBuilding.registered_lights()
	var cam := get_viewport().get_camera_3d()
	var maxn := int(BlockRegistry.lights_cfg().get("max_active", 8))
	# мерцание каждый кадр
	for l in lights:
		if is_instance_valid(l) and (l as Light3D).visible:
			var f := float(l.get_meta("flicker", 0.0))
			if f > 0.0:
				var n := _noise.get_noise_1d(_t * 6.0 + float(l.get_meta("phase", 0.0))) * 0.5 + _noise.get_noise_1d(_t * 17.0 + 31.0) * 0.25
				(l as Light3D).light_energy = float(l.get_meta("base_energy", 1.0)) * (1.0 + n * f)
	# выбор ближайших — реже
	if int(_t * 4.0) == int((_t - delta) * 4.0):
		return
	if cam == null:
		return
	var cp := cam.global_position
	var valid: Array = []
	for l in lights.duplicate():
		if is_instance_valid(l):
			valid.append(l)
		else:
			lights.erase(l)
	valid.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(cp) < b.global_position.distance_squared_to(cp))
	for i in valid.size():
		(valid[i] as Light3D).visible = i < maxn
