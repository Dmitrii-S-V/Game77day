class_name Atmosphere
extends RefCounted
## Атмосфера по профилям времени суток: «День», «Сумерки» (рассвет/закат), «Ночь», «Кровавая луна». Каждый профиль —
## набор параметров неба, солнца/луны, света и теней, тумана и цвета; main.gd смешивает их по высоте солнца
## (кровавая луна — поверх, плавно). Значения правятся отладочной панелью (F6, AtmospherePanel) и хранятся
## в data/atmosphere.json (в собранной игре — user://atmosphere.json).

const RES_PATH := "res://data/atmosphere.json"
const USER_PATH := "user://atmosphere.json"
const PROFILES := ["day", "dusk", "night", "blood"]
const PROFILE_NAMES := {"day": "День", "dusk": "Сумерки (рассвет/закат)", "night": "Ночь", "blood": "Кровавая луна"}

## Параметры: [ключ, подпись, группа, тип ("c" цвет | "f" число), мин, макс]
const PARAMS := [
	["sky_top", "Небо: зенит", "Небо", "c", 0, 0],
	["sky_horizon", "Небо: горизонт", "Небо", "c", 0, 0],
	["sky_curve", "Градиент (меньше — резче к зениту)", "Небо", "f", 0.1, 2.0],
	["sky_ground_dark", "Под горизонтом темнее", "Небо", "f", 0.0, 1.0],
	["stars", "Звёзды", "Небо", "f", 0.0, 3.0],
	["sun_color", "Солнце: цвет света", "Солнце и луна", "c", 0, 0],
	["sun_energy", "Солнце: яркость", "Солнце и луна", "f", 0.0, 3.0],
	["sun_size", "Солнце: размер диска", "Солнце и луна", "f", 0.2, 4.0],
	["sun_glow", "Солнце: ореол", "Солнце и луна", "f", 0.0, 4.0],
	["moon_color", "Луна: цвет (свет и диск)", "Солнце и луна", "c", 0, 0],
	["moon_energy", "Луна: яркость света", "Солнце и луна", "f", 0.0, 3.0],
	["moon_size", "Луна: размер диска", "Солнце и луна", "f", 0.2, 4.0],
	["moon_glow", "Луна: ореол", "Солнце и луна", "f", 0.0, 4.0],
	["ambient_color", "Окружающий свет: цвет", "Свет и тени", "c", 0, 0],
	["ambient_energy", "Окружающий свет: яркость", "Свет и тени", "f", 0.0, 3.0],
	["shadow_opacity", "Плотность теней", "Свет и тени", "f", 0.0, 1.0],
	["shadow_blur", "Размытие теней", "Свет и тени", "f", 0.0, 5.0],
	["ssao", "Затенение в щелях (SSAO)", "Свет и тени", "f", 0.0, 8.0],
	["fog_color", "Туман: цвет", "Туман", "c", 0, 0],
	["fog_begin", "Туман: начало, м", "Туман", "f", 0.0, 400.0],
	["fog_end", "Туман: полный, м", "Туман", "f", 30.0, 4000.0],
	["fog_curve", "Туман: кривая (меньше — гуще сразу)", "Туман", "f", 0.1, 3.0],
	["fog_density", "Туман: плотность", "Туман", "f", 0.0, 1.0],
	["fog_sky_affect", "Туман: влияние на небо", "Туман", "f", 0.0, 1.0],
	["fog_aerial", "Воздушная перспектива", "Туман", "f", 0.0, 1.0],
	["fog_height", "Низинный туман: высота, м", "Туман", "f", -20.0, 80.0],
	["fog_height_density", "Низинный туман: плотность", "Туман", "f", 0.0, 0.1],
	["exposure", "Экспозиция", "Цвет", "f", 0.2, 3.0],
	["brightness", "Яркость", "Цвет", "f", 0.3, 2.0],
	["contrast", "Контраст", "Цвет", "f", 0.5, 2.0],
	["saturation", "Насыщенность", "Цвет", "f", 0.0, 2.0],
	["tint", "Цветовая гамма (оттенок экрана)", "Цвет", "c", 0, 0],
	["glow", "Свечение ярких мест", "Цвет", "f", 0.0, 2.0],
	["vignette", "Виньетка", "Цвет", "f", 0.0, 1.0],
	["grain", "Плёночное зерно", "Цвет", "f", 0.0, 0.2],
]

const _BASE := {
	"sky_curve": 0.42, "sky_ground_dark": 0.45, "stars": 0.0,
	"sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 1.1, "sun_size": 1.0, "sun_glow": 1.0,
	"moon_color": Color(0.82, 0.86, 0.95), "moon_energy": 0.0, "moon_size": 1.0, "moon_glow": 1.0,
	"ambient_color": Color(0.56, 0.62, 0.7), "ambient_energy": 0.62, "shadow_opacity": 1.0, "shadow_blur": 1.4, "ssao": 3.2,
	"fog_color": Color(0.746, 0.765, 0.777), "fog_begin": 10.0, "fog_end": 480.0, "fog_curve": 0.7, "fog_density": 0.95,
	"fog_sky_affect": 0.25, "fog_aerial": 0.55, "fog_height": 8.0, "fog_height_density": 0.004,
	"exposure": 1.05, "brightness": 1.0, "contrast": 1.06, "saturation": 0.95, "tint": Color(1, 1, 1), "glow": 0.35,
	"vignette": 0.3, "grain": 0.03,
	"sky_top": Color(0.24, 0.42, 0.70), "sky_horizon": Color(0.76, 0.80, 0.84),
}

## Стандартные профили (поверх _BASE) — как атмосфера была до панели.
const _DEFAULTS := {
	"day": {},
	"dusk": {"sky_top": Color(0.13, 0.22, 0.38), "sky_horizon": Color(0.62, 0.46, 0.38), "sun_color": Color(1.0, 0.58, 0.32),
		"ambient_color": Color(0.55, 0.55, 0.62), "ambient_energy": 0.35, "fog_color": Color(0.55, 0.46, 0.42),
		"fog_begin": 8.0, "fog_end": 420.0, "stars": 0.3, "moon_energy": 0.15},
	"night": {"sky_top": Color(0.03, 0.045, 0.085), "sky_horizon": Color(0.105, 0.125, 0.17), "sun_energy": 0.0,
		"moon_color": Color(0.55, 0.65, 0.95), "moon_energy": 0.7, "ambient_color": Color(0.5, 0.56, 0.68), "ambient_energy": 0.42,
		"fog_color": Color(0.105, 0.125, 0.17), "fog_begin": 4.0, "fog_end": 264.0, "fog_density": 0.98, "stars": 1.0},
	"blood": {"sky_top": Color(0.10, 0.01, 0.01), "sky_horizon": Color(0.42, 0.07, 0.04), "sun_energy": 0.0,
		"moon_color": Color(1.0, 0.32, 0.22), "moon_energy": 0.8, "moon_size": 1.6, "moon_glow": 2.0,
		"ambient_color": Color(0.5, 0.3, 0.27), "ambient_energy": 0.36, "fog_color": Color(0.24, 0.05, 0.035),
		"fog_begin": 4.0, "fog_end": 220.0, "fog_density": 0.98, "stars": 0.35, "tint": Color(1.03, 0.93, 0.9),
		"contrast": 1.12, "saturation": 1.05},
}

static var profiles := {}       # профиль -> {параметр: значение}
static var _loaded := false


static func defaults(profile: String) -> Dictionary:
	var d := _BASE.duplicate()
	d.merge(_DEFAULTS.get(profile, {}), true)
	return d


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for p: String in PROFILES:
		profiles[p] = defaults(p)
	var path := USER_PATH if (OS.has_feature("template") and FileAccess.file_exists(USER_PATH)) else RES_PATH
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	for p: String in PROFILES:
		var src: Dictionary = (d as Dictionary).get(p, {})
		for k: String in src:
			if not (profiles[p] as Dictionary).has(k):
				continue
			var v: Variant = src[k]
			profiles[p][k] = Color(v[0], v[1], v[2]) if v is Array else float(v)


## Сохранить: в проект (data/atmosphere.json), в собранной игре — user://. Возвращает путь или "".
static func save() -> String:
	ensure()
	var out := {}
	for p: String in PROFILES:
		var o := {}
		for k: String in profiles[p]:
			var v: Variant = profiles[p][k]
			o[k] = [snappedf(v.r, 0.001), snappedf(v.g, 0.001), snappedf(v.b, 0.001)] if v is Color else snappedf(float(v), 0.0001)
		out[p] = o
	var path := USER_PATH if OS.has_feature("template") else RES_PATH
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	return path


static func reset(profile: String) -> void:
	ensure()
	profiles[profile] = defaults(profile)


## Смесь профилей с весами {профиль: вес} (сумма весов — любая > 0).
static func blend(weights: Dictionary) -> Dictionary:
	ensure()
	var total := 0.0
	for p: String in weights:
		total += float(weights[p])
	var out := {}
	for prm: Array in PARAMS:
		var k: String = prm[0]
		var acc: Variant = Color(0, 0, 0) if prm[3] == "c" else 0.0
		for p: String in weights:
			var w := float(weights[p]) / maxf(total, 1e-6)
			if w <= 0.0:
				continue
			var v: Variant = profiles[p][k]
			acc = (acc as Color) + (v as Color) * w if prm[3] == "c" else float(acc) + float(v) * w
		out[k] = acc
	return out


## Веса «день / сумерки / ночь» по высоте солнца (sun_y — синус высоты).
static func time_weights(sun_y: float) -> Dictionary:
	var day := smoothstep(0.04, 0.3, sun_y)
	var night := smoothstep(0.0, -0.16, sun_y)
	return {"day": day, "dusk": maxf(0.0, 1.0 - day - night), "night": night}
