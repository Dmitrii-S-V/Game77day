class_name WorldMap
extends RefCounted
## Сгенерированная карта мира: макро-рельеф (сетка 4 м) по шуму и процентам гор/холмов/равнин,
## реки и озёра, города, POI и дороги. Строится один раз в меню, затем читается игрой.

const CELL := 4.0
const SEA := 13.5
const BINS := 4096

var params: WorldParams
var size := 2048
var gw := 0
var hm := PackedFloat32Array()
var hydro := Hydro.new()
var roads: RoadNet
var spawn := Vector3.ZERO
var biome := BiomeMap.new()
var info := ""
var ready := false

var _raw := PackedFloat32Array()
var _cdf := PackedFloat32Array()
var _hist_parts: Array = []
var _shares := Vector3(0.2, 0.3, 0.5)
var _n_base := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _hillock := FastNoiseLite.new()
var _side_n := FastNoiseLite.new()
const RDF_CELL := 8.0
const RDF_MAX := 60.0
var _rdf := PackedFloat32Array()   # расстояние до края дороги (м) по сетке RDF_CELL
var _rdf_w := 0
var _pv_size := 0
var _pv_rows := PackedByteArray()


## Генерация. Без tree (None) — блокирующая; с tree — асинхронная (кадры не замораживаются).
func generate(p: WorldParams, tree: SceneTree = null, progress: Callable = Callable()) -> void:
	ready = false
	params = p
	size = p.size
	gw = int(size / CELL) + 1
	_shares = p.shares()
	_setup_noise(p.seed_value)

	_report(progress, 0.02, "Шум рельефа")
	_raw.resize(gw * gw)
	await _wait(WorkerThreadPool.add_group_task(_raw_row, gw), tree)

	_report(progress, 0.25, "Распределение высот")
	var parts := ceili(gw / 16.0)
	_hist_parts.clear()
	_hist_parts.resize(parts)
	await _wait(WorkerThreadPool.add_group_task(_hist_job, parts), tree)
	var hist := PackedInt32Array()
	hist.resize(BINS)
	for part: PackedInt32Array in _hist_parts:
		for i in BINS:
			hist[i] += part[i]
	_cdf.resize(BINS + 1)
	var total := float(gw * gw)
	var acc := 0.0
	_cdf[0] = 0.0
	for i in BINS:
		acc += hist[i]
		_cdf[i + 1] = acc / total

	_report(progress, 0.35, "Горы, холмы, равнины")
	hm.resize(gw * gw)
	await _wait(WorkerThreadPool.add_group_task(_hm_row, gw), tree)
	_raw = PackedFloat32Array()

	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed_value
	hydro = Hydro.new()
	_report(progress, 0.55, "Реки и озёра")
	_gen_hydro(rng, p)

	_report(progress, 0.7, "Города, POI и дороги")
	roads = RoadNet.new(p.seed_value, terrain_height, SEA)
	roads.plan(self, rng, p)
	_build_road_field()
	if tree != null:
		await tree.process_frame
	spawn = roads.pick_spawn(Vector2(size * 0.5, size * 0.5))
	biome = BiomeMap.new()
	biome.build(size, p.seed_value, spawn, float(p.pct_burn))
	info = "Города: %d, POI: %d, реки: %d, озёра: %d, дороги: %d" % [
		roads.towns.size(), roads.pois.size(), hydro.rivers.size(), hydro.lakes.size(), roads.link_paths.size()]
	_report(progress, 1.0, "Готово")
	ready = true


func _report(progress: Callable, frac: float, text: String) -> void:
	if progress.is_valid():
		progress.call(frac, text)


func _wait(gid: int, tree: SceneTree) -> void:
	if tree == null:
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		while not WorkerThreadPool.is_group_task_completed(gid):
			await tree.process_frame
		WorkerThreadPool.wait_for_group_task_completion(gid)


func _setup_noise(s: int) -> void:
	_n_base.seed = s
	_n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.0007
	_n_base.fractal_octaves = 4
	_n_base.fractal_gain = 0.42
	_n_base.domain_warp_enabled = true
	_n_base.domain_warp_amplitude = 110.0
	_n_base.domain_warp_frequency = 0.0025
	_n_ridge.seed = s + 11
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.frequency = 0.0014
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 3
	_detail.seed = s + 21
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.05
	_detail.fractal_octaves = 3
	_roll.seed = s + 31
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.0065           # пологие волны равнин (~150 м)
	_roll.fractal_octaves = 2
	_hillock.seed = s + 41
	_hillock.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hillock.frequency = 0.0042        # отдельные холмы (~240 м)
	_hillock.fractal_octaves = 2
	_side_n.seed = s + 51
	_side_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_side_n.frequency = 0.022          # холмики вдоль дорог (~45 м)


func _raw_row(y: int) -> void:
	var z := y * CELL
	for x in gw:
		var wx := x * CELL
		_raw[y * gw + x] = clampf(_n_base.get_noise_2d(wx, z) * 0.74 + _n_ridge.get_noise_2d(wx, z) * 0.26, -1.0, 1.0)


func _hist_job(part: int) -> void:
	var h := PackedInt32Array()
	h.resize(BINS)
	for y in range(part * 16, mini(gw, part * 16 + 16)):
		for x in gw:
			var b := clampi(int((_raw[y * gw + x] + 1.0) * 0.5 * BINS), 0, BINS - 1)
			h[b] += 1
	_hist_parts[part] = h


func _hm_row(y: int) -> void:
	var bw := clampf(size * 0.07, 70.0, 280.0)
	for x in gw:
		var pos := clampf((_raw[y * gw + x] + 1.0) * 0.5, 0.0, 0.99999) * BINS
		var bi := int(pos)
		var q := lerpf(_cdf[bi], _cdf[bi + 1], pos - bi)
		var h := _elev(q)
		var edge := minf(minf(x * CELL, y * CELL), minf(size - x * CELL, size - y * CELL))
		h = lerpf(SEA - 9.0, h, smoothstep(0.0, bw, edge))
		hm[y * gw + x] = h


## Квантиль (0..1) -> высота. Нижние q — равнины, средние — холмы, верхние — горы.
func _elev(q: float) -> float:
	var mount := _shares.x
	var hill := _shares.y
	var plain := _shares.z
	if q < plain and plain > 0.0:
		return lerpf(16.5, 23.0, pow(q / plain, 1.1))
	if q < plain + hill and hill > 0.0:
		return lerpf(23.0, 46.0, pow((q - plain) / hill, 1.15))
	if mount > 0.0:
		return lerpf(46.0, 106.0, pow(clampf((q - plain - hill) / mount, 0.0, 1.0), 1.5))
	return 46.0


# --- высоты ----------------------------------------------------------------------

func macro(x: float, z: float) -> float:
	var gx := clampf(x / CELL, 0.0, gw - 1.001)
	var gz := clampf(z / CELL, 0.0, gw - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * gw + ix
	return lerpf(lerpf(hm[i], hm[i + 1], fx), lerpf(hm[i + gw], hm[i + gw + 1], fx), fz)


func base_height(x: float, z: float) -> float:
	var m := macro(x, z)
	return m + _detail.get_noise_2d(x, z) * lerpf(0.5, 4.5, smoothstep(22.0, 90.0, m)) + _relief(x, z, m)


## Неровности равнин и холмов (не гор): пологие волны 0..2.5 м и отдельные холмы — тем выше и чаще,
## чем больше доля холмов в параметрах мира (при 30% — до ~8 м).
func _relief(x: float, z: float, m: float) -> float:
	var low := 1.0 - smoothstep(32.0, 60.0, m)
	if low <= 0.0:
		return 0.0
	var roll := (_roll.get_noise_2d(x, z) * 0.5 + 0.5) * 2.5
	var hl := maxf(0.0, _hillock.get_noise_2d(x, z) - 0.12) * (6.0 + 16.0 * _shares.y)
	return (roll + hl) * low


## Холмики вдоль загородных дорог (в 8–35 м от края, не в городах): дорога прорезает их выемкой — как в 7DTD.
func roadside_bump(x: float, z: float) -> float:
	var d := road_dist(x, z)
	if d > 38.0:
		return 0.0
	var band := smoothstep(6.0, 12.0, d) * (1.0 - smoothstep(26.0, 38.0, d))
	if band <= 0.0:
		return 0.0
	var n := maxf(0.0, _side_n.get_noise_2d(x, z) + 0.15)
	return band * n * (3.0 + 6.0 * _shares.y) * (1.0 - _town_weight(x, z))


## 1 внутри городов и POI (и их склонов), 0 — вдали от них.
func _town_weight(x: float, z: float) -> float:
	var w := 0.0
	for t: Dictionary in roads.all_places():
		var c: Vector2 = t["center"]
		var rr: float = float(t["radius"]) + float(t["falloff"]) + 25.0
		if absf(x - c.x) < rr and absf(z - c.y) < rr:
			w = maxf(w, 1.0 - smoothstep(float(t["radius"]), rr, Vector2(x - c.x, z - c.y).length()))
	return w


## Расстояние от точки до края ближайшей дороги, м (по сетке RDF_CELL, дальше RDF_MAX — RDF_MAX).
func road_dist(x: float, z: float) -> float:
	if _rdf.is_empty():
		return RDF_MAX
	var gx := clampf(x / RDF_CELL, 0.0, _rdf_w - 1.001)
	var gz := clampf(z / RDF_CELL, 0.0, _rdf_w - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * _rdf_w + ix
	return lerpf(lerpf(_rdf[i], _rdf[i + 1], fx), lerpf(_rdf[i + _rdf_w], _rdf[i + _rdf_w + 1], fx), fz)


## Поле расстояний до дорог (все дороги, кроме улиц внутри городов): после планирования дорог.
func _build_road_field() -> void:
	_rdf_w = int(size / RDF_CELL) + 2
	_rdf = PackedFloat32Array()
	_rdf.resize(_rdf_w * _rdf_w)
	_rdf.fill(RDF_MAX)
	var seg := roads._seg
	var r := RDF_MAX + RDF_CELL
	for q in range(0, seg.size(), RoadNet.SS):
		if int(seg[q + RoadNet.F_TOWN]) != 0:
			continue
		var a := Vector2(seg[q], seg[q + 1])
		var b := Vector2(seg[q + 3], seg[q + 4])
		var edge := seg[q + RoadNet.F_HW] + seg[q + RoadNet.F_SIDE]
		var x0 := maxi(0, floori((minf(a.x, b.x) - r) / RDF_CELL))
		var x1 := mini(_rdf_w - 1, ceili((maxf(a.x, b.x) + r) / RDF_CELL))
		var z0 := maxi(0, floori((minf(a.y, b.y) - r) / RDF_CELL))
		var z1 := mini(_rdf_w - 1, ceili((maxf(a.y, b.y) + r) / RDF_CELL))
		for gz in range(z0, z1 + 1):
			for gx in range(x0, x1 + 1):
				var p := Vector2(gx * RDF_CELL, gz * RDF_CELL)
				var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - edge
				var i := gz * _rdf_w + gx
				if d < _rdf[i]:
					_rdf[i] = maxf(d, 0.0)


## Для дальнего ландшафта: рельеф, реки/озёра и площадки городов (дороги не учитываются).
func far_height(x: float, z: float) -> float:
	return roads.plateau_blend(x, z, hydro.carve_at(x, z, base_height(x, z) + roadside_bump(x, z), 7.0))


## Рельеф с реками и озёрами, без городов и дорог (по нему размещаются города и дороги).
func terrain_height(x: float, z: float) -> float:
	return hydro.carve_at(x, z, base_height(x, z))


# --- реки и озёра -------------------------------------------------------------

func _gen_hydro(rng: RandomNumberGenerator, p: WorldParams) -> void:
	if p.rivers > 0:
		var made := _gen_rivers_flow(rng, p.rivers)
		if made == 0:
			for i in p.rivers:
				_trace_river(rng)
	var placed := 0
	var tries := 0
	while placed < p.lakes and tries < 600:
		tries += 1
		var c := Vector2(rng.randf_range(0.12, 0.88) * size, rng.randf_range(0.12, 0.88) * size)
		var radius := rng.randf_range(22.0, 75.0)
		var h := macro(c.x, c.y)
		if h < SEA + 3.0 or h > 52.0 or hydro.near(c.x, c.y, radius * 1.8):
			continue
		var lo := INF
		var hi := -INF
		for k in 8:
			var a := TAU * k / 8.0
			var hr := macro(c.x + cos(a) * radius * 1.3, c.y + sin(a) * radius * 1.3)
			lo = minf(lo, hr)
			hi = maxf(hi, hr)
		if hi - lo > 7.0:
			continue
		var level := maxf(lo - 0.2, SEA + 0.8)
		hydro.add_lake(c, radius, level, 3.5 + radius * 0.04, rng.randf() * TAU, rng.randf() * TAU)
		placed += 1


## Реки по стоку: на грубой сетке (RC м) заливаются впадины (priority-flood), у каждой клетки
## есть направление к океану, реки — главные русла по накоплению стока + притоки. Возвращает число рек.
const RC := 16.0
const FLOOD_EPS := 0.012


func _gen_rivers_flow(rng: RandomNumberGenerator, count: int) -> int:
	var n := int(size / RC) + 1
	var total := n * n
	var h := PackedFloat32Array()
	h.resize(total)
	for j in n:
		for i in n:
			h[i + j * n] = macro(i * RC, j * RC)
	var sea := SEA + 0.3
	var fh := h.duplicate()
	var down := PackedInt32Array()
	down.resize(total)
	down.fill(-1)
	var done := PackedByteArray()
	done.resize(total)
	var order := PackedInt32Array()
	var nb := 4400
	var lo := SEA - 12.0
	var buckets: Array = []
	buckets.resize(nb)
	for b in nb:
		buckets[b] = []
	for j in n:
		for i in n:
			var c := i + j * n
			if i == 0 or j == 0 or i == n - 1 or j == n - 1 or h[c] < sea:
				done[c] = 1
				(buckets[clampi(int((h[c] - lo) * 30.0), 0, nb - 1)] as Array).append(c)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	for b in nb:
		var arr: Array = buckets[b]
		var qi := 0
		while qi < arr.size():
			var c: int = arr[qi]
			qi += 1
			order.append(c)
			var cx := c % n
			var cz := c / n
			for d: Vector2i in dirs:
				var x := cx + d.x
				var z := cz + d.y
				if x < 0 or z < 0 or x >= n or z >= n:
					continue
				var k := x + z * n
				if done[k] != 0:
					continue
				done[k] = 1
				var step := FLOOD_EPS * (1.4 if (d.x != 0 and d.y != 0) else 1.0)
				fh[k] = maxf(h[k], fh[c] + step)
				down[k] = c
				(buckets[maxi(b, clampi(int((fh[k] - lo) * 30.0), 0, nb - 1))] as Array).append(k)
	var acc := PackedFloat32Array()
	acc.resize(total)
	acc.fill(1.0)
	for idx in range(order.size() - 1, -1, -1):
		var c := order[idx]
		var dn := down[c]
		if dn >= 0:
			acc[dn] += acc[c]
	# исток каждой клетки: соседи, чей сток идёт в неё
	var ups := {}
	for c in total:
		var dn := down[c]
		if dn >= 0:
			if not ups.has(dn):
				ups[dn] = []
			(ups[dn] as Array).append(c)
	# устья: клетки суши, впадающие в океан/край; берём самые полноводные с интервалом
	var mouths: Array = []
	for c in total:
		var dn := down[c]
		if dn >= 0 and down[dn] < 0 and h[c] >= sea and acc[c] >= 10.0 and h[dn] < sea + 6.0:
			mouths.append(c)
	mouths.sort_custom(func(a: int, b: int) -> bool: return acc[a] > acc[b])
	var chosen: Array[int] = []
	for c: int in mouths:
		if chosen.size() >= count:
			break
		var ok := true
		for m in chosen:
			if Vector2(c % n - m % n, c / n - m / n).length() < 10.0:
				ok = false
				break
		if ok:
			chosen.append(c)
	var made := 0
	var used_src := {}
	for mouth in chosen:
		var main := _trace_up(mouth, ups, acc, maxf(8.0, acc[mouth] * 0.08))
		if main.size() < 5:
			continue
		used_src[main[main.size() - 1]] = true
		var main_ref := _emit_river(main, down, acc, n, h, rng, {})
		made += 1
		# притоки: на стрежне ищем боковые ветви
		var tribs := 0
		for k in range(main.size() - 2, 1, -1):
			if tribs >= 3:
				break
			var cell: int = main[k]
			for u: int in ups.get(cell, []):
				if u == main[k - 1] or acc[u] < maxf(12.0, acc[cell] * 0.2):
					continue
				var tr := _trace_up(u, ups, acc, 6.0)
				if tr.size() < 4 or used_src.has(tr[tr.size() - 1]):
					continue
				used_src[tr[tr.size() - 1]] = true
				tr.reverse()
				tr.append(cell)
				tr.reverse()
				_emit_river(tr, down, acc, n, h, rng, main_ref)
				tribs += 1
				made += 1
				break
	return made


## Идёт вверх по руслу (соседний приток с наибольшим стоком) пока сток больше порога. Порядок: устье -> исток.
func _trace_up(start: int, ups: Dictionary, acc: PackedFloat32Array, cutoff: float) -> Array[int]:
	var path: Array[int] = [start]
	var cur := start
	while ups.has(cur):
		var best := -1
		var ba := 0.0
		for u: int in ups[cur]:
			if acc[u] > ba:
				ba = acc[u]
				best = u
		if best < 0 or ba < cutoff:
			break
		path.append(best)
		cur = best
		if path.size() > 2000:
			break
	return path


## path: устье -> исток (клетки). Строит полилинию исток -> устье: сглаживание, меандр, уровни воды, ширины.
## main_ref (не пуст) — приток: конец притягивается к ближайшей точке главной реки, уровень воды стыкуется с ней.
func _emit_river(path: Array[int], down: PackedInt32Array, acc: PackedFloat32Array, n: int, h: PackedFloat32Array, rng: RandomNumberGenerator, main_ref: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	var ac := PackedFloat32Array()
	for k in range(path.size() - 1, -1, -1):
		var c: int = path[k]
		pts.append(Vector2((c % n) * RC, (c / n) * RC))
		ac.append(acc[c])
	# продолжаем в океан
	var last := pts[pts.size() - 1]
	var dn := down[path[0]]
	var dirv := Vector2.ZERO
	if dn >= 0:
		dirv = (Vector2((dn % n) * RC, (dn / n) * RC) - last).normalized()
	else:
		dirv = (last - pts[maxi(pts.size() - 2, 0)]).normalized()
	pts.append(last + dirv * RC)
	ac.append(ac[ac.size() - 1])
	# Chaikin x2, ac сглаживаем тем же правилом
	for it in 2:
		var np := PackedVector2Array([pts[0]])
		var na := PackedFloat32Array([ac[0]])
		for i in pts.size() - 1:
			np.append(pts[i].lerp(pts[i + 1], 0.25))
			np.append(pts[i].lerp(pts[i + 1], 0.75))
			na.append(lerpf(ac[i], ac[i + 1], 0.25))
			na.append(lerpf(ac[i], ac[i + 1], 0.75))
		np.append(pts[pts.size() - 1])
		na.append(ac[ac.size() - 1])
		pts = np
		ac = na
	# ресэмплинг ~6 м
	var rp := PackedVector2Array([pts[0]])
	var ra := PackedFloat32Array([ac[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		var pos := 6.0 - carry
		while pos <= seg:
			var t := pos / seg
			rp.append(pts[i].lerp(pts[i + 1], t))
			ra.append(lerpf(ac[i], ac[i + 1], t))
			pos += 6.0
		carry = seg - (pos - 6.0)
	rp.append(pts[pts.size() - 1])
	ra.append(ac[ac.size() - 1])
	# меандр: смещение по гладкому векторному полю (общее для всех рек — притоки сходятся с руслом)
	var mn := FastNoiseLite.new()
	mn.seed = params.seed_value + 77
	mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mn.frequency = 0.006
	var out := PackedVector2Array()
	for i in rp.size():
		var p := rp[i]
		var amp := clampf(sqrt(ra[i]) * 1.8, 4.0, 15.0)
		out.append(p + Vector2(mn.get_noise_2d(p.x, p.y + 311.0), mn.get_noise_2d(p.x + 733.0, p.y)) * amp * 1.1)
	var m := out.size()
	var jl := -1.0
	if not main_ref.is_empty():
		var mp: PackedVector2Array = main_ref["pts"]
		var bj := 0
		var bd := INF
		for j in mp.size():
			var dj := mp[j].distance_squared_to(out[m - 1])
			if dj < bd:
				bd = dj
				bj = j
		var delta := mp[bj] - out[m - 1]
		for t in mini(10, m):
			out[m - 1 - t] += delta * (1.0 - float(t) / 10.0)
		jl = (main_ref["lv"] as PackedFloat32Array)[bj]
	var lv := PackedFloat32Array()
	lv.resize(m)
	var run := INF
	for i in m:
		var th := macro(out[i].x, out[i].y)
		run = minf(run, th - 0.75)
		lv[i] = run
	for i in m:
		lv[i] = maxf(lv[i], SEA - 0.3)
	if jl >= 0.0:
		for i in m:
			lv[i] = maxf(lv[i], jl + 0.012 * 6.0 * float(m - 1 - i))
		lv[m - 1] = jl
	for i in range(m - 2, -1, -1):
		lv[i] = maxf(lv[i], lv[i + 1])
	var hw := PackedFloat32Array()
	hw.resize(m)
	var base_acc := ra[0]
	for i in m:
		hw[i] = clampf(1.4 + 1.25 * log(1.0 + maxf(ra[i] - base_acc * 0.75, 0.0) / 5.0), 1.4, 7.5)
	for i in m:
		hw[i] = lerpf(1.2, hw[i], smoothstep(0.0, 14.0, float(i)))   # исток — тонкий ручей
	hydro.add_river(out, lv, hw)
	return {"pts": out, "lv": lv, "hw": hw}


func _grad(pos: Vector2) -> Vector2:
	return Vector2(macro(pos.x + 6.0, pos.y) - macro(pos.x - 6.0, pos.y), macro(pos.x, pos.y + 6.0) - macro(pos.x, pos.y - 6.0)) / 12.0


func _trace_river(rng: RandomNumberGenerator) -> void:
	var src := Vector2.ZERO
	var ok := false
	for a in 400:
		src = Vector2(rng.randf_range(0.08, 0.92) * size, rng.randf_range(0.08, 0.92) * size)
		var h := macro(src.x, src.y)
		if h > 34.0 and h < 90.0 and not hydro.near(src.x, src.y, 60.0):
			ok = true
			break
	if not ok:
		return
	var pts := PackedVector2Array([src])
	var hs := PackedFloat32Array([macro(src.x, src.y)])
	var pos := src
	var dir := Vector2.ZERO
	var min_h := hs[0]
	var since := 0
	var basin := false
	for step in 1100:
		var nd := -_grad(pos)
		if nd.length() < 0.004:
			nd = dir if dir != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
		else:
			nd = nd.normalized()
		dir = (dir * 0.7 + nd * 0.45 + Vector2.from_angle(rng.randf() * TAU) * 0.12)
		dir = dir.normalized()
		pos += dir * 6.0
		pts.append(pos)
		var h := macro(pos.x, pos.y)
		hs.append(h)
		if pos.x < 30.0 or pos.y < 30.0 or pos.x > size - 30.0 or pos.y > size - 30.0:
			break
		if h < SEA + 0.3:
			break
		if h < min_h - 0.02:
			min_h = h
			since = 0
		else:
			since += 1
		if since > 45:
			basin = true
			break
		if step > 12 and hydro.near(pos.x, pos.y, 9.0):
			break
	var n := pts.size()
	if n < 25:
		return
	var lv := PackedFloat32Array()
	lv.resize(n)
	for i in n:
		lv[i] = hs[i] - 0.9
	for pass_i in 4:
		var sm := lv.duplicate()
		for i in n:
			var s := 0.0
			var c := 0
			for k in range(maxi(0, i - 2), mini(n, i + 3)):
				s += lv[k]
				c += 1
			sm[i] = s / c
		lv = sm
		for i in range(1, n):
			lv[i] = minf(lv[i], lv[i - 1])
	for i in n:
		lv[i] = maxf(lv[i], SEA - 0.3)
	var hw := PackedFloat32Array()
	hw.resize(n)
	var k := rng.randf_range(0.9, 1.15)
	for i in n:
		hw[i] = lerpf(2.4, 6.5, float(i) / n) * k
	hydro.add_river(pts, lv, hw)
	if basin:
		hydro.add_lake(pts[n - 1], rng.randf_range(26.0, 44.0), lv[n - 1], 3.5, rng.randf() * TAU, rng.randf() * TAU)


# --- предпросмотр -----------------------------------------------------------------

## overlays=false — без рек, дорог, городов и меток (миникарта рисует их сама векторно, чёткими при любом масштабе).
func render_preview(px: int, tree: SceneTree = null, overlays := true) -> Image:
	_pv_size = px
	_pv_rows.resize(px * px * 3)
	await _wait(WorkerThreadPool.add_group_task(_pv_row, px), tree)
	var img := Image.create_from_data(px, px, false, Image.FORMAT_RGB8, _pv_rows)
	var sc := float(px) / size
	# озёра
	for lk: Dictionary in hydro.lakes:
		var c: Vector2 = lk["center"]
		var r: float = lk["R"] * 1.25
		for iy in range(int((c.y - r) * sc) - 1, int((c.y + r) * sc) + 2):
			for ix in range(int((c.x - r) * sc) - 1, int((c.x + r) * sc) + 2):
				if ix < 0 or iy < 0 or ix >= px or iy >= px:
					continue
				var dx := ix / sc - c.x
				var dz := iy / sc - c.y
				if sqrt(dx * dx + dz * dz) < hydro.lake_radius(lk["R"], lk["ph1"], lk["ph2"], atan2(dz, dx)):
					img.set_pixel(ix, iy, Color(0.18, 0.42, 0.72))
	if not overlays:
		return img
	# реки
	for rv: Dictionary in hydro.rivers:
		var pts: PackedVector2Array = rv["pts"]
		for i in pts.size() - 1:
			_line(img, pts[i] * sc, pts[i + 1] * sc, Color(0.2, 0.45, 0.85), 2)
	# дороги
	var road_cols := {
		RoadNet.ASPHALT: Color(0.08, 0.08, 0.09), RoadNet.CONCRETE: Color(0.85, 0.85, 0.85),
		RoadNet.GRAVEL: Color(0.62, 0.52, 0.36), RoadNet.ROADSAND: Color(0.92, 0.82, 0.5),
	}
	if roads != null:
		for lp: Dictionary in roads.link_paths:
			var pts: PackedVector2Array = lp["pts"]
			var col: Color = road_cols.get(lp["mat"], Color.GRAY)
			for i in pts.size() - 1:
				_line(img, pts[i] * sc, pts[i + 1] * sc, col, 2)
		for t: Dictionary in roads.towns:
			var c: Vector2 = t["center"]
			var s: int = [3, 5, 7][t["tier"]]
			_box(img, c * sc, s, Color(1.0, 0.25, 0.2) if t["tier"] == 2 else (Color(1.0, 0.55, 0.1) if t["tier"] == 1 else Color(1.0, 0.85, 0.2)))
		for t: Dictionary in roads.pois:
			_box(img, (t["center"] as Vector2) * sc, 3, Color(0.75, 0.2, 0.9))
	_box(img, Vector2(spawn.x, spawn.z) * sc, 3, Color.WHITE)
	return img


func _pv_row(y: int) -> void:
	var px := _pv_size
	var step := float(size) / px
	for x in px:
		var wx := (x + 0.5) * step
		var wz := (y + 0.5) * step
		var h := macro(wx, wz)
		var dh := (macro(wx - step, wz) - macro(wx + step, wz)) + (macro(wx, wz - step) - macro(wx, wz + step))
		var shade := clampf(dh * 0.12 / maxf(step * 0.25, 1.0), -0.25, 0.25)
		var c := Color(0.27, 0.45, 0.2).lerp(Color(0.5, 0.45, 0.33), clampf((h - 24.0) / 50.0, 0.0, 1.0))
		if h > 66.0:
			c = c.lerp(Color(0.88, 0.88, 0.9), clampf((h - 66.0) / 30.0, 0.0, 1.0))
		if h < SEA:
			c = Color(0.1, 0.3, 0.5).lerp(Color(0.2, 0.5, 0.65), clampf((h - (SEA - 9.0)) / 9.0, 0.0, 1.0))
		elif h < SEA + 1.5:
			c = Color(0.78, 0.7, 0.48)
		else:
			c = Color(c.r + shade, c.g + shade, c.b + shade)
		var o := (y * px + x) * 3
		_pv_rows[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
		_pv_rows[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
		_pv_rows[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)


func _line(img: Image, a: Vector2, b: Vector2, col: Color, thick: int) -> void:
	var n := maxi(1, int(a.distance_to(b) * 1.5))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for ox in thick:
			for oy in thick:
				var x := int(p.x) + ox
				var y := int(p.y) + oy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)


func _box(img: Image, c: Vector2, s: int, col: Color) -> void:
	var h := s / 2
	for ox in range(-h - 1, h + 2):
		for oy in range(-h - 1, h + 2):
			var x := int(c.x) + ox
			var y := int(c.y) + oy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var edge := absi(ox) > h or absi(oy) > h
				img.set_pixel(x, y, Color.BLACK if edge else col)
