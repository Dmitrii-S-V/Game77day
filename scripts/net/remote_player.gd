class_name RemotePlayer
extends CharacterBody3D
## Другой игрок по сети: модель от третьего лица (PlayerAvatar) с именем над головой, плавно догоняет положение
## из его сообщений (Net._pstate, 20 раз в секунду). Для зомби хоста — такая же цель, как свой игрок
## (группа survivors, crouching/_sprinting/_dead_t, take_damage — урон уходит этому игроку по сети).
## Сталкивается с зомби и игроками (слой игрока 4), но удары игроков по нему не проходят (нет урона друг другу).

var peer_id := 0
var display_name := ""
var crouching := false
var _sprinting := false
var flying := false
var _dead_t := 0.0
var avatar: PlayerAvatar

var _to := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _speed := 0.0
var _last_pos := Vector3.ZERO
var _last_ms := 0
var _act_seq := -1
var _snap := true


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	add_to_group("survivors")
	avatar = PlayerAvatar.new()
	add_child(avatar)
	avatar.build(PlayerAvatar.tint_for(peer_id), display_name)
	_to = position
	_last_pos = position


func apply_state(pos: Vector3, yaw: float, pitch: float, flags: int, item: String, act_seq: int, act: String) -> void:
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		var dt := maxf((now - _last_ms) / 1000.0, 0.02)
		var v := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / dt
		_speed = lerpf(_speed, v, 0.5)
	_last_ms = now
	_last_pos = pos
	if _snap or pos.distance_to(global_position) > 8.0:
		global_position = pos     # первый раз / телепорт (возрождение) — без «пролёта»
		_snap = false
	_to = pos
	_yaw = yaw
	_pitch = pitch
	crouching = (flags & 1) != 0
	_sprinting = (flags & 2) != 0
	_dead_t = 1.0 if (flags & 4) != 0 else 0.0
	flying = (flags & 8) != 0
	avatar.set_backpack((flags & 16) != 0)
	avatar.set_item(item)
	if act_seq != _act_seq:
		if _act_seq >= 0 and act != "":
			avatar.play_action(act)
		_act_seq = act_seq


func _physics_process(delta: float) -> void:
	# догоняет присланное положение (между сообщениями — плавно)
	global_position = global_position.lerp(_to, 1.0 - exp(-delta * 14.0))
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-delta * 14.0))
	avatar.animate(delta, 0.0 if flying else _speed, crouching, _pitch, _dead_t > 0.0)


## Урон от зомби (на хосте) — этому игроку по сети.
func take_damage(amount: float) -> void:
	if _dead_t > 0.0 or not Net.is_host():
		return
	Net.inst.damage_remote(peer_id, amount)
