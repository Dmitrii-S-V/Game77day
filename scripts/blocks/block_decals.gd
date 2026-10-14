class_name BlockDecals
extends RefCounted
## Декали на гранях блоков (грязь, отпечатки, знаки, афиши, пробоины, царапины, ржавчина).
## Данные: data/blocks/decals.json (таблица спрайтов, размеры, классы, веса), спрайты assets/textures/decals/*.png.
## Хранение в BlockGrid.decals: ключ ячейка*8 + грань (0..5: +x -x +y -y +z -z) -> упакованное значение
##   слой(8 бит) | поворот(2) << 8 | зеркало(1) << 10 | смещение x (6) << 11 | смещение y (6) << 17.
## Шейдер block.gdshader читает упакованное значение из UV.y граней кубов.

const MAX_LAYERS := 128

static var _loaded := false
static var _all: Array = []                 # все записи таблицы (Dictionary), по порядку
static var _wall: Array = []                # записи для граней блоков; индекс = слой в массиве
static var _by_key := {}                    # key -> слой стены
static var _by_kind := {}                   # kind -> Array[слой стены]
static var _weather := {}
static var _array: Texture2DArray
static var _info := PackedVector4Array()
static var _icons := {}


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/blocks/decals.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	_all = d.get("decals", [])
	_weather = d.get("weather", {})
	for e: Dictionary in _all:
		if "wall" in (e.get("places", []) as Array) and _wall.size() < MAX_LAYERS:
			var layer := _wall.size()
			_wall.append(e)
			_by_key[String(e["key"])] = layer
			var kind := String(e["kind"])
			if not _by_kind.has(kind):
				_by_kind[kind] = []
			(_by_kind[kind] as Array).append(layer)


static func count() -> int:
	ensure()
	return _wall.size()


static func entry(layer: int) -> Dictionary:
	ensure()
	return _wall[layer] if layer >= 0 and layer < _wall.size() else {}


static func layer_of(key: String) -> int:
	ensure()
	return int(_by_key.get(key, -1))


static func layers_of_kind(kind: String) -> Array:
	ensure()
	return _by_kind.get(kind, [])


static func kinds() -> Array:
	ensure()
	return _by_kind.keys()


static func weather_cfg() -> Dictionary:
	ensure()
	return _weather


## Может ли декаль вращаться (знаки, афиши и трафареты всегда стоят «вверх ногами» не должны).
static func can_rotate(layer: int) -> bool:
	return not (String(entry(layer).get("kind", "")) in ["sign", "poster", "stencil"])


static func size_of(layer: int) -> float:
	return float(entry(layer).get("size", 0.8))


## Упаковка параметров декали: смещения ox, oy в -1..1 (в пределах свободного места на грани).
static func pack(layer: int, rot: int = 0, flip: bool = false, ox: float = 0.0, oy: float = 0.0) -> int:
	var sz := size_of(layer)
	var room := clampf((1.0 - sz) / 0.4, 0.0, 1.0)   # шейдер смещает на offset * 0.4
	var qx := clampi(int(round((clampf(ox * room, -1.0, 1.0) * 0.5 + 0.5) * 63.0)), 0, 63)
	var qy := clampi(int(round((clampf(oy * room, -1.0, 1.0) * 0.5 + 0.5) * 63.0)), 0, 63)
	return (layer & 255) | ((rot & 3) << 8) | ((1 if flip else 0) << 10) | (qx << 11) | (qy << 17)


static func layer_of_packed(v: int) -> int:
	return v & 255


## Текстуры и параметры для материала блоков.
static func apply_to_material(mat: ShaderMaterial) -> void:
	ensure()
	mat.set_shader_parameter("tex_decals", texture_array())
	mat.set_shader_parameter("decal_info", info_array())


static func texture_array() -> Texture2DArray:
	ensure()
	if _array != null:
		return _array
	var imgs: Array[Image] = []
	for e: Dictionary in _wall:
		var im := TexCache.load_image(String(e["file"]))
		if im == null:
			im = Image.create(256, 256, false, Image.FORMAT_RGBA8)
		im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != 256 or im.get_height() != 256:
			im.resize(256, 256)
		im.generate_mipmaps()
		imgs.append(im)
	if imgs.is_empty():
		var empty := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		empty.generate_mipmaps()
		imgs.append(empty)
	var ta := Texture2DArray.new()
	ta.create_from_images(imgs)
	_array = ta
	return ta


static func info_array() -> PackedVector4Array:
	ensure()
	if _info.size() == MAX_LAYERS:
		return _info
	_info = PackedVector4Array()
	_info.resize(MAX_LAYERS)
	for i in MAX_LAYERS:
		_info[i] = Vector4(0.8, 0.0, 1.0, 0.0)
	for i in _wall.size():
		var e: Dictionary = _wall[i]
		var kind := String(e["kind"])
		var strength := 1.0
		match kind:
			"grime", "print":
				strength = 0.95
			"rust", "scratch":
				strength = 0.9
		_info[i] = Vector4(float(e.get("size", 0.8)), 1.0 if can_rotate(i) else 0.0, strength, 0.0)
	return _info


static func icon(layer: int) -> Texture2D:
	if _icons.has(layer):
		return _icons[layer]
	var e := entry(layer)
	var im := TexCache.load_image(String(e.get("file", "")))
	if im == null:
		im = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	im.convert(Image.FORMAT_RGBA8)
	im.resize(40, 40, Image.INTERPOLATE_LANCZOS)
	var bg := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.45, 0.47, 0.5, 1.0))
	bg.blend_rect(im, Rect2i(0, 0, 40, 40), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(bg)
	_icons[layer] = tex
	return tex
