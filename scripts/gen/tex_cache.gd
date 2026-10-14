class_name TexCache
extends RefCounted
## Кэш обработанных текстур: декодирование PNG (2K), уменьшение, мипмапы и сжатие в формат видеокарты (BC/DXT)
## делаются один раз, результат лежит в user://texcache/ и при следующих запусках читается почти мгновенно.
## Ключ включает время изменения исходных файлов: заменили PNG — кэш пересоберётся сам.

const DIR := "user://texcache/"
const VERSION := 1

static var _mem := {}
static var _mutex := Mutex.new()


## PNG из res:// как картинка: исходный файл (в редакторе) или импортированная текстура — в собранной игре (exe)
## исходных PNG нет, только импортированные (у всех текстур импорт без потерь — картинка та же).
static func load_image(res_path: String) -> Image:
	if FileAccess.file_exists(res_path):
		return Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if ResourceLoader.exists(res_path):
		var tex := ResourceLoader.load(res_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		if tex != null:
			var im := tex.get_image()
			if im != null and im.is_compressed():
				im.decompress()
			return im
	return null


## Есть ли такая картинка (исходный PNG или импортированная текстура).
static func has_image(res_path: String) -> bool:
	return FileAccess.file_exists(res_path) or ResourceLoader.exists(res_path)


static func _stamp(files: Array) -> String:
	var s := str(VERSION)
	for f: String in files:
		s += "|" + f + ":" + str(FileAccess.get_modified_time(f) if FileAccess.file_exists(f) else 0)
	return s.md5_text()


## Картинка из кэша или построенная builder() (и сохранённая). files — исходники, от которых она зависит.
## baked — сжатая (BC) картинка, которую можно «запечь» в сборку: в собранной игре (exe) Godot не умеет сжимать
## в BC, поэтому сжатые текстуры заранее сохраняются в res://texbake/ (запуск редактора с --bake-tex) и в exe
## берутся оттуда — быстрая загрузка и вчетверо-вшестеро меньше видеопамяти.
static func image(key: String, files: Array, builder: Callable, baked := false) -> Image:
	var bkey := key.validate_filename()
	if baked and not files.is_empty() and not FileAccess.file_exists(String(files[0])):
		# собранная игра (исходных PNG нет): запечённая
		var bp := BAKE_DIR + bkey + ".res"
		if ResourceLoader.exists(bp):
			var b := ResourceLoader.load(bp, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image
			if b != null and not b.is_empty():
				return b
	var path := DIR + bkey + "_" + _stamp(files) + ".res"
	var img: Image = null
	if ResourceLoader.exists(path):
		img = ResourceLoader.load(path, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image
		if img != null and img.is_empty():
			img = null
	if img == null:
		img = builder.call()
		if img != null and not img.is_empty():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
			ResourceSaver.save(img, path, ResourceSaver.FLAG_COMPRESS)
	if baked and img != null and img.is_compressed() and _baking:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
		if not FileAccess.file_exists(BAKE_DIR + bkey + ".res"):
			ResourceSaver.save(img, BAKE_DIR + bkey + ".res", ResourceSaver.FLAG_COMPRESS)
			print("BAKE ", bkey)
	return img


const BAKE_DIR := "res://texbake/"
static var MOBILE := OS.has_feature("mobile")
static var _baking := OS.get_cmdline_user_args().has("--bake-tex")


## Цвет + шероховатость в альфе (одна выборка в шейдере даёт и то и другое). Сжатие BC3 (DXT5).
static func texture_rgb_a(res_path: String, alpha_path: String, max_size: int = 0) -> Texture2D:
	if MOBILE:
		max_size = 512 if max_size <= 0 else mini(max_size, 512)
	var mk := "%s|%s|%d|ra" % [res_path, alpha_path, max_size]
	_mutex.lock()
	var t: Texture2D = _mem.get(mk)
	_mutex.unlock()
	if t != null:
		return t
	if not has_image(res_path):
		return null
	var img := image("texra_" + res_path.get_file().get_basename() + "_%d" % max_size, [res_path, alpha_path], func() -> Image:
		var im := load_image(res_path)
		if im == null:
			return null
		if max_size > 0 and im.get_width() > max_size:
			im.resize(max_size, int(im.get_height() * float(max_size) / im.get_width()), Image.INTERPOLATE_LANCZOS)
		im.convert(Image.FORMAT_RGBA8)
		var r := load_image(alpha_path) if has_image(alpha_path) else null
		if r != null:
			r.convert(Image.FORMAT_L8)
			if r.get_size() != im.get_size():
				r.resize(im.get_width(), im.get_height(), Image.INTERPOLATE_LANCZOS)
			for y in im.get_height():
				for x in im.get_width():
					var c := im.get_pixel(x, y)
					c.a = r.get_pixel(x, y).r
					im.set_pixel(x, y, c)
		else:
			# нет карты — средняя шероховатость (0.85)
			for y in im.get_height():
				for x in im.get_width():
					var c2 := im.get_pixel(x, y)
					c2.a = 0.85
					im.set_pixel(x, y, c2)
		im.generate_mipmaps()
		if not MOBILE:
			im.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		return im, not MOBILE)
	if img == null:
		return null
	t = ImageTexture.create_from_image(img)
	_mutex.lock()
	_mem[mk] = t
	_mutex.unlock()
	return t


## Текстура PNG: мипмапы, сжатие BC (srgb — цветовая, иначе данные: нормали/высота), ограничение размера.
static func texture(res_path: String, srgb: bool = true, max_size: int = 0, compress: bool = true) -> Texture2D:
	if MOBILE:
		# телефон: BC-сжатия нет (и видеокарты его не знают) — меньше размер вместо сжатия
		max_size = 512 if max_size <= 0 else mini(max_size, 512)
		compress = false
	var mk := "%s|%s|%d|%s" % [res_path, srgb, max_size, compress]
	_mutex.lock()
	var t: Texture2D = _mem.get(mk)
	_mutex.unlock()
	if t != null:
		return t
	if not has_image(res_path):
		return null
	var img := image("tex_" + res_path.get_file().get_basename() + "_%d_%d_%d" % [int(srgb), max_size, int(compress)], [res_path], func() -> Image:
		var im := load_image(res_path)
		if im == null:
			return null
		if max_size > 0 and im.get_width() > max_size:
			im.resize(max_size, int(im.get_height() * float(max_size) / im.get_width()), Image.INTERPOLATE_LANCZOS)
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		im.generate_mipmaps()
		if compress:
			im.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB if srgb else Image.COMPRESS_SOURCE_GENERIC)
		return im, compress)
	if img == null:
		return null
	t = ImageTexture.create_from_image(img)
	_mutex.lock()
	_mem[mk] = t
	_mutex.unlock()
	return t
