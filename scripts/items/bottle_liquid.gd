class_name BottleLiquid
extends RefCounted
## Поведение воды в бутылке: уровень остаётся горизонтальным (плоскость отсечения в мировых
## координатах) и плещется при ускорениях. Объём сохраняется для цилиндрической части.

var root: Node3D
var mat: ShaderMaterial
var fill := 1.0
var slosh := Vector2.ZERO
var slosh_v := Vector2.ZERO

var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _has_prev := false


func _init(r: Node3D, m: ShaderMaterial, f: float) -> void:
	root = r
	mat = m
	fill = f


func update(delta: float) -> void:
	if mat == null or root == null or not root.is_inside_tree():
		return
	var pos := root.global_position
	if _has_prev and delta > 0.0:
		var vel := (pos - _prev_pos) / delta
		var acc := (vel - _prev_vel) / delta
		_prev_vel = vel
		slosh_v += Vector2(-acc.x, -acc.z) * 0.012 * delta * 30.0 * 0.04
		slosh_v += Vector2(-acc.x, -acc.z) * 0.0006
	_prev_pos = pos
	_has_prev = true
	slosh_v += (-70.0 * slosh - 3.5 * slosh_v) * delta
	slosh += slosh_v * delta
	if slosh.length() > 0.8:
		slosh = slosh.normalized() * 0.8
	var axis := root.global_basis.y.normalized()
	var level := ItemModels.LIQ_BOTTOM + fill * ItemModels.LIQ_HEIGHT
	var point := pos + axis * level
	var normal := Vector3(slosh.x, 1.0, slosh.y).normalized()
	mat.set_shader_parameter("plane_point", point)
	mat.set_shader_parameter("plane_normal", normal)
