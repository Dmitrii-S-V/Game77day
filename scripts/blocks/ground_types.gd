class_name GroundTypes
extends RefCounted
## Покрытие земли под постройкой (рисуется в редакторе структур, хранится в префабе «ground»): асфальт, бетон, гравий,
## грунтовка, песок, трава. В мире — тонкий слой поверх ландшафта (BlockBuilding), с рваным краем по шуму.
## Новый тип — строка в TYPES (текстура из assets/textures/, её _n — нормаль).

const TYPES := {
	"grass":    {"name": "Трава",     "tex": "grass_a",        "tile": 2.5, "rough": 0.95, "desat": 0.45, "gain": 1.45},
	"asphalt":  {"name": "Асфальт",   "tex": "road_asphalt",   "tile": 3.0, "rough": 0.85},
	"concrete": {"name": "Бетон",     "tex": "road_concrete",  "tile": 3.0, "rough": 0.9},
	"gravel":   {"name": "Гравий",    "tex": "terrain_gravel", "tile": 2.0, "rough": 0.95},
	"dirt":     {"name": "Грунтовка", "tex": "road_dirt",      "tile": 3.0, "rough": 0.95},
	"sand":     {"name": "Песок",     "tex": "terrain_sand",   "tile": 3.0, "rough": 0.9},
}
const ORDER := ["grass", "asphalt", "concrete", "gravel", "dirt", "sand"]

static var _mats := {}
static var _icons := {}


static func material(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var t: Dictionary = TYPES.get(key, TYPES["grass"])
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground_paint.gdshader")
	m.set_shader_parameter("tex", TexCache.texture("res://assets/textures/%s.png" % t["tex"], true, 1024))
	var np := "res://assets/textures/%s_n.png" % t["tex"]
	if ResourceLoader.exists(np) or FileAccess.file_exists(np):
		m.set_shader_parameter("tex_n", TexCache.texture(np, false, 1024))
		m.set_shader_parameter("use_n", true)
	m.set_shader_parameter("tile", float(t["tile"]))
	m.set_shader_parameter("rough", float(t["rough"]))
	m.set_shader_parameter("desat", float(t.get("desat", 0.0)))
	m.set_shader_parameter("gain", float(t.get("gain", 1.0)))
	_mats[key] = m
	return m


static func icon(key: String) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var img := TexCache.load_image("res://assets/textures/%s.png" % TYPES[key]["tex"])
	if img == null:
		img = Image.create(40, 40, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.5, 0.5))
	img.resize(40, 40, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## Узел с покрытием: cells — Vector2i(x, z) -> ключ; ячейка (x, z) занимает [x, x+1] x [z, z+1] м от начала узла.
## Альфа вершины = доля закрашенных соседних ячеек: у внешнего края покрытие истончается (шейдер рвёт край по шуму).
static func make_node(cells: Dictionary, cell: float = 1.0, seed_v: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundPaint"
	var by_type := {}
	for c: Vector2i in cells:
		var k: String = cells[c]
		if not by_type.has(k):
			by_type[k] = []
		(by_type[k] as Array).append(c)
	for k: String in by_type:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c: Vector2i in by_type[k]:
			var corners := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
			var a: Array = []
			for o: Vector2i in corners:
				# вершина (c + o) окружена 4 ячейками: (c+o) - (0/1, 0/1)
				var same := 0
				for dz in 2:
					for dx in 2:
						# любой закрашенный сосед: между двумя покрытиями граница ровная (без щелей), рвётся только край к земле
						if cells.has(c + o - Vector2i(dx, dz)):
							same += 1
				a.append(same / 4.0)
			var p := [Vector3(c.x, 0, c.y), Vector3(c.x + 1, 0, c.y), Vector3(c.x + 1, 0, c.y + 1), Vector3(c.x, 0, c.y + 1)]
			for t: Array in [[0, 1, 2], [0, 2, 3]]:   # по часовой при взгляде сверху — лицевая сторона вверх
				for i: int in t:
					st.set_normal(Vector3.UP)
					st.set_color(Color(1, 1, 1, a[i]))
					st.add_vertex((p[i] as Vector3) * cell)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = material(k)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# на траве сама растёт низкая трава (кустики осоки)
	if by_type.has("grass"):
		root.add_child(PropFactory.tufts_for(cells, cell, seed_v))
	return root
