extends SceneTree
## Синтез звуков игры в assets/sounds/*.wav (моно, 22050 Гц): шаги по разным покрытиям, удары, взмах, еда, обыск,
## ветер и сверчки (бесшовные петли), птицы, голос зомби, хрип игрока. Шум + фильтры + огибающие, голос — формантный синтез.
## Свои записи можно подложить вместо любого файла с тем же именем.
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/gen_sounds.gd

const SR := 22050
const OUT := "res://assets/sounds/"
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7771
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for v in 4:
		_save("step_grass_%d" % v, _step(0.16, 900.0, 2600.0, 0.55, 0.0, 3))
		_save("step_gravel_%d" % v, _gravel_step())
		_save("step_hard_%d" % v, _step(0.12, 2200.0, 6000.0, 0.7, 0.35, 1))
		_save("step_wood_%d" % v, _wood_step())
	for v in 3:
		_save("hit_wood_%d" % v, _impact(0.45, 140.0 + v * 15.0, 0.6, 1800.0, 0.25))
		_save("hit_stone_%d" % v, _impact(0.3, 420.0 + v * 40.0, 0.25, 5000.0, 0.6))
		_save("hit_dirt_%d" % v, _impact(0.3, 80.0, 0.5, 900.0, 0.5))
		_save("hit_flesh_%d" % v, _flesh())
		_save("swing_%d" % v, _swing())
		_save("eat_%d" % v, _eat())
		_save("rustle_%d" % v, _rustle(0.9))
		_save("zombie_groan_%d" % v, _voice(1.6 + v * 0.3, 85.0 + v * 12.0, [[600, 1000, 2500], [450, 900, 2400], [700, 1150, 2600]][v], 0.45, true))
		_save("zombie_attack_%d" % v, _voice(0.7, 150.0 + v * 15.0, [800, 1250, 2700], 0.7, true))
		_save("player_hurt_%d" % v, _voice(0.35, 130.0 + v * 10.0, [650, 1100, 2500], 0.3, false))
	_save("zombie_death_0", _voice(1.4, 70.0, [550, 950, 2400], 0.6, true, -0.45))
	_save("drink_0", _drink())
	_save("bird_0", _bird(0))
	_save("bird_1", _bird(1))
	_save("wind_loop", _wind(8.0), true)
	_save("crickets_loop", _crickets(6.0), true)
	for v in 3:
		_save("gun_shot_%d" % v, _gunshot())
	_save("gun_dry_0", _clicks(0.12, [0.0], 2600.0))
	_save("gun_reload_0", _clicks(1.25, [0.12, 0.16, 0.62, 0.66, 0.98, 1.06], 1900.0))
	print("sounds done")
	quit()


# --- примитивы ----------------------------------------------------------------------

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b


## Полосовой фильтр (biquad, RBJ) — на месте.
func _bandpass(x: PackedFloat32Array, f: float, q: float) -> PackedFloat32Array:
	var w := TAU * f / SR
	var al := sin(w) / (2.0 * q)
	var b0 := al
	var a0 := 1.0 + al
	var a1 := -2.0 * cos(w)
	var a2 := 1.0 - al
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	for i in x.size():
		var v := (b0 * x[i] - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1; x1 = x[i]; y2 = y1; y1 = v
		y[i] = v
	return y


func _lowpass(x: PackedFloat32Array, f: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * f / SR)
	var y := 0.0
	for i in x.size():
		y += (x[i] - y) * a
		x[i] = y
	return x


func _highpass(x: PackedFloat32Array, f: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * f / SR)
	var lp := 0.0
	for i in x.size():
		lp += (x[i] - lp) * a
		x[i] = x[i] - lp
	return x


func _noise(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	return b


func _normalize(x: PackedFloat32Array, peak: float = 0.85) -> PackedFloat32Array:
	var m := 0.0001
	for v in x:
		m = maxf(m, absf(v))
	for i in x.size():
		x[i] *= peak / m
	return x


## Огибающая: атака a, спад по экспоненте (tau).
func _env(i: int, a: float, tau: float) -> float:
	var t := float(i) / SR
	return minf(t / maxf(a, 1e-4), 1.0) * exp(-maxf(t - a, 0.0) / tau)


# --- звуки --------------------------------------------------------------------------

## Шаг: короткий шумовой удар пятки + шорох (bursts — сколько «хрустов» по траве).
func _step(len: float, f_lo: float, f_hi: float, tau_k: float, click: float, bursts: int) -> PackedFloat32Array:
	var n := int(len * SR)
	var x := _bandpass(_noise(n), sqrt(f_lo * f_hi) * rng.randf_range(0.85, 1.15), 0.9)
	var out := _buf(len)
	for i in n:
		out[i] = x[i] * _env(i, 0.004, len * tau_k * 0.35)
	for k in bursts:
		var off := int(rng.randf_range(0.01, len * 0.6) * SR)
		var y := _bandpass(_noise(int(0.04 * SR)), f_hi * rng.randf_range(0.7, 1.2), 1.5)
		for j in y.size():
			if off + j < n:
				out[off + j] += y[j] * 0.5 * _env(j, 0.002, 0.012)
	if click > 0.0:
		for i in mini(n, int(0.01 * SR)):
			out[i] += sin(TAU * 180.0 * i / SR) * click * _env(i, 0.0005, 0.008)
	return _normalize(_highpass(out, 80.0), 0.7)


func _gravel_step() -> PackedFloat32Array:
	var len := 0.22
	var out := _buf(len)
	# много мелких камешков: случайные короткие щелчки
	for k in 40:
		var off := int(rng.randf_range(0.0, len * 0.7) * SR * pow(rng.randf(), 0.6))
		var f := rng.randf_range(1800.0, 5500.0)
		for j in int(0.006 * SR):
			if off + j < out.size():
				out[off + j] += sin(TAU * f * j / SR) * rng.randf_range(0.2, 1.0) * _env(j, 0.0003, 0.002)
	var body := _bandpass(_noise(out.size()), 700.0, 0.8)
	for i in out.size():
		out[i] += body[i] * 0.5 * _env(i, 0.005, 0.05)
	return _normalize(out, 0.7)


func _wood_step() -> PackedFloat32Array:
	var len := 0.2
	var out := _buf(len)
	var f := rng.randf_range(110.0, 150.0)
	var nz := _bandpass(_noise(out.size()), 900.0, 1.2)
	for i in out.size():
		out[i] = sin(TAU * f * i / SR) * _env(i, 0.002, 0.05) + nz[i] * 0.4 * _env(i, 0.001, 0.025)
	return _normalize(out, 0.7)


## Удар: тон корпуса (f0, tau) + щелчок/хруст (шум с частотой nf, доля mix).
func _impact(len: float, f0: float, tau: float, nf: float, mix: float) -> PackedFloat32Array:
	var out := _buf(len)
	var nz := _bandpass(_noise(out.size()), nf, 0.9)
	for i in out.size():
		var t := float(i) / SR
		var tone := sin(TAU * f0 * t * (1.0 - t * 0.6)) + 0.4 * sin(TAU * f0 * 2.7 * t)
		out[i] = tone * (1.0 - mix) * _env(i, 0.001, tau * 0.12) + nz[i] * mix * 2.0 * _env(i, 0.0005, tau * 0.06)
	return _normalize(out, 0.9)


## Выстрел: резкий хлопок (широкополосный шум), низкий удар и затухающее эхо.
func _gunshot() -> PackedFloat32Array:
	var len := 1.1
	var out := _buf(len)
	var crack := _highpass(_noise(out.size()), 1200.0)
	var tail := _lowpass(_noise(out.size()), 900.0)
	var f0 := rng.randf_range(55.0, 70.0)
	for i in out.size():
		var t := float(i) / SR
		out[i] = crack[i] * 1.6 * _env(i, 0.0003, 0.012) + sin(TAU * f0 * t * (1.0 - t * 0.8)) * 0.9 * _env(i, 0.001, 0.09) \
			+ tail[i] * 2.2 * _env(i, 0.004, 0.28)
	return _normalize(out, 0.95)


## Металлические щелчки (спуск без патрона, смена магазина, затвор) в заданные моменты.
func _clicks(len: float, times: Array, f: float) -> PackedFloat32Array:
	var out := _buf(len)
	for tm: float in times:
		var off := int(tm * SR)
		var ff := f * rng.randf_range(0.8, 1.25)
		var nz := _bandpass(_noise(int(0.03 * SR)), ff * 1.6, 2.0)
		for j in nz.size():
			if off + j < out.size():
				out[off + j] += (sin(TAU * ff * j / SR) * 0.6 + nz[j] * 1.5) * _env(j, 0.0002, 0.006)
	return _normalize(out, 0.7)


func _flesh() -> PackedFloat32Array:
	var len := 0.35
	var out := _buf(len)
	var nz := _lowpass(_noise(out.size()), 700.0)
	for i in out.size():
		var t := float(i) / SR
		out[i] = sin(TAU * 70.0 * t) * _env(i, 0.002, 0.05) + nz[i] * 3.0 * _env(i, 0.003, 0.07)
	return _normalize(out, 0.9)


func _swing() -> PackedFloat32Array:
	var len := 0.32
	var nz := _noise(int(len * SR))
	var out := _buf(len)
	# свист: полосовой шум, частота нарастает и спадает
	var y1 := 0.0; var y2 := 0.0; var x1 := 0.0; var x2 := 0.0
	for i in out.size():
		var t := float(i) / out.size()
		var f := 400.0 + 1400.0 * sin(t * PI)
		var w := TAU * f / SR
		var al := sin(w) / 3.0
		var v := (al * nz[i] - al * x2 + 2.0 * cos(w) * y1 - (1.0 - al) * y2) / (1.0 + al)
		x2 = x1; x1 = nz[i]; y2 = y1; y1 = v
		out[i] = v * sin(t * PI)
	return _normalize(out, 0.6)


func _eat() -> PackedFloat32Array:
	var len := 0.7
	var out := _buf(len)
	for k in 3:
		var off := int((0.05 + k * 0.2 + rng.randf_range(0, 0.04)) * SR)
		var y := _bandpass(_noise(int(0.12 * SR)), rng.randf_range(1500, 3200), 0.7)
		for j in y.size():
			if off + j < out.size():
				out[off + j] += y[j] * _env(j, 0.003, 0.03)
	return _normalize(out, 0.6)


func _drink() -> PackedFloat32Array:
	var len := 1.0
	var out := _buf(len)
	for k in 4:
		var off := int((0.05 + k * 0.22) * SR)
		for j in int(0.15 * SR):
			if off + j < out.size():
				var t := float(j) / SR
				out[off + j] += sin(TAU * (220.0 + 400.0 * t) * t) * _env(j, 0.01, 0.04)
	return _normalize(_lowpass(out, 1500.0), 0.6)


func _rustle(len: float) -> PackedFloat32Array:
	var out := _buf(len)
	var nz := _highpass(_noise(out.size()), 1500.0)
	for i in out.size():
		var t := float(i) / SR
		var am := 0.5 + 0.5 * sin(t * 37.0 + sin(t * 11.0) * 3.0)
		out[i] = nz[i] * am * am * sin(t / len * PI)
	return _normalize(out, 0.5)


## Голос: пила с плавающей высотой через 3 форманты (гласная), хрип — подмешанный шум. bend — изменение высоты к концу.
func _voice(len: float, f0: float, formants: Array, breath: float, rasp: bool, bend: float = -0.2) -> PackedFloat32Array:
	var n := int(len * SR)
	var src := PackedFloat32Array()
	src.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var jitter := (rng.randf() - 0.5) * (0.08 if rasp else 0.02)
		var f := f0 * (1.0 + bend * t + 0.06 * sin(t * 23.0) + jitter)
		ph = fmod(ph + f / SR, 1.0)
		var saw := ph * 2.0 - 1.0
		src[i] = saw + rng.randf_range(-1.0, 1.0) * breath
	var out := PackedFloat32Array()
	out.resize(n)
	for k in 3:
		var y := _bandpass(src, float(formants[k]), 6.0 - k)
		for i in n:
			out[i] += y[i] * (1.0 / (k + 1))
	for i in n:
		var t := float(i) / n
		out[i] *= minf(t * 12.0, 1.0) * minf((1.0 - t) * 4.0, 1.0)
	return _normalize(out, 0.8)


func _bird(kind: int) -> PackedFloat32Array:
	var len := 0.9
	var out := _buf(len)
	var notes := 4 if kind == 0 else 6
	for k in notes:
		var off := int((0.05 + k * 0.13) * SR)
		var f0 := rng.randf_range(2600.0, 4200.0)
		for j in int(0.08 * SR):
			if off + j < out.size():
				var t := float(j) / SR
				out[off + j] += sin(TAU * (f0 + 1500.0 * sin(t * 60.0)) * t) * sin(t / 0.08 * PI)
	return _normalize(out, 0.4)


## Петля ветра: низкочастотный шум с медленными порывами; конец сшит с началом (кроссфейд) — бесшовно.
func _wind(len: float) -> PackedFloat32Array:
	var n := int(len * SR)
	var x := _lowpass(_lowpass(_noise(n + SR), 380.0), 600.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var gust := 0.55 + 0.45 * sin(TAU * t / len * 2.0 + sin(TAU * t / len) * 1.5)
		out[i] = x[i] * gust
	var fade := SR
	for i in fade:
		var a := float(i) / fade
		out[i] = out[i] * a + x[n + i] * (0.55 + 0.45 * sin(TAU * float(n + i) / SR / len * 2.0)) * (1.0 - a)
	return _normalize(out, 0.5)


func _crickets(len: float) -> PackedFloat32Array:
	var n := int(len * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in 3:
		var f := rng.randf_range(4200.0, 5200.0)
		var rate := rng.randf_range(2.5, 4.0)
		var ph := rng.randf()
		for i in n:
			var t := float(i) / SR
			# период подгоняем под длину петли — бесшовно
			var cyc := fmod(t * round(rate * len) / len + ph, 1.0)
			var on := 1.0 if cyc < 0.35 else 0.0
			var trill := 0.5 + 0.5 * sin(TAU * 45.0 * t)
			out[i] += sin(TAU * f * t) * on * trill * 0.3
	return _normalize(_lowpass(out, 6000.0), 0.35)


func _save(name: String, data: PackedFloat32Array, loop := false) -> void:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	w.save_to_wav(ProjectSettings.globalize_path(OUT + name + ".wav"))
