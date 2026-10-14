class_name BiomeMap
extends RefCounted
## Карта биомов. Сейчас один особый биом — «выжженная земля» (burn 0..1): пепел вместо травы, обугленные деревья,
## постоянная дымка и копоть. Низкочастотный шум, порог подбирается так, чтобы выжженное занимало burn_pct % карты;
## вокруг точки появления игрока всегда чисто. Данные: R8-текстура для шейдеров и массив для быстрых запросов с CPU.

const CELL := 8.0       # метров на пиксель
const MAX_PX := 512

var px := 0
var size := 0
var burn := PackedFloat32Array()
var tex: ImageTexture
var coverage := 0.0


func build(world_size: int, seed_value: int, spawn: Vector3, burn_pct: float) -> void:
	size = world_size
	px = mini(int(ceil(world_size / CELL)), MAX_PX)
	var cell := float(world_size) / px
	var n := FastNoiseLite.new()
	n.seed = seed_value + 99
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0011
	n.fractal_octaves = 3
	n.domain_warp_enabled = true
	n.domain_warp_amplitude = 140.0
	n.domain_warp_frequency = 0.003
	var vals := PackedFloat32Array()
	vals.resize(px * px)
	for j in px:
		for i in px:
			var v := n.get_noise_2d((i + 0.5) * cell, (j + 0.5) * cell)
			# вне карты (края) не выжигаем
			vals[i + j * px] = v
	# порог по квантилю: нужная доля клеток выше порога
	var sorted := vals.duplicate()
	sorted.sort()
	var q := clampf(1.0 - burn_pct / 100.0, 0.0, 1.0)
	var thr: float = sorted[mini(int(q * (sorted.size() - 1)), sorted.size() - 1)] if burn_pct > 0.0 else 9.0
	burn.resize(px * px)
	var img := Image.create(px, px, false, Image.FORMAT_R8)
	var covered := 0
	for j in px:
		for i in px:
			var b := smoothstep(thr, thr + 0.1, vals[i + j * px])
			var wx := (i + 0.5) * cell
			var wz := (j + 0.5) * cell
			b *= smoothstep(260.0, 520.0, Vector2(wx, wz).distance_to(Vector2(spawn.x, spawn.z)))
			burn[i + j * px] = b
			img.set_pixel(i, j, Color(b, 0, 0, 1))
			if b > 0.5:
				covered += 1
	coverage = float(covered) / float(px * px)
	tex = ImageTexture.create_from_image(img)


## Степень выжженности в точке мира, 0..1 (билинейно).
func burn_at(x: float, z: float) -> float:
	if px == 0:
		return 0.0
	var cell := float(size) / px
	var gx := clampf(x / cell - 0.5, 0.0, px - 1.001)
	var gz := clampf(z / cell - 0.5, 0.0, px - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := ix + iz * px
	return lerpf(lerpf(burn[i], burn[i + 1], fx), lerpf(burn[i + px], burn[i + px + 1], fx), fz)
