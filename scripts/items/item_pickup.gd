class_name ItemPickup
extends RigidBody3D
## Предмет на земле (топор, дерево, камень...). Подбирается клавишей E.


static func spawn(parent: Node, pos: Vector3, item: Dictionary, vel: Vector3 = Vector3.ZERO) -> ItemPickup:
	var p := ItemPickup.new()
	var id: String = item["id"]
	var mi := MeshInstance3D.new()
	var size := Vector3(0.2, 0.2, 0.2)
	if id == "stone_axe":
		var axe := ItemModels.stone_axe()
		axe.rotation.z = PI * 0.5
		axe.position = Vector3(-0.1, 0.03, 0)
		p.add_child(axe)
		size = Vector3(0.55, 0.1, 0.12)
	else:
		var bm := BoxMesh.new()
		bm.size = size * 0.8
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = ItemDB.info(id)["color"]
		m.roughness = 0.9
		mi.material_override = m
		p.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	p.add_child(cs)
	p.collision_layer = 16
	p.collision_mask = 3
	p.mass = 1.0
	p.add_to_group("pickups")
	p.set_meta("item", item)
	parent.add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	return p
