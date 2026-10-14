class_name RoadOverview
extends RefCounted
## Обзорная карта дорог для дальнего ландшафта (LOD): вся карта одной текстурой RGBA8, чтобы дороги и площади
## города были видны с любого расстояния. R — покрытие (мягкий край), G — материал (0 асфальт, 1/3 бетон, 2/3 щебень, 1 песок),
## B — тротуар/обочина (1), A — площадка/площадь (1). Строится один раз при старте мира (десятки миллисекунд).

const MAX_PX := 4096


static func build(roads: RoadNet, world_size: int) -> Dictionary:
	var ppm := minf(1.0, float(MAX_PX) / float(world_size))
	var px := int(ceil(world_size * ppm))
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var data := img.get_data()
	var ss := RoadNet.SS
	var seg := roads._seg
	var n: int = roads._seg_n
	for i in n:
		var q := i * ss
		var ax := seg[q]
		var az := seg[q + 1]
		var bx := seg[q + 3]
		var bz := seg[q + 4]
		var hw: float = seg[q + RoadNet.F_HW]
		var side: float = seg[q + RoadNet.F_SIDE]
		var mat := int(seg[q + RoadNet.F_MAT])
		var reach := hw + side + 1.5
		var x0 := maxi(int((minf(ax, bx) - reach) * ppm), 0)
		var x1 := mini(int((maxf(ax, bx) + reach) * ppm) + 1, px - 1)
		var z0 := maxi(int((minf(az, bz) - reach) * ppm), 0)
		var z1 := mini(int((maxf(az, bz) + reach) * ppm) + 1, px - 1)
		var abx := bx - ax
		var abz := bz - az
		var l2 := maxf(abx * abx + abz * abz, 1e-6)
		var gk := float(clampi(mat - RoadNet.ASPHALT, 0, 3)) / 3.0
		for zz in range(z0, z1 + 1):
			for xx in range(x0, x1 + 1):
				var wx := (xx + 0.5) / ppm
				var wz := (zz + 0.5) / ppm
				var t := clampf(((wx - ax) * abx + (wz - az) * abz) / l2, 0.0, 1.0)
				var dx := wx - (ax + abx * t)
				var dz := wz - (az + abz * t)
				var d := sqrt(dx * dx + dz * dz)
				var cov := clampf((hw + 0.5 / ppm - d) * ppm, 0.0, 1.0)
				var sd := 0.0
				if side > 0.0 and d > hw:
					sd = clampf((hw + side + 0.5 / ppm - d) * ppm, 0.0, 1.0)
				var o := (zz * px + xx) * 4
				if cov > 0.0 and cov >= data[o] / 255.0:
					data[o] = int(cov * 255.0)
					data[o + 1] = int(gk * 255.0)
				if sd > 0.0 and cov < 1.0 and data[o] < 40:
					data[o + 2] = maxi(data[o + 2], int(sd * 255.0))
	# площадки и площади города (бетон/асфальт/щебень)
	for l: Dictionary in roads._lot_meta:
		var mat := int(l["mat"])
		if mat == 0:
			continue
		var c: Vector2 = l["pos"]
		var hx: float = l["hx"]
		var hz: float = l["hz"]
		var rot: float = l["rot"]
		var rad := (hx if int(l["shape"]) == 1 else Vector2(hx, hz).length()) + 1.0
		var cs := cos(rot)
		var sn := sin(rot)
		var x0 := maxi(int((c.x - rad) * ppm), 0)
		var x1 := mini(int((c.x + rad) * ppm) + 1, px - 1)
		var z0 := maxi(int((c.y - rad) * ppm), 0)
		var z1 := mini(int((c.y + rad) * ppm) + 1, px - 1)
		var gk := float(clampi(mat - RoadNet.ASPHALT, 0, 3)) / 3.0
		for zz in range(z0, z1 + 1):
			for xx in range(x0, x1 + 1):
				var dx := (xx + 0.5) / ppm - c.x
				var dz := (zz + 0.5) / ppm - c.y
				var inside := false
				if int(l["shape"]) == 1:
					inside = dx * dx + dz * dz <= hx * hx
				else:
					var u := dx * cs + dz * sn
					var v := -dx * sn + dz * cs
					inside = absf(u) <= hx and absf(v) <= hz
				if inside:
					var o := (zz * px + xx) * 4
					data[o + 3] = 255
					data[o + 1] = int(gk * 255.0)
	img.set_data(px, px, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(img), "ppm": ppm, "px": px}
