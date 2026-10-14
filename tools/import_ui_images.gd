extends SceneTree
## Свои картинки -> игра. Положить PNG/JPG в D:\77Days\assets\src\ui_in\ с именами:
##   <id предмета>.png (grass_rope, stone, planks, plastic, …) -> иконка assets/icons/<id>.png (128 px);
##   cursor.png -> курсор assets/ui/cursor.png (40 px);
##   panel/slot/slot_sel/button/… .png -> элементы оформления assets/ui/<имя>.png (как есть, без обрезки фона).
## Белый (или однотонный светлый) фон вокруг предмета убирается заливкой от краёв, края сглаживаются, картинка
## обрезается по содержимому. Иконки из своих картинок записываются в assets/icons/custom.txt — tools/gen_icons.gd
## их не перезаписывает.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/import_ui_images.gd
## Затем: godot --headless --path D:\77Days --import --quit

const SRC := "res://assets/src/ui_in/"
const UI_PARTS := ["panel", "slot", "slot_hover", "slot_sel", "slot_bad", "button", "button_hover", "button_press",
	"button_off", "tab", "tab_hover", "tab_on", "row", "row_hover", "row_sel"]


func _init() -> void:
	var d := DirAccess.open(SRC)
	if d == null:
		print("Нет папки ", ProjectSettings.globalize_path(SRC))
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/"))
	var custom := _read_custom()
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if not ext in ["png", "jpg", "jpeg", "webp"]:
			continue
		var name := f.get_basename().to_lower()
		var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + f))
		if img == null:
			print("не прочитал ", f)
			continue
		img.convert(Image.FORMAT_RGBA8)
		if name in UI_PARTS:
			img.save_png(ProjectSettings.globalize_path("res://assets/ui/%s.png" % name))
			print("UI ", name)
		elif name == "cursor":
			var c := _fit(_cut_bg(img), 40, 0)
			c.save_png(ProjectSettings.globalize_path("res://assets/ui/cursor.png"))
			print("CURSOR")
		elif ItemDB.ITEMS.has(name):
			var ic := _fit(_cut_bg(img), 128, 6)
			ic.save_png(ProjectSettings.globalize_path("res://assets/icons/%s.png" % name))
			custom[name] = true
			print("ICON ", name)
		else:
			print("пропущен (неизвестное имя): ", f)
	var fw := FileAccess.open("res://assets/icons/custom.txt", FileAccess.WRITE)
	fw.store_string("\n".join(PackedStringArray(custom.keys())))
	quit()


static func _read_custom() -> Dictionary:
	var out := {}
	if FileAccess.file_exists("res://assets/icons/custom.txt"):
		for l in FileAccess.get_file_as_string("res://assets/icons/custom.txt").split("\n", false):
			out[l.strip_edges()] = true
	return out


## Убрать фон: цвет фона — по углам; заливка от краёв по похожим пикселям -> прозрачно; мягкий край 1 px.
static func _cut_bg(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var bg := (img.get_pixel(0, 0) + img.get_pixel(w - 1, 0) + img.get_pixel(0, h - 1) + img.get_pixel(w - 1, h - 1)) / 4.0
	if img.get_pixel(0, 0).a < 0.1:
		return img     # уже с прозрачностью
	var tol := 0.16
	var mask := PackedByteArray()
	mask.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if mask[i] != 0:
			continue
		var c := img.get_pixel(i % w, i / w)
		if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > tol * 3.0:
			continue
		mask[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	# дыры внутри предмета (петли верёвки, ручка пакета): крупные области почти точно цвета фона
	var seen := PackedByteArray()
	seen.resize(w * h)
	for i0 in w * h:
		if mask[i0] != 0 or seen[i0] != 0 or not _near(img.get_pixel(i0 % w, i0 / w), bg, 0.06):
			continue
		var comp: Array[int] = []
		var st: Array[int] = [i0]
		seen[i0] = 1
		while not st.is_empty():
			var j: int = st.pop_back()
			comp.append(j)
			var jx := j % w
			var jy := j / w
			for nb in [j - 1 if jx > 0 else -1, j + 1 if jx < w - 1 else -1, j - w if jy > 0 else -1, j + w if jy < h - 1 else -1]:
				if nb >= 0 and seen[nb] == 0 and mask[nb] == 0 and _near(img.get_pixel(nb % w, nb / w), bg, 0.06):
					seen[nb] = 1
					st.append(nb)
		if comp.size() >= w * h / 4000 + 40:     # мелкие светлые блики на предмете не трогаем
			for j in comp:
				mask[j] = 1
	var out := img.duplicate() as Image
	for y in h:
		for x in w:
			var i := y * w + x
			if mask[i] != 0:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# край: пиксель предмета рядом с фоном — полупрозрачный (без белой каймы)
				var edge := (x > 0 and mask[i - 1] != 0) or (x < w - 1 and mask[i + 1] != 0) or (y > 0 and mask[i - w] != 0) or (y < h - 1 and mask[i + w] != 0)
				if edge:
					var c := out.get_pixel(x, y)
					c.a = 0.5
					out.set_pixel(x, y, c)
	return out


static func _near(c: Color, bg: Color, tol: float) -> bool:
	return absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) <= tol * 3.0


## Обрезать по содержимому, вписать в квадрат size с отступом pad.
static func _fit(img: Image, size: int, pad: int) -> Image:
	var r := img.get_used_rect()
	if r.size.x <= 0:
		r = Rect2i(0, 0, img.get_width(), img.get_height())
	var part := img.get_region(r)
	var inner := size - pad * 2
	var k := float(inner) / maxf(r.size.x, r.size.y)
	part.resize(maxi(1, roundi(r.size.x * k)), maxi(1, roundi(r.size.y * k)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var at := Vector2i((size - part.get_width()) / 2, (size - part.get_height()) / 2) if pad > 0 else Vector2i.ZERO
	out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), at)
	return out
