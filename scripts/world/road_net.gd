class_name RoadNet
extends RefCounted
## Города, POI и дороги по плану мира (WorldMap). Всё строится один раз в plan() и дальше
## только читается (потокобезопасно). Дороги меняют рельеф (выравнивание, выемки/насыпи);
## сами покрытия рисует RoadMesher отдельной геометрией. Здания — BuildingGen по участкам (lots).

const ASPHALT := 4
const CONCRETE := 5
const GRAVEL := 6
const ROADSAND := 7

const CELL := 32.0
const SHOULDER := 8.0   # плавный переход рельефа вокруг дороги
const SW := 2.0         # ширина тротуара
const BED := 0.0        # дорога лежит прямо на грунте (часть ландшафта)
const LOT_RAMP := 3.0    # ширина склона вокруг ровной площадки/участка
const PARK_P := 10       # % участков под дома в городах, которые становятся парками (скамейки, деревья)
const BIG_BLOCK_P := 30  # % кварталов городов-сеток под одно крупное здание (если есть префабы крупнее обычного участка)
const CURB_H := 0.14   # высота бордюра
const SS := 28          # шаг в массиве сегментов
const LST := 10         # шаг в массиве участков

# поля сегмента
const F_HW := 6
const F_SIDE := 7
const F_MAT := 8
const F_LINE := 9
const F_S0 := 10
const F_LEN := 11
const F_WEAR := 16
const F_PRIO := 17
const F_SID := 18
const F_TOWN := 19
const F_N0X := 20
const F_PREV := 24
const F_NEXT := 25
const F_GID := 26

enum Pattern { GRID, RADIAL, LINEAR, CULDESAC }
enum Lot { RESIDENTIAL, COMMERCIAL, INDUSTRIAL, PLAZA, TURNAROUND, PAD_ASPHALT }

var towns: Array = []        # города (tier 0 деревня, 1 город, 2 мегаполис)
var pois: Array = []         # точки интереса
var link_paths: Array = []   # {pts, mat} для предпросмотра

var _seed: int
var _base_fn: Callable
var _water: float
var _world: WorldMap
var _seg := PackedFloat32Array()
var _seg_n := 0
var _seg_cells := {}
var _lot := PackedFloat32Array()
var _lot_n := 0
var _lot_cells := {}
var _lot_meta: Array = []
var _ends: Array = []
var _sid := 0
var _town_flag := 1
var _lrng := RandomNumberGenerator.new()
var _town_seg0 := 0


func _init(seed_in: int, base_fn: Callable, water_level: float) -> void:
	_seed = seed_in
	_base_fn = base_fn
	_water = water_level


func all_places() -> Array:
	return towns + pois


## Рельеф с учётом площадок городов и POI (без дорог): для дальнего ландшафта.
func plateau_blend(x: float, z: float, h: float) -> float:
	for t: Dictionary in towns:
		var c: Vector2 = t["center"]
		var rr: float = float(t["radius"]) + float(t["falloff"])
		if absf(x - c.x) < rr and absf(z - c.y) < rr:
			var d := Vector2(x - c.x, z - c.y).length()
			if d < rr:
				h = lerpf(h, float(t["plateau"]), 1.0 - smoothstep(float(t["radius"]), rr, d))
	for t: Dictionary in pois:
		var c: Vector2 = t["center"]
		var rr: float = float(t["radius"]) + float(t["falloff"])
		if absf(x - c.x) < rr and absf(z - c.y) < rr:
			var d := Vector2(x - c.x, z - c.y).length()
			if d < rr:
				h = lerpf(h, float(t["plateau"]), 1.0 - smoothstep(float(t["radius"]), rr, d))
	return h


# --- планирование -------------------------------------------------------------

func plan(world: WorldMap, rng: RandomNumberGenerator, p: WorldParams) -> void:
	_world = world
	_place_towns(rng, p.towns)
	for t: Dictionary in towns:
		_ensure_streets(t)
	_link_towns(rng)
	_place_pois(rng, p.pois)
	for t: Dictionary in pois:
		_poi_layout(t)
	_link_pois(rng)


func pick_spawn(center: Vector2) -> Vector3:
	var best := {}
	var bd := INF
	for t: Dictionary in towns:
		if int(t["tier"]) < 1:
			continue
		var d := (t["center"] as Vector2).distance_to(center)
		if d < bd:
			bd = d
			best = t
	if best.is_empty() and not towns.is_empty():
		best = towns[0]
	if best.is_empty() and not pois.is_empty():
		best = pois[0]
	if best.is_empty():
		return Vector3(center.x, _base_fn.call(center.x, center.y) + 2.0, center.y)
	var c: Vector2 = best["center"]
	return Vector3(c.x + 6.0, float(best["plateau"]) + 2.0, c.y + 6.0)


func _sample_flat(c: Vector2, rad: float) -> Dictionary:
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for k in 9:
		var p := c
		if k > 0:
			var a := TAU * k / 8.0
			p += Vector2(cos(a), sin(a)) * rad * 0.9
		var h: float = _base_fn.call(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	return {"lo": lo, "hi": hi, "mean": sum / 9.0}


func _place_towns(rng: RandomNumberGenerator, count: int) -> void:
	var n2 := int(round(count * 0.2))
	var n1 := int(round(count * 0.35))
	var n0 := maxi(0, count - n1 - n2)
	var tiers: Array[int] = []
	for i in n2:
		tiers.append(2)
	for i in n1:
		tiers.append(1)
	for i in n0:
		tiers.append(0)
	var size := float(_world.size)
	var gid := 0
	for tier in tiers:
		var rad: float = [55.0, 90.0, 130.0][tier] * rng.randf_range(0.92, 1.0)
		var margin := rad + 170.0
		if size - 2.0 * margin < 50.0:
			continue
		for attempt in 700:
			var c := Vector2(rng.randf_range(margin, size - margin), rng.randf_range(margin, size - margin))
			var close := false
			for t: Dictionary in towns:
				if c.distance_to(t["center"]) < (rad + float(t["radius"])) * 1.25 + 110.0:
					close = true
					break
			if close or _world.hydro.near(c.x, c.y, rad + 30.0):
				continue
			var s := _sample_flat(c, rad)
			if s["lo"] < _water + 2.5 or s["hi"] > 52.0 or s["hi"] - s["lo"] > 14.0:
				continue
			var pat_roll := rng.randf()
			var pattern := Pattern.GRID
			match tier:
				# в городах только прямые улицы кварталами (кольцевой RADIAL не используется — как в 7DTD);
				# изгибы остаются у загородных дорог
				2: pattern = Pattern.GRID
				1: pattern = Pattern.GRID if pat_roll < 0.6 else Pattern.LINEAR
				0: pattern = Pattern.LINEAR if pat_roll < 0.5 else Pattern.CULDESAC
			towns.append({
				"id": gid, "kind": "town", "center": c, "radius": rad, "falloff": 36.0, "tier": tier,
				"pattern": pattern, "angle": rng.randf() * PI, "plateau": float(s["mean"]), "lots": [], "streets": false,
			})
			gid += 1
			break


func _place_pois(rng: RandomNumberGenerator, count: int) -> void:
	var size := float(_world.size)
	var types := ["farm", "cabin", "gas", "yard"]
	for i in count:
		var rad := 26.0
		for attempt in 500:
			var c := Vector2(rng.randf_range(160.0, size - 160.0), rng.randf_range(160.0, size - 160.0))
			var bad := false
			for t: Dictionary in towns:
				if c.distance_to(t["center"]) < float(t["radius"]) + 70.0:
					bad = true
					break
			if not bad:
				for t: Dictionary in pois:
					if c.distance_to(t["center"]) < 110.0:
						bad = true
						break
			if bad or _world.hydro.near(c.x, c.y, rad + 20.0):
				continue
			var s := _sample_flat(c, rad)
			if s["lo"] < _water + 2.0 or s["hi"] > 70.0 or s["hi"] - s["lo"] > 6.0:
				continue
			pois.append({
				"id": 1000 + i, "kind": "poi", "poi_type": types[rng.randi() % types.size()], "center": c,
				"radius": rad, "falloff": 22.0, "tier": -1, "angle": rng.randf() * TAU,
				"plateau": float(s["mean"]), "lots": [], "streets": true, "seed": rng.randi(),
			})
			break


# --- дорожный граф ----------------------------------------------------------------

func _link_towns(rng: RandomNumberGenerator) -> void:
	var n := towns.size()
	if n < 2:
		return
	var edges := {}
	var in_tree := [0]
	while in_tree.size() < n:
		var best_i := -1
		var best_j := -1
		var bd := INF
		for i: int in in_tree:
			for j in n:
				if in_tree.has(j):
					continue
				var d: float = (towns[i]["center"] as Vector2).distance_to(towns[j]["center"])
				if d < bd:
					bd = d
					best_i = i
					best_j = j
		in_tree.append(best_j)
		edges[Vector2i(mini(best_i, best_j), maxi(best_i, best_j))] = true
	for i in n:
		var order := range(n)
		order.sort_custom(func(a: int, b: int) -> bool:
			return (towns[i]["center"] as Vector2).distance_to(towns[a]["center"]) < (towns[i]["center"] as Vector2).distance_to(towns[b]["center"]))
		var added := 0
		for j: int in order:
			if j == i:
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			if not edges.has(key) and added < 1 and rng.randf() < 0.6:
				edges[key] = true
				added += 1
	for key: Vector2i in edges.keys():
		_gen_link(towns[key.x], towns[key.y], rng)


func _link_pois(rng: RandomNumberGenerator) -> void:
	for p: Dictionary in pois:
		var c: Vector2 = p["center"]
		var best := {}
		var bd := INF
		for t: Dictionary in towns:
			var d := c.distance_to(t["center"])
			if d < bd:
				bd = d
				best = t
		if best.is_empty() or bd > 1100.0:
			continue
		var gate := _gate(best, c)
		var st := {"mat": ROADSAND if rng.randf() < 0.55 else GRAVEL, "hw": 2.4, "side": 0.0, "line": false, "wear": rng.randf_range(0.5, 0.9)}
		if st["mat"] == GRAVEL:
			st["hw"] = 3.0
		_build_link(c, gate, float(p["plateau"]), float(best["plateau"]), st, 2, rng)


func _gen_link(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := mini(a["tier"], b["tier"])
	var roll := rng.randf()
	var st := {"mat": GRAVEL, "hw": 3.0, "side": 0.0, "line": false, "wear": rng.randf_range(0.35, 0.8)}
	match m:
		2:
			st = {"mat": ASPHALT, "hw": 4.4, "side": 0.0, "line": true, "wear": rng.randf_range(0.2, 0.65)} if roll < 0.75 else {"mat": CONCRETE, "hw": 4.2, "side": 0.0, "line": false, "wear": rng.randf_range(0.2, 0.6)}
		1:
			if roll < 0.35:
				st = {"mat": ASPHALT, "hw": 4.4, "side": 0.0, "line": true, "wear": rng.randf_range(0.3, 0.75)}
			elif roll < 0.5:
				st = {"mat": CONCRETE, "hw": 4.2, "side": 0.0, "line": false, "wear": rng.randf_range(0.3, 0.7)}
		0:
			if roll >= 0.45:
				st = {"mat": ROADSAND, "hw": 2.2, "side": 0.0, "line": false, "wear": rng.randf_range(0.45, 0.9)}
	var ca: Vector2 = a["center"]
	var cb: Vector2 = b["center"]
	var p0 := _gate(a, cb)
	var p1 := _gate(b, ca)
	_build_link(p0, p1, float(a["plateau"]), float(b["plateau"]), st, 0, rng)


## Строит дорогу p0 -> p1 по кривой Безье с извилинами; пробует объезды. Возвращает успех.
func _build_link(p0: Vector2, p1: Vector2, h0: float, h1: float, st: Dictionary, town_flag: int, rng: RandomNumberGenerator) -> bool:
	var dv := p1 - p0
	var length := dv.length()
	if length < 30.0:
		return false
	var nrm := Vector2(-dv.y, dv.x).normalized()
	var size := float(_world.size)
	var offsets: Array[float] = [0.0, 70.0, -70.0, 150.0, -150.0, 280.0, -280.0]
	for off in offsets:
		var ctrl := (p0 + p1) * 0.5 + nrm * off * 2.0
		var n := int(ceil(length * 1.08 / 8.0))
		var amp := minf(22.0, length * 0.07)
		var k1 := rng.randf_range(1.0, 2.0)
		var k2 := rng.randf_range(2.5, 4.0)
		var ph1 := rng.randf() * TAU
		var ph2 := rng.randf() * TAU
		var pts := PackedVector2Array()
		var hs := PackedFloat32Array()
		var minh := PackedFloat32Array()
		var under := 0
		var bad := false
		for i in n + 1:
			var t := float(i) / n
			var bz := p0 * ((1.0 - t) * (1.0 - t)) + ctrl * (2.0 * (1.0 - t) * t) + p1 * (t * t)
			var wob := amp * sin(PI * t) * (sin(t * TAU * k1 + ph1) * 0.6 + sin(t * TAU * k2 + ph2) * 0.4)
			var p := bz + nrm * wob
			if p.x < 30.0 or p.y < 30.0 or p.x > size - 30.0 or p.y > size - 30.0 or _world.hydro.in_lake(p.x, p.y, 8.0):
				bad = true
				break
			var h: float = _base_fn.call(p.x, p.y)
			if h < _water - 0.5:
				under += 1
			var mh := _world.hydro.min_road_height(p.x, p.y)
			pts.append(p)
			hs.append(maxf(h, mh))
			minh.append(mh)
		if bad or under > 0.1 * (n + 1):
			continue
		for pass_i in 24:
			var prev := hs[0]
			for i in range(1, n):
				var cur := hs[i]
				hs[i] = maxf((prev + 2.0 * cur + hs[i + 1]) * 0.25, minh[i])
				prev = cur
		var arc := PackedFloat32Array()
		arc.append(0.0)
		for i in range(1, n + 1):
			arc.append(arc[i - 1] + pts[i - 1].distance_to(pts[i]))
		var total := arc[n]
		var da := h0 - hs[0]
		var db := h1 - hs[n]
		for i in n + 1:
			hs[i] += da * exp(-arc[i] / 50.0) + db * exp(-(total - arc[i]) / 50.0)
			hs[i] = maxf(maxf(hs[i], _water + 1.2), minh[i])
		var steep := false
		for i in n:
			if absf(hs[i + 1] - hs[i]) / maxf(arc[i + 1] - arc[i], 0.1) > 0.55:
				steep = true
				break
		if steep:
			continue
		_sid += 1
		_town_flag = town_flag
		var first := _seg_n
		for i in n:
			_add_seg(pts[i], pts[i + 1], hs[i], hs[i + 1], st, arc[i])
		_link_pieces(first, _seg_n - 1, false)
		link_paths.append({"pts": pts, "mat": st["mat"]})
		return true
	return false


# --- запрос --------------------------------------------------------------------

## Считает квадрат w x w узлов от (x0, z0) поверх высот hin: итоговая высота,
## материал грунта под покрытием (0 = естественный) и флаг "занято".
func compute_area(x0: int, z0: int, w: int, hin: PackedFloat32Array) -> Dictionary:
	var n := w * w
	var pad := SHOULDER + 12.0
	var minx := x0 - pad
	var maxx := x0 + w + pad
	var minz := z0 - pad
	var maxz := z0 + w + pad
	var tl := PackedFloat32Array()   # cx cz R falloff plateau
	for t: Dictionary in all_places():
		var c: Vector2 = t["center"]
		var rad: float = t["radius"] + t["falloff"] + pad
		if c.x > minx - rad and c.x < maxx + rad and c.y > minz - rad and c.y < maxz + rad:
			tl.append_array(PackedFloat32Array([c.x, c.y, t["radius"], t["falloff"], t["plateau"]]))
	var ls := gather_segments(minx, maxx, minz, maxz)
	var lots := PackedFloat32Array()
	var seen := {}
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			if _lot_cells.has(key):
				for idx: int in _lot_cells[key]:
					if not seen.has(idx):
						seen[idx] = true
						lots.append_array(_lot.slice(idx * LST, idx * LST + LST))

	var out_h := hin.duplicate()
	var out_m := PackedByteArray()
	out_m.resize(n)
	var out_b := PackedByteArray()
	out_b.resize(n)
	for j in w:
		var z := float(z0 + j)
		for i in w:
			var x := float(x0 + i)
			var k := i + w * j
			var hh := hin[k]
			var blk := 0
			for q in range(0, tl.size(), 5):
				var tdx := x - tl[q]
				var tdz := z - tl[q + 1]
				var dd := sqrt(tdx * tdx + tdz * tdz)
				var rr := tl[q + 2]
				if dd < rr + tl[q + 3]:
					hh = lerpf(hh, tl[q + 4], 1.0 - smoothstep(rr, rr + tl[q + 3], dd))
					if dd < rr + 6.0:
						blk = 1
			var pave := 0
			var walk := 0
			var shoulder := 0
			var walk_d := 1e9
			var walk_h := 0.0
			var walk_side := 0.0
			# поле дорог как в RoadField: по каждой улице — расстояние до проезжей части, улицы сливаются
			# плавным минимумом (скруглённые перекрёстки), поэтому вокселы совпадают с рисунком шейдера
			var sids := {}
			for q in range(0, ls.size(), SS):
				if x < ls[q + 12] or x > ls[q + 13] or z < ls[q + 14] or z > ls[q + 15]:
					continue
				var ax := ls[q]
				var az := ls[q + 1]
				var abx := ls[q + 3] - ax
				var abz := ls[q + 4] - az
				var l2 := abx * abx + abz * abz
				var t := 0.0
				if l2 > 1e-6:
					t = clampf(((x - ax) * abx + (z - az) * abz) / l2, 0.0, 1.0)
				var ddx := x - (ax + abx * t)
				var ddz := z - (az + abz * t)
				var e := sqrt(ddx * ddx + ddz * ddz) - ls[q + F_HW]
				var side := ls[q + F_SIDE]
				if e - side > SHOULDER + RoadField.FILLET:
					continue
				var sid := int(ls[q + F_SID])
				var cur: PackedFloat32Array = sids.get(sid, PackedFloat32Array())
				if cur.is_empty() or e < cur[0]:
					sids[sid] = PackedFloat32Array([e, lerpf(ls[q + 2], ls[q + 5], t), ls[q + F_MAT], side])
			var fp := 1e9
			var fo := 1e9
			var own := PackedFloat32Array()
			for sid in sids:
				var c: PackedFloat32Array = sids[sid]
				var wv := c[0] - c[3]
				if fp > 1e8:
					fp = c[0]
					fo = wv
				else:
					fp = RoadField._smin(fp, c[0], RoadField.FILLET)
					fo = RoadField._smin(fo, wv, RoadField.FILLET)
				if own.is_empty() or c[0] < own[0]:
					own = c
			if not own.is_empty():
				if fo < SHOULDER:
					hh = lerpf(hh, own[1] - BED, 1.0 - smoothstep(0.5, SHOULDER, fo))
				if fo <= 3.0:
					blk = 1
				if fp <= 0.0:
					pave = int(own[2])
				elif fo <= 0.0:
					walk = CONCRETE
					walk_d = fp
					walk_h = own[1]
					walk_side = own[3]
				elif fo <= 2.2:
					# кромка: материал грунта чуть шире покрытия, чтобы край рисовала карта дорог, а не воксели
					shoulder = int(own[2])
			# тротуар приподнят над проезжей частью (бордюр), мягкий подъём и спад
			if pave == 0 and walk != 0:
				var up_t := smoothstep(0.0, 1.9, walk_d)
				var down_t := 1.0 - smoothstep(walk_side - 1.8, walk_side + 0.4, walk_d)
				hh = walk_h + CURB_H * up_t * down_t
			var lot_m := 0
			var ramp_done := false
			for q in range(0, lots.size(), LST):
				var ldx := x - lots[q]
				var ldz := z - lots[q + 1]
				var sd := 0.0   # расстояние до края участка: < 0 внутри
				if int(lots[q + 8]) == 1:
					sd = sqrt(ldx * ldx + ldz * ldz) - lots[q + 2]
				else:
					var u := ldx * lots[q + 4] + ldz * lots[q + 5]
					var v := -ldx * lots[q + 5] + ldz * lots[q + 4]
					var ex := absf(u) - lots[q + 2]
					var ey := absf(v) - lots[q + 3]
					if ex < 0.0 and ey < 0.0:
						sd = maxf(ex, ey)
					else:
						sd = sqrt(maxf(ex, 0.0) * maxf(ex, 0.0) + maxf(ey, 0.0) * maxf(ey, 0.0))
				if sd <= 0.8 and lot_m == 0:
					lot_m = int(lots[q + 6])
					blk = 1
				if int(lots[q + 6]) != 0 and not ramp_done:
					if sd <= 0.0:
						hh = lots[q + 9]
						ramp_done = true
					elif sd < LOT_RAMP:
						# плавный склон от площадки к рельефу/дороге вместо обрыва, который воксели рубят в лесенку
						hh = lerpf(lots[q + 9], hh, smoothstep(0.0, LOT_RAMP, sd))
						ramp_done = true
				if lot_m != 0 and ramp_done:
					break
			out_h[k] = hh
			out_m[k] = pave if pave != 0 else (walk if walk != 0 else (lot_m if lot_m != 0 else shoulder))
			out_b[k] = blk
	return {"h": out_h, "mat": out_m, "blocked": out_b}


## Копия сегментов дорог, чьи рамки пересекают область (шаг SS на сегмент).
func gather_segments(minx: float, maxx: float, minz: float, maxz: float) -> PackedFloat32Array:
	var ls := PackedFloat32Array()
	var seen := {}
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			if _seg_cells.has(key):
				for idx: int in _seg_cells[key]:
					if not seen.has(idx):
						seen[idx] = true
						ls.append_array(_seg.slice(idx * SS, idx * SS + SS))
	return ls


func segment(gid: int) -> PackedFloat32Array:
	return _seg.slice(gid * SS, gid * SS + SS)


## Участки (мета-словари), пересекающие область.
func lots_in(minx: float, maxx: float, minz: float, maxz: float) -> Array:
	var out := []
	var seen := {}
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			if _lot_cells.has(key):
				for idx: int in _lot_cells[key]:
					if not seen.has(idx):
						seen[idx] = true
						out.append(_lot_meta[idx])
	return out


## Здания колонки: участки с btype, чей центр внутри колонки.
func buildings_in_column(cx: int, cz: int) -> Array:
	var ox := cx * 16.0
	var oz := cz * 16.0
	var out := []
	for l: Dictionary in lots_in(ox - 20.0, ox + 36.0, oz - 20.0, oz + 36.0):
		if String(l["btype"]) == "":
			continue
		var p: Vector2 = l["pos"]
		if p.x >= ox and p.x < ox + 16.0 and p.y >= oz and p.y < oz + 16.0:
			out.append(l)
	return out


## Мусор колонки: {pos, kind, yaw, seed, tilt}. В городах и на изношенных дорогах чаще.
func litter_in_column(cx: int, cz: int) -> Array:
	var ox := cx * 16.0
	var oz := cz * 16.0
	var out := []
	var ls := gather_segments(ox - 6.0, ox + 22.0, oz - 6.0, oz + 22.0)
	var kinds := ["tire", "barrel", "planks", "bag", "box", "cans", "pile"]
	var weights := [0.1, 0.08, 0.12, 0.16, 0.13, 0.21, 0.2]
	for q in range(0, ls.size(), SS):
		var gid := int(ls[q + F_GID])
		var town := int(ls[q + F_TOWN])
		var wear := ls[q + F_WEAR]
		var length := ls[q + F_LEN]
		var hw := ls[q + F_HW]
		var sw := ls[q + F_SIDE]
		var a := Vector2(ls[q], ls[q + 1])
		var b := Vector2(ls[q + 3], ls[q + 4])
		var dirv := (b - a) / maxf(length, 0.001)
		var nrm := Vector2(-dirv.y, dirv.x)
		var rate := (0.45 if town == 1 else 0.14) * (0.4 + wear)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, gid, 91])
		var n := int(length / 10.0 * rate + rng.randf())
		for k in n:
			var t := rng.randf()
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var zone := rng.randf()
			var lat := 0.0
			if zone < 0.4:
				lat = hw + sw * 0.5 + rng.randf_range(-0.3, 0.3) if sw > 0.0 else hw + rng.randf_range(0.4, 1.4)   # тротуар / обочина
			elif zone < 0.7:
				lat = hw - rng.randf_range(0.2, 0.7)                                                      # у бордюра
			else:
				lat = rng.randf_range(0.0, hw * 0.8)                                                      # на проезжей части
			var pos := a + dirv * (length * t) + nrm * lat * sgn
			var roll := rng.randf()
			var acc := 0.0
			var kind := "cans"
			for ki in kinds.size():
				acc += weights[ki]
				if roll <= acc:
					kind = kinds[ki]
					break
			if pos.x >= ox and pos.x < ox + 16.0 and pos.y >= oz and pos.y < oz + 16.0:
				out.append({"pos": pos, "kind": kind, "yaw": rng.randf() * TAU, "seed": rng.randi() & 0xffff, "tilt": rng.randf()})
	return out


## Столбы колонки: {pos, kind, yaw, seed, lean, across}. Чаще в городе, реже за городом,
## часть сломана, ржавая или лежит (в т.ч. поперёк дороги).
func poles_in_column(cx: int, cz: int) -> Array:
	var ox := cx * 16.0
	var oz := cz * 16.0
	var out := []
	var ls := gather_segments(ox - 4.0, ox + 20.0, oz - 4.0, oz + 20.0)
	for q in range(0, ls.size(), SS):
		var town := int(ls[q + F_TOWN])
		var spacing := 22.0 if town == 1 else (60.0 if town == 0 else 45.0)
		var s0 := ls[q + F_S0]
		var length := ls[q + F_LEN]
		var sid := int(ls[q + F_SID])
		var hw := ls[q + F_HW]
		var sw := ls[q + F_SIDE]
		var a := Vector2(ls[q], ls[q + 1])
		var b := Vector2(ls[q + 3], ls[q + 4])
		var dirv := (b - a) / maxf(length, 0.001)
		var nrm := Vector2(-dirv.y, dirv.x)
		var k := int(ceil(s0 / spacing))
		while k * spacing < s0 + length - 0.001:
			var s := k * spacing
			var h := hash([_seed, sid, k])
			var r1 := float(h & 1023) / 1024.0
			var r2 := float((h >> 10) & 1023) / 1024.0
			var r3 := float((h >> 20) & 1023) / 1024.0
			var pres := 0.8 if town == 1 else (0.5 if town == 0 else 0.3)
			if r1 < pres:
				var pos := a + dirv * (s - s0)
				var sgn := 1.0 if k % 2 == 0 else -1.0
				var off := hw + sw + 0.9
				var kind := "wood"
				if town == 1:
					kind = "wood" if r2 < 0.34 else ("lamp" if r2 < 0.66 else ("lamp_rust" if r2 < 0.76 else ("broken" if r2 < 0.88 else "fallen")))
				else:
					kind = "wood" if r2 < 0.5 else ("broken" if r2 < 0.7 else ("fallen" if r2 < 0.85 else "metal_rust"))
				var yaw := r3 * TAU
				var across := false
				var ppos := pos + nrm * sgn * off
				if kind == "lamp" or kind == "lamp_rust":
					var toward := -nrm * sgn
					yaw = atan2(-toward.y, toward.x)
				elif kind == "fallen":
					if r3 < 0.5:
						across = true
						ppos = pos + nrm * (r3 * 2.0 - 0.5) * hw
						yaw = atan2(-nrm.y, nrm.x) + (r2 - 0.5) * 0.8
					else:
						yaw = atan2(-dirv.y, dirv.x) + (r2 - 0.5) * 0.5
				if ppos.x >= ox and ppos.x < ox + 16.0 and ppos.y >= oz and ppos.y < oz + 16.0:
					out.append({"pos": ppos, "kind": kind, "yaw": yaw, "seed": h & 0xffff, "across": across})
			k += 1
	return out


# --- города --------------------------------------------------------------------

func _ensure_streets(t: Dictionary) -> void:
	if t["streets"]:
		return
	t["streets"] = true
	_town_seg0 = _seg_n
	_ends = []
	_town_flag = 1
	_lrng.seed = hash([_seed, int(t["id"]), 3])
	match t["pattern"]:
		Pattern.GRID: _grid(t, _lrng)
		Pattern.RADIAL: _radial(t, _lrng)
		Pattern.LINEAR: _linear(t, _lrng)
		Pattern.CULDESAC: _culdesac(t, _lrng)
	t["ends"] = _ends


## Конец улицы на границе города, ближайший к точке toward (иначе центр).
func _gate(t: Dictionary, toward: Vector2) -> Vector2:
	var c: Vector2 = t["center"]
	var rad: float = t["radius"]
	var best := c
	var bd := INF
	for e: Vector2 in t.get("ends", []):
		if e.distance_to(c) < rad * 0.7:
			continue
		var d := e.distance_to(toward)
		if d < bd:
			bd = d
			best = e
	return best


func _style(tier: int, main: bool, rng: RandomNumberGenerator) -> Dictionary:
	var wear := rng.randf_range(0.1, 0.5) + (0.0 if tier == 2 else (0.1 if tier == 1 else 0.25))
	match tier:
		2:
			if main:
				return {"mat": ASPHALT, "hw": 5.0, "side": SW, "line": true, "wear": wear}
			if rng.randf() < 0.35:
				return {"mat": CONCRETE, "hw": 4.0, "side": SW, "line": false, "wear": wear}
			return {"mat": ASPHALT, "hw": 4.0, "side": SW, "line": true, "wear": wear}
		1:
			if main:
				return {"mat": ASPHALT, "hw": 4.4, "side": SW, "line": true, "wear": wear}
			return {"mat": GRAVEL, "hw": 3.4, "side": 0.0, "line": false, "wear": wear + 0.2}
	if main:
		return {"mat": GRAVEL, "hw": 3.6, "side": 0.0, "line": false, "wear": wear + 0.2}
	return {"mat": ROADSAND, "hw": 2.6, "side": 0.0, "line": false, "wear": wear + 0.2}


func _lot_kind(tier: int, d: float, rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if tier == 2:
		if d < 0.5:
			return Lot.COMMERCIAL
		return Lot.INDUSTRIAL if (d > 0.7 and roll < 0.3) else Lot.RESIDENTIAL
	if tier == 1:
		if d < 0.3:
			return Lot.COMMERCIAL
		return Lot.INDUSTRIAL if (d > 0.7 and roll < 0.3) else Lot.RESIDENTIAL
	return Lot.RESIDENTIAL


func _btype(kind: int, tier: int, d: float, rng: RandomNumberGenerator) -> String:
	match kind:
		Lot.COMMERCIAL:
			return "office" if (tier == 2 and d < 0.4 and rng.randf() < 0.6) else "shop"
		Lot.INDUSTRIAL:
			return "warehouse"
		Lot.RESIDENTIAL:
			return "apartment" if (tier == 2 and rng.randf() < 0.3) else "house"
	return ""


func _w(t: Dictionary, p: Vector2) -> Vector2:
	return (t["center"] as Vector2) + p.rotated(t["angle"])


func _add_line(a: Vector2, b: Vector2, h: float, st: Dictionary) -> void:
	_ends.append(a)
	_ends.append(b)
	_sid += 1
	var len := a.distance_to(b)
	var n := maxi(1, int(ceil(len / 20.0)))
	var first := _seg_n
	for i in n:
		_add_seg(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), h, h, st, len * i / n)
	_link_pieces(first, _seg_n - 1, false)


func _add_seg(a: Vector2, b: Vector2, ha: float, hb: float, st: Dictionary, s0: float) -> int:
	var hw: float = st["hw"]
	var side: float = st["side"]
	var m := hw + side + SHOULDER + 1.0
	var minx := minf(a.x, b.x) - m
	var maxx := maxf(a.x, b.x) + m
	var minz := minf(a.y, b.y) - m
	var maxz := maxf(a.y, b.y) + m
	var mat: int = st["mat"]
	# приоритет на перекрёстках: весь перекрёсток достаётся старшей дороге (асфальт > бетон > щебень > грунт, шире > уже);
	# равенства быть не должно — иначе граница идёт по диагоналям («бабочкой»), см. RoadField._eval
	var rank := 4.0 if mat == ASPHALT else (3.0 if mat == CONCRETE else (2.0 if mat == GRAVEL else 1.0))
	var dirv := (b - a).normalized()
	var n := Vector2(-dirv.y, dirv.x)
	_seg.append_array(PackedFloat32Array([
		a.x, a.y, ha, b.x, b.y, hb, hw, side, float(mat), 1.0 if st["line"] else 0.0,
		s0, a.distance_to(b), minx, maxx, minz, maxz,
		float(st.get("wear", 0.4)), rank * 10.0 + hw, float(_sid), float(_town_flag),
		n.x, n.y, n.x, n.y, -1.0, -1.0, float(_seg_n), 0.0]))
	_register(_seg_cells, _seg_n, minx, maxx, minz, maxz)
	_seg_n += 1
	return _seg_n - 1


## Связывает куски одной ломаной: соседи и скошенные (miter) нормали на стыках.
func _link_pieces(i0: int, i1: int, closed: bool) -> void:
	var normals: Array[Vector2] = []
	for i in range(i0, i1 + 1):
		var q := i * SS
		var dv := Vector2(_seg[q + 3] - _seg[q], _seg[q + 4] - _seg[q + 1]).normalized()
		normals.append(Vector2(-dv.y, dv.x))
	var cnt := i1 - i0 + 1
	for k in cnt:
		var q := (i0 + k) * SS
		var n := normals[k]
		var prev := i0 + k - 1 if k > 0 else (i1 if closed else -1)
		var next := i0 + k + 1 if k < cnt - 1 else (i0 if closed else -1)
		_seg[q + F_PREV] = float(prev)
		_seg[q + F_NEXT] = float(next)
		var o0 := n
		var o1 := n
		if prev >= 0:
			var avg := (normals[prev - i0] + n).normalized()
			o0 = avg / maxf(0.6, avg.dot(n))
		if next >= 0:
			var avg2 := (normals[next - i0] + n).normalized()
			o1 = avg2 / maxf(0.6, avg2.dot(n))
		_seg[q + F_N0X] = o0.x
		_seg[q + F_N0X + 1] = o0.y
		_seg[q + F_N0X + 2] = o1.x
		_seg[q + F_N0X + 3] = o1.y


func _add_lot(t: Dictionary, local_c: Vector2, hx: float, hz: float, local_rot: float, kind: int, shape: int, road_mat: int, btype: String = "?") -> void:
	var c := _w(t, local_c)
	var rot: float = t["angle"] + local_rot
	# фасад здания (+Z) разворачиваем к ближайшей улице города
	if btype != "" and shape == 0 and kind != Lot.PLAZA and int(t["tier"]) >= 0:
		var best_d := INF
		var best_v := Vector2.ZERO
		for i in range(_town_seg0, _seg_n):
			var q := i * SS
			var ax := _seg[q]
			var az := _seg[q + 1]
			var abx := _seg[q + 3] - ax
			var abz := _seg[q + 4] - az
			var l2 := abx * abx + abz * abz
			var tt := 0.0
			if l2 > 1e-6:
				tt = clampf(((c.x - ax) * abx + (c.y - az) * abz) / l2, 0.0, 1.0)
			var v := Vector2(ax + abx * tt - c.x, az + abz * tt - c.y)
			var dd := v.length()
			if dd < best_d:
				best_d = dd
				best_v = v
		if best_d < 60.0:
			var best_k := 0
			var best_dot := -2.0
			for k in 4:
				var ang := rot + k * PI * 0.5
				var f := Vector2(-sin(ang), cos(ang))   # локальный +Z в мировых координатах
				var dt := f.dot(best_v.normalized())
				if dt > best_dot:
					best_dot = dt
					best_k = k
			rot += best_k * PI * 0.5
			if best_k % 2 == 1:
				var tmp := hx
				hx = hz
				hz = tmp
	var mat := 0
	match kind:
		Lot.COMMERCIAL, Lot.PLAZA:
			mat = CONCRETE
		Lot.INDUSTRIAL:
			mat = GRAVEL
		Lot.TURNAROUND:
			mat = road_mat
		Lot.PAD_ASPHALT:
			mat = ASPHALT
	var bt := btype
	if bt == "?":
		var d := local_c.length() / float(t["radius"])
		bt = _btype(kind, int(t["tier"]), d, _lrng)
		# небольшие парки в городах: часть участков под дома (по месту, без расхода общего ГСЧ — мир не сдвигается)
		if bt == "house" and int(t["tier"]) >= 1 and absi(hash(Vector2i(roundi(c.x), roundi(c.y)))) % 100 < PARK_P:
			bt = "park"
	var plateau: float = t["plateau"]
	_lot.append_array(PackedFloat32Array([c.x, c.y, hx, hz, cos(rot), sin(rot), float(mat), float(kind), float(shape), plateau]))
	var rad := hx if shape == 1 else Vector2(hx, hz).length()
	_register(_lot_cells, _lot_n, c.x - rad, c.x + rad, c.y - rad, c.y + rad)
	_lot_n += 1
	var meta := {"pos": c, "hx": hx, "hz": hz, "rot": rot, "kind": kind, "shape": shape, "btype": bt,
		"plateau": plateau, "mat": mat, "seed": hash([_seed, int(c.x), int(c.y)]) & 0xffffff,
		"poi": String(t.get("kind", "")) == "poi"}
	_lot_meta.append(meta)
	(t["lots"] as Array).append(meta)


func _register(cells: Dictionary, idx: int, minx: float, maxx: float, minz: float, maxz: float) -> void:
	for cz in range(floori(minz / CELL), floori(maxz / CELL) + 1):
		for cx in range(floori(minx / CELL), floori(maxx / CELL) + 1):
			var key := Vector2i(cx, cz)
			var arr: PackedInt32Array = cells.get(key, PackedInt32Array())
			arr.append(idx)
			cells[key] = arr


# --- паттерны ------------------------------------------------------------------

func _grid(t: Dictionary, rng: RandomNumberGenerator) -> void:
	var tier: int = t["tier"]
	var rad: float = t["radius"]
	var ph: float = t["plateau"]
	var p := 52.0 if tier == 2 else 46.0
	var n := int(ceil(rad / p))
	for axis in 2:
		for k in range(-n, n + 1):
			var off := k * p
			var half := sqrt(maxf(rad * rad - off * off, 0.0)) - 6.0
			if half < 12.0:
				continue
			var st := _style(tier, k == 0, rng)
			var a := Vector2(-half, off) if axis == 0 else Vector2(off, -half)
			var b := Vector2(half, off) if axis == 0 else Vector2(off, half)
			_add_line(_w(t, a), _w(t, b), ph, st)
	var inner := p - 16.0
	var q := inner * 0.25
	var big_p := BIG_BLOCK_P if PrefabRegistry.has_big(2.0 * (q - 1.0) - 1.0) else 0
	for i in range(-n - 1, n + 1):
		for j in range(-n - 1, n + 1):
			var bc := Vector2((i + 0.5) * p, (j + 0.5) * p)
			if bc.length() + inner * 0.71 > rad - 6.0:
				continue
			var kinds: Array[int] = []
			for a in 2:
				for b in 2:
					var lc0 := bc + Vector2((a - 0.5) * inner * 0.5, (b - 0.5) * inner * 0.5)
					kinds.append(_lot_kind(tier, lc0.length() / rad, rng))   # ГСЧ расходуется одинаково — остальной мир не сдвигается
			# крупные префабы (не влезают в обычный участок): иногда весь квартал — один участок
			if big_p > 0 and absi(hash([t["center"], i, j, 515])) % 100 < big_p:
				_add_lot(t, bc, inner * 0.5 - 1.0, inner * 0.5 - 1.0, 0.0, kinds[0], 0, ASPHALT)
				continue
			var ki := 0
			for a in 2:
				for b in 2:
					var lc := bc + Vector2((a - 0.5) * inner * 0.5, (b - 0.5) * inner * 0.5)
					_add_lot(t, lc, q - 1.0, q - 1.0, 0.0, kinds[ki], 0, ASPHALT)
					ki += 1


func _radial(t: Dictionary, rng: RandomNumberGenerator) -> void:
	var tier: int = t["tier"]
	var rad: float = t["radius"]
	var ph: float = t["plateau"]
	var plaza := 14.0 + 4.0 * tier
	_add_lot(t, Vector2.ZERO, plaza, plaza, 0.0, Lot.PLAZA, 1, CONCRETE, "")
	var rings: Array[float] = [rad * 0.55]
	if tier == 2:
		rings = [rad * 0.36, rad * 0.7]
	var spokes := 6 if tier == 2 else 5
	for ri in rings.size():
		var r := rings[ri]
		var st := _style(tier, ri == 0, rng)
		var m := int(ceil(TAU * r / 14.0))
		_sid += 1
		var first := _seg_n
		var prev := Vector2(r, 0.0)
		var s := 0.0
		for q in range(1, m + 1):
			var cur := Vector2(cos(TAU * q / m), sin(TAU * q / m)) * r
			_add_seg(_w(t, prev), _w(t, cur), ph, ph, st, s)
			s += prev.distance_to(cur)
			prev = cur
		_link_pieces(first, _seg_n - 1, true)
	for k in spokes:
		var ang := TAU * k / spokes
		var d := Vector2(cos(ang), sin(ang))
		_add_line(_w(t, d * (plaza + 2.0)), _w(t, d * (rad - 6.0)), ph, _style(tier, k % 2 == 0, rng))
	for ri in rings.size():
		var r := rings[ri]
		for band: float in [15.0, -15.0]:
			var rl := r + band
			if rl - 12.0 < plaza + 6.0 or rl + 12.0 > rad - 6.0:
				continue
			var cnt := int(TAU * rl / 22.0)
			for q in cnt:
				var ang := TAU * (q + 0.5) / cnt
				var near := false
				for k in spokes:
					if absf(wrapf(ang - TAU * k / spokes, -PI, PI)) * rl < 17.0:
						near = true
				if near:
					continue
				_add_lot(t, Vector2(cos(ang), sin(ang)) * rl, 9.0, 7.0, ang + PI * 0.5, _lot_kind(tier, rl / rad, rng), 0, ASPHALT)


func _linear(t: Dictionary, rng: RandomNumberGenerator) -> void:
	var tier: int = t["tier"]
	var rad: float = t["radius"]
	var ph: float = t["plateau"]
	var half := rad - 6.0
	var main_st := _style(tier, true, rng)
	_add_line(_w(t, Vector2(-half, 0.0)), _w(t, Vector2(half, 0.0)), ph, main_st)
	var sp := 50.0
	var n := int(floor(half / sp))
	var cross_x: Array[float] = []
	for k in range(-n, n + 1):
		var x := k * sp
		var len := minf(sqrt(maxf(rad * rad - x * x, 0.0)) - 6.0, 62.0)
		if len < 16.0:
			continue
		var st := _style(tier, false, rng)
		_add_line(_w(t, Vector2(x, -len)), _w(t, Vector2(x, len)), ph, st)
		cross_x.append(x)
		var cc: float = float(st["hw"]) + float(st["side"]) + 8.0
		for sgn: float in [-1.0, 1.0]:
			for zs: float in [-1.0, 1.0]:
				var z := 24.0
				while z + 9.0 <= len - 4.0:
					var lc := Vector2(x + sgn * cc, zs * z)
					if lc.length() + 10.0 <= rad - 6.0:
						_add_lot(t, lc, 7.0, 9.0, 0.0, _lot_kind(tier, lc.length() / rad, rng), 0, ASPHALT)
					z += 22.0
	var main_off: float = float(main_st["hw"]) + float(main_st["side"]) + 8.0
	var lx := -half + 12.0
	while lx <= half - 12.0:
		var blocked := false
		for x in cross_x:
			if absf(lx - x) < 16.0:
				blocked = true
		if not blocked:
			for sgn: float in [-1.0, 1.0]:
				var lc := Vector2(lx, sgn * main_off)
				if lc.length() + 10.0 <= rad - 6.0:
					_add_lot(t, lc, 9.0, 7.0, 0.0, _lot_kind(tier, lc.length() / rad, rng), 0, ASPHALT)
		lx += 22.0


func _culdesac(t: Dictionary, rng: RandomNumberGenerator) -> void:
	var tier: int = t["tier"]
	var rad: float = t["radius"]
	var ph: float = t["plateau"]
	var half := rad - 8.0
	_add_line(_w(t, Vector2(-half, 0.0)), _w(t, Vector2(half, 0.0)), ph, _style(tier, true, rng))
	var x := -half + 26.0
	var dir := 1.0
	while x < half - 20.0:
		var bl := minf(rng.randf_range(34.0, 50.0), sqrt(maxf(rad * rad - x * x, 0.0)) - 20.0)
		if bl >= 22.0:
			var st := _style(tier, false, rng)
			var end := Vector2(x, dir * bl)
			_add_line(_w(t, Vector2(x, 0.0)), _w(t, end), ph, st)
			_add_lot(t, end, 9.0, 9.0, 0.0, Lot.TURNAROUND, 1, int(st["mat"]), "")
			var cc: float = float(st["hw"]) + float(st["side"]) + 8.0
			var z := 16.0
			while z + 9.0 <= bl - 6.0:
				for sgn: float in [-1.0, 1.0]:
					_add_lot(t, Vector2(x + sgn * cc, dir * z), 7.0, 9.0, 0.0, Lot.RESIDENTIAL, 0, ASPHALT, "house")
				z += 20.0
		x += 44.0
		dir = -dir


# --- POI ------------------------------------------------------------------------

func _poi_layout(t: Dictionary) -> void:
	_lrng.seed = int(t["seed"])
	var gravel := Lot.INDUSTRIAL
	match t["poi_type"]:
		"farm":
			_add_lot(t, Vector2.ZERO, 21.0, 21.0, 0.0, gravel, 1, GRAVEL, "")
			_add_lot(t, Vector2(-11.0, -8.0), 9.0, 6.5, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "barn")
			_add_lot(t, Vector2(9.0, -9.0), 6.0, 5.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "farmhouse")
			_add_lot(t, Vector2(-13.0, 10.0), 3.4, 3.4, 0.0, Lot.RESIDENTIAL, 1, GRAVEL, "silo")
			_add_lot(t, Vector2(9.0, 10.0), 4.0, 3.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "shed")
		"cabin":
			_add_lot(t, Vector2.ZERO, 14.0, 14.0, 0.0, gravel, 1, GRAVEL, "")
			_add_lot(t, Vector2(-2.0, -3.0), 5.0, 4.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "cabin")
			_add_lot(t, Vector2(7.0, 6.0), 3.0, 2.5, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "shed")
		"gas":
			_add_lot(t, Vector2.ZERO, 17.0, 13.0, 0.0, Lot.PAD_ASPHALT, 0, ASPHALT, "")
			_add_lot(t, Vector2(0.0, -8.0), 7.5, 5.0, 0.0, Lot.RESIDENTIAL, 0, ASPHALT, "gas_store")
			_add_lot(t, Vector2(0.0, 4.0), 8.0, 4.0, 0.0, Lot.RESIDENTIAL, 0, ASPHALT, "gas_canopy")
		_:
			_add_lot(t, Vector2.ZERO, 26.0, 18.0, 0.0, gravel, 0, GRAVEL, "")
			_add_lot(t, Vector2(-11.0, -6.0), 11.0, 6.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "warehouse")
			_add_lot(t, Vector2(-10.0, 8.0), 9.0, 5.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "warehouse")
			_add_lot(t, Vector2(15.0, 0.0), 4.0, 3.0, 0.0, Lot.RESIDENTIAL, 0, GRAVEL, "shed")
