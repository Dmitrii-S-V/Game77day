extends SceneTree
## Р“РµРЅРµСЂР°С‚РѕСЂ Р±РµСЃС€РѕРІРЅС‹С… С‚РµРєСЃС‚СѓСЂ Р»Р°РЅРґС€Р°С„С‚Р° (С‚СЂР°РІР°, Р·РµРјР»СЏ, РєР°РјРµРЅСЊ, РїРµСЃРѕРє).
## Р—Р°РїСѓСЃРє: C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_textures.gd

const SIZE := 512
const OUT := "res://assets/textures/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_grass()
	_dirt()
	_stone()
	_sand()
	_asphalt()
	_concrete()
	_gravel()
	_road_sand()
	quit()


# Р‘РµСЃС€РѕРІРЅРѕРµ РїРѕР»Рµ С€СѓРјР° 0..1
func _field(type: int, freq: float, seed_v: int, octaves: int = 4, fractal: int = FastNoiseLite.FRACTAL_FBM, cell_ret: int = -1) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.seed = seed_v
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	if cell_ret >= 0:
		n.cellular_return_type = cell_ret
	var img := n.get_seamless_image(SIZE, SIZE, false, false, 0.2, true)
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()
	var out := PackedFloat32Array()
	out.resize(SIZE * SIZE)
	for i in out.size():
		out[i] = data[i] / 255.0
	return out


func _gradient(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


func _save(name: String, pix: PackedByteArray) -> void:
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, pix)
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	var err := img.save_png(path)
	print("%s -> %s (err %d)" % [name, path, err])


func _bake(name: String, color_fn: Callable) -> void:
	var pix := PackedByteArray()
	pix.resize(SIZE * SIZE * 3)
	for i in SIZE * SIZE:
		var c: Color = color_fn.call(i)
		pix[i * 3] = int(clampf(c.r, 0.0, 1.0) * 255.0)
		pix[i * 3 + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
		pix[i * 3 + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
	_save(name, pix)


func _grass() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 11, 4)
	var mid := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 12, 3)
	var blades := _field(FastNoiseLite.TYPE_SIMPLEX, 0.35, 13, 2)
	var dry := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 14, 2)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.10, 0.22, 0.06), Color(0.22, 0.38, 0.10), Color(0.38, 0.50, 0.16)])
	var dry_col := Color(0.50, 0.46, 0.20)
	_bake("terrain_grass", func(i: int) -> Color:
		var t := low[i] * 0.45 + mid[i] * 0.25 + blades[i] * 0.30
		var c := ramp.sample(t)
		c = c.lerp(dry_col, smoothstep(0.62, 0.95, dry[i]) * 0.55)
		return c * (0.72 + 0.55 * blades[i]))


func _dirt() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.015, 21, 4)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.30, 22, 2)
	var pebbles := _field(FastNoiseLite.TYPE_CELLULAR, 0.07, 23, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.RETURN_DISTANCE)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.16, 0.10, 0.06), Color(0.30, 0.20, 0.12), Color(0.42, 0.30, 0.19)])
	_bake("terrain_dirt", func(i: int) -> Color:
		var c := ramp.sample(low[i] * 0.55 + grain[i] * 0.45)
		var peb := smoothstep(0.30, 0.20, pebbles[i]) * smoothstep(0.55, 0.75, grain[i])
		c = c.lerp(Color(0.45, 0.40, 0.34), peb * 0.6)
		return c * (0.8 + 0.4 * grain[i]))


func _stone() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 31, 5)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.25, 32, 3)
	var cracks := _field(FastNoiseLite.TYPE_CELLULAR, 0.012, 33, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var strata := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 34, 3)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.22, 0.22, 0.23), Color(0.40, 0.39, 0.38), Color(0.58, 0.56, 0.53)])
	_bake("terrain_stone", func(i: int) -> Color:
		var t := low[i] * 0.4 + grain[i] * 0.35 + strata[i] * 0.25
		var c := ramp.sample(t)
		var crack := smoothstep(0.0, 0.10, cracks[i])
		c *= mix_f(0.6, 1.0, crack)
		c = c.lerp(Color(0.38, 0.33, 0.28), smoothstep(0.7, 0.95, strata[i]) * 0.25)
		return c * (0.85 + 0.3 * grain[i]))


func _sand() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 41, 3)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.5, 42, 2)
	var ripples := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 43, 2)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.62, 0.53, 0.36), Color(0.76, 0.67, 0.48), Color(0.86, 0.78, 0.58)])
	_bake("terrain_sand", func(i: int) -> Color:
		var c := ramp.sample(low[i] * 0.4 + ripples[i] * 0.3 + grain[i] * 0.3)
		return c * (0.88 + 0.24 * grain[i]))


func _asphalt() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.01, 51, 4)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.6, 52, 2)
	var fine := _field(FastNoiseLite.TYPE_SIMPLEX, 0.25, 53, 2)
	var cracks := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 54, 4, FastNoiseLite.FRACTAL_RIDGED)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.07, 0.07, 0.08), Color(0.14, 0.14, 0.15), Color(0.22, 0.22, 0.23)])
	_bake("terrain_asphalt", func(i: int) -> Color:
		var c := ramp.sample(low[i] * 0.35 + grain[i] * 0.4 + fine[i] * 0.25)
		c *= mix_f(0.55, 1.0, 1.0 - smoothstep(0.93, 1.0, cracks[i]))
		return c * (0.85 + 0.3 * grain[i]))


func _concrete() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 61, 4)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.5, 62, 3)
	var stain := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 63, 3)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.42, 0.42, 0.41), Color(0.56, 0.56, 0.54), Color(0.68, 0.67, 0.65)])
	_bake("terrain_concrete", func(i: int) -> Color:
		var x := i % SIZE
		var y := i / SIZE
		var c := ramp.sample(low[i] * 0.4 + grain[i] * 0.35 + stain[i] * 0.25)
		# швы плит: каждые SIZE/2 пикселей по обеим осям (тайл 5 м -> плита 2.5 м)
		var jx := minf(float(x % (SIZE / 2)), float((SIZE / 2) - x % (SIZE / 2)))
		var jy := minf(float(y % (SIZE / 2)), float((SIZE / 2) - y % (SIZE / 2)))
		var joint := smoothstep(0.0, 2.5, minf(jx, jy))
		c *= mix_f(0.45, 1.0, joint)
		c = c.lerp(Color(0.40, 0.38, 0.34), smoothstep(0.7, 0.95, stain[i]) * 0.3)
		return c * (0.9 + 0.2 * grain[i]))


func _gravel() -> void:
	var cell := _field(FastNoiseLite.TYPE_CELLULAR, 0.22, 71, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.RETURN_CELL_VALUE)
	var edge := _field(FastNoiseLite.TYPE_CELLULAR, 0.22, 71, 1, FastNoiseLite.FRACTAL_NONE, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.5, 72, 2)
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.015, 73, 3)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.30, 0.28, 0.26), Color(0.52, 0.48, 0.42), Color(0.68, 0.64, 0.58)])
	_bake("terrain_gravel", func(i: int) -> Color:
		var c := ramp.sample(0.25 + cell[i] * 0.35 + low[i] * 0.2 + grain[i] * 0.2)
		c *= mix_f(0.6, 1.0, smoothstep(0.0, 0.12, edge[i]))
		return c * (0.8 + 0.4 * grain[i]))


func _road_sand() -> void:
	var low := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.015, 81, 3)
	var grain := _field(FastNoiseLite.TYPE_SIMPLEX, 0.55, 82, 2)
	var drift := _field(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.04, 83, 2)
	var ramp := _gradient([0.0, 0.5, 1.0], [Color(0.66, 0.56, 0.38), Color(0.80, 0.70, 0.50), Color(0.90, 0.82, 0.62)])
	_bake("terrain_roadsand", func(i: int) -> Color:
		var c := ramp.sample(low[i] * 0.3 + drift[i] * 0.3 + grain[i] * 0.4)
		c = c.lerp(Color(0.50, 0.42, 0.30), smoothstep(0.75, 0.95, grain[i]) * 0.35)
		return c * (0.9 + 0.2 * grain[i]))


func mix_f(a: float, b: float, t: float) -> float:
	return a + (b - a) * t
