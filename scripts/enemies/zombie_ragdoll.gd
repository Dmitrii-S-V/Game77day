class_name ZombieRagdoll
extends Node
## Смерть зомби: ragdoll (PhysicalBone3D) с толчком от удара → когда тело полностью легло, физика отключается и поза
## фиксируется → через ROT_DELAY секунд тело темнеет и «сгнивает» (ROT_TIME) → остаются кости и тёмное пятно,
## которые исчезают через REMAINS_TIME. Обыск (E) — по коллайдеру трупа у таза.

const ROT_DELAY := 30.0
const ROT_TIME := 6.0
const REMAINS_TIME := 180.0
const MAX_ACTIVE := 8          # одновременно падающих ragdoll (дальше — анимация смерти)
const LAYER := 32              # кости: сталкиваются с землёй и постройками, игрок и лучи их не видят

static var active := 0

# роль кости: [радиус, масса, конус (градусы), длина, если нет подходящего ребёнка]
const ROLES := {
	"hips": [0.13, 12.0, 0.0, 0.15], "spine": [0.13, 9.0, 30.0, 0.15], "spine1": [0.13, 8.0, 25.0, 0.15],
	"spine2": [0.14, 8.0, 25.0, 0.15], "chest": [0.14, 9.0, 30.0, 0.2], "head": [0.11, 5.0, 45.0, 0.22],
	"upper_arm_l": [0.055, 3.0, 75.0, 0.3], "upper_arm_r": [0.055, 3.0, 75.0, 0.3], "leftarm": [0.055, 3.0, 75.0, 0.3], "rightarm": [0.055, 3.0, 75.0, 0.3],
	"forearm_l": [0.045, 2.0, 70.0, 0.28], "forearm_r": [0.045, 2.0, 70.0, 0.28], "leftforearm": [0.045, 2.0, 70.0, 0.28], "rightforearm": [0.045, 2.0, 70.0, 0.28],
	"thigh_l": [0.08, 8.0, 55.0, 0.4], "thigh_r": [0.08, 8.0, 55.0, 0.4], "leftupleg": [0.08, 8.0, 55.0, 0.4], "rightupleg": [0.08, 8.0, 55.0, 0.4],
	"shin_l": [0.06, 4.0, 60.0, 0.42], "shin_r": [0.06, 4.0, 60.0, 0.42], "leftleg": [0.06, 4.0, 60.0, 0.4], "rightleg": [0.06, 4.0, 60.0, 0.4],
}

var zombie: Node3D
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var _sim: PhysicalBoneSimulator3D
var _bones: Array[PhysicalBone3D] = []
var _t := 0.0
var _still_t := 0.0
var _state := 0              # 0 падает, 1 лежит (поза зафиксирована), 2 гниёт, 3 останки
var _state_t := 0.0
var _mats: Array = []        # [MeshInstance3D, поверхность, StandardMaterial3D копия, исходный цвет]
var _ground_y := 0.0         # мировая высота земли под лежащим телом
var knock := false           # сбит с ног: после фиксации не гниёт, зомби встаёт (state 10)


static func _role(bone_name: String) -> String:
	return bone_name.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")


## Создать ragdoll на скелете модели. false — нельзя (нет скелета, слишком много падающих тел).
func setup(z: Node3D, m: Node3D, impulse: Vector3, vel: Vector3) -> bool:
	if active >= MAX_ACTIVE:
		return false
	var sks := m.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	zombie = z
	model = m
	skel = sks[0] as Skeleton3D
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	anim = aps[0] as AnimationPlayer if not aps.is_empty() else null
	_sim = PhysicalBoneSimulator3D.new()
	skel.add_child(_sim)
	var chosen := {}
	for i in skel.get_bone_count():
		if ROLES.has(_role(skel.get_bone_name(i))):
			chosen[i] = true
	for i: int in chosen:
		_add_bone(i, chosen)
	if _bones.is_empty():
		_sim.queue_free()
		return false
	_sim.physical_bones_start_simulation()
	for pb in _bones:
		pb.linear_velocity = vel
	# толчок от удара — в верх туловища
	var top: PhysicalBone3D = _bones[0]
	for pb in _bones:
		if _role(pb.bone_name) in ["chest", "spine2"]:
			top = pb
	top.apply_central_impulse(impulse)
	active += 1
	return true


func _add_bone(i: int, chosen: Dictionary) -> void:
	var role := _role(skel.get_bone_name(i))
	var r: Array = ROLES[role]
	# направление кости: к выбранному ребёнку (или к любому прямому ребёнку), иначе — вдоль родительской кости
	var target := Vector3.ZERO
	for ch in skel.get_bone_children(i):
		if chosen.has(ch) or (target == Vector3.ZERO and skel.get_bone_rest(ch).origin.length() > 0.05 and not _role(skel.get_bone_name(ch)).begins_with("bone_")):
			target = skel.get_bone_rest(ch).origin
			if chosen.has(ch):
				break
	if target == Vector3.ZERO or role == "head":
		var p := skel.get_bone_parent(i)
		var dir := Vector3.UP
		if p >= 0:
			var gp := skel.get_bone_global_rest(p).origin
			var gi := skel.get_bone_global_rest(i)
			var wdir := (gi.origin - gp).normalized()
			dir = (gi.basis.inverse() * wdir).normalized()
		target = dir * float(r[3])
	var half := maxf(target.length() * 0.5, 0.05)
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + skel.get_bone_name(i)
	pb.bone_name = skel.get_bone_name(i)
	pb.mass = float(r[1])
	pb.linear_damp = 0.3
	pb.angular_damp = 3.0
	pb.friction = 0.9
	pb.collision_layer = LAYER
	pb.collision_mask = 1 | 2
	# как «Создать физический скелет» в редакторе: тело вдоль кости, середина — на половине длины, сустав — у начала кости
	var body := Transform3D(Basis.looking_at(target.normalized(), Vector3.UP if absf(target.normalized().y) < 0.95 else Vector3.BACK), Vector3.ZERO)
	body.origin = body.basis * Vector3(0, 0, -half)
	pb.body_offset = body
	pb.joint_offset = Transform3D(Basis(), Vector3(0, 0, half))
	var cs := CollisionShape3D.new()
	if role == "head":
		var sp := SphereShape3D.new()
		sp.radius = float(r[0])
		cs.shape = sp
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = float(r[0])
		cap.height = maxf(half * 2.0, cap.radius * 2.2)
		cs.shape = cap
		cs.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3.ZERO)   # капсула вдоль Z
	pb.add_child(cs)
	var cone := float(r[2])
	if cone > 0.0:
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.set("joint_constraints/swing_span", cone)
		pb.set("joint_constraints/twist_span", 20.0)
	_sim.add_child(pb)
	if role == "hips":
		_bones.push_front(pb)
	else:
		_bones.append(pb)


func _physics_process(delta: float) -> void:
	if _state != 0:
		return
	_t += delta
	var maxv := 0.0
	for pb in _bones:
		maxv = maxf(maxv, pb.linear_velocity.length())
	_still_t = _still_t + delta if maxv < 0.25 else 0.0
	if (_t > 0.8 and _still_t > 0.4) or _t > 6.0:
		_freeze()


## Тело легло: поза костей фиксируется, физика выключается (дальше тело — просто меш).
func _freeze() -> void:
	var inv_sk := skel.global_transform.affine_inverse()
	var phys := {}
	for pb in _bones:
		var bi := skel.find_bone(pb.bone_name)
		phys[bi] = inv_sk * pb.global_transform * pb.body_offset.affine_inverse()
	var n := skel.get_bone_count()
	var g: Array[Transform3D] = []
	g.resize(n)
	for i in n:
		var p := skel.get_bone_parent(i)
		if phys.has(i):
			g[i] = phys[i]
		elif p >= 0:
			g[i] = g[p] * skel.get_bone_pose(i)
		else:
			g[i] = skel.get_bone_pose(i)
	_sim.physical_bones_stop_simulation()
	_sim.queue_free()
	_bones.clear()
	if anim != null:
		anim.active = false
	for i in n:
		var p2 := skel.get_bone_parent(i)
		var l := g[i] if p2 < 0 else g[p2].affine_inverse() * g[i]
		skel.set_bone_pose_position(i, l.origin)
		skel.set_bone_pose_rotation(i, l.basis.get_rotation_quaternion())
	active = maxi(0, active - 1)
	if knock:
		# сбит с ног (не смерть): поза зафиксирована — дальше зомби сам встаёт из неё (Zombie.on_knock_settled)
		_state = 10
		zombie.call("on_knock_settled")
		return
	# высота земли под телом (до оседания при гниении) — по ней кладутся останки
	var hp := bone_global("hips")
	var q := PhysicsRayQueryParameters3D.create(hp + Vector3.UP * 0.5, hp + Vector3.DOWN * 2.0, 1 | 2)
	var hit := (zombie as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	_ground_y = (hit["position"] as Vector3).y if not hit.is_empty() else hp.y - 0.12
	_state = 1
	_state_t = 0.0
	if zombie.has_method("on_ragdoll_settled"):
		zombie.call("on_ragdoll_settled", bone_global("hips"), bone_global("chest", "spine2"), bone_global("head"))


## Мировая позиция кости по роли (или первой найденной из списка).
func bone_global(role: String, alt: String = "") -> Vector3:
	for i in skel.get_bone_count():
		var rr := _role(skel.get_bone_name(i))
		if rr == role or (alt != "" and rr == alt):
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return zombie.global_position


func _process(delta: float) -> void:
	if _state == 0 or _state == 10:
		return
	_state_t += delta
	match _state:
		1:
			if _state_t >= ROT_DELAY:
				_state = 2
				_state_t = 0.0
				_prepare_rot()
		2:
			# гниение: тело темнеет и оседает
			var k := clampf(_state_t / ROT_TIME, 0.0, 1.0)
			for e: Array in _mats:
				(e[2] as StandardMaterial3D).albedo_color = (e[3] as Color).lerp(Color(0.16, 0.13, 0.09), k)
			model.position.y -= delta * 0.03
			if _state_t >= ROT_TIME:
				_state = 3
				_state_t = 0.0
				_spawn_remains()
				model.visible = false
		3:
			if _state_t >= REMAINS_TIME:
				zombie.queue_free()


func _prepare_rot() -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, m)
			_mats.append([mi, s, m, m.albedo_color])


## Останки: череп, грудная клетка, таз, кости конечностей по позе лежащего тела, тёмное пятно на земле.
func _spawn_remains() -> void:
	var mb := MeshBuilder.new()
	var bone_c := Color(0.72, 0.68, 0.56)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zombie.global_position)
	var inv := (zombie as Node3D).global_transform.affine_inverse()
	var segs: Array = []
	for i in skel.get_bone_count():
		var role := _role(skel.get_bone_name(i))
		if not ROLES.has(role) or role in ["head", "hips", "spine", "spine1", "spine2", "chest"]:
			continue
		var a := skel.global_transform * skel.get_bone_global_pose(i).origin
		var ch := skel.get_bone_children(i)
		if ch.is_empty():
			continue
		var b := skel.global_transform * skel.get_bone_global_pose(ch[0]).origin
		segs.append([inv * a, inv * b])
	var head := inv * bone_global("head")
	var chest := inv * bone_global("chest", "spine2")
	var hips := inv * bone_global("hips")
	var hw := bone_global("hips")
	var gy := (inv * Vector3(hw.x, _ground_y, hw.z)).y
	for s: Array in segs:
		var a2: Vector3 = s[0]
		var b2: Vector3 = s[1]
		a2.y = gy + 0.035
		b2.y = gy + 0.035
		ModelGen._tube(mb, ModelGen_pts([a2, a2.lerp(b2, 0.5) + Vector3(0, 0.01, 0), b2]), _rad([0.034, 0.024, 0.034]), 6, bone_c, bone_c.darkened(0.2), rng)
	# ось тела таз → голова (кость chest у разных скелетов на разной высоте груди)
	var ax := Vector3(head.x - hips.x, 0, head.z - hips.z)
	if ax.length() < 0.05:
		ax = Vector3(chest.x - hips.x, 0, chest.z - hips.z)
	if ax.length() < 0.05:
		ax = Vector3.FORWARD
	ax = ax.normalized()
	var side := ax.cross(Vector3.UP)
	# череп — чуть дальше шейной кости
	var hc := Vector3(head.x, gy + 0.09, head.z) + ax * 0.08
	mb.append_mesh(ItemModels.lathe([Vector2(0.0, -0.08), Vector2(0.06, -0.07), Vector2(0.085, -0.02), Vector2(0.09, 0.03), Vector2(0.07, 0.07), Vector2(0.0, 0.09)], 10, bone_c),
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.4, 0.4)).rotated(Vector3.UP, rng.randf() * TAU), hc))
	for ex in [-0.032, 0.032]:
		mb.box(hc + Vector3(ex, 0.05, 0.06), Vector3(0.025, 0.02, 0.02), Color(0.05, 0.04, 0.03))
	# рёбра: дуги поперёк линии таз–шея
	var neck := Vector3(head.x, hips.y, head.z)
	for k in 5:
		var c := hips.lerp(neck, 0.38 + k * 0.11)
		c.y = gy + 0.05
		var pts: Array[Vector3] = []
		for q in 7:
			var ang := lerpf(-1.2, 1.2, q / 6.0)
			pts.append(c + side * sin(ang) * 0.13 + Vector3.UP * cos(ang) * 0.05)
		ModelGen._tube(mb, pts, ModelGen_radii(7, 0.016), 5, bone_c, bone_c.darkened(0.25), rng)
	ModelGen._tube(mb, ModelGen_pts([Vector3(hips.x, gy + 0.05, hips.z), Vector3(head.x, gy + 0.05, head.z)]), _rad([0.03, 0.025]), 6, bone_c, bone_c.darkened(0.2), rng)
	mb.box(Vector3(hips.x, gy + 0.06, hips.z), Vector3(0.24, 0.06, 0.12), bone_c.darkened(0.1))   # таз
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	mi.material_override = ItemModels.vertex_color_material()
	zombie.add_child(mi)
	# тёмное пятно
	var stain := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.4, 1.8)
	stain.mesh = pm
	stain.material_override = _stain_mat()
	stain.position = Vector3((hips.x + head.x) * 0.5, gy + 0.02, (hips.z + head.z) * 0.5)
	stain.rotation.y = atan2(ax.x, ax.z)
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zombie.add_child(stain)


static var _stain: StandardMaterial3D


## Пятно: тёмное в центре, мягко исчезает к краям (общий материал на все трупы).
static func _stain_mat() -> StandardMaterial3D:
	if _stain == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.09, 0.06, 0.035, 0.9))
		g.set_color(1, Color(0.12, 0.09, 0.05, 0.0))
		g.add_point(0.55, Color(0.1, 0.07, 0.04, 0.7))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_stain = StandardMaterial3D.new()
		_stain.albedo_texture = tex
		_stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_stain.roughness = 0.6
	return _stain


static func ModelGen_pts(a: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in a:
		out.append(p)
	return out


static func _rad(a: Array) -> Array[float]:
	var out: Array[float] = []
	for v in a:
		out.append(float(v))
	return out


static func ModelGen_radii(n: int, r: float) -> Array[float]:
	var out: Array[float] = []
	for i in n:
		out.append(r)
	return out


func _exit_tree() -> void:
	if _state == 0 and not _bones.is_empty():
		active = maxi(0, active - 1)
		_bones.clear()


## Убрать ragdoll сбивания без фиксации (зомби удалён/умер иначе): физика выключается, счётчик — назад.
func cancel() -> void:
	if _state == 0 and not _bones.is_empty():
		_sim.physical_bones_stop_simulation()
		_sim.queue_free()
		_bones.clear()
		active = maxi(0, active - 1)
	_state = 10
	queue_free()


## Индекс кости по роли (hips, head, chest/spine2…), -1 — нет.
static func bone_index(sk: Skeleton3D, role: String, alt: String = "") -> int:
	for i in sk.get_bone_count():
		var rr := _role(sk.get_bone_name(i))
		if rr == role or (alt != "" and rr == alt):
			return i
	return -1
