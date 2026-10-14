extends SceneTree
## Импорт PBR-материала (ambientCG / Poly Haven / любой набор карт) в текстуры блоков.
## Запуск:
##   C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/import_pbr.gd -- <папка_с_картами> <имя_текстуры> [ao=0.5] [dir=blocks|terrain]
## Пример: --script res://tools/import_pbr.gd -- C:/dl/Concrete034_1K-JPG concrete_smooth_0
## Имена (<имя_текстуры>) — из data/blocks/materials.json, поле "tex" (например planks_fresh_0, concrete_cracked_1, brass).
## Находит по суффиксу: цвет (_Color, _Albedo, _BaseColor, _diff), нормаль (_NormalGL, _nor_gl, _normal_gl; DirectX-нормали
## (_NormalDX, _nor_dx) переворачиваются), шероховатость (_Roughness, _rough), AO (_AmbientOcclusion, _ao) — подмешивается в цвет.
## Результат (dir=blocks, по умолчанию): assets/textures/blocks/<имя>.png, <имя>_n.png, <имя>_r.png (игра подхватывает сразу).
## dir=terrain: assets/textures/<имя>.png и <имя>_n.png (RGB — нормаль, A — высота из карты смещения _Displacement/_height; её читает шейдер
## ландшафта) + маркер <имя>.photo: tools/prepare_textures.gd такие файлы больше не перезаписывает.

const COLOR_KEYS := ["_color", "_albedo", "_basecolor", "_base_color", "_diff", "_diffuse"]
const NORMAL_GL_KEYS := ["_normalgl", "_nor_gl", "_normal_gl", "_normal-gl"]
const NORMAL_DX_KEYS := ["_normaldx", "_nor_dx", "_normal_dx", "_normal-dx"]
const NORMAL_PLAIN_KEYS := ["_normal", "_nrm", "_nor"]
const ROUGH_KEYS := ["_roughness", "_rough"]
const AO_KEYS := ["_ambientocclusion", "_ao", "_occlusion"]
const DISP_KEYS := ["_displacement", "_disp", "_height", "_bump"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("Использование: import_pbr.gd -- <папка> <имя_текстуры> [ao=0.5]")
		quit(1)
		return
	var ao_amount := 0.5
	var terrain := false
	var out_size := 0
	for a in args:
		if a.begins_with("size="):
			out_size = int(a.substr(5))
		elif a.begins_with("ao="):
			ao_amount = float(a.substr(3))
		elif a == "dir=terrain":
			terrain = true
	var folder := String(args[0])
	var tex_name := String(args[1])
	var files := _list(folder)
	if files.is_empty():
		print("Нет файлов изображений в ", folder)
		quit(1)
		return
	var color_f := _find(files, COLOR_KEYS)
	var ngl_f := _find(files, NORMAL_GL_KEYS)
	var ndx_f := _find(files, NORMAL_DX_KEYS)
	var nplain_f := _find(files, NORMAL_PLAIN_KEYS, NORMAL_GL_KEYS + NORMAL_DX_KEYS)
	var rough_f := _find(files, ROUGH_KEYS)
	var ao_f := _find(files, AO_KEYS)
	var disp_f := _find(files, DISP_KEYS)
	if color_f == "":
		print("Не найдена карта цвета (_Color/_Albedo/_diff) в ", folder)
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://assets/textures/" if terrain else "res://assets/textures/blocks/")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var col := Image.load_from_file(color_f)
	col.convert(Image.FORMAT_RGBA8)
	if out_size > 0 and col.get_width() > out_size:
		col.resize(out_size, int(col.get_height() * float(out_size) / col.get_width()), Image.INTERPOLATE_LANCZOS)
	if ao_f != "" and ao_amount > 0.0:
		var ao := Image.load_from_file(ao_f)
		ao.convert(Image.FORMAT_L8)
		if ao.get_size() != col.get_size():
			ao.resize(col.get_width(), col.get_height(), Image.INTERPOLATE_LANCZOS)
		for y in col.get_height():
			for x in col.get_width():
				var c := col.get_pixel(x, y)
				var k := lerpf(1.0, ao.get_pixel(x, y).r, ao_amount)
				col.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	col.save_png(out_dir + tex_name + ".png")
	var report := "цвет " + color_f.get_file()
	var nfile := ngl_f if ngl_f != "" else (nplain_f if ndx_f == "" else ndx_f)
	if nfile != "":
		var n := Image.load_from_file(nfile)
		n.convert(Image.FORMAT_RGBA8)
		if n.get_size() != col.get_size():
			n.resize(col.get_width(), col.get_height(), Image.INTERPOLATE_LANCZOS)
		if nfile == ndx_f:
			for y in n.get_height():
				for x in n.get_width():
					var c := n.get_pixel(x, y)
					n.set_pixel(x, y, Color(c.r, 1.0 - c.g, c.b, 1.0))
		if terrain:
			# альфа = высота (смещение), шейдер ландшафта использует её для детальной светотени
			var hgt: Image = null
			if disp_f != "":
				hgt = Image.load_from_file(disp_f)
				hgt.convert(Image.FORMAT_L8)
				if hgt.get_size() != n.get_size():
					hgt.resize(n.get_width(), n.get_height(), Image.INTERPOLATE_LANCZOS)
			for y in n.get_height():
				for x in n.get_width():
					var c2 := n.get_pixel(x, y)
					c2.a = hgt.get_pixel(x, y).r if hgt != null else 0.5
					n.set_pixel(x, y, c2)
		n.save_png(out_dir + tex_name + "_n.png")
		report += ", нормаль " + nfile.get_file() + (" (DX->GL)" if nfile == ndx_f else "")
	if rough_f != "":
		var r := Image.load_from_file(rough_f)
		r.convert(Image.FORMAT_L8)
		if r.get_size() != col.get_size():
			r.resize(col.get_width(), col.get_height(), Image.INTERPOLATE_LANCZOS)
		r.save_png(out_dir + tex_name + "_r.png")
		report += ", шероховатость " + rough_f.get_file()
	if terrain:
		var mf := FileAccess.open(out_dir + tex_name + ".photo", FileAccess.WRITE)
		mf.store_string("photoreal import - do not overwrite\n")
	print("Импортировано в ", tex_name, ": ", report)
	quit()


func _list(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(folder)
	if d == null:
		return out
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "exr", "tga", "bmp"]:
			out.append(folder.path_join(f))
	return out


func _find(files: PackedStringArray, keys: Array, exclude: Array = []) -> String:
	for f in files:
		var base := f.get_file().get_basename().to_lower()
		var bad := false
		for e: String in exclude:
			if e in base:
				bad = true
		if bad:
			continue
		for k: String in keys:
			if base.ends_with(k) or (k + "_") in base or (k + "-") in base:
				return f
	return ""
