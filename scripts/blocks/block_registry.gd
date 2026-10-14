class_name BlockRegistry
extends RefCounted
## Реестр блоков построек (data-driven): типы блоков и материалы читаются из res://data/blocks/*.json.
## Состояние ячейки: id (байт в BlockGrid.cells) + meta (int32 в BlockGrid.meta):
##   бит 0-1 поворот, 2-5 tier, 6-9 вариант текстуры, 10-11 состояние (бит 10 — открыто),
##   бит 12 — «часть» многоячеечного блока, 13-16 / 17-20 / 21-24 — смещение части от якоря (x, y, z).
## Старые блоки зданий (id 1..18) в реестр не входят и работают как раньше (BlockDefs).

const FIRST_ID := 32
const DIR := "res://data/blocks/"
const TEX_DIR := "res://assets/textures/blocks/"
static var tex_size := 256

static var _loaded := false
static var _blocks := {}          # id -> Dictionary
static var _by_key := {}          # key -> id
static var _materials := {}       # key -> Dictionary
static var _tools := {}
static var _categories: Array = []
static var _lights := {"max_active": 8, "fade_begin": 16.0, "fade_length": 6.0}
static var _layer_of := {}        # имя текстуры -> слой массива
static var _layer_names: Array[String] = []
static var _tex_array: Texture2DArray
static var _nr_array: Texture2DArray
static var _icons := {}


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var mats := _read_json(DIR + "materials.json")
	_materials = mats.get("materials", {})
	_tools = mats.get("tool_multipliers", {})
	tex_size = clampi(int(mats.get("texture_size", 256)), 64, 2048)
	if OS.has_feature("mobile"):
		tex_size = mini(tex_size, 256)    # телефон: массивы текстур блоков без сжатия — иначе сотни МБ видеопамяти
	var blocks := _read_json(DIR + "blocks.json")
	_categories = blocks.get("categories", [])
	_lights = blocks.get("lights", _lights)
	var all_blocks: Array = blocks.get("blocks", [])
	var wall_tiers: Array = []
	for b0: Dictionary in all_blocks:
		if b0.has("tiers") and wall_tiers.is_empty():
			wall_tiers = b0["tiers"]
	for b: Dictionary in all_blocks:
		if b.has("tiers_from") and not b.has("tiers"):
			# те же материалы, что у базового блока (кроме каркаса), категория — блока
			var tl: Array = []
			for td: Dictionary in wall_tiers:
				if not bool(td.get("frame", false)):
					var c := td.duplicate()
					c["category"] = b.get("category", "")
					tl.append(c)
			b["tiers"] = tl
		_blocks[int(b["id"])] = b
		_by_key[String(b["key"])] = int(b["id"])
	# слои текстур: сначала все варианты материалов, затем дополнительные
	var names: Array[String] = []
	for m: Dictionary in _materials.values():
		for t: String in m.get("tex", []):
			if not names.has(t):
				names.append(t)
	for t: String in mats.get("extra_textures", []):
		if not names.has(t):
			names.append(t)
	_layer_names = names
	for i in names.size():
		_layer_of[names[i]] = i


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Нет файла данных блоков: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Перечитать данные с диска (редактор: после правки JSON без перезапуска).
static func reload() -> void:
	_loaded = false
	_blocks = {}
	_by_key = {}
	_materials = {}
	_layer_of = {}
	_tex_array = null
	_nr_array = null
	_icons = {}
	ensure()


# --- метаданные ячейки ---------------------------------------------------------------

## Метаданные якоря: поворот вокруг вертикали (rot, 0..3), tier, вариант текстуры, состояние, «верх» (up, 0..5 —
## какая ось блока смотрит вверх: +Y, -Y, +X, -X, +Z, -Z; вместе с rot — любая из 24 ориентаций, только для блоков 1x1x1).
static func make_meta(rot: int = 0, tier: int = 0, variant: int = 0, state: int = 0, up: int = 0) -> int:
	return (rot & 3) | ((tier & 15) << 2) | ((variant & 15) << 6) | ((state & 3) << 10) | ((up & 7) << UP_SHIFT)


const UP_SHIFT := 25


static func up_of(meta: int) -> int:
	return (meta >> UP_SHIFT) & 7


## Тот же блок с другим материалом/вариантом (поворот, «верх» и состояние сохраняются).
static func with_tier_variant(meta: int, tier: int, variant: int) -> int:
	return make_meta(rot_of(meta), tier, variant, state_of(meta), up_of(meta))


## Поворот «верха»: какая ось блока смотрит вверх.
static func up_basis(up: int) -> Basis:
	match up:
		1: return Basis(Vector3.RIGHT, PI)
		2: return Basis(Vector3.BACK, -PI * 0.5)    # +Y -> +X
		3: return Basis(Vector3.BACK, PI * 0.5)     # +Y -> -X
		4: return Basis(Vector3.RIGHT, PI * 0.5)    # +Y -> +Z
		5: return Basis(Vector3.RIGHT, -PI * 0.5)   # +Y -> -Z
	return Basis()


## Полная ориентация блока: сначала поворот вокруг вертикали, затем «верх».
static func orient_basis(meta: int) -> Basis:
	return up_basis(up_of(meta)) * Basis(Vector3.UP, rot_of(meta) * PI * 0.5)


## Ближайшая из 24 ориентаций к базису: Vector2i(up, rot).
static func orient_from_basis(b: Basis) -> Vector2i:
	var best := Vector2i.ZERO
	var bd := 1e9
	for up in 6:
		for r in 4:
			var c := up_basis(up) * Basis(Vector3.UP, r * PI * 0.5)
			var d := (c.x - b.x).length_squared() + (c.y - b.y).length_squared() + (c.z - b.z).length_squared()
			if d < bd:
				bd = d
				best = Vector2i(up, r)
	return best


## Ориентация метаданных, повёрнутая дополнительным поворотом r (в мировых осях).
static func rotate_meta(meta: int, r: Basis) -> int:
	var o := orient_from_basis(r * orient_basis(meta))
	return make_meta(o.y, tier_of(meta), variant_of(meta), state_of(meta), o.x)


static func make_part(dx: int, dy: int, dz: int) -> int:
	return (1 << 12) | ((dx & 15) << 13) | ((dy & 15) << 17) | ((dz & 15) << 21)


static func rot_of(meta: int) -> int:
	return meta & 3


static func tier_of(meta: int) -> int:
	return (meta >> 2) & 15


static func variant_of(meta: int) -> int:
	return (meta >> 6) & 15


static func state_of(meta: int) -> int:
	return (meta >> 10) & 3


static func is_part(meta: int) -> bool:
	return ((meta >> 12) & 1) == 1


static func part_offset(meta: int) -> Vector3i:
	return Vector3i((meta >> 13) & 15, (meta >> 17) & 15, (meta >> 21) & 15)


# --- запросы -------------------------------------------------------------------------

static func is_new(id: int) -> bool:
	ensure()
	return _blocks.has(id)


static func block(id: int) -> Dictionary:
	ensure()
	return _blocks.get(id, {})


static func id_by_key(key: String) -> int:
	ensure()
	return int(_by_key.get(key, 0))


static func all_ids() -> Array:
	ensure()
	var ids := _blocks.keys()
	ids.sort()
	return ids


static func shape_of(id: int) -> String:
	return String(block(id).get("shape", "cube"))


static func is_cube(id: int) -> bool:
	return shape_of(id) == "cube"


static func tier_def(id: int, tier: int) -> Dictionary:
	var b := block(id)
	var tiers: Array = b.get("tiers", [])
	if tiers.is_empty():
		return {}
	return tiers[clampi(tier, 0, tiers.size() - 1)]


static func tier_count(id: int) -> int:
	return (block(id).get("tiers", []) as Array).size()


static func material_key(id: int, tier: int = 0) -> String:
	var td := tier_def(id, tier)
	if not td.is_empty():
		return String(td.get("material", ""))
	return String(block(id).get("material", ""))


static func material(id: int, tier: int = 0) -> Dictionary:
	ensure()
	return _materials.get(material_key(id, tier), {})


static func material_by_key(key: String) -> Dictionary:
	ensure()
	return _materials.get(key, {})


static func hp(id: int, tier: int = 0) -> float:
	return float(material(id, tier).get("hp", 50))


static func kind(id: int, tier: int = 0) -> String:
	return String(material(id, tier).get("kind", "wood"))


static func display_name(id: int, tier: int = 0) -> String:
	var td := tier_def(id, tier)
	if not td.is_empty():
		return String(td.get("name", ""))
	return String(block(id).get("name", ""))


static func category(id: int, tier: int = 0) -> String:
	var td := tier_def(id, tier)
	if not td.is_empty():
		return String(td.get("category", ""))
	return String(block(id).get("category", ""))


static func categories() -> Array:
	ensure()
	return _categories


## Множитель урона инструмента (axe | pickaxe | hand) по материалу блока.
static func tool_mult(tool_name: String, id: int, tier: int = 0) -> float:
	ensure()
	var t: Dictionary = _tools.get(tool_name, _tools.get("axe", {}))
	return float(t.get(kind(id, tier), 1.0))


static func is_frame(id: int, tier: int) -> bool:
	return bool(tier_def(id, tier).get("frame", false))


## Закрывает ли блок грани соседей (только сплошные кубы, не каркас).
static func occludes(id: int, meta: int) -> bool:
	if not is_new(id):
		return true
	if not is_cube(id):
		return false
	return not is_frame(id, tier_of(meta))


## Твёрдая опора для креплений (свеча, ковёр, люстра, паутина).
static func supports(id: int, meta: int) -> bool:
	if id == 0:
		return false
	if not is_new(id):
		return id != BlockDefs.GLASS
	return is_cube(id)


static func footprint(id: int, rot: int) -> Vector3i:
	var s: Array = block(id).get("size", [1, 1, 1])
	var v := Vector3i(int(s[0]), int(s[1]), int(s[2]))
	if rot & 1:
		return Vector3i(v.z, v.y, v.x)
	return v


static func support_mode(id: int) -> String:
	return String(block(id).get("support", ""))


static func is_soft(id: int) -> bool:
	return bool(block(id).get("soft", false))


static func light_cfg(id: int) -> Dictionary:
	return block(id).get("light", {})


static func lights_cfg() -> Dictionary:
	ensure()
	return _lights


## Палитра редактора: по пункту на каждый tier кубического блока и на каждый остальной блок.
static func palette() -> Array:
	ensure()
	var out := []
	for id: int in all_ids():
		var b: Dictionary = _blocks[id]
		var tiers: Array = b.get("tiers", [])
		if tiers.is_empty():
			out.append({"id": id, "tier": 0, "key": b["key"], "name": b["name"], "category": b.get("category", "")})
		else:
			for t in tiers.size():
				var td: Dictionary = tiers[t]
				out.append({"id": id, "tier": t, "key": "%s:%s" % [b["key"], td["key"]], "name": td["name"], "category": td.get("category", "")})
	return out


# --- текстуры ------------------------------------------------------------------------

static func layer_of(tex_name: String) -> int:
	ensure()
	return int(_layer_of.get(tex_name, 0))


## Слой массива текстур для (блок, tier, вариант).
static func tex_layer(id: int, tier: int, variant: int) -> int:
	var list: Array = material(id, tier).get("tex", [])
	if list.is_empty():
		return 0
	return layer_of(String(list[variant % list.size()]))


static func variant_count(id: int, tier: int = 0) -> int:
	return maxi(1, (material(id, tier).get("tex", []) as Array).size())


static func texture_image(tex_name: String) -> Image:
	var path := TEX_DIR + tex_name + ".png"
	var img: Image = null
	if TexCache.has_image(path):
		img = TexCache.load_image(path)
	if img == null:
		img = BlockTexGen.make(tex_name)
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != tex_size or img.get_height() != tex_size:
		img.resize(tex_size, tex_size, Image.INTERPOLATE_LANCZOS)
	return img


## Нормаль (RGB, OpenGL) + шероховатость (A) слоя: файлы <имя>_n.png и <имя>_r.png, иначе плоская нормаль и 0.85.
static func normal_rough_image(tex_name: String) -> Image:
	var out := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.5, 0.5, 1.0, 0.85))
	var np := TEX_DIR + tex_name + "_n.png"
	if TexCache.has_image(np):
		var n := TexCache.load_image(np)
		if n != null:
			n.convert(Image.FORMAT_RGBA8)
			n.resize(tex_size, tex_size, Image.INTERPOLATE_LANCZOS)
			out.blit_rect(n, Rect2i(0, 0, tex_size, tex_size), Vector2i.ZERO)
	var rp := TEX_DIR + tex_name + "_r.png"
	if TexCache.has_image(rp):
		var r := TexCache.load_image(rp)
		if r != null:
			r.convert(Image.FORMAT_L8)
			r.resize(tex_size, tex_size, Image.INTERPOLATE_LANCZOS)
			for y in tex_size:
				for x in tex_size:
					var c := out.get_pixel(x, y)
					c.a = r.get_pixel(x, y).r
					out.set_pixel(x, y, c)
	else:
		for y in tex_size:
			for x in tex_size:
				var c2 := out.get_pixel(x, y)
				c2.a = 0.85
				out.set_pixel(x, y, c2)
	return out


static func texture_array() -> Texture2DArray:
	ensure()
	if _tex_array != null:
		return _tex_array
	var imgs: Array[Image] = []
	for n in _layer_names:
		# слой из кэша (user://texcache): декодирование PNG и уменьшение — только при первом запуске
		var im := TexCache.image("blk_c_%s_%d" % [n, tex_size], [TEX_DIR + n + ".png"], func() -> Image:
			var a := texture_image(n)
			a.generate_mipmaps()
			return a)
		imgs.append(im)
	var ta := Texture2DArray.new()
	ta.create_from_images(imgs)
	_tex_array = ta
	return ta


static func normal_rough_array() -> Texture2DArray:
	ensure()
	if _nr_array != null:
		return _nr_array
	var imgs: Array[Image] = []
	for n in _layer_names:
		var im := TexCache.image("blk_nr_%s_%d" % [n, tex_size], [TEX_DIR + n + "_n.png", TEX_DIR + n + "_r.png"], func() -> Image:
			var a := normal_rough_image(n)
			a.generate_mipmaps()
			return a)
		imgs.append(im)
	var ta := Texture2DArray.new()
	ta.create_from_images(imgs)
	_nr_array = ta
	return ta


## Сколько метров занимает один повтор текстуры материала (по умолчанию 1).
static func tile_of(id: int, tier: int) -> float:
	return maxf(float(material(id, tier).get("tile", 1.0)), 0.05)


static func apply_to_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("tex_blocks", texture_array())
	mat.set_shader_parameter("tex_nr", normal_rough_array())
	BlockDecals.apply_to_material(mat)


## Материал блоков построек (шейдер block.gdshader + массив текстур).
static func make_block_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/block.gdshader")
	apply_to_material(m)
	return m


static func make_glass_material() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.55, 0.75, 0.85, 0.28)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.05
	g.metallic_specular = 0.9
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g


## Иконка палитры (32x32) из первого варианта текстуры.
static func icon(id: int, tier: int) -> Texture2D:
	var key := "%d:%d" % [id, tier]
	if _icons.has(key):
		return _icons[key]
	var list: Array = material(id, tier).get("tex", [])
	var img: Image
	if list.is_empty():
		img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.4, 0.4, 0.4))
	else:
		img = texture_image(String(list[0]))
		img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		if is_frame(id, tier):
			for y in 32:
				for x in 32:
					if x > 3 and x < 28 and y > 3 and y < 28:
						img.set_pixel(x, y, Color(0.15, 0.15, 0.18))
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex
