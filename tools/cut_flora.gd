extends SceneTree
## Нарезка листов растений (белый фон) в атласы карточек для GrassField:
##   assets/textures/flora_hogweed.png — борщевик (4x2 ячейки 384x768),
##   assets/textures/flora_wild.png    — трава, цветы, сухие кусты и трава (9x8 ячеек 256x256),
##   data/blocks/flora_wild.json       — ячейки: лист, ряд, вид, доля ячейки по высоте/ширине.
## Фон — заливкой от краёв по почти белым пикселям (кремовые соцветия внутри остаются), край — мягкий,
## белая кайма вычитается. Растения — по сетке листа (в ряду своё число растений); в ячейке берётся самый большой
## связный кусок и отдельные куски внутри, обрывки соседей у краёв ячейки отбрасываются.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/cut_flora.gd -- <hogweed.webp> <green.webp> <dry.webp>

const BG_MIN := 228          # фон: все каналы выше
const BG_SPREAD := 30        # и почти серый
const POCKET_MIN := 4       # белый «карман» внутри растения — от стольких пикселей


static func _pure_white(data: PackedByteArray, i: int) -> bool:
	var r := data[i * 4]
	var g := data[i * 4 + 1]
	var b := data[i * 4 + 2]
	return mini(r, mini(g, b)) > 236 and maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 16


const GRIDS := {"hogweed": [4, 4], "green": [8, 8, 8, 8], "dry": [7, 7, 7, 8, 8]}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("нужно 3 файла")
		quit()
		return
	var hog := _cut(Image.load_from_file(a[0]), "hogweed")
	var green := _cut(Image.load_from_file(a[1]), "green")
	var dry := _cut(Image.load_from_file(a[2]), "dry")
	print("hogweed %d, green %d, dry %d" % [hog.size(), green.size(), dry.size()])
	var items: Array = []
	_atlas(hog, 4, 2, Vector2i(384, 768), "res://assets/textures/flora_hogweed.png", items, "hogweed")
	_atlas(green + dry, 9, 8, Vector2i(256, 256), "res://assets/textures/flora_wild.png", items, "wild")
	var f := FileAccess.open("res://data/blocks/flora_wild.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"_comment": "Карточки растений (tools/cut_flora.gd). atlas: hogweed (4x2) | wild (9x8). " +
		"kind: hogweed | grass | flower | dry_bush | dry_grass | dry_weed. hf/wf — доля ячейки, занятая растением (высота/ширина); size — высота растения, м.",
		"items": items}, "  "))
	f.close()
	quit()


## Растения листа: [{img (RGBA, обрезано), row, sheet}]
func _cut(src: Image, sheet: String) -> Array:
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var data := src.get_data()
	# фон: заливка от краёв по почти белым пикселям
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] != 0:
			continue
		var r := data[i * 4]
		var g := data[i * 4 + 1]
		var b := data[i * 4 + 2]
		if mini(r, mini(g, b)) < BG_MIN or maxi(r, maxi(g, b)) - mini(r, mini(g, b)) > BG_SPREAD:
			continue
		bg[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	# замкнутые белые «карманы» между листьями: связные области почти чистого белого (строже, чем фон у краёв —
	# кремовые соцветия борщевика желтоватые и мелкие, остаются)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for i0 in w * h:
		if bg[i0] != 0 or seen[i0] != 0 or not _pure_white(data, i0):
			continue
		var region := PackedInt32Array()
		var st := PackedInt32Array([i0])
		seen[i0] = 1
		while not st.is_empty():
			var q := st[st.size() - 1]
			st.resize(st.size() - 1)
			region.append(q)
			var qx := q % w
			var qy := q / w
			for nb: int in [q - 1, q + 1, q - w, q + w]:
				if nb < 0 or nb >= w * h or (nb == q - 1 and qx == 0) or (nb == q + 1 and qx == w - 1):
					continue
				if seen[nb] == 0 and bg[nb] == 0 and _pure_white(data, nb):
					seen[nb] = 1
					st.append(nb)
		if region.size() >= POCKET_MIN:
			for q: int in region:
				bg[q] = 1
	var grid: Array = GRIDS[sheet]
	var out: Array = []
	var rh := float(h) / grid.size()
	for ri in grid.size():
		var nc: int = grid[ri]
		var cw := float(w) / nc
		for ci in nc:
			var keep := _components(bg, w, int(ci * cw), int(ri * rh), int((ci + 1) * cw), int((ri + 1) * rh))
			if keep.is_empty():
				continue
			var tx0 := w
			var tx1 := 0
			var ty0 := h
			var ty1 := 0
			for i: int in keep:
				tx0 = mini(tx0, i % w)
				tx1 = maxi(tx1, i % w + 1)
				ty0 = mini(ty0, i / w)
				ty1 = maxi(ty1, i / w + 1)
			var img := Image.create(tx1 - tx0 + 4, ty1 - ty0 + 4, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for i: int in keep:
				var x := i % w
				var y := i / w
				var c := Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
				# мягкий край: чем ближе к белому фону рядом, тем прозрачнее; белая кайма вычитается
				var near_bg := (x > 0 and bg[i - 1] != 0) or (x < w - 1 and bg[i + 1] != 0) or (y > 0 and bg[i - w] != 0) or (y < h - 1 and bg[i + w] != 0)
				var al := 1.0
				# почти белые и почти серые пиксели внутри (дырочки в листьях, просветы между травинками) — прозрачные;
				# кремовые соцветия желтоватые (разброс каналов больше) — остаются
				var mn := minf(c.r, minf(c.g, c.b))
				if maxf(c.r, maxf(c.g, c.b)) - mn < 0.09:
					al = 1.0 - smoothstep(0.84, 0.94, mn)
				if near_bg:
					var wht := clampf((minf(c.r, minf(c.g, c.b)) - 0.55) / 0.35, 0.0, 1.0)
					al = minf(al, 1.0 - wht * 0.85)
					if al < 0.98:
						c = Color((c.r - (1.0 - al)) / al, (c.g - (1.0 - al)) / al, (c.b - (1.0 - al)) / al).clamp()
				img.set_pixel(x - tx0 + 2, y - ty0 + 2, Color(c, al))
			out.append({"img": img, "row": ri, "sheet": sheet})
	return out


## Пиксели растения в ячейке: самый большой связный кусок + отдельные куски (соцветия, листья), не касающиеся
## краёв ячейки (касающиеся — обрывки соседних растений).
func _components(bg: PackedByteArray, w: int, x0: int, y0: int, x1: int, y1: int) -> PackedInt32Array:
	var cw := x1 - x0
	var chh := y1 - y0
	var lab := PackedInt32Array()
	lab.resize(cw * chh)
	var comps: Array = []
	for ly in chh:
		for lx in cw:
			var li := ly * cw + lx
			if lab[li] != 0 or bg[(y0 + ly) * w + x0 + lx] != 0:
				continue
			var id := comps.size() + 1
			var px := PackedInt32Array()
			var edge := false
			var st := PackedInt32Array([li])
			lab[li] = id
			while not st.is_empty():
				var q := st[st.size() - 1]
				st.resize(st.size() - 1)
				var qx := q % cw
				var qy := q / cw
				px.append((y0 + qy) * w + x0 + qx)
				if qx == 0 or qy == 0 or qx == cw - 1 or qy == chh - 1:
					edge = true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := qx + dx
						var ny := qy + dy
						if nx < 0 or ny < 0 or nx >= cw or ny >= chh:
							continue
						var ni := ny * cw + nx
						if lab[ni] == 0 and bg[(y0 + ny) * w + x0 + nx] == 0:
							lab[ni] = id
							st.append(ni)
			comps.append({"px": px, "edge": edge})
	if comps.is_empty():
		return PackedInt32Array()
	var big := 0
	for i in comps.size():
		if (comps[i]["px"] as PackedInt32Array).size() > (comps[big]["px"] as PackedInt32Array).size():
			big = i
	var out := PackedInt32Array()
	var min_px := maxi(12, int(cw * chh * 0.0015))
	for i in comps.size():
		var n := (comps[i]["px"] as PackedInt32Array).size()
		if i == big or (not bool(comps[i]["edge"]) and n >= min_px):
			out.append_array(comps[i]["px"])
	return out


func _kind(e: Dictionary) -> Array:
	# [вид, высота м] по листу и ряду
	match String(e["sheet"]):
		"hogweed":
			return ["hogweed", 2.4]
		"green":
			return [["grass", 1.0], ["flower", 0.45], ["grass", 0.95], ["flower", 0.6]][mini(int(e["row"]), 3)]
		_:
			return [["dry_bush", 1.0], ["dry_bush", 0.95], ["dry_grass", 1.05], ["dry_weed", 0.75], ["dry_grass", 0.85]][mini(int(e["row"]), 4)]


func _atlas(list: Array, cols: int, rows: int, cell: Vector2i, path: String, items: Array, atlas: String) -> void:
	var at := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	at.fill(Color(0, 0, 0, 0))
	for n in mini(list.size(), cols * rows):
		var e: Dictionary = list[n]
		var img: Image = e["img"]
		var pad := 4
		var k := minf(float(cell.x - pad * 2) / img.get_width(), float(cell.y - pad) / img.get_height())
		var sw := maxi(1, roundi(img.get_width() * k))
		var sh := maxi(1, roundi(img.get_height() * k))
		var sc := img.duplicate() as Image
		sc.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
		var ox := (n % cols) * cell.x + (cell.x - sw) / 2
		var oy := (n / cols) * cell.y + cell.y - sh      # корень — у нижнего края ячейки
		at.blend_rect(sc, Rect2i(0, 0, sw, sh), Vector2i(ox, oy))
		var kd := _kind(e)
		items.append({"atlas": atlas, "cell": n, "kind": kd[0], "size": kd[1], "hf": float(sh) / cell.y, "wf": float(sw) / cell.x,
			"sheet": e["sheet"], "row": e["row"]})
	_bleed(at)
	at.save_png(path)
	print("атлас ", path, " ", at.get_size(), " растений ", mini(list.size(), cols * rows))


## Цвет прозрачных пикселей у края растения — от соседних (без тёмной/белой каймы в мипмапах).
func _bleed(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for pass_i in 4:
		var src := img.duplicate() as Image
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a > 0.05:
					continue
				var acc := Color(0, 0, 0, 0)
				var n := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var px := x + d.x
					var py := y + d.y
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var q := src.get_pixel(px, py)
					if q.a > 0.05:
						acc += Color(q.r, q.g, q.b, 0)
						n += 1
				if n > 0:
					img.set_pixel(x, y, Color(acc.r / n, acc.g / n, acc.b / n, 0.0))
