class_name Zombie
extends CharacterBody3D
## Зомби по образцу 7 Days to Die. Чувства: зрение (конус ~120°, луч до игрока; ночью и пригнувшись — ближе)
## и слух (шум игрока: шаги, удары, двери — ZombieDirector.noise). Состояния: бродит, идёт проверить шум,
## преследует (днём шагом, ночью и в кровавую луну — бегом), спит в здании (будят шум и игрок вблизи),
## идёт с бродячей ордой. Упёрся в постройку — ломает блоки на пути к цели. Голова — двойной урон.
## Труп остаётся на земле, его можно обыскать (E). Модель: assets/ready/zombie_friend.glb (иначе процедурное тело).

signal killed(z: Zombie)

const LAYER := 16            # слой столкновений живых зомби
const CORPSE_LAYER := 8      # трупы: игрок проходит сквозь, но может обыскать/ударить
const HP_MAX := 300.0
const ATTACK_RANGE := 1.45
const ATTACK_DMG := 12.0
const ATTACK_CD := 1.3
const BLOCK_DMG := 18.0      # урон блоку за удар (множители — tool «zombie» в data/blocks/materials.json)
const CORPSE_TIME := 90.0

enum S { IDLE, INVESTIGATE, CHASE, SLEEP, HORDE }

var player: Node3D
var gen: WorldGen             # высота поверхности (страховка от провала)
var night := false            # ночью бегут, но видят хуже (задаёт ZombieDirector)
var blood_moon := false       # орда кровавой луны: всегда знает, где игрок, бежит
var feral := false            # дикий: бежит и днём
var kind := ""                # кто создал: biome | sleeper | horde | blood (для ZombieDirector)
var home := Vector2i.ZERO     # клетка появления (biome)
var home_key := ""            # здание (sleeper)
var state := S.IDLE
var target := Vector3.ZERO    # куда идти: шум, последнее место игрока, цель орды
var hp := HP_MAX
var dead := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _parts := {}              # имя -> Node3D (суставы процедурного тела)
var _model: Node3D
var _meshes: Array = []
var _shadows := true
var _cs: CollisionShape3D
var _phase := 0.0
var _attack_t := 0.0          # >0 — идёт удар
var _attack_block := {}       # удар по блоку постройки: {bb, pos, nrm, col}
var _cd := 0.0
var _stagger := 0.0
var _groan_t := 0.0
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _dead_t := 0.0
var _sense_t := 0.0
var _sees := false
var _lost_t := 0.0            # сколько не видит игрока (в погоне)
var _look_t := 0.0            # осматривается на месте после проверки шума
var _side := 1.0              # сторона обхода препятствия
var _stuck_t := 0.0
var _block_hold := 0.0        # >0 — ломает блок постройки перед собой
var _speed_k := 1.0
# LOD и плавность
const SIMPLE_DIST := 28.0     # дальше — упрощённое движение
const SIMPLE_DT := 1.0 / 15.0
const SENSE_DT := 0.5         # как часто зомби «смотрит» (луч до игрока) и пересматривает решения
var terrain: Terrain          # высота поверхности для упрощённого движения (с учётом выкопанного)
var _simple := false
var _acc := 0.0
var _far_anim := false
var _anim_acc := 0.0
var _vis: VisibleOnScreenNotifier3D
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _cur_yaw := 0.0
var _teleported := false
var _tilt := Quaternion.IDENTITY   # наклон трупа по склону
var _mscale := 1.0
var _ground_y := NAN               # кэш высоты поверхности (упрощённое движение)
var _ground_at := Vector2(1e9, 1e9)

## Заметность (0..100): растёт, пока зомби видит игрока (быстрее вблизи, на бегу) и от его шума; сама спадает.
## 35+ — идёт проверить, 100 — заметил (погоня). Если 100 набралось от звука — с шансом 50% всё же не заметил:
## шкала откатывается, зомби только идёт проверить шум.
const AW_NOTICE := 100.0
const AW_INVESTIGATE := 35.0
const AW_DECAY := 7.0          # в секунду, когда нет ни вида, ни звука
const AW_HOLD := 1.5           # после стимула шкала столько секунд не спадает
const AW_SOUND_K := 65.0       # шум громкостью 1.0 (у самого источника) даёт +65
const AW_SOUND_MISS := 0.5     # шанс не заметить, когда шкала заполнилась от звука
const AW_MISS_BACK := 70.0     # куда откатывается шкала после «не заметил»
var awareness := 0.0
var aw_target: Node3D          # кого почуял (на кого смотрит/чей шум)
var _aw_hold := 0.0
static var sound_misses := 0   # для тестов: сколько раз «не заметил» от звука

## Сеть: на хосте зомби настоящий (ИИ), у клиентов — «марионетка» (puppet): положение, анимация и события с хоста.
static var _next_id := 1
static var by_id := {}         # net_id -> Zombie
var net_id := 0
var puppet := false
var last_hitter := 1           # peer id того, кто ударил последним (засчитать убийство)
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_anim := ""
var _net_spd := 1.0
var net_seen_ms := 0
var aw_mine := 0.0             # (марионетка) заметность своего игрока этим зомби


func _ready() -> void:
	if net_id == 0:
		net_id = _next_id
		_next_id += 1
	by_id[net_id] = self
	_net_pos = position
	_net_yaw = rotation.y
	collision_layer = LAYER
	collision_mask = 1 | 2 | 4 | LAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	_cs = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = float(_type()["height"])
	_cs.shape = cap
	_cs.position.y = cap.height * 0.5
	add_child(_cs)
	_speed_k = randf_range(0.85, 1.15)
	_groan_t = randf_range(1.0, 6.0)
	_sense_t = randf() * SENSE_DT     # разные зомби «думают» в разные кадры
	max_slides = 4
	_build_body()
	_meshes = find_children("*", "MeshInstance3D", true, false)
	_vis = VisibleOnScreenNotifier3D.new()
	_vis.aabb = AABB(Vector3(-0.8, 0.0, -1.5), Vector3(1.6, 2.0, 2.3))
	add_child(_vis)
	_prev_pos = global_position
	_cur_pos = global_position
	_prev_yaw = rotation.y
	_cur_yaw = rotation.y


## Тени дальних зомби выключаются (ZombieDirector по расстоянию).
func set_shadows(on: bool) -> void:
	if on == _shadows:
		return
	_shadows = on
	for mi: MeshInstance3D in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func sleep() -> void:
	state = S.SLEEP


# --- тело ---------------------------------------------------------------------------

func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _caps(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	_parts[name] = j
	return j


## Типы зомби: модель со скелетом и анимациями (scripts/ai3d/zombie_rig.py): idle, walk, run, attack, hit, death
## (+ у прыгуна crouch и leap). corpse_z — где лежит труп (friend падает навзничь, mudworn — ничком),
## head — высота, выше которой попадание считается в голову; walk_spd — скорость шага анимации walk (м/с, мокап).
const TYPES := {
	"friend": {"model": "res://assets/ready/zombie_friend.glb", "height": 1.75, "head": 1.45, "corpse_z": -0.45, "leaper": false, "walk_spd": 0.47},
	"mudworn": {"model": "res://assets/ready/zombie_mudworn.glb", "height": 1.62, "head": 1.33, "corpse_z": -0.45, "leaper": true, "walk_spd": 0.4},
}
const MODEL := "res://assets/ready/zombie_friend.glb"
static var _scenes := {}
var ztype := "friend"         # задаётся до add_child (ZombieDirector)
var _anim: AnimationPlayer
var _cur := ""


## Загрузить модели заранее (на экране загрузки), а не при первом появлении зомби.
static func preload_model() -> void:
	for t: String in TYPES:
		var path: String = TYPES[t]["model"]
		if not _scenes.has(t) and ResourceLoader.exists(path):
			_scenes[t] = load(path) as PackedScene


func _type() -> Dictionary:
	return TYPES.get(ztype, TYPES["friend"])


func _build_model() -> bool:
	if not _scenes.has(ztype):
		preload_model()
		if not _scenes.has(ztype):
			return false
	var m := (_scenes[ztype] as PackedScene).instantiate() as Node3D
	_mscale = randf_range(0.95, 1.05)
	m.scale = Vector3.ONE * _mscale
	m.top_level = true      # положение модели задаётся в _process (сглаживание между шагами физики)
	add_child(m)
	m.global_transform = Transform3D(Basis(Vector3.UP, rotation.y).scaled(Vector3.ONE * _mscale), position)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		m.queue_free()
		return false
	_model = m
	# свой визуальный слой: декали крови (Blood, cull_mask 1) ложатся на землю, а не на тело
	for mi: VisualInstance3D in m.find_children("*", "VisualInstance3D", true, false):
		mi.layers = 2
	_anim = aps[0] as AnimationPlayer
	for nm in ["idle", "walk", "run", "crouch"]:
		if _anim.has_animation(nm):
			_anim.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	_anim.playback_default_blend_time = 0.2
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # обновляем сами (реже вдали)
	_play("idle")
	_anim.seek(randf() * 1.5, true)   # разные зомби — не в одну фазу
	return true


func _play(nm: String, spd: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(nm):
		return
	_anim.speed_scale = spd
	if nm != _cur:
		_cur = nm
		_anim.play(nm, 0.18)


func _build_body() -> void:
	if _build_model():
		return
	var skin := _mat(Color(0.47, 0.5, 0.4).lerp(Color(0.55, 0.47, 0.42), randf()), 0.75)
	var shirt := _mat([Color(0.25, 0.27, 0.3), Color(0.38, 0.3, 0.22), Color(0.4, 0.12, 0.1), Color(0.55, 0.53, 0.48)][randi() % 4])
	var pants := _mat([Color(0.16, 0.18, 0.24), Color(0.22, 0.2, 0.16), Color(0.12, 0.12, 0.12)][randi() % 3])
	var dark := _mat(Color(0.08, 0.05, 0.05), 0.4)
	var blood := _mat(Color(0.25, 0.04, 0.03), 0.5)
	var root := _joint(self, "root", Vector3.ZERO)
	var hips := _joint(root, "hips", Vector3(0, 0.95, 0))
	# туловище наклонено вперёд (сутулость)
	var spine := _joint(hips, "spine", Vector3(0, 0.05, 0))
	spine.rotation.x = -0.28
	_box(spine, Vector3(0.46, 0.6, 0.27), Vector3(0, 0.3, 0), shirt)
	_box(hips, Vector3(0.4, 0.2, 0.25), Vector3(0, -0.02, 0), pants)   # таз
	_box(spine, Vector3(0.16, 0.12, 0.02), Vector3(0.08, 0.38, 0.125), blood)   # пятно крови
	var neck := _joint(spine, "neck", Vector3(0, 0.6, 0.02))
	_caps(neck, 0.06, 0.16, Vector3(0, 0.04, 0), skin)
	var head := _joint(neck, "head", Vector3(0, 0.14, 0))
	head.rotation = Vector3(0.25, 0.0, randf_range(-0.35, 0.35))   # голова свёрнута набок
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.27
	hm.mesh = sm
	hm.material_override = skin
	hm.position = Vector3(0, 0.1, 0)
	head.add_child(hm)
	for sx in [-0.045, 0.045]:
		_box(head, Vector3(0.04, 0.025, 0.02), Vector3(sx, 0.12, 0.112), dark)   # глазницы
	_box(head, Vector3(0.07, 0.025, 0.02), Vector3(0, 0.04, 0.11), dark)          # рот
	for side in [-1.0, 1.0]:
		var nm := "l" if side < 0.0 else "r"
		var sh := _joint(spine, nm + "_shoulder", Vector3(0.25 * side, 0.52, 0))
		_caps(sh, 0.07, 0.36, Vector3(0, -0.14, 0), shirt)
		var el := _joint(sh, nm + "_elbow", Vector3(0, -0.3, 0))
		_caps(el, 0.055, 0.32, Vector3(0, -0.13, 0), skin)
		_box(el, Vector3(0.08, 0.11, 0.045), Vector3(0, -0.3, 0), skin)
		var hp_ := _joint(hips, nm + "_hip", Vector3(0.11 * side, -0.02, 0))
		_caps(hp_, 0.1, 0.5, Vector3(0, -0.22, 0), pants)
		var kn := _joint(hp_, nm + "_knee", Vector3(0, -0.45, 0))
		_caps(kn, 0.08, 0.48, Vector3(0, -0.22, 0), pants)
		_box(kn, Vector3(0.12, 0.08, 0.26), Vector3(0, -0.46, 0.05), dark)        # ботинок
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- урон и смерть ----------------------------------------------------------------

## Удар игрока. hit_pos — точка попадания (выше 1.45 м от ног — голова, урон x2). kind — чем ударили:
## "fist" кулак, "bat" бита, "melee" прочее ближнее, "gun" огнестрел; bonus — прибавка к шансам (уровень биты).
func take_hit(dmg: float, dir: Vector3, hit_pos: Vector3 = Vector3.INF, kind: String = "melee", bonus: float = 0.0,
		from: Node3D = null, by_peer: int = 1) -> void:
	if dead or puppet:
		return
	last_hitter = by_peer
	_last_hit_dir = dir      # до сбивания: ragdoll падает по направлению этого удара
	if from != null and is_instance_valid(from):
		player = from        # бьющий — сразу цель
	var head := hit_pos != Vector3.INF and hit_pos.y - global_position.y > float(_type()["head"])
	if head:
		dmg *= 2.0
	hp -= dmg
	# сбить с ног / оглушить (шансы — chances(); лежачего удар роняет снова лишь с шансом 10%)
	var ch := chances(kind, bonus)
	if _down_t > 0.0 or _kphase > 0:
		if randf() < KNOCK_AGAIN:
			_knock_down()
	elif randf() < float(ch["knock"]):
		_knock_down()
	elif randf() < float(ch["stun"]):
		_stagger = STUN_TIME      # стоит на месте, замах сорван
		_attack_t = 0.0
		_attack_block = {}
	if player != null and is_instance_valid(player):
		aw_target = player
		_alert(player.global_position)
	if _kphase == 0 and _down_t <= 0.0:
		# толчок: заметный — только при оглушении; обычный удар — лёгкое вздрагивание (без «стана» каждым ударом)
		var push := 3.0 if _stagger >= STUN_TIME - 0.01 else 0.6
		velocity += Vector3(dir.x, 0.0, dir.z).normalized() * push + Vector3.UP * (1.0 if push > 1.0 else 0.0)
	_last_hit_dir = dir
	if hp <= 0.0:
		_die()
	else:
		_voice("hurt", 0.0, 40.0)


## Шансы при попадании (без прокачки персонажа/баффов): сбить с ног — кулак 25%, бита 33%, прочее оружие
## (и огнестрел) 15%; оглушить на STUN_TIME — ближний бой 25%, огнестрел 20%. Бита: +3% к обоим за уровень (bonus).
const KNOCK_CHANCE := {"fist": 0.25, "bat": 0.33, "melee": 0.15, "gun": 0.15}
const STUN_CHANCE := {"fist": 0.25, "bat": 0.25, "melee": 0.25, "gun": 0.2}
const STUN_TIME := 1.0
const KNOCK_AGAIN := 0.1


static func chances(kind: String, bonus: float = 0.0) -> Dictionary:
	return {"knock": float(KNOCK_CHANCE.get(kind, 0.15)) + bonus, "stun": float(STUN_CHANCE.get(kind, 0.25)) + bonus}
const DOWN_TIME := 3.4      # с: падение (анимация death ~1.2 с) + лежит + подъём
const GETUP_TIME := 1.3     # последние секунды — встаёт (death задом наперёд)
var _down_t := 0.0          # > 0 — сбит с ног


## Сбит с ног: ragdoll (тело падает по физике и сразу замирает), лежит, поза перетекает в лежачую позу анимации
## death, зомби встаёт (death задом наперёд). Без ragdoll (лимит одновременных) — падение анимацией death.
## Повторный сбив, пока лежит, — снова полное время на земле.
const LIE_TIME := 1.4       # лежит после того, как тело замерло
const BLEND_TIME := 0.45    # поза ragdoll -> лежачая поза death
var _kphase := 0            # ragdoll-сбивание: 0 нет, 1 падает, 2 лежит, 3 перетекает, 4 встаёт
var _kt := 0.0
var _knock_rd: ZombieRagdoll
var _kfrom: Array = []      # [позиция, поворот] костей из ragdoll
var _kto: Array = []        # [позиция, поворот] костей лежачей позы death


func _knock_down() -> void:
	if _kphase == 1:
		return
	if _kphase == 2:
		_kt = maxf(_kt, LIE_TIME)    # лежит дольше
		return
	_net_ev("knock")
	if _model != null and _knock_ragdoll():
		_attack_t = 0.0
		_leap_state = 0
		_stagger = 0.0
		_down_t = 0.0
		return
	_knock_anim()


## Событие для марионеток у клиентов (только на хосте сетевой игры).
func _net_ev(ev: String, extra: int = 0) -> void:
	if not puppet and Net.is_host():
		Net.inst.zevent(net_id, ev, _last_hit_dir, extra)


func _knock_ragdoll() -> bool:
	if _knock_rd != null and is_instance_valid(_knock_rd):
		_knock_rd.cancel()
	var rd := ZombieRagdoll.new()
	rd.knock = true
	var hd := Vector3(_last_hit_dir.x, 0.0, _last_hit_dir.z).normalized()
	if not rd.setup(self, _model, hd * 24.0 + Vector3.UP * 5.0, Vector3(velocity.x, 0.0, velocity.z)):
		return false
	add_child(rd)
	_knock_rd = rd
	_kphase = 1
	_kt = 0.0
	velocity = Vector3.ZERO
	# по падающему телу можно попасть (кости — на слое живых зомби); стоячая капсула выключена — по воздуху не бьётся
	for pb in rd._bones:
		pb.collision_layer = ZombieRagdoll.LAYER | LAYER
	_save_capsule()
	_cs.disabled = true
	return true


var _cap_shape: Shape3D
var _cap_xf := Transform3D.IDENTITY


func _save_capsule() -> void:
	if _cap_shape == null and _cs.shape is CapsuleShape3D:
		_cap_shape = _cs.shape
		_cap_xf = _cs.transform


func _restore_capsule() -> void:
	if _cap_shape != null:
		_cs.shape = _cap_shape
		_cs.transform = _cap_xf
	_cs.disabled = false


## Зомби, которому принадлежит коллайдер (сам зомби или кость его ragdoll), иначе null.
static func of(obj: Object) -> Zombie:
	var n := obj as Node
	for i in 8:
		if n == null:
			return null
		if n is Zombie:
			return n
		n = n.get_parent()
	return null


## Ragdoll сбивания замер: тело лежит в позе падения; попадать — по коробке вдоль лежащего тела.
func on_knock_settled() -> void:
	_kphase = 2
	_kt = LIE_TIME
	var a := to_local(_knock_rd.bone_global("hips"))
	var b := to_local(_knock_rd.bone_global("head"))
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.4, maxf(a.distance_to(b), 0.6) + 0.5)
	_cs.shape = box
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var mid := (a + b) * 0.5
	_cs.transform = Transform3D(Basis(Vector3.UP, atan2(flat.x, flat.z)) if flat.length() > 0.05 else Basis(), Vector3(mid.x, minf(a.y, b.y) + 0.2, mid.z))
	_cs.disabled = false


func _knock_step(delta: float) -> void:
	_stagger = maxf(_stagger, 0.01)    # не ходит и не бьёт
	velocity = Vector3(0.0, velocity.y, 0.0)
	match _kphase:
		2:
			_kt -= delta
			if _kt <= 0.0:
				_begin_getup()
		3:
			_kt -= delta
			var s := smoothstep(0.0, 1.0, 1.0 - _kt / BLEND_TIME)
			var sk := _knock_rd.skel
			for i in _kfrom.size():
				sk.set_bone_pose_position(i, (_kfrom[i][0] as Vector3).lerp(_kto[i][0], s))
				sk.set_bone_pose_rotation(i, (_kfrom[i][1] as Quaternion).slerp(_kto[i][1], s))
			if _kt <= 0.0:
				_kphase = 4
				_kt = GETUP_TIME
				_restore_capsule()     # встаёт — снова обычная капсула (зомби уже перенесён к телу)
				_anim.active = true
				_cur = "getup"
				_anim.speed_scale = 1.0
				_anim.play("death", 0.0, -_anim.get_animation("death").length / GETUP_TIME, true)
				_anim.advance(0.0)
		4:
			_kt -= delta
			if _kt <= 0.0:
				_kphase = 0
				if _knock_rd != null and is_instance_valid(_knock_rd):
					_knock_rd.queue_free()
				_knock_rd = null


## Подъём из позы ragdoll: модель ставится так, чтобы лежачая поза death совпала с телом (таз на месте, по
## направлению таз→голова), поза костей плавно перетекает в неё, затем — death задом наперёд.
func _begin_getup() -> void:
	var sk := _knock_rd.skel
	var n := sk.get_bone_count()
	var hips_i := ZombieRagdoll.bone_index(sk, "hips")
	var head_i := ZombieRagdoll.bone_index(sk, "head")
	if hips_i < 0 or head_i < 0 or _anim == null or not _anim.has_animation("death"):
		_kphase = 0
		_anim.active = true
		return
	var world: Array[Transform3D] = []
	for i in n:
		world.append(sk.global_transform * sk.get_bone_global_pose(i))
	var m_s := _model.global_transform.affine_inverse() * sk.global_transform   # скелет в системе модели
	# лежачая поза death (последний кадр)
	_anim.active = true
	_anim.play("death", 0.0, 1.0)
	_anim.seek(_anim.get_animation("death").length, true)
	_kto.clear()
	for i in n:
		_kto.append([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i)])
	var hd := m_s * sk.get_bone_global_pose(hips_i).origin
	var dd := m_s * sk.get_bone_global_pose(head_i).origin - hd
	_anim.active = false
	# куда поставить модель: таз — на тело, голова — в ту же сторону
	var hr: Vector3 = world[hips_i].origin
	var dr: Vector3 = world[head_i].origin - hr
	var yaw := atan2(dr.x, dr.z) - atan2(dd.x, dd.z)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _mscale)
	var o := hr - b * hd
	var q := PhysicsRayQueryParameters3D.create(hr + Vector3.UP * 0.6, hr + Vector3.DOWN * 2.5, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	o.y = (hit["position"] as Vector3).y if not hit.is_empty() else o.y
	_model.global_transform = Transform3D(b, o)
	# поза ragdoll в новой системе модели
	var skg := sk.global_transform.affine_inverse()
	var g: Array[Transform3D] = []
	for i in n:
		g.append(skg * world[i])
	_kfrom.clear()
	for i in n:
		var p := sk.get_bone_parent(i)
		var l := g[i] if p < 0 else g[p].affine_inverse() * g[i]
		_kfrom.append([l.origin, l.basis.orthonormalized().get_rotation_quaternion()])
		sk.set_bone_pose_position(i, l.origin)
		sk.set_bone_pose_rotation(i, l.basis.orthonormalized().get_rotation_quaternion())
	# сам зомби — туда же (после подъёма идёт оттуда)
	global_position = o
	rotation.y = yaw
	_prev_pos = o
	_cur_pos = o
	_prev_yaw = yaw
	_cur_yaw = yaw
	_tilt = Quaternion.IDENTITY
	_kphase = 3
	_kt = BLEND_TIME


## Сбросить сбивание (тесты): ragdoll убрать, анимацию вернуть.
func reset_knock() -> void:
	if _knock_rd != null and is_instance_valid(_knock_rd):
		_knock_rd.cancel()
	_knock_rd = null
	_kphase = 0
	_down_t = 0.0
	_restore_capsule()
	if _anim != null:
		_anim.active = true


## Падение анимацией (запасной вариант без ragdoll).
func _knock_anim() -> void:
	var was_getting_up := _down_t > 0.0 and _down_t <= GETUP_TIME
	_down_t = DOWN_TIME if (_down_t <= 0.0 or was_getting_up) else maxf(_down_t, DOWN_TIME - 1.2)
	if was_getting_up:
		_cur = ""          # снова падение с начала
	_attack_t = 0.0
	_leap_state = 0
	_stagger = 0.0


func _die() -> void:
	dead = true
	_down_t = 0.0
	_net_ev("die", last_hitter)
	# умер, пока падал после сбивания: тот же ragdoll становится смертельным (дальше — гниение)
	if _kphase == 1 and _knock_rd != null and is_instance_valid(_knock_rd):
		_kphase = 0
		_knock_rd.knock = false
		for pb in _knock_rd._bones:
			pb.collision_layer = ZombieRagdoll.LAYER     # смертельный ragdoll — как обычно
		_ragdoll = _knock_rd
		_knock_rd = null
		_simple = false
		_dead_t = CORPSE_TIME
		_attack_t = 0.0
		set_meta("loot", "zombie")
		_voice("death", 2.0, 45.0)
		killed.emit(self)
		collision_layer = 0
		collision_mask = 0
		_cs.disabled = true
		velocity = Vector3.ZERO
		return
	if _kphase > 0:
		_kphase = 0
		if _knock_rd != null and is_instance_valid(_knock_rd):
			_knock_rd.queue_free()   # лежал/вставал: смертельный ragdoll — заново из текущей позы
		_knock_rd = null
		_restore_capsule()
		if _anim != null:
			_anim.active = true
	_simple = false
	_dead_t = CORPSE_TIME
	_attack_t = 0.0
	set_meta("loot", "zombie")
	_voice("death", 2.0, 45.0)
	killed.emit(self)
	# ragdoll: тело падает по физике (толчок от удара, инерция бега); потом поза фиксируется, тело гниёт до костей
	if _model != null:
		var rd := ZombieRagdoll.new()
		var hd := Vector3(_last_hit_dir.x, 0.0, _last_hit_dir.z).normalized()
		if rd.setup(self, _model, hd * 38.0 + Vector3.UP * 10.0, Vector3(velocity.x, maxf(velocity.y, 0.0), velocity.z)):
			add_child(rd)
			_ragdoll = rd
			collision_layer = 0
			collision_mask = 0
			_cs.disabled = true
			velocity = Vector3.ZERO
			return
	velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
	Blood.pool(self, global_position + global_basis * Vector3(0, 0, float(_type()["corpse_z"])))
	# труп без ragdoll: лежачая коробка вдоль тела (анимация death кладёт его на спину, голова назад, -Z)
	collision_layer = CORPSE_LAYER
	collision_mask = 1 | 2
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.3, 1.9)
	_cs.shape = box
	_cs.position = Vector3(0.0, 0.15, float(_type()["corpse_z"]))
	_cs.rotation = Vector3.ZERO


var _ragdoll: ZombieRagdoll
var _last_hit_dir := Vector3.FORWARD


## Ragdoll лёг: под телом растекается кровь; коллайдер для обыска (E) — коробка вдоль тела от таза до головы.
func on_ragdoll_settled(hips: Vector3, chest: Vector3, head: Vector3) -> void:
	Blood.pool(self, hips.lerp(chest, 0.4) + Vector3.DOWN * 0.1)
	var a := to_local(hips)
	var b := to_local(head)
	var mid := (a + b) * 0.5
	var len := maxf(a.distance_to(b), 0.6)
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.35, len + 0.5)
	_cs.shape = box
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	_cs.transform = Transform3D(Basis(Vector3.UP, atan2(flat.x, flat.z)) if flat.length() > 0.05 else Basis(), Vector3(mid.x, minf(a.y, b.y) + 0.15, mid.z))
	_cs.disabled = false
	collision_layer = CORPSE_LAYER
	collision_mask = 0


func _exit_tree() -> void:
	if by_id.get(net_id) == self:
		by_id.erase(net_id)
	if dead:
		Loot.forget(global_position)


# --- чувства -------------------------------------------------------------------------

## Шум (ZombieDirector.noise): loud 0..1 — насколько громко слышно здесь; src — кто шумел (игрок) или null.
## Шум наполняет шкалу заметности: 35+ — идёт проверить, 100 — с шансом 50% заметил (погоня), иначе шкала
## откатывается до 70 и он только проверяет шум. Спящий просыпается, когда шкала дойдёт до его порога (25–75).
func hear(pos: Vector3, loud: float, src: Node3D = null) -> void:
	if dead or blood_moon or puppet:
		return
	if state == S.CHASE and _sees:
		return
	if state == S.SLEEP:
		# спящий: будит только шум вплотную (до 2 блоков от него) — и сразу в полную силу
		if global_position.distance_to(pos) > WAKE_NOISE_R + 0.3:
			return
		_wake()
		awareness = AW_NOTICE
		if src != null and is_instance_valid(src):
			player = src
			aw_target = src
		_alert(pos if src == null else src.global_position)
		return
	awareness = minf(AW_NOTICE, awareness + loud * AW_SOUND_K)
	_aw_hold = AW_HOLD
	if src != null:
		aw_target = src
	# чем тише, тем неточнее понятно, откуда звук
	var err := global_position.distance_to(pos) * 0.2 * (1.0 - loud)
	var spot := pos + Vector3(randf_range(-err, err), 0.0, randf_range(-err, err))
	if awareness >= AW_NOTICE and state != S.CHASE:
		if randf() < AW_SOUND_MISS:
			# шкала заполнилась от звука, но зомби не понял, что это игрок: только проверит
			sound_misses += 1
			awareness = AW_MISS_BACK
		else:
			if src != null and is_instance_valid(src):
				player = src
			_alert(spot)
			return
	if awareness < AW_INVESTIGATE:
		return       # еле слышно: шкала растёт, но с места не сходит
	target = spot
	if state != S.CHASE:
		state = S.INVESTIGATE
		_look_t = 0.0


## Во сколько раз зрение и слух зомби короче исходных (зрение днём 32 / ночью 13 м, радиусы шумов — в коде игрока):
## 1.5 → днём ~21 м, ночью ~9 м, выстрел ~47 м, бег 16 м, шаг ~7 м, крадучись 2 м.
const SENSE_RANGE_DIV := 1.5


## Спящие (зоны спавна в зданиях) просыпаются только от: урона, триггерной зоны своего цвета, шума ближе 2 блоков.
const WAKE_NOISE_R := 2.0
var wake_color := ""           # цвет зоны спавна (её будит триггер того же цвета в том же здании)


## Триггерная зона: проснуться и сразу заметить того, кто наступил.
func wake_by_trigger(who: Node3D) -> void:
	if dead or state != S.SLEEP:
		return
	_wake(true)
	if who != null and is_instance_valid(who):
		player = who
		aw_target = who
		_alert(who.global_position)


func _wake(silent := false) -> void:
	state = S.IDLE
	_stagger = 0.5    # вздрагивает (анимация hit)
	if not silent:
		_voice("groan", 0.0, 40.0)
	_groan_t = randf_range(3.0, 6.0)


## Голос зомби: свой у типа (zombie_<тип>_<событие>, озвучка — scripts/ai3d/voice_proc.py), иначе общий
## zombie_<событие>; новых событий нет в общих — для них замена из FALLBACK ("" — молчать).
const VOICE_FALLBACK := {"alert": "groan", "chase": "groan", "leap": "attack", "crouch": "", "sleep": ""}


func _voice(ev: String, vol: float, dist: float) -> void:
	if puppet:
		return       # голоса марионеток приходят с хоста (Sfx — эхо звуков по сети)
	var nm := "zombie_%s_%s" % [ztype, ev]
	if Sfx.streams(nm).is_empty():
		var fb: String = VOICE_FALLBACK.get(ev, ev)
		if fb == "":
			return
		nm = "zombie_" + fb
	Sfx.play_at(self, nm, global_position + Vector3.UP * 1.5, vol, dist, 0.12 if ev in ["groan", "chase", "sleep"] else 0.07)


## Заметил игрока: погоня (с рыком, если раньше не гнался).
func _alert(pos: Vector3) -> void:
	if state == S.SLEEP:
		_wake(true)       # вместо стона — рык «заметил»
	if state != S.CHASE:
		_voice("alert", 1.0, 45.0)
		_groan_t = randf_range(3.0, 6.0)
		_leap_plan = randf() < LEAP_CHANCE
	state = S.CHASE
	target = pos
	_lost_t = 0.0
	awareness = AW_NOTICE


func _sight_range(p: Node3D) -> float:
	var r := (13.0 if night else 32.0) / SENSE_RANGE_DIV     # в темноте видят плохо
	if p.get("crouching"):
		r *= 0.55
	if state == S.SLEEP:
		r *= 0.3
	elif state == S.CHASE:
		r *= 1.5
	return r


## Кого зомби может заметить: все выжившие (группа survivors: свой игрок и игроки по сети), плюс заданный player.
func _candidates() -> Array:
	var out: Array = get_tree().get_nodes_in_group("survivors") if is_inside_tree() else []
	if player != null and is_instance_valid(player) and not out.has(player):
		out.append(player)
	return out


static func _alive(p: Node3D) -> bool:
	return p != null and is_instance_valid(p) and p.is_inside_tree() and float(p.get("_dead_t")) <= 0.0


## Насколько быстро растёт заметность, пока зомби видит p (в секунду), или -1, если не видит.
## Вблизи — быстро (в 2.5 м — сразу), у края дальности зрения — медленно; бегущего замечают быстрее, пригнувшегося — медленнее.
func _sight_rate(p: Node3D) -> float:
	var eye := global_position + Vector3.UP * 1.6
	var pe := p.global_position + Vector3.UP * 1.3
	var d := eye.distance_to(pe)
	var r := _sight_range(p)
	if d > r:
		return -1.0
	# вне поля зрения (~120°, в погоне шире) — не видит, кроме совсем рядом
	var cone := global_basis.z.dot((pe - eye) / maxf(d, 0.01))
	if d > 2.5 and cone < (0.2 if state == S.CHASE else 0.45):
		return -1.0
	var q := PhysicsRayQueryParameters3D.create(eye, pe, 1 | 2)
	q.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return -1.0
	if d <= 2.5:
		return 1000.0
	var close := 1.0 - d / r
	var rate := lerpf(18.0, 140.0, close * close)
	if p.get("_sprinting"):
		rate *= 1.5
	elif p.get("crouching"):
		rate *= 0.6
	if state == S.SLEEP:
		rate *= 0.5
	return rate


func _sense() -> void:
	_sees = false
	if state == S.SLEEP:
		awareness = 0.0
		return     # спящий не видит (будят только урон, триггер, шум вплотную)
	var best: Node3D = null
	var best_rate := 0.0
	var best_d := 1e9
	for p: Node3D in _candidates():
		if not _alive(p):
			continue
		if blood_moon:
			# орда кровавой луны всегда знает, где ближайший игрок
			var bd := global_position.distance_squared_to(p.global_position)
			if bd < best_d:
				best_d = bd
				player = p
			continue
		var rate := _sight_rate(p)
		if rate < 0.0:
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if best == null or d < best_d:
			best = p
			best_d = d
			best_rate = rate
	if blood_moon:
		awareness = AW_NOTICE
		aw_target = player
		return
	if best == null:
		return
	aw_target = best
	_aw_hold = AW_HOLD
	if state == S.CHASE:
		_sees = true
		player = best
		awareness = AW_NOTICE
		return
	awareness = minf(AW_NOTICE, awareness + best_rate * SENSE_DT)
	if awareness >= AW_NOTICE:
		_sees = true      # заметил — в _step начнётся погоня
		player = best
	elif awareness >= AW_INVESTIGATE and state != S.SLEEP:
		# что-то видит: идёт посмотреть, что там
		target = best.global_position
		if state != S.INVESTIGATE:
			state = S.INVESTIGATE
		_look_t = 0.0


# --- поведение ---------------------------------------------------------------------

## Уровень детализации (задаёт ZombieDirector по расстоянию до игрока): дальние — упрощённое движение 15 раз
## в секунду по поверхности без физики (и без столкновений друг с другом), анимация реже.
func set_lod(dist: float) -> void:
	var simple := dist > SIMPLE_DIST and not dead
	if simple != _simple:
		_simple = simple
		_acc = 0.0
		# дальние друг с другом не сталкиваются (их расталкивает ZombieDirector), ближние — как обычно
		if not dead:
			collision_mask = (1 | 2 | 4) if simple else (1 | 2 | 4 | LAYER)
		if not simple:
			velocity.y = 0.0
	_far_anim = dist > 35.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if global_position.distance_squared_to(_cur_pos) > 25.0:
		# переставили извне (тест, страховка от провала) — без «пролёта» модели
		_cur_pos = global_position
		_prev_pos = global_position
	if puppet:
		_prev_pos = _cur_pos
		_prev_yaw = _cur_yaw
		_puppet_step(delta)
		_cur_pos = global_position
		_cur_yaw = rotation.y
		if _teleported:
			_teleported = false
			_prev_pos = _cur_pos
		return
	if _simple and not dead:
		_acc += delta
		if _acc + 1e-4 < SIMPLE_DT:
			return
		var dt := _acc
		_acc = 0.0
		_prev_pos = _cur_pos
		_prev_yaw = _cur_yaw
		_step(dt)
	else:
		_prev_pos = _cur_pos
		_prev_yaw = _cur_yaw
		_step(delta)
	_cur_pos = global_position
	_cur_yaw = rotation.y
	if _teleported:
		_teleported = false
		_prev_pos = _cur_pos
	Prof.add("zombies", Time.get_ticks_usec() - t0)


## Модель рисуется между двумя последними шагами (плавно при любой частоте кадров и при 15 Гц у дальних);
## анимация скелета: вблизи и на экране — каждый кадр, далеко — 15 раз в секунду, вне экрана — 4 раза.
func _process(delta: float) -> void:
	if _ragdoll != null:
		return     # тело ведёт физика / поза зафиксирована
	if _kphase > 0 and _kphase < 4:
		return     # сбит: ragdoll / лежит / перетекает — модель не двигаем, анимация выключена
	if _kphase == 4 and _anim != null:
		_anim.advance(delta)    # встаёт: модель стоит, где поставили в _begin_getup
		return
	if _model != null:
		var f := clampf(_acc / SIMPLE_DT if (_simple and not dead) else Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
		var p := _prev_pos.lerp(_cur_pos, f)
		var yaw := lerp_angle(_prev_yaw, _cur_yaw, f)
		_model.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(_tilt) * Basis().scaled(Vector3.ONE * _mscale), p)
	if _anim != null:
		var rate := 0.0
		if _vis != null and not _vis.is_on_screen():
			rate = 0.25
		elif _far_anim:
			rate = 1.0 / 15.0
		_anim_acc += delta
		if _anim_acc >= rate:
			var t0 := Time.get_ticks_usec()
			_anim.advance(_anim_acc)
			_anim_acc = 0.0
			Prof.add("z_anim", Time.get_ticks_usec() - t0)


func _step(delta: float) -> void:
	if dead:
		_step_dead(delta)
		return
	_cd = maxf(0.0, _cd - delta)
	_stagger = maxf(0.0, _stagger - delta)
	if _kphase > 0:
		_knock_step(delta)
	if _down_t > 0.0:
		_down_t = maxf(0.0, _down_t - delta)
		_stagger = maxf(_stagger, 0.01)   # на земле: не идёт и не бьёт (как при стане)
	_sense_t -= delta
	var think := false
	if _sense_t <= 0.0:
		_sense_t += SENSE_DT
		think = true
		var ts := Time.get_ticks_usec()
		_sense()
		Prof.add("z_sense", Time.get_ticks_usec() - ts)
	# заметность спадает, если какое-то время ни вида, ни звука
	if _aw_hold > 0.0:
		_aw_hold -= delta
	elif not (state == S.CHASE and _sees):
		awareness = maxf(0.0, awareness - AW_DECAY * delta)
	var has_p := player != null and is_instance_valid(player)
	var to_p := Vector3.ZERO
	var dist := 1e9
	if has_p:
		to_p = player.global_position - global_position
		dist = Vector2(to_p.x, to_p.z).length()
	if has_p and (_sees or blood_moon):
		# цель (место игрока) обновляется при каждом «взгляде»; вблизи — постоянно, чтобы не промахиваться
		if think or state != S.CHASE or dist < 6.0:
			_alert(player.global_position)
	elif state == S.SLEEP and _stagger <= 0.0:
		# спит: без физики и поворотов — дёшево, даже если в городе их десятки
		_animate(delta, 0.0)
		return
	elif state == S.CHASE:
		# потерял из виду: идёт к последнему месту, где видел, потом осматривается
		_lost_t += delta
		if _lost_t > 8.0 or _flat_dist(target) < 1.2:
			state = S.INVESTIGATE
			_look_t = 0.0

	var dir := Vector3.ZERO
	var speed := 0.0
	match state:
		S.SLEEP:
			pass
		S.IDLE:
			_wander_t -= delta
			if _wander_t <= 0.0:
				_wander_t = randf_range(3.0, 8.0)
				_wander = Vector3.ZERO if randf() < 0.4 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			dir = _wander
			speed = 0.9
		S.INVESTIGATE:
			if _flat_dist(target) > 1.3 and _look_t <= 0.0:
				dir = _dir_to(target)
				speed = 1.6
			else:
				# на месте: осматривается, затем снова бродит
				_look_t += delta
				if _look_t > 4.5:
					state = S.IDLE
		S.HORDE:
			if _flat_dist(target) > 2.0:
				dir = _dir_to(target)
				speed = 2.0 if night else 1.5
			else:
				state = S.IDLE
		S.CHASE:
			dir = _dir_to(target)
			speed = _chase_speed()
			# прыгун изредка садится на корточки и выпрыгивает на игрока
			# решение «прыгну ли на этом заходе» — заранее, издалека (иначе бегущий проскакивает дистанцию прыжка)
			if dist > 13.0:
				_leap_plan = randf() < LEAP_CHANCE if think else _leap_plan
			if _leap_state == 0 and _leap_plan and bool(_type()["leaper"]) and has_p and not _simple and _leap_cd <= 0.0 and not _disabled() \
					and dist > 4.0 and dist < 10.0 and absf(to_p.y) < 2.0 and (_sees or blood_moon) and is_on_floor():
				_leap_plan = false
				_leap_state = 1
				_leap_t = randf_range(0.7, 1.2)
				_voice("crouch", 0.0, 30.0)
			if _leap_state > 0:
				dir = Vector3.ZERO
			# удар, если игрок рядом и примерно на одной высоте (не достать игрока на крыше)
			elif has_p and dist < ATTACK_RANGE and absf(to_p.y) < 1.6:
				dir = Vector3.ZERO
				if _cd <= 0.0 and _attack_t <= 0.0:
					_start_attack({})
	speed *= _speed_k
	if not _simple:
		var ta := Time.get_ticks_usec()
		dir = _avoid(dir, delta)
		Prof.add("z_avoid", Time.get_ticks_usec() - ta)
	if _stagger > 0.0 or _attack_t > 0.0:
		dir = Vector3.ZERO
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if _leap_state > 0:
		_leap_tick(delta, has_p, to_p)
		dir = Vector3.ZERO
	var target_v := dir * speed
	var k := 6.0 if (_simple or is_on_floor()) else 1.0
	if _leap_state != 2:     # в прыжке скорость не гасится (летит по дуге)
		velocity.x = move_toward(velocity.x, target_v.x, k * delta * 4.0)
		velocity.z = move_toward(velocity.z, target_v.z, k * delta * 4.0)
	var tm := Time.get_ticks_usec()
	if _simple:
		_simple_move(delta)
	else:
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		_unstick_ground()
	Prof.add("z_move", Time.get_ticks_usec() - tm)
	# поворот к направлению движения / к игроку / к ломаемому блоку
	var face := dir
	if face == Vector3.ZERO:
		if not _attack_block.is_empty():
			face = _flat((_attack_block["pos"] as Vector3) - global_position)
		elif state == S.CHASE:
			face = _flat(to_p)
	if face != Vector3.ZERO:
		var yaw := atan2(face.x, face.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 6.0))
	var tt := Time.get_ticks_usec()
	_update_attack(delta, dist, to_p)
	Prof.add("z_attack", Time.get_ticks_usec() - tt)
	_groan_t -= delta
	if _groan_t <= 0.0:
		if state == S.SLEEP:
			# спит — тихое сиплое дыхание, слышно только вблизи
			_groan_t = randf_range(7.0, 14.0)
			if player != null and global_position.distance_to(player.global_position) < 15.0:
				_voice("sleep", -6.0, 14.0)
		elif state == S.CHASE:
			_groan_t = randf_range(4.0, 11.0)
			_voice("chase", -1.0, 45.0)
		else:
			_groan_t = randf_range(8.0, 18.0)
			_voice("groan", -2.0, 45.0)
	_animate(delta, Vector2(velocity.x, velocity.z).length())


## Прыжок: 1 — сидит на корточках (собирается), 2 — в полёте. Урон, если долетел до игрока.
const LEAP_DMG := 18.0
const LEAP_UP := 5.0
var _leap_state := 0
var _leap_t := 0.0
var _leap_cd := 0.0
var _leap_air := 0.0
var _leap_hit := false
var _leap_plan := false
const LEAP_CHANCE := 0.4      # «изредка»: на ~40% заходов к игроку
static var leap_count := 0     # для журнала (--zlog=1)
static var leap_hits := 0


func _leap_tick(delta: float, has_p: bool, to_p: Vector3) -> void:
	if _leap_state == 1:
		_leap_t -= delta
		if _stagger > 0.0 or not has_p:
			_leap_state = 0      # сбили ударом — передумал
			_leap_cd = randf_range(3.0, 6.0)
			return
		if _leap_t <= 0.0:
			# дальность прыжка — чтобы приземлиться у игрока (время полёта по вертикальной скорости и разнице высот)
			var flat := Vector3(to_p.x, 0.0, to_p.z)
			var d := flat.length()
			var tf := (LEAP_UP + sqrt(maxf(LEAP_UP * LEAP_UP - 2.0 * _gravity * to_p.y, 1.0))) / _gravity
			var vh := clampf((d - 0.6) / tf, 3.5, 11.0)
			velocity = flat.normalized() * vh + Vector3.UP * LEAP_UP
			rotation.y = atan2(flat.x, flat.z)
			_leap_state = 2
			leap_count += 1
			_leap_air = 0.0
			_leap_hit = false
			_voice("leap", 2.0, 40.0)
	elif _leap_state == 2:
		_leap_air += delta
		if not _leap_hit and has_p and to_p.length() < 1.5 and player.has_method("take_damage"):
			_leap_hit = true
			leap_hits += 1
			player.take_damage(LEAP_DMG)
		if _leap_air > 0.2 and is_on_floor():
			_leap_state = 0
			_leap_cd = randf_range(6.0, 12.0)
			_cd = maxf(_cd, 0.6)         # после приземления не сразу бьёт
			velocity.x *= 0.3
			velocity.z *= 0.3


func _chase_speed() -> float:
	if blood_moon or night:
		return 5.4    # ночью бегут (игрок: шаг 5, бег 8.5)
	if feral:
		return 4.2
	return 2.1


## Препятствие по ходу: низкое — перепрыгнуть; постройка — ломать (если есть цель); иначе обойти сбоку.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	if _block_hold > 0.0:
		# уже ломает постройку: стоит у блока и бьёт, пока перед ним есть что ломать
		_block_hold -= delta
		if dir == Vector3.ZERO or state == S.IDLE:
			_block_hold = 0.0
			return dir
		if _cd <= 0.0 and _attack_t <= 0.0:
			var hb := _chest_ray(dir)
			if not hb.is_empty() and (hb["collider"] as Object).has_meta("block_building"):
				_attack_obstacle(hb)
			else:
				_block_hold = 0.0
				return dir
		return Vector3.ZERO
	if dir == Vector3.ZERO or not is_on_wall():
		_stuck_t = maxf(0.0, _stuck_t - delta)
		return dir
	_stuck_t += delta
	var hc := _chest_ray(dir)
	if hc.is_empty():
		var knee := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.45, global_position + Vector3.UP * 0.45 + dir * 0.8, 1 | 2)
		knee.exclude = [get_rid()]
		if is_on_floor() and not get_world_3d().direct_space_state.intersect_ray(knee).is_empty():
			velocity.y = 4.6
		elif _stuck_t > 0.6:
			dir = (dir + dir.cross(Vector3.UP) * _side * 1.4).normalized()
		return dir
	var col: Object = hc["collider"]
	if state != S.IDLE and col.has_meta("block_building") and _stuck_t > 1.2:
		# не обойти — ломает постройку по пути к цели (как в 7DTD)
		if _cd <= 0.0 and _attack_t <= 0.0:
			_attack_obstacle(hc)
		return Vector3.ZERO
	if is_on_floor() and _stuck_t < 0.3:
		velocity.y = 4.6
	if _stuck_t > 0.6:
		dir = (dir + dir.cross(Vector3.UP) * _side * 1.4).normalized()
	if _stuck_t > 2.5:
		_side = -_side
		_stuck_t = 0.0
	return dir


func _chest_ray(dir: Vector3) -> Dictionary:
	var from := global_position + Vector3.UP * 1.3
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.9, 2)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _attack_obstacle(h: Dictionary) -> void:
	var col: Object = h["collider"]
	_block_hold = 2.0
	_start_attack({"bb": col.get_meta("block_building"), "pos": h["position"], "nrm": h["normal"], "col": col})


## Оглушён, сбит с ног или встаёт — не бьёт и не прыгает.
func _disabled() -> bool:
	return _stagger > 0.0 or _kphase > 0 or _down_t > 0.0


func _start_attack(block: Dictionary) -> void:
	if _disabled():
		return
	_attack_t = 0.75
	_cd = ATTACK_CD
	_attack_block = block
	_voice("attack", 0.0, 35.0)


## Удар: в середине замаха (руки вниз) — урон игроку (если ещё рядом) или блоку.
func _update_attack(delta: float, dist: float, to_p: Vector3) -> void:
	if _attack_t <= 0.0:
		return
	if _kphase > 0 or _down_t > 0.0:
		_attack_t = 0.0     # сбит посреди замаха — удар сорван
		_attack_block = {}
		return
	var before := _attack_t
	_attack_t -= delta
	if before > 0.3 and _attack_t <= 0.3:
		if not _attack_block.is_empty():
			var bb: Variant = _attack_block["bb"]
			if is_instance_valid(bb) and bb is BlockBuilding and is_instance_valid(_attack_block["col"]):
				var p: Vector3 = _attack_block["pos"]
				var bk := (bb as BlockBuilding).kind_at_hit(p, _attack_block["nrm"], _attack_block["col"])
				(bb as BlockBuilding).hit(p, _attack_block["nrm"], BLOCK_DMG, "zombie", _attack_block["col"])
				var snd := "hit_stone" if bk == "stone" else (Sfx.pick("hit_metal", "hit_stone") if bk == "metal" else "hit_wood")
				Sfx.play_at(self, snd, p, 0.0, 35.0)
		elif dist < ATTACK_RANGE + 0.4 and absf(to_p.y) < 1.8 and player.has_method("take_damage"):
			player.take_damage(ATTACK_DMG)
	if _attack_t <= 0.0:
		_attack_block = {}


## Далеко от игрока коллизия ландшафта подключается с задержкой: провалившегося — обратно на поверхность.
func _unstick_ground() -> void:
	if gen == null:
		return
	var gh := gen.height_at(global_position.x, global_position.z)
	if global_position.y < gh - 3.0:
		global_position.y = gh + 0.3
		velocity.y = 0.0
		_teleported = true


## Упрощённое движение дальнего зомби: без физики, по поверхности ландшафта (высота — с кэшем на ~0.7 м).
## Стена постройки впереди (один луч) — шаг в сторону; расталкивание с соседями — в ZombieDirector.
func _simple_move(dt: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length_squared() > 0.01:
		var d := hv.normalized()
		var from := global_position + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(from, from + d * (0.5 + hv.length() * dt), 2)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			hv = d.cross(Vector3.UP) * _side * hv.length() * 0.8
			_stuck_t += dt
			if _stuck_t > 2.5:
				_side = -_side
				_stuck_t = 0.0
		var p := global_position + hv * dt
		global_position = Vector3(p.x, _surface(p.x, p.z, global_position.y), p.z)
	velocity.y = 0.0


func _surface(x: float, z: float, fallback: float) -> float:
	if Vector2(x, z).distance_squared_to(_ground_at) > 0.25 or is_nan(_ground_y):
		_ground_at = Vector2(x, z)
		var h := gen.height_at(x, z) if gen != null else fallback
		_ground_y = terrain.surface_y(x, z, h) if terrain != null else h
		if is_nan(_ground_y):
			_ground_y = h
	return _ground_y


func _step_dead(delta: float) -> void:
	if _ragdoll != null:
		return     # падение, гниение и исчезновение — в ZombieRagdoll
	_dead_t -= delta
	# падение навзничь: анимация модели или поворот процедурного тела
	if _anim != null:
		_play("death")
	else:
		var r: Node3D = _parts["root"]
		r.rotation.x = move_toward(r.rotation.x, -PI * 0.5, delta * 4.0)
		r.position.y = move_toward(r.position.y, 0.15, delta * 1.5)
	if not is_on_floor():
		velocity.y -= _gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 6.0)
		move_and_slide()
		_unstick_ground()
	elif _model != null:
		# тело ложится по склону (иначе на уклоне один конец висит в воздухе)
		var n := global_basis.inverse() * get_floor_normal()
		var q := Quaternion(Vector3.UP, n.normalized())
		_tilt = _tilt.slerp(q, 1.0 - exp(-delta * 5.0))
	if _dead_t <= 0.0:
		queue_free()


# --- сеть ------------------------------------------------------------------------------

## Снимок для клиентов: [id, тип, позиция, поворот, анимация, её скорость, состояние, заметность, чья, мёртв].
func net_state() -> Array:
	var anim := _cur if _kphase == 0 else ""
	var who := 0
	if aw_target != null and is_instance_valid(aw_target):
		who = int(aw_target.get("peer_id")) if aw_target.get("peer_id") != null else 1
	return [net_id, 1 if ztype == "mudworn" else 0, global_position, rotation.y, anim,
		_anim.speed_scale if _anim != null else 1.0, state, roundi(awareness), who, dead]


## Марионетка: куда идти и что играть (из снимка хоста).
func net_apply(pos: Vector3, yaw: float, anim: String, spd: float, st: int, aw: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_anim = anim
	_net_spd = spd
	state = st as S
	awareness = aw
	net_seen_ms = Time.get_ticks_msec()


func net_knock(dir: Vector3) -> void:
	if dead:
		return
	_last_hit_dir = dir
	_knock_down()


func net_die(dir: Vector3) -> void:
	if dead:
		return
	_last_hit_dir = dir
	hp = 0.0
	_die()


func _puppet_step(delta: float) -> void:
	if dead:
		_step_dead(delta)
		return
	if _kphase > 0:
		_knock_step(delta)    # сбит: своё ragdoll-падение и подъём (потом догоняет положение с хоста)
		return
	_stagger = 0.0
	var to := _net_pos
	if global_position.distance_to(to) > 4.0:
		global_position = to
		_teleported = true
	else:
		var np := global_position.lerp(to, 1.0 - exp(-delta * 10.0))
		velocity = (np - global_position) / maxf(delta, 1e-4)
		global_position = np
	rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-delta * 10.0))
	if _anim == null or _net_anim == "":
		return
	if _net_anim == "getup":
		if _cur != "getup":
			_cur = "getup"
			_anim.speed_scale = 1.0
			_anim.play("death", 0.1, -_anim.get_animation("death").length / GETUP_TIME, true)
	else:
		_play(_net_anim, _net_spd)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


func _dir_to(p: Vector3) -> Vector3:
	return _flat(p - global_position)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Анимации модели по состоянию; скорость шага — под фактическую скорость (без «скольжения» ног).
func _animate(delta: float, spd: float) -> void:
	if _anim != null:
		if _kphase > 0:
			return      # ragdoll-сбивание: позой управляет _knock_step
		if _down_t > 0.0 and _anim.has_animation("death"):
			# сбит: death вперёд (падает и лежит — анимация держит последний кадр), в конце — задом наперёд (встаёт)
			if _down_t <= GETUP_TIME:
				if _cur != "getup":
					_cur = "getup"
					_anim.speed_scale = 1.0
					_anim.play("death", 0.1, -_anim.get_animation("death").length / GETUP_TIME, true)
			else:
				_play("death", 1.0)
			return
		if _leap_state == 1:
			_play("crouch", 1.0)
		elif _leap_state == 2:
			_play("leap", 0.85)
		elif _attack_t > 0.0:
			_play("attack", 1.15)
		elif _stagger > 0.0:
			_play("hit", 1.0)
		elif state == S.SLEEP:
			_play("idle", 0.25)
		elif spd > 2.6:
			_play("run", clampf(spd / 3.8, 0.7, 1.4))
		elif spd > 0.25:
			# ходьба из мокапа (естественная скорость шага walk_spd): темп ~ скорость^0.75, не выше ×1.8 —
			# компромисс: линейно (×2.2) мокап дёргается, корень (×1.35) — сильно скользят ноги
			_play("walk", clampf(pow(spd / float(_type().get("walk_spd", 1.5)), 0.75), 0.65, 1.8))
		else:
			_play("idle", 1.0)
		return
	# процедурное тело: ноги и руки маятником (руки вытянуты вперёд), туловище раскачивается
	_phase += delta * (2.2 + spd * 2.4)
	var sw := clampf(spd / 2.0, 0.0, 1.0)
	var s := sin(_phase)
	(_parts["l_hip"] as Node3D).rotation.x = s * 0.55 * sw
	(_parts["r_hip"] as Node3D).rotation.x = -s * 0.55 * sw
	(_parts["l_knee"] as Node3D).rotation.x = maxf(0.0, -s) * 0.8 * sw
	(_parts["r_knee"] as Node3D).rotation.x = maxf(0.0, s) * 0.8 * sw
	(_parts["hips"] as Node3D).position.y = 0.95 - absf(cos(_phase)) * 0.04 * sw
	(_parts["spine"] as Node3D).rotation.z = sin(_phase) * 0.08 * sw
	var reach := -1.35   # руки вытянуты вперёд
	var arm_l := reach + s * 0.15 * sw
	var arm_r := reach - s * 0.15 * sw
	if _attack_t > 0.0:
		var t := 1.0 - _attack_t / 0.75
		var a := -2.6 + t * 2.2 if t > 0.35 else -1.35 - t / 0.35 * 1.25
		arm_l = a
		arm_r = a
	(_parts["l_shoulder"] as Node3D).rotation.x = arm_l
	(_parts["r_shoulder"] as Node3D).rotation.x = arm_r
	(_parts["l_elbow"] as Node3D).rotation.x = -0.25
	(_parts["r_elbow"] as Node3D).rotation.x = -0.35
