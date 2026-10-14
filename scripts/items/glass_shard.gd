class_name GlassShard
extends RigidBody3D
## Осколок стекла: физическое тело, которое наносит урон при попадании в игрока (по скорости).

static var _mat: StandardMaterial3D
static var _mesh: BoxMesh

var spent := false
var damage := 4.0


static func burst(parent: Node, pos: Vector3, impulse_dir: Vector3, count: int = 11, speed: float = 4.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.75, 0.92, 0.88, 0.55)
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.roughness = 0.05
		_mat.metallic_specular = 1.0
		_mesh = BoxMesh.new()
	for i in count:
		var s := GlassShard.new()
		var sz := Vector3(randf_range(0.025, 0.07), randf_range(0.003, 0.006), randf_range(0.02, 0.055))
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.scale = sz
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = sz
		cs.shape = sh
		s.add_child(cs)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4   # игрок
		var acs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.1
		acs.shape = sph
		area.add_child(acs)
		area.body_entered.connect(s._on_body)
		s.add_child(area)
		s.collision_layer = 8
		s.collision_mask = 3
		s.mass = 0.02
		s.linear_damp = 0.15
		s.top_level = true
		parent.add_child(s)
		s.global_position = pos + Vector3(randf_range(-0.04, 0.04), randf_range(0.0, 0.06), randf_range(-0.04, 0.04))
		s.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var d := (impulse_dir + Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1))).normalized()
		s.linear_velocity = d * speed * randf_range(0.4, 1.1)
		s.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		var tmr := s.get_tree().create_timer(randf_range(9.0, 14.0))
		tmr.timeout.connect(func() -> void:
			if is_instance_valid(s):
				s.queue_free())


func _on_body(body: Node3D) -> void:
	if spent or not body.has_method("take_damage"):
		return
	var v := linear_velocity.length()
	if v < 2.2:
		return
	spent = true
	body.take_damage(clampf(damage * (v / 4.0), 1.5, 9.0))
