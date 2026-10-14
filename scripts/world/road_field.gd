class_name RoadField
extends RefCounted
## Поле дорог для колонки 16x16 м: на сетке 0.4 м (41x41 узел) считает расстояния до границы
## проезжей части (Fp) и внешней границы тротуара (Fo), поперечную/продольную координаты,
## тип покрытия, износ, разметку. Улицы объединяются плавным минимумом — на перекрёстках
## бордюры скруглены. Шейдер ландшафта читает эту карту попиксельно, поэтому края дорог
## чёткие, хотя вокселы ландшафта крупные, а сама дорога остаётся частью грунта.

const COL := 16
const SS := RoadNet.SS
const STEP := 0.4
const NODES := 41
const BEVEL := 0.0
const FILLET := 7.0
const PAD_TOP := 0.0

const F_FO := 0
const F_FP := 1
const F_LAT := 2
const F_ALONG := 3
const F_HW := 4
const F_KIND := 5
const F_WEAR := 6
const F_MARK := 7
const F_CURB := 8
const F_N := 9

var _roads: RoadNet
var _gen: WorldGen
var _ox := 0.0
var _oz := 0.0
var _ls := PackedFloat32Array()
var _tb := PackedFloat32Array()
var _pads := PackedFloat32Array()


## Блок данных колонки: {a: RGBAF(Fp, Fo, lat, along), b: RGBA8(kind*20, wear, mark, curb), c: RGBA8(hw/12, valid)}.
static func build_block(roads: RoadNet, cx: int, cz: int, gen: WorldGen = null) -> Dictionary:
	var f := RoadField.new()
	f._roads = roads
	f._gen = gen
	f._ox = cx * COL
	f._oz = cz * COL
	return f._run()


static func kind_of(mat: int) -> int:
	match mat:
		RoadNet.ASPHALT: return 0
		RoadNet.CONCRETE: return 1
		RoadNet.GRAVEL: return 2
	return 3


func _run() -> Dictionary:
	var pad := 6.0
	_ls = _roads.gather_segments(_ox - pad, _ox + COL + pad, _oz - pad, _oz + COL + pad)
	var n := _ls.size() / SS
	_tb.resize(n * 4)
	for i in n:
		var q := i * SS
		var m := _ls[q + RoadNet.F_HW] + _ls[q + RoadNet.F_SIDE] + FILLET + 1.0
		_tb[i * 4] = minf(_ls[q], _ls[q + 3]) - m
		_tb[i * 4 + 1] = maxf(_ls[q], _ls[q + 3]) + m
		_tb[i * 4 + 2] = minf(_ls[q + 1], _ls[q + 4]) - m
		_tb[i * 4 + 3] = maxf(_ls[q + 1], _ls[q + 4]) + m
	# запас по участкам должен быть не меньше самого большого участка (площадь города — десятки метров): иначе
	# часть площади не попадает в карту и выглядит другим покрытием, обрезанным по границам колонок
	for lot: Dictionary in _roads.lots_in(_ox - pad - 120.0, _ox + COL + pad + 120.0, _oz - pad - 120.0, _oz + COL + pad + 120.0):
		var mat := int(lot["mat"])
		if mat == 0:
			continue
		var kind := 5
		if mat == RoadNet.GRAVEL or mat == RoadNet.ROADSAND:
			kind = 6
		elif mat == RoadNet.ASPHALT:
			kind = 7
		var c: Vector2 = lot["pos"]
		var hx: float = lot["hx"]
		var hz: float = lot["hz"]
		var r := (hx if int(lot["shape"]) == 1 else Vector2(hx, hz).length()) + 2.0
		var rot: float = lot["rot"]
		var wear := float(int(lot["seed"]) % 100) / 160.0 + 0.1
		_pads.append_array(PackedFloat32Array([c.x, c.y, hx, hz, cos(rot), sin(rot), float(int(lot["shape"])), float(kind), float(lot["plateau"]), wear,
			c.x - r, c.x + r, c.y - r, c.y + r]))

	var a := PackedFloat32Array()
	a.resize(NODES * NODES * 4)
	var b := PackedByteArray()
	b.resize(NODES * NODES * 4)
	var c_ := PackedByteArray()
	c_.resize(NODES * NODES * 4)
	# для плавных стыков покрытий (шейдер читает их с мипмапа — размытие делает видеокарта):
	# k1 = веса основы покрытия (асфальт, бетон, щебень, грунт), k2 = (площадка, тротуар, износ, -)
	var k1 := PackedByteArray()
	k1.resize(NODES * NODES * 4)
	var k2 := PackedByteArray()
	k2.resize(NODES * NODES * 4)
	var gx0 := int(round(_ox / STEP))
	var gz0 := int(round(_oz / STEP))
	for j in NODES:
		for i in NODES:
			var k := (i + NODES * j) * 4
			var x := (gx0 + i) * STEP
			var z := (gz0 + j) * STEP
			var s := PackedFloat32Array()
			if (n > 0 or not _pads.is_empty()) and _near_any(x, z):
				s = _eval(x, z)
			if s.size() >= F_N:
				a[k] = s[F_FP]
				a[k + 1] = s[F_FO]
				a[k + 2] = s[F_LAT]
				a[k + 3] = s[F_ALONG]
				b[k] = int(s[F_KIND]) * 20
				b[k + 1] = int(clampf(s[F_WEAR], 0.0, 1.0) * 255.0)
				b[k + 2] = int(clampf(s[F_MARK], 0.0, 1.0) * 255.0)
				b[k + 3] = int(s[F_CURB] * 255.0)
				c_[k] = int(clampf(s[F_HW] / 12.0, 0.0, 1.0) * 255.0)
				var kd := int(s[F_KIND])
				var base := kd
				if kd >= 5:
					base = 1 if kd == 5 else (2 if kd == 6 else 0)
				k1[k + clampi(base, 0, 3)] = 255
				k2[k] = 255 if kd >= 5 else 0
				k2[k + 1] = b[k + 3]
				k2[k + 2] = b[k + 1]
				k2[k + 3] = 255
				if _gen != null and s[F_FO] < 4.0:
					var hv := clampi(roundi((_gen.height_at(x, z) + 50.0) * 100.0), 0, 65535)
					c_[k + 2] = hv >> 8
					c_[k + 3] = hv & 255
			else:
				a[k] = 1000.0
				a[k + 1] = 1000.0
			c_[k + 1] = 255
	return {
		"a": Image.create_from_data(NODES, NODES, false, Image.FORMAT_RGBAF, a.to_byte_array()),
		"b": Image.create_from_data(NODES, NODES, false, Image.FORMAT_RGBA8, b),
		"c": Image.create_from_data(NODES, NODES, false, Image.FORMAT_RGBA8, c_),
		"k1": Image.create_from_data(NODES, NODES, false, Image.FORMAT_RGBA8, k1),
		"k2": Image.create_from_data(NODES, NODES, false, Image.FORMAT_RGBA8, k2),
	}


static func _smin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


func _near_any(x: float, z: float) -> bool:
	var n := _tb.size() / 4
	for i in n:
		if x >= _tb[i * 4] and x <= _tb[i * 4 + 1] and z >= _tb[i * 4 + 2] and z <= _tb[i * 4 + 3]:
			return true
	for q in range(0, _pads.size(), 14):
		if x >= _pads[q + 10] and x <= _pads[q + 11] and z >= _pads[q + 12] and z <= _pads[q + 13]:
			return true
	return false


func _eval(x: float, z: float) -> PackedFloat32Array:
	var rel_idx := PackedInt32Array()
	var rel_e := PackedFloat32Array()
	var rel_t := PackedFloat32Array()
	var rel_lat := PackedFloat32Array()
	var n := _tb.size() / 4
	for i in n:
		if x < _tb[i * 4] or x > _tb[i * 4 + 1] or z < _tb[i * 4 + 2] or z > _tb[i * 4 + 3]:
			continue
		var q := i * SS
		var ax := _ls[q]
		var az := _ls[q + 1]
		var abx := _ls[q + 3] - ax
		var abz := _ls[q + 4] - az
		var l2 := abx * abx + abz * abz
		var t := 0.0
		var t_raw := 0.0
		if l2 > 1e-6:
			t_raw = ((x - ax) * abx + (z - az) * abz) / l2
			t = clampf(t_raw, 0.0, 1.0)
		var dx := x - (ax + abx * t)
		var dz := z - (az + abz * t)
		var d := sqrt(dx * dx + dz * dz)
		var ln := sqrt(l2)
		var lat := 0.0
		if ln > 1e-4:
			lat = (dx * (-abz) + dz * abx) / ln
		rel_idx.append(i)
		rel_e.append(d - _ls[q + RoadNet.F_HW])
		rel_t.append(t_raw)   # продольная координата продолжается за концом сегмента: иначе она там постоянна и декали тянутся полосами
		rel_lat.append(lat)
	var pad_e := 1e9
	var pad_q := -1
	for q in range(0, _pads.size(), 14):
		if x < _pads[q + 10] or x > _pads[q + 11] or z < _pads[q + 12] or z > _pads[q + 13]:
			continue
		var dx := x - _pads[q]
		var dz := z - _pads[q + 1]
		var u := dx * _pads[q + 4] + dz * _pads[q + 5]
		var v := -dx * _pads[q + 5] + dz * _pads[q + 4]
		var e := 0.0
		if int(_pads[q + 6]) == 1:
			e = sqrt(u * u + v * v) - _pads[q + 2]
		else:
			var qx := absf(u) - _pads[q + 2]
			var qz := absf(v) - _pads[q + 3]
			e = Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0)
		if e < pad_e:
			pad_e = e
			pad_q = q
	if rel_idx.is_empty() and pad_q < 0:
		return PackedFloat32Array()

	var by_sid := {}
	for k in rel_idx.size():
		var q := rel_idx[k] * SS
		var sid := int(_ls[q + RoadNet.F_SID])
		var e := rel_e[k]
		var w := e - _ls[q + RoadNet.F_SIDE]
		if by_sid.has(sid):
			var cur: PackedFloat32Array = by_sid[sid]
			cur[0] = minf(cur[0], e)
			cur[1] = minf(cur[1], w)
			by_sid[sid] = cur
		else:
			by_sid[sid] = PackedFloat32Array([e, w])
	var fp := 1e9
	var fo := 1e9
	for sid in by_sid:
		var cur: PackedFloat32Array = by_sid[sid]
		if fp > 1e8:
			fp = cur[0]
			fo = cur[1]
		else:
			fp = _smin(fp, cur[0], FILLET)
			fo = _smin(fo, cur[1], FILLET)
	if pad_q >= 0:
		fp = minf(fp, pad_e)
		fo = minf(fo, pad_e)
	var out := PackedFloat32Array()
	out.resize(F_N)
	out[F_FO] = fo
	out[F_FP] = fp
	if fo > 4.0:
		return out

	var use_pad := pad_q >= 0 and (rel_idx.is_empty() or pad_e <= fp + 0.0001)
	if use_pad:
		var u2 := (x - _pads[pad_q]) * _pads[pad_q + 4] + (z - _pads[pad_q + 1]) * _pads[pad_q + 5]
		var v2 := -(x - _pads[pad_q]) * _pads[pad_q + 5] + (z - _pads[pad_q + 1]) * _pads[pad_q + 4]
		out[F_LAT] = v2
		out[F_ALONG] = u2
		out[F_HW] = 99.0
		out[F_KIND] = _pads[pad_q + 7]
		out[F_WEAR] = _pads[pad_q + 9]
		out[F_MARK] = 0.0
		out[F_CURB] = 0.0
		return out
	var owner := -1
	var best_prio := -1.0
	var best_e := 1e9
	var near_e := 1e9
	for k in rel_idx.size():
		near_e = minf(near_e, rel_e[k])
	var thr := maxf(near_e, 0.0) + 0.6
	var min_w := 1e9
	var w_owner := -1
	for k in rel_idx.size():
		var q := rel_idx[k] * SS
		if fp <= 0.0:
			if rel_e[k] <= thr:
				# при равном приоритете решает номер улицы (а не расстояние до оси — оно делит перекрёсток по диагоналям)
				var pr := _ls[q + RoadNet.F_PRIO] + 0.001 * fmod(_ls[q + RoadNet.F_SID], 97.0) / 97.0
				if pr > best_prio or (absf(pr - best_prio) < 1e-6 and rel_e[k] < best_e):
					best_prio = pr
					best_e = rel_e[k]
					owner = k
		else:
			var w := rel_e[k] - _ls[q + RoadNet.F_SIDE]
			if w < min_w:
				min_w = w
				w_owner = k
	if fp > 0.0:
		owner = w_owner
	var oq := rel_idx[owner] * SS
	out[F_LAT] = rel_lat[owner]
	out[F_ALONG] = _ls[oq + RoadNet.F_S0] + rel_t[owner] * _ls[oq + RoadNet.F_LEN]
	out[F_HW] = _ls[oq + RoadNet.F_HW]
	out[F_KIND] = float(kind_of(int(_ls[oq + RoadNet.F_MAT])))
	out[F_WEAR] = _ls[oq + RoadNet.F_WEAR]
	out[F_CURB] = 1.0 if _ls[oq + RoadNet.F_SIDE] > 0.0 else 0.0
	var mark := 0.0
	if _ls[oq + RoadNet.F_LINE] > 0.5 and fp <= 0.0:
		mark = 1.0
		var osid := int(_ls[oq + RoadNet.F_SID])
		for k in rel_idx.size():
			var q := rel_idx[k] * SS
			if int(_ls[q + RoadNet.F_SID]) != osid and rel_e[k] < 2.0:
				mark = 0.0
				break
	out[F_MARK] = mark
	return out
