class_name ThrownBottle
extends RigidBody3D
## Бутылка в мире: брошенная или упавшая. Вода внутри подчиняется гравитации (уровень горизонтален,
## плещется). При сильном ударе разбивается: разлетаются осколки (бьют по игроку), а если
## была вода — ещё и брызги. Целая лежащая бутылка подбирается (группа "pickups").

const BREAK_SPEED := 3.5

var item_id := "water_bottle"
var fill := 1.0
var broken := false

var _liquid: BottleLiquid
var _last_vel := Vector3.ZERO
var _age := 0.0


func setup(id: String, f: float) -> void:
	item_id = id
	fill = f
	var b := ItemModels.bottle(id == "water_bottle" and f > 0.0)
	var root: Node3D = b["root"]
	root.position = Vector3(0, -0.13, 0)
	add_child(root)
	if b["liquid_mat"] != null:
		_liquid = BottleLiquid.new(root, b["liquid_mat"], f)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.034
	cap.height = 0.27
	cs.shape = cap
	add_child(cs)
	collision_layer = 16
	collision_mask = 3
	mass = 0.5
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.12
	pm.friction = 0.6
	physics_material_override = pm
	add_to_group("pickups")
	set_meta("item", {"id": id, "n": 1, "fill": f})
	body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	_age += delta
	_last_vel = linear_velocity


func _process(delta: float) -> void:
	if _liquid != null:
		_liquid.update(delta)


func _on_body(_body: Node) -> void:
	if broken or _age < 0.08:
		return
	if _last_vel.length() > BREAK_SPEED:
		shatter(_last_vel)


func shatter(vel: Vector3 = Vector3.ZERO) -> void:
	if broken:
		return
	broken = true
	var root := get_tree().current_scene
	var pos := global_position
	var n := vel.normalized() * -0.3 + Vector3.UP
	GlassShard.burst(root, pos, n, 12, clampf(vel.length() * 0.7, 3.0, 8.0))
	if item_id == "water_bottle" and fill > 0.04:
		_splash(root, pos, fill)
	queue_free()


static func _splash(parent: Node, pos: Vector3, amount: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = int(30.0 + amount * 60.0)
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 78.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.2
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.82, 0.95, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	sm.material = mat
	p.mesh = sm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tmr := p.get_tree().create_timer(2.0)
	tmr.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
