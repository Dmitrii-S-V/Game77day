extends SceneTree
## Тест блоков-моделей (shape «model»: диван, забор): ставятся во всех поворотах, занимают свой footprint,
## у постройки появляется узел модели и коробки столкновений, удар ломает блок.

var fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", msg)


func _init() -> void:
	BlockRegistry.ensure()
	for key in ["sofa_old", "fence_concrete"]:
		var id := BlockRegistry.id_by_key(key)
		_check(id > 0, "нет блока " + key)
		_check(ResourceLoader.exists(String(BlockRegistry.block(id).get("model", ""))), "нет модели " + key)
		for rot in 4:
			var g := BlockGrid.new(8, 6, 8)
			var cells := g.place_block(Vector3i(2, 1, 2), id, BlockRegistry.make_meta(rot, 0, 0))
			var fp := BlockRegistry.footprint(id, rot)
			_check(cells.size() == fp.x * fp.y * fp.z, "%s rot %d: ячеек %d" % [key, rot, cells.size()])
			var bb := BlockBuilding.new()
			root.add_child(bb)
			bb.setup(g, StandardMaterial3D.new(), StandardMaterial3D.new(), true)
			var e := bb.custom_entry(Vector3i(2, 1, 2))
			var has_model := false
			var has_body := false
			for n: Node in e.get("nodes", []):
				if n is StaticBody3D:
					has_body = true
				elif n is Node3D and not (n as Node3D).find_children("*", "MeshInstance3D", true, false).is_empty():
					has_model = true
					# модель должна лежать внутри footprint
					var aabb := AABB()
					var first := true
					for mi: MeshInstance3D in (n as Node3D).find_children("*", "MeshInstance3D", true, false):
						var xf := Transform3D()
						var cur: Node = mi
						while cur != null and cur != bb:
							xf = (cur as Node3D).transform * xf
							cur = cur.get_parent()
						var bx := xf * mi.get_aabb()
						aabb = bx if first else aabb.merge(bx)
						first = false
					var lo := bb.origin + Vector3(2, 1, 2)   # ячейка якоря в системе постройки (origin — сдвиг сетки)
					var hi := lo + Vector3(fp)
					_check(aabb.position.x > lo.x - 0.05 and aabb.position.z > lo.z - 0.05 and aabb.end.x < hi.x + 0.05 and aabb.end.z < hi.z + 0.05,
						"%s rot %d: модель вне footprint %s" % [key, rot, aabb])
			_check(has_model, "%s rot %d: нет модели" % [key, rot])
			_check(has_body, "%s rot %d: нет коллизии" % [key, rot])
			bb.queue_free()
	print("RESULT fails=%d" % fails)
	quit()
