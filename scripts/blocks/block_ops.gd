class_name BlockOps
extends RefCounted
## Операции над блоками построек (общие для редактора, игры и тестов):
## «Улучшить» (каркас -> материал), «Текстура» (вариант), «Прочность» (осмотр).

## Заглушка стоимости улучшения в обычной игре: {ресурс: количество}. В редакторе бесплатно.
static func upgrade_cost(id: int, tier: int) -> Dictionary:
	return {}   # TODO: подключить ресурсы (доски, цемент) когда появится система ресурсов


## Улучшить/заменить материал кубического блока. editor=true — любой tier бесплатно;
## в игре только вверх по ступеням (с каркаса) и с оплатой (заглушка).
static func upgrade(bb: BlockBuilding, c: Vector3i, tier: int, editor: bool = true) -> bool:
	var g := bb.grid
	var a := g.anchor_of(c)
	var id := g.get_cell(a.x, a.y, a.z)
	if id == 0 or not BlockRegistry.is_new(id) or BlockRegistry.tier_count(id) == 0:
		return false
	var m := g.get_meta_at(a.x, a.y, a.z)
	var cur := BlockRegistry.tier_of(m)
	tier = clampi(tier, 0, BlockRegistry.tier_count(id) - 1)
	if tier == cur:
		return false
	if not editor and tier < cur:
		return false
	var variant := mini(BlockRegistry.variant_of(m), BlockRegistry.variant_count(id, tier) - 1)
	g.set_cell(a.x, a.y, a.z, id, BlockRegistry.with_tier_variant(m, tier, variant))
	g.hp.erase(g.idx(a.x, a.y, a.z))      # новый материал — полная прочность по таблице
	bb.refresh_cells([a])
	return true


## Установить вариант текстуры (по модулю числа вариантов материала); прочность и материал не меняются.
static func set_variant(bb: BlockBuilding, c: Vector3i, variant: int) -> bool:
	var g := bb.grid
	var a := g.anchor_of(c)
	var id := g.get_cell(a.x, a.y, a.z)
	if id == 0 or not BlockRegistry.is_new(id):
		return false
	var m := g.get_meta_at(a.x, a.y, a.z)
	var tier := BlockRegistry.tier_of(m)
	var n := BlockRegistry.variant_count(id, tier)
	variant = posmod(variant, n)
	if variant == BlockRegistry.variant_of(m):
		return false
	g.set_cell(a.x, a.y, a.z, id, BlockRegistry.with_tier_variant(m, tier, variant))
	bb.refresh_cells([a])
	return true


static func cycle_variant(bb: BlockBuilding, c: Vector3i, delta: int) -> bool:
	var a := bb.grid.anchor_of(c)
	return set_variant(bb, c, BlockRegistry.variant_of(bb.grid.get_meta_at(a.x, a.y, a.z)) + delta)


## Осмотр блока: имя, материал, тип, hp (максимум и текущее), tier, вариант.
static func inspect(g: BlockGrid, c: Vector3i) -> Dictionary:
	var id := g.get_cell(c.x, c.y, c.z)
	if id == 0:
		return {}
	var a := g.anchor_of(c)
	id = g.get_cell(a.x, a.y, a.z)
	var m := g.get_meta_at(a.x, a.y, a.z)
	if not BlockRegistry.is_new(id):
		return {"name": "старый блок %d" % id, "material": "legacy", "kind": "-", "hp_max": float(BlockDefs.hp(id)), "hp": float(g.hp.get(g.idx(a.x, a.y, a.z), BlockDefs.hp(id))), "tier": 0, "variant": 0, "anchor": a}
	var tier := BlockRegistry.tier_of(m)
	var hpm := BlockRegistry.hp(id, tier)
	return {
		"name": BlockRegistry.display_name(id, tier),
		"material": BlockRegistry.material_key(id, tier),
		"kind": BlockRegistry.kind(id, tier),
		"hp_max": hpm,
		"hp": float(g.hp.get(g.idx(a.x, a.y, a.z), hpm)),
		"tier": tier,
		"variant": BlockRegistry.variant_of(m),
		"variants": BlockRegistry.variant_count(id, tier),
		"rot": BlockRegistry.rot_of(m),
		"anchor": a,
	}
