class_name ContactShadow
extends RefCounted
## Простая контактная тень под камнем или предметом на земле: тёмное размытое пятно (декаль сверху вниз) — объект
## «стоит» на земле, а не висит, даже там, где солнечные тени не считаются или их не видно. Ложится только на мир
## (cull_mask 1), гаснет с расстоянием.

const FADE_BEGIN := 35.0
const FADE_LEN := 15.0
static var _tex: Texture2D


## Тень под узлом: radius — радиус пятна, м (в масштабе мира), strength — непрозрачность в центре.
static func add(node: Node3D, radius: float, strength: float = 0.6) -> Decal:
	if _tex == null:
		_tex = ImageTexture.create_from_image(_image())
	var dc := Decal.new()
	dc.texture_albedo = _tex
	var s := maxf(absf(node.scale.x), 0.01)    # декаль — дочерняя: размер задаётся в системе узла
	dc.size = Vector3(radius * 2.0, 1.2, radius * 2.0) / s
	dc.position = Vector3(0.0, 0.25, 0.0) / s
	dc.modulate = Color(1, 1, 1, strength)
	dc.upper_fade = 0.15
	dc.lower_fade = 0.5
	dc.normal_fade = 0.5
	dc.cull_mask = 1
	dc.distance_fade_enabled = true
	dc.distance_fade_begin = FADE_BEGIN
	dc.distance_fade_length = FADE_LEN
	node.add_child(dc)
	return dc


## Круглое пятно: чёрное в центре, плавно к краю.
static func _image() -> Image:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	img.generate_mipmaps()
	return img
