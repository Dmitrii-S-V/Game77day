shader_type spatial;
// Ландшафт + дороги как часть грунта.
// Природные материалы (трава / земля / камень / песок) — по весам вершин (COLOR).
// Дороги, тротуары и площадки рисуются попиксельно по карте дорог (road_a/b/c, см. RoadAtlas):
// края чёткие. Поверх — декали дефектов (трещины, ямы, вскрытый асфальт, пятна, люки).
// Вершинные веса дорожных материалов (CUSTOM0) служат маской: где грунт выкопан, дорога пропадает
// вместе с ним, край разлома рваный.
// COLOR = трава/земля/камень/песок, CUSTOM0 = асфальт/бетон/щебень дороги/песок дороги, UV.x = подушка из щебня.

uniform sampler2D tex_grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass2 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass3 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dirt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_stone : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_asph : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_asph2 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_walk : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_brick : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_conc : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dirtroad : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_moss : source_color, repeat_enable, filter_linear_mipmap_anisotropic;    // мох — пятнами среди травы
uniform sampler2D tex_tramp : source_color, repeat_enable, filter_linear_mipmap_anisotropic;   // вытоптанная трава у дорог
uniform sampler2D n_moss : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float grass_scale = 2.0;   // травяные текстуры (вид 1x1 м) мельче остальных: повтор раз в 1/(tile*grass_scale) м
uniform float moss_amount = 0.35;  // доля пятен мха
// карты нормалей (RGB) + высоты (A), строятся tools/prepare_textures.gd из яркости текстур
uniform sampler2D n_grass : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_grass2 : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_grass3 : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_dirt : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_stone : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_sand : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_gravel : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_asph : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_walk : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_conc : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_dirtroad : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_decals : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D road_a : filter_linear, repeat_enable;
uniform sampler2D road_b : filter_nearest, repeat_enable;
uniform sampler2D road_c : filter_nearest, repeat_enable;
uniform sampler2D road_k1 : filter_linear, repeat_enable;   // веса основы покрытия (RoadAtlas)
uniform sampler2D road_k2 : filter_linear, repeat_enable;   // площадка, тротуар, износ, «есть дорога»
uniform float tile = 0.2;
uniform vec3 grass_tint = vec3(1.0);
uniform vec3 grass_color = vec3(0.05, 0.085, 0.022);   // общий цвет травы (линейный): земля и кусты травы в один тон
uniform float grass_recolor = 0.0;                     // 0 — цвета текстур, 1 — полностью в grass_color (светотень остаётся)   // оттенок земли под травой (темнее и зеленее: просветы между кустами не светятся)
uniform sampler2D biome_mask : filter_linear, repeat_disable;   // BiomeMap: R — степень выжженности
uniform float biome_world = 2048.0;
uniform bool has_biome = false;
uniform float road_tile = 0.2;
uniform float atlas_n = 640.0;
uniform float atlas_step = 0.4;
uniform int debug_mode = 0;
uniform int perf_skip = 0;
uniform bool use_decals = false;
uniform vec3 pom_sun = vec3(0.0, 1.0, 0.0);   // направление на солнце (main.gd) — для самозатенения рельефа
uniform bool use_pom = false;     // объёмный рельеф покрытий вблизи (галочка в настройках графики)
uniform float detail_far = 85.0;   // до какой дистанции рельеф карт нормалей (настройки графики)
uniform float asph_m = 2.2;    // размер плитки фото-асфальта, м (камешки 1-2 см)
uniform float asph_bump = 1.4;  // сила рельефа асфальта   // наложенные декали дефектов дорог (отключены: разнообразие — в самих материалах)
uniform sampler2D tex_noise : filter_linear_mipmap, repeat_enable;   // R — fbm, G — value-шум (бесшовные, 256 px = 64 ед.)   // отладка стоимости: 1 — без декалей дорог, 2 — без окна типов, 4 — без дорог, 8 — без грунта

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wa;
varying vec4 wb;
varying float wl;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wa = COLOR;
	wb = CUSTOM0;
	wl = UV.x;
}

// Тип покрытия на стыках: веса основы (асфальт, бетон, щебень, грунт) и признаки (площадка, тротуар, износ)
// лежат в road_k1/road_k2 с мипмапами — размытый уровень даёт видеокарта одной выборкой (раньше — окно 9x9,
// до 162 выборок на пиксель: в зонах стыков это съедало до 17 мс кадра). Берутся два самых весомых типа,
// возвращается доля второго (0..0.5) — материалы на стыке плавно перетекают друг в друга.
float road_kinds(vec2 w, out int k1, out int k2, out float wear_s, out float curb_s) {
	vec2 uv = (w / atlas_step + 0.5) / atlas_n;
	// размытие сеткой 3x3 билинейных выборок (шаг 1.6 текселя, веса 1-2-1): ровное, без диагональных «зубцов»
	float o = 1.6 / atlas_n;
	vec4 m = vec4(0.0);
	vec4 e = vec4(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			float wgt = (i == 0 ? 2.0 : 1.0) * (j == 0 ? 2.0 : 1.0);
			vec2 su = uv + vec2(float(i), float(j)) * o;
			m += textureLod(road_k1, su, 0.0) * wgt;
			e += textureLod(road_k2, su, 0.0) * wgt;
		}
	}
	m /= 16.0;
	e /= 16.0;
	float valid = max(e.a, 0.01);
	wear_s = e.b / valid;
	curb_s = e.g / valid;
	bool pad = e.r / valid > 0.5;
	float s[4] = float[4](m.r, m.g, m.b, m.a);
	int i1 = 0;
	for (int i = 1; i < 4; i++) {
		if (s[i] > s[i1]) i1 = i;
	}
	int i2 = i1 == 0 ? 1 : 0;
	for (int i = 0; i < 4; i++) {
		if (i != i1 && s[i] > s[i2]) i2 = i;
	}
	// основа -> тип (площадки: бетон 5, щебень 6, асфальт 7)
	k1 = pad ? (i1 == 0 ? 7 : (i1 == 1 ? 5 : (i1 == 2 ? 6 : 3))) : i1;
	k2 = pad ? (i2 == 0 ? 7 : (i2 == 1 ? 5 : (i2 == 2 ? 6 : 3))) : i2;
	if ((perf_skip & 2) != 0 || s[i2] < 0.004) {
		k2 = k1;
		return 0.0;
	}
	return s[i2] / max(s[i1] + s[i2], 0.0001);
}

vec3 tri(sampler2D t, vec3 p, vec3 b, vec3 dx, vec3 dy) {
	vec3 c = vec3(0.0);
	if (b.x > 0.02) c += textureGrad(t, p.zy, dx.zy, dy.zy).rgb * b.x;
	if (b.y > 0.02) c += textureGrad(t, p.xz, dx.xz, dy.xz).rgb * b.y;
	if (b.z > 0.02) c += textureGrad(t, p.xy, dx.xy, dy.xy).rgb * b.z;
	return c;
}

// Смещение мировой нормали от карты нормалей (трипланар).
vec3 tri_n(sampler2D t, vec3 p, vec3 b, vec3 dx, vec3 dy) {
	vec3 o = vec3(0.0);
	if (b.x > 0.02) { vec2 v = textureGrad(t, p.zy, dx.zy, dy.zy).xy * 2.0 - 1.0; o += vec3(0.0, v.y, v.x) * b.x; }
	if (b.y > 0.02) { vec2 v = textureGrad(t, p.xz, dx.xz, dy.xz).xy * 2.0 - 1.0; o += vec3(v.x, 0.0, v.y) * b.y; }
	if (b.z > 0.02) { vec2 v = textureGrad(t, p.xy, dx.xy, dy.xy).xy * 2.0 - 1.0; o += vec3(v.x, v.y, 0.0) * b.z; }
	return o;
}

// То же для плоской проекции сверху (дорожные текстуры).
vec3 nm2(sampler2D t, vec2 uv, vec2 gx, vec2 gy) {
	vec2 v = textureGrad(t, uv, gx, gy).xy * 2.0 - 1.0;
	return vec3(v.x, 0.0, v.y);
}

// мягкая кривая весов: переходы между материалами всегда плавные
float sharp(float w) {
	return smoothstep(0.02, 0.98, w);
}

// два масштаба выборки: убирает заметную повторяемость плитки
vec3 tri2(sampler2D t, vec3 p, vec3 b, vec3 dx, vec3 dy) {
	return mix(tri(t, p, b, dx, dy), tri(t, p * 0.29 + vec3(0.13, 0.41, 0.27), b, dx * 0.29, dy * 0.29), 0.35);
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);   // без sin: на больших координатах sin() у GPU теряет точность и рвёт шум по ячейкам
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 hash4(vec2 p) {
	return vec4(hash(p), hash(p + vec2(17.3, 5.1)), hash(p + vec2(3.7, 29.9)), hash(p + vec2(41.2, 13.3)));
}

// Шумы дорог берутся из заранее сгенерированной бесшовной текстуры (main.gd: _make_noise_tex): одна выборка
// вместо десятков хешей на пиксель. Период — 64 единицы аргумента (ячейка шума = 1 единица, как у gnoise).
float vnoise(vec2 p) {
	return texture(tex_noise, p * (1.0 / 64.0) + vec2(0.37, 0.61)).g;
}

vec2 ghash(vec2 p) {
	float a = hash(p) * 6.2831853;
	return vec2(cos(a), sin(a));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(ghash(i), f);
	float b = dot(ghash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(ghash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(ghash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5, 0.0, 1.0);
}

// Пятна мха: отдельный шум; на пологих склонах (у оврагов, холмов) мха больше.
float moss_mask(vec2 w, float up) {
	float n = gnoise(w * 0.045 + 51.0);
	return smoothstep(1.0 - moss_amount, 1.0 - moss_amount + 0.12, n + (1.0 - smoothstep(0.86, 0.97, up)) * 0.15);
}

float fbm(vec2 p) {
	// прежний аналитический fbm давал значения примерно в 0.2..0.8 — сжимаем полный диапазон текстуры так же
	return 0.5 + (texture(tex_noise, p * (1.0 / 64.0)).r - 0.5) * 0.75;
}

// Декаль из атласа 4x4: p — точка, center — центр, rot — поворот, size — размер в метрах.
vec4 decal(vec2 p, vec2 center, float rot, float size, int id, vec2 gx, vec2 gy) {
	vec2 d = p - center;
	float c = cos(rot);
	float s = sin(rot);
	vec2 q = vec2(c * d.x + s * d.y, -s * d.x + c * d.y) / size + 0.5;
	if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) return vec4(0.0);
	vec2 cell = vec2(float(id % 4), float(id / 4));
	vec2 uv = (cell + clamp(q, 0.004, 0.996)) * 0.25;
	return textureGrad(tex_decals, uv, gx / size * 0.25, gy / size * 0.25);
}

void apply_decal(inout vec3 col, inout float rough, vec4 dc, float strength) {
	float a = dc.a * strength;
	col = mix(col, dc.rgb, a);
	rough = mix(rough, 0.92, a);
}

// Набор декалей дефектов по дорожным координатам (вдоль, поперёк).
void road_decals(inout vec3 col, inout float rough, vec2 p, float hw, float wear, float seed, int kind, vec2 gx, vec2 gy) {
	float S = 5.0;
	float cell = floor(p.x / S);
	bool walk = kind == 4;
	for (int k = -1; k <= 1; k++) {
		float cid = cell + float(k);
		// пятна: масло, следы шин
		vec4 h = hash4(vec2(cid, seed + 3.0));
		if (!walk && h.x < 0.22 + wear * 0.25) {
			int id = 10 + int(h.y * 2.99);
			vec2 c = vec2((cid + h.z) * S, (h.w * 2.0 - 1.0) * hw * 0.7);
			float rot = (id == 12) ? (floor(h.y * 4.0) * 1.5708 + (h.z - 0.5) * 0.3) : h.w * 6.2831;
			apply_decal(col, rough, decal(p, c, rot, mix(2.4, 4.4, h.z), id, gx, gy), 0.8);
		}
		// трещины
		h = hash4(vec2(cid, seed + 11.0));
		if (h.x < 0.15 + wear * 0.8) {
			int id = h.y < 0.5 ? 0 : 1;
			vec2 c = vec2((cid + h.z) * S, (h.w * 2.0 - 1.0) * hw * 0.8);
			apply_decal(col, rough, decal(p, c, h.x * 40.0, mix(3.2, 6.0, h.w), id, gx, gy), 0.95);
		}
		// вскрытый асфальт
		h = hash4(vec2(cid, seed + 23.0));
		if (!walk && h.x < pow(wear, 1.5) * 0.5) {
			int id = 6 + int(h.y * 3.99);
			vec2 c = vec2((cid + h.z) * S, (h.w * 2.0 - 1.0) * hw * 0.7);
			apply_decal(col, rough, decal(p, c, h.z * 6.2831, mix(2.6, 4.6, h.w), id, gx, gy), 1.0);
		}
		// ямы
		h = hash4(vec2(cid, seed + 37.0));
		if (!walk && h.x < pow(wear, 1.2) * 0.8) {
			int id = 3 + int(h.y * 2.99);
			vec2 c = vec2((cid + h.z) * S, (h.w * 2.0 - 1.0) * hw * 0.75);
			float sz = mix(1.5, 3.0, h.w);
			vec4 d = decal(p, c, h.z * 6.2831, sz, id, gx, gy);
			apply_decal(col, rough, d, 1.0);
			// влажная яма: тёмная блестящая середина
			float wetness = step(0.55, hash(vec2(cid, seed + 5.0)));
			float inner = d.a * (1.0 - smoothstep(0.0, 0.5, length(p - c) / sz * 2.0));
			col = mix(col, col * vec3(0.55, 0.62, 0.7), inner * 0.5 * wetness);
			rough = mix(rough, 0.18, inner * wetness * 0.8);
		}
		// люки и решётки
		h = hash4(vec2(cid, seed + 53.0));
		if (kind <= 1 && h.x < 0.09) {
			bool manhole = h.y < 0.6;
			vec2 c = vec2((cid + h.z) * S, manhole ? (h.w * 2.0 - 1.0) * hw * 0.35 : (h.w < 0.5 ? -1.0 : 1.0) * (hw - 0.55));
			float rot = manhole ? h.w * 6.2831 : ((h.w < 0.5 ? 0.0 : 3.14159) + 1.5708);
			vec4 d = decal(p, c, rot, manhole ? 1.1 : 1.0, manhole ? 14 : 15, gx, gy);
			apply_decal(col, rough, d, 1.0);
		}
	}
}

// Материал покрытия дороги (тип kind 0..7 или тротуар): цвет, шероховатость, смещение нормали и «высота» для
// смешивания по высоте на стыках (светлые выступы текстуры выше, щели ниже; у тротуара и бетона база выше).
void road_material(int kind, bool sidewalk, vec2 wp, vec2 uvw, vec2 gxu, vec2 gyu, vec3 p, vec3 b, vec3 dx, vec3 dy,
		float lat, float along, float hw, float wear, float mark, float jf, float n1, float n2, float sp,
		out vec3 rc, out float rr, out vec3 noff, out float hgt) {
	bool pad = kind >= 5;
	int base = kind;
	if (pad) base = (kind == 5) ? 1 : ((kind == 6) ? 2 : 0);
	rc = vec3(0.3);
	rr = 0.88;
	noff = vec3(0.0);
	float hbase = 0.0;
	if (sidewalk) {
		vec4 tw = textureGrad(tex_walk, uvw * 1.4, gxu * 1.4, gyu * 1.4);
		rc = tw.rgb * 1.3;
		noff = nm2(n_walk, uvw * 1.4, gxu * 1.4, gyu * 1.4);
		vec2 g = abs(fract(vec2(lat, along) / 1.5 + 0.5) - 0.5) * 1.5;
		float joint = (1.0 - smoothstep(0.012, 0.045, min(g.x, g.y))) * jf;
		rc *= mix(1.0, 0.5, joint);
		rc = mix(rc, rc * 0.7, smoothstep(0.55, 0.85, n2) * wear * 0.5);
		rc = mix(rc, vec3(0.15, 0.23, 0.08), joint * wear * smoothstep(0.4, 0.75, n1) * 0.7);
		// шероховатость из альфы текстуры; швы с грязью — матовые, вытоптанные места чуть глаже
		rr = mix(clamp(tw.a, 0.55, 0.98), 0.97, joint) * mix(1.0, 0.92, smoothstep(0.55, 0.85, n2) * wear);
		hbase = 0.16 - joint * 0.2;
	} else if (base == 0) {
		// фото-асфальт в реальном масштабе (плитка asph_m метров): две выборки — прямая и повёрнутая на 37° с другим
		// масштабом — смешиваются по плавному шуму, поэтому крупные пятна фото не складываются в заметную «клетку»
		vec2 ua = wp / asph_m;
		vec2 gxa = gxu / road_tile / asph_m;
		vec2 gya = gyu / road_tile / asph_m;
		mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
		float sb = 0.77;
		vec2 ub = rot * ua * sb + vec2(0.37, 0.61);
		float mixab = smoothstep(0.32, 0.68, fbm(wp * 0.13 + 5.0));
		vec4 t1 = textureGrad(tex_asph, ua, gxa, gya);
		vec4 t2 = textureGrad(tex_asph, ub, rot * gxa * sb, rot * gya * sb);
		rc = mix(t1.rgb, t2.rgb, mixab);
		float ra = clamp(mix(t1.a, t2.a, mixab), 0.4, 0.98);   // попиксельная шероховатость фото: камешки гладкие, битум матовый
		vec2 na = textureGrad(n_asph, ua, gxa, gya).xy * 2.0 - 1.0;
		vec2 nb = transpose(rot) * (textureGrad(n_asph, ub, rot * gxa * sb, rot * gya * sb).xy * 2.0 - 1.0);   // нормаль повёрнутой выборки — обратно в мир
		vec2 nn = mix(na, nb, mixab);
		noff = vec3(nn.x, 0.0, nn.y) * asph_bump;
		vec3 rough_t = textureGrad(tex_asph2, uvw * 0.8, gxu * 0.8, gyu * 0.8).rgb;
		rc = mix(rc, rough_t, smoothstep(0.62, 0.85, n1) * wear * 0.25);
		rc *= 0.85 + 0.3 * sp;
		rc = mix(rc, rc * 1.25 + 0.015, wear * 0.45 * n1);
		// вариации самого покрытия вместо наложенных декалей: крупные выбеленные участки и свежие тёмные заплатки
		// с неровным краем (низкочастотный шум в мировых координатах — плавно и без повторов)
		float faded = smoothstep(0.5, 0.75, fbm(wp * 0.07 + 41.0));
		rc = mix(rc, rc * 1.18 + vec3(0.02, 0.018, 0.015), faded * (0.35 + wear * 0.4));
		float patch = smoothstep(0.62, 0.66, fbm(wp * 0.11 + vec2(13.0, 77.0)) + (vnoise(wp * 1.3) - 0.5) * 0.06) * smoothstep(0.15, 0.45, wear);
		vec4 fresh = textureGrad(tex_asph, ua * 1.3 + 0.21, gxa * 1.3, gya * 1.3);
		rc = mix(rc, fresh.rgb * 0.62, patch * 0.9);
		ra = mix(ra, clamp(fresh.a, 0.4, 0.98) * 0.85, patch);   // свежая заплатка ещё блестит битумом
		ra = mix(ra, min(ra + 0.12, 0.98), faded * 0.6);           // выбеленный, обветренный асфальт — матовее
		float track = exp(-pow((abs(lat) - hw * 0.5) / 0.55, 2.0)) * float(!pad) * jf;
		rc *= 1.0 - 0.2 * track * (0.6 + 0.4 * n2);
		rr = ra * mix(1.0, 0.78, track * (0.5 + wear * 0.5));   // накатанная колея отполирована шинами
		if (mark * jf > 0.01 && kind == 0) {
			float aa2 = fwidth(lat) * 1.2 + 0.001;
			float dash = step(fract(along / 9.0), 5.0 / 9.0);
			float cl = (1.0 - smoothstep(0.1 - aa2, 0.1 + aa2, abs(lat))) * dash;
			float el = 1.0 - smoothstep(0.07 - aa2, 0.07 + aa2, abs(abs(lat) - (hw - 0.45)));
			float chip = 1.0 - wear * 0.9 * smoothstep(0.3, 0.9, vnoise(wp * 3.0));
			rc = mix(rc, vec3(0.68, 0.54, 0.07), cl * mark * chip * 0.92);
			rc = mix(rc, vec3(0.72, 0.72, 0.68), el * mark * chip * 0.85);
		}
		hbase = 0.0;
	} else if (base == 1) {
		vec4 tc = textureGrad(tex_conc, uvw * 1.3, gxu * 1.3, gyu * 1.3);
		rc = tc.rgb * 1.05;
		noff = nm2(n_conc, uvw * 1.3, gxu * 1.3, gyu * 1.3);
		float j;
		if (pad) {
			vec2 g = abs(fract(vec2(lat, along) / 3.0 + 0.5) - 0.5) * 3.0;
			j = min(g.x, g.y);
		} else {
			j = abs(fract(along / 4.5 + 0.5) - 0.5) * 4.5;
		}
		float joint = (1.0 - smoothstep(0.015, 0.06, j)) * jf;
		// плиты чуть различаются тоном (заливали в разное время), плюс крупные пятна выцветания
		vec2 slab = floor(pad ? vec2(lat, along) / 3.0 : vec2(0.0, along / 4.5));
		rc *= 0.93 + 0.14 * hash(slab + vec2(3.7, 1.9));
		rc = mix(rc, rc * 1.12 + 0.015, smoothstep(0.5, 0.75, fbm(wp * 0.08 + 17.0)) * 0.5);
		rc *= mix(1.0, 0.45, joint);
		rc = mix(rc, vec3(0.16, 0.24, 0.08), joint * wear * smoothstep(0.45, 0.8, n1) * 0.6);
		rr = mix(clamp(tc.a, 0.55, 0.98), 0.97, joint);
		hbase = 0.08 - joint * 0.2;
	} else if (base == 2) {
		rc = mix(tri(tex_gravel, p * 1.4, b, dx * 1.4, dy * 1.4), textureGrad(tex_asph2, uvw * 0.9, gxu * 0.9, gyu * 0.9).rgb * 1.3, 0.35);
		noff = tri_n(n_gravel, p * 1.4, b, dx * 1.4, dy * 1.4);
		float rut = exp(-pow((abs(lat) - hw * 0.38) / 0.42, 2.0)) * float(!pad);
		rc *= 1.0 - 0.28 * rut;
		float mud = smoothstep(0.55, 0.8, fbm(wp * 0.5 + 9.0)) * rut * (0.3 + wear);
		rc = mix(rc, vec3(0.16, 0.12, 0.08), mud * 0.85);
		rr = mix(0.95, 0.35, mud);
		float tuft = smoothstep(0.52, 0.8, fbm(wp * 2.2)) * (1.0 - rut) * (0.25 + wear) * (1.0 - smoothstep(hw * 0.1, hw * 0.75, abs(lat))) * float(!pad);
		rc = mix(rc, vec3(0.21, 0.29, 0.10), tuft * 0.8);
		hbase = -0.04;
	} else {
		rc = tri(tex_dirtroad, p * 1.1, b, dx * 1.1, dy * 1.1);
		noff = tri_n(n_dirtroad, p * 1.1, b, dx * 1.1, dy * 1.1);
		float rut = exp(-pow((abs(lat) - hw * 0.4) / 0.4, 2.0));
		rc *= 1.0 - 0.22 * rut;
		float mud = smoothstep(0.58, 0.82, fbm(wp * 0.5 + 21.0)) * rut * (0.2 + wear);
		rc = mix(rc, vec3(0.2, 0.14, 0.09), mud * 0.8);
		rr = mix(0.97, 0.4, mud);
		float tuft = smoothstep(0.5, 0.78, fbm(wp * 2.0 + 5.0)) * (1.0 - rut) * (0.2 + wear) * (1.0 - smoothstep(hw * 0.1, hw * 0.75, abs(lat)));
		rc = mix(rc, vec3(0.28, 0.3, 0.12), tuft * 0.7);
		hbase = -0.08;
	}
	// высота: база материала + рельеф текстуры (яркость) + рваный шум края
	// крупный неровный шум (0.6 и 2.1 1/м) + немного рельефа текстуры: край рваный, но не пилой
	hgt = hbase + (dot(rc, vec3(0.333)) - 0.3) * 0.35 + (fbm(wp * 0.6 + float(kind) * 7.3) - 0.5) * 0.5 + (vnoise(wp * 2.1 + float(kind) * 3.1) - 0.5) * 0.2;
}

// Смешивание двух материалов по высоте: на стыке побеждает тот, что «выше» в этой точке — рваная естественная
// граница (выщербленный край плитки, щебень в трещинах) вместо прямой линии или мыльного полупрозрачного перехода.
vec2 hblend(float w_a, float h_a, float w_b, float h_b) {
	float d = 0.18;
	float A = w_a + h_a;
	float B = w_b + h_b;
	float m = max(A, B) - d;
	float a = max(A - m, 0.0);
	float c = max(B - m, 0.0);
	float s = a + c + 1e-5;
	return vec2(a / s, c / s);
}

// Parallax Occlusion Mapping по карте высот покрытия (альфа *_n): луч от камеры «входит» в поверхность,
// шагами ищем точку, где он ниже рельефа, и берём текстуры оттуда — камешки и плитка выглядят объёмными.
// mode: 0 асфальт, 1 бетон, 2 тротуар. depth_m — глубина рельефа в метрах. Возвращает сдвинутую мировую точку XZ.
float pom_depth(int mode, vec2 w, vec2 gx, vec2 gy) {
	if (mode == 0) return 1.0 - textureGrad(n_asph, w / asph_m, gx / asph_m, gy / asph_m).a;
	if (mode == 1) return 1.0 - textureGrad(n_conc, w * road_tile * 1.3, gx * road_tile * 1.3, gy * road_tile * 1.3).a;
	return 1.0 - textureGrad(n_walk, w * road_tile * 1.4, gx * road_tile * 1.4, gy * road_tile * 1.4).a;
}

vec2 pom_shift(vec2 wp, vec3 vdir, int mode, float depth_m) {
	vec2 gx = dFdx(wp);
	vec2 gy = dFdy(wp);
	float vy = max(vdir.y, 0.2);
	int n = int(mix(20.0, 8.0, vy));
	vec2 step_w = -vdir.xz / vy * depth_m / float(n);   // сдвиг по поверхности на один слой глубины
	float layer = 1.0 / float(n);
	vec2 p = wp;
	float cur = 0.0;
	float d = pom_depth(mode, p, gx, gy);
	for (int i = 0; i < 20; i++) {
		if (i >= n || cur >= d) break;
		p += step_w;
		cur += layer;
		d = pom_depth(mode, p, gx, gy);
	}
	// уточнение между двумя последними слоями
	vec2 prev = p - step_w;
	float after = d - cur;
	float before = pom_depth(mode, prev, gx, gy) - (cur - layer);
	float t = after / min(after - before, -1e-4);
	return mix(p, prev, clamp(t, 0.0, 1.0));
}

// Самозатенение рельефа: от найденной точки идём к солнцу; если рельеф по пути выше луча — точка в тени соседнего
// камешка. Возвращает освещённость 0..1 (мягко, по самому глубокому «перекрытию»).
float pom_shadow(vec2 p, int mode, float depth_m, vec3 sun) {
	if (sun.y < 0.05) return 1.0;
	vec2 gx = dFdx(p);
	vec2 gy = dFdy(p);
	float h0 = 1.0 - pom_depth(mode, p, gx, gy);
	vec2 step_w = sun.xz / max(sun.y, 0.15) * depth_m / 8.0;
	float occl = 0.0;
	for (int i = 1; i <= 6; i++) {
		float ray_h = h0 + float(i) / 8.0;
		float hh = 1.0 - pom_depth(mode, p + step_w * float(i), gx, gy);
		occl = max(occl, (hh - ray_h) * (1.0 - float(i) / 7.0));
	}
	return 1.0 - clamp(occl * 4.0, 0.0, 1.0);
}

// Декали дефектов в мировых координатах (сетка 6x6 м, по одной декали на ячейку): не зависят от того, какой дороге
// принадлежит пиксель, поэтому не обрубаются на стыках; strength — доля покрытия, на котором декали уместны.
void road_decals_w(inout vec3 col, inout float rough, vec2 wp, float wear, float strength, bool walk, vec2 gx, vec2 gy) {
	float S = 6.0;
	vec2 cf = wp / S;
	vec2 c0 = floor(cf);
	vec2 f = cf - c0;
	vec2 o = vec2(f.x < 0.5 ? -1.0 : 1.0, f.y < 0.5 ? -1.0 : 1.0);
	for (int q = 0; q < 4; q++) {
		vec2 cell = c0 + vec2(float(q & 1) * o.x, float(q >> 1) * o.y);
		vec4 h = hash4(cell + vec2(91.7, 13.1));
		if (h.x > 0.14 + wear * 0.36) continue;
		vec4 h2 = hash4(cell + vec2(7.9, 55.3));
		vec2 c = (cell + 0.2 + 0.6 * h2.xy) * S;
		float rot = h2.z * 6.2831;
		float pick = h.y;
		int id;
		float sz;
		float st = 0.9;
		if (walk) {
			id = h.z < 0.5 ? 0 : 1;
			sz = mix(2.0, 3.5, h.w);
		} else if (pick < 0.3) {
			id = 10 + int(h.z * 2.99);
			sz = mix(2.4, 4.2, h.w);
			st = 0.8;
		} else if (pick < 0.65) {
			id = h.z < 0.5 ? 0 : 1;
			sz = mix(3.2, 5.6, h.w);
			st = 0.95;
		} else if (pick < 0.82) {
			if (wear < 0.35) continue;
			id = 6 + int(h.z * 3.99);
			sz = mix(2.6, 4.4, h.w);
			st = 1.0;
		} else if (pick < 0.96) {
			if (wear < 0.25) continue;
			id = 3 + int(h.z * 2.99);
			sz = mix(1.5, 3.0, h.w);
			st = 1.0;
		} else {
			id = h.z < 0.6 ? 14 : 15;
			sz = 1.1;
			st = 1.0;
		}
		vec4 d = decal(wp, c, rot, sz, id, gx, gy);
		if (d.a <= 0.001) continue;
		apply_decal(col, rough, d, st * strength * 0.8);
		if (id >= 3 && id <= 5) {
			// влажная яма: тёмная блестящая середина
			float wet = step(0.55, h2.w);
			float inner = d.a * (1.0 - smoothstep(0.0, 0.5, length(wp - c) / sz * 2.0)) * strength;
			col = mix(col, col * vec3(0.55, 0.62, 0.7), inner * 0.5 * wet);
			rough = mix(rough, 0.18, inner * wet * 0.8);
		}
	}
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 p = wpos * tile;
	vec3 dx = dFdx(p);
	vec3 dy = dFdy(p);

	float wg = wa.r;
	float wd = wa.g;
	float ws = wa.b;
	float wsa = wa.a;
	float w_asp = wb.r;
	float w_con = wb.g;
	float w_gra = wb.b;
	float w_rsa = wb.a;
	float w_base = wl;

	float up = clamp(n.y, 0.0, 1.0);
	float up_r = up;
	float grass_ok = smoothstep(0.6, 0.85, up);
	wd += wg * (1.0 - grass_ok);
	wg *= grass_ok;
	float steep = 1.0 - smoothstep(0.5, 0.78, up);
	ws += (wg + wd + wsa) * steep;
	wg *= 1.0 - steep;
	wd *= 1.0 - steep;
	wsa *= 1.0 - steep;

	wg = sharp(wg);
	wd = sharp(wd);
	ws = sharp(ws);
	wsa = sharp(wsa);
	float rv = clamp(w_asp + w_con + w_gra + w_rsa, 0.0, 1.0);   // сумма без sharp: на стыке двух дорожных материалов маска не проваливается
	// у дорожных вокселей без покрытия (кромка, выкопано) под ногами — земля/щебень
	float wdirt = wd + sharp(w_asp) * 0.7 + sharp(w_con) * 0.7 + sharp(w_rsa) * 0.4;
	float wgrav = sharp(w_gra) * 0.6 + sharp(w_base);

	float sum = wg + wdirt + ws + wsa + wgrav + 0.0001;
	float natural = wg + wd + ws + wsa;
	vec3 col = vec3(0.3);
	float rough = 0.95;
	vec3 nbump = n;
	vec3 curb_off = vec3(0.0);
	float nfade = 1.0 - smoothstep(detail_far * 0.26, detail_far, length(wpos - CAMERA_POSITION_WORLD));
	vec3 g_off = vec3(0.0);
	// дешёвая проверка «пиксель целиком под целым покрытием дороги»: тогда грунт (десятки выборок текстур)
	// не считаем вовсе — он всё равно полностью закрыт. В городе это большая часть экрана.
	vec2 auv = (wpos.xz / atlas_step + 0.5) / atlas_n;
	vec4 cv = texture(road_c, auv);
	bool road_solid = false;
	if (cv.g > 0.5 && up > 0.96 && cv.b + cv.a > 0.0) {
		float fo0 = texture(road_a, auv).g;
		float h0 = (round(cv.b * 255.0) * 256.0 + round(cv.a * 255.0)) / 100.0 - 50.0;
		road_solid = fo0 < -1.4 && abs(wpos.y - h0) < 0.22;
	}
	if (!road_solid && (perf_skip & 8) == 0) {
	vec3 gtex = vec3(0.0);
	if (wg > 0.01) {
		// три травы: ухоженная, высокая и сухая — плавно перетекают по низкочастотному шуму
		float m1 = smoothstep(0.25, 0.75, gnoise(wpos.xz * 0.06 + 2.0));
		float m2 = smoothstep(0.45, 0.95, gnoise(wpos.xz * 0.031 + 17.0));
		vec3 pg = p * grass_scale;
		vec3 dxg = dx * grass_scale;
		vec3 dyg = dy * grass_scale;
		gtex = mix(mix(tri2(tex_grass, pg, b, dxg, dyg), tri2(tex_grass2, pg * 0.77 + 0.31, b, dxg * 0.77, dyg * 0.77), m1),
			tri2(tex_grass3, pg * 0.9 + 0.57, b, dxg * 0.9, dyg * 0.9), m2 * 0.85);
		// мох пятнами (тот же шум, что выбирает кусты на мху — GrassField._ground_pool)
		float mm = moss_mask(wpos.xz, up);
		if (mm > 0.01) gtex = mix(gtex, tri2(tex_moss, pg * 0.93 + 0.11, b, dxg * 0.93, dyg * 0.93), mm);
		gtex *= grass_tint;
		if (grass_recolor > 0.0) {
			// яркость относительно средней у своей текстуры (grass_a тёмная, b и c светлые) — рисунок остаётся, цвет общий
			float lref = mix(mix(0.048, 0.205, m1), 0.208, m2 * 0.85);
			float sh = clamp(dot(gtex, vec3(0.299, 0.587, 0.114)) / (lref * dot(grass_tint, vec3(0.333))), 0.45, 1.7);
			gtex = mix(gtex, grass_color * sh, grass_recolor);
		}
	}
	col = vec3(0.0);
	if (wg > 0.01) col += gtex * wg;
	if (wdirt > 0.01) col += tri2(tex_dirt, p, b, dx, dy) * wdirt;
	if (ws > 0.01) col += tri(tex_stone, p, b, dx, dy) * ws;
	if (wsa > 0.01) col += tri(tex_sand, p, b, dx, dy) * wsa;
	if (wgrav > 0.01) col += tri(tex_gravel, p, b, dx, dy) * wgrav;
	col /= sum;
	float macro = mix(0.78, 1.15, gnoise(wpos.xz * 0.045 + 3.0) * 0.6 + gnoise(wpos.xz * 0.2 + 9.0) * 0.4);
	col *=mix(1.0, macro, clamp(natural / sum, 0.0, 1.0));
	if (has_biome) {
		// выжженная земля: обесцвеченный пепел, копоть пятнами, чёрные проплешины
		float bn = texture(biome_mask, wpos.xz / biome_world).r;
		if (bn > 0.01) {
			float l = dot(col, vec3(0.299, 0.587, 0.114));
			float soot = gnoise(wpos.xz * 0.23 + 40.0) * 0.6 + gnoise(wpos.xz * 1.3) * 0.4;
			vec3 ash = vec3(l) * vec3(0.62, 0.57, 0.53) * mix(0.6, 1.15, soot);
			ash = mix(ash, vec3(0.025, 0.022, 0.02), smoothstep(0.62, 0.8, gnoise(wpos.xz * 0.11 + 9.0)) * 0.8);
			col = mix(col, ash, clamp(bn * 0.92 * clamp(natural / sum, 0.0, 1.0) + 0.0, 0.0, 1.0));
		}
	}
	// рельеф и детализация вблизи: карты нормалей материалов + мелкая детальная текстура
	if (nfade > 0.01) {
		vec3 acc = vec3(0.0);
		if (wg > 0.01) {
			float m1 = smoothstep(0.25, 0.75, gnoise(wpos.xz * 0.06 + 2.0));
			float m2 = smoothstep(0.45, 0.95, gnoise(wpos.xz * 0.031 + 17.0));
			vec3 pg = p * grass_scale;
			vec3 dxg = dx * grass_scale;
			vec3 dyg = dy * grass_scale;
			vec3 ng = tri_n(n_grass, pg, b, dxg, dyg);
			if (m1 > 0.02) ng = mix(ng, tri_n(n_grass2, pg * 0.77 + 0.31, b, dxg * 0.77, dyg * 0.77), m1);
			if (m2 > 0.02) ng = mix(ng, tri_n(n_grass3, pg * 0.9 + 0.57, b, dxg * 0.9, dyg * 0.9), m2 * 0.85);
			float mm = moss_mask(wpos.xz, up);
			if (mm > 0.02) ng = mix(ng, tri_n(n_moss, pg * 0.93 + 0.11, b, dxg * 0.93, dyg * 0.93), mm);
			acc += ng * wg;
		}
		if (wdirt > 0.01) acc += tri_n(n_dirt, p, b, dx, dy) * wdirt;
		if (ws > 0.01) acc += tri_n(n_stone, p, b, dx, dy) * ws;
		if (wsa > 0.01) acc += tri_n(n_sand, p, b, dx, dy) * wsa;
		if (wgrav > 0.01) acc += tri_n(n_gravel, p, b, dx, dy) * wgrav;
		g_off = acc / sum * 0.85;
		float dh = textureGrad(n_dirt, p.xz * 6.3, dx.xz * 6.3, dy.xz * 6.3).a;
		col *= 1.0 + (dh - 0.5) * 1.1 * nfade * b.y * clamp(natural / sum, 0.0, 1.0);
	}
	}   // !road_solid

	// --- дороги по карте ---
	float d_cover = -1.0;
	float d_kmix = 0.0;
	if (cv.g > 0.5 && up_r > 0.8 && (perf_skip & 4) == 0) {
		vec4 A = texture(road_a, auv);
		vec4 Bk = texture(road_b, auv);
		float fp = A.r;
		float fo = A.g;
		if (fo < 2.4) {
			int kind_a;
			int kind_b;
			float wear_s;
			float curb_s;
			float kmix = road_kinds(wpos.xz, kind_a, kind_b, wear_s, curb_s);
			float jf = 1.0 - smoothstep(0.02, 0.22, kmix);   // швы/разметка гаснут в зоне перехода (там lat/along двух объектов не совпадают)
			int kdom = kind_a;
			float wear = pow(clamp(wear_s * 1.35 + 0.12, 0.0, 1.0), 0.65);
			float mark = smoothstep(0.4, 0.6, Bk.b);
			bool curb = curb_s > 0.5;   // по размытому окну: конец тротуара — гладкая кривая, а не ступеньки по текселям
			float hw = cv.r * 12.0;
			float lat = A.b;
			float along = A.a;
			vec2 wp = wpos.xz;
			// плавный переход дорога -> грунт: ширина зависит от типа (грунтовка/щебень шире, бордюр уже),
			// край слегка «дышит» по шуму, поверх — размытая придорожная грязь
			float ew = curb ? 0.16 : ((kdom == 2 || kdom == 3 || kdom == 6) ? 0.75 : 0.38);
			float fo_n = fo + (gnoise(wp * 2.3 + 5.0) - 0.5) * ew * 1.6 + (gnoise(wp * 0.7 + 13.0) - 0.5) * ew * 1.2;
			float cover = 1.0 - smoothstep(-ew, ew, fo_n);
			// рваный край: маска по вокселам (там, где дорогу выкопали, она пропадает)
			// порог рваного края: крупный + мелкий шум, чтобы край выкопанного покрытия был крошащимся, а не воксельной лесенкой
			float thr = 0.5 + (gnoise(wp * 1.7) - 0.5) * 0.9 + (gnoise(wp * 0.6 + 7.0) - 0.5) * 0.5 + (gnoise(wp * 5.3 + 3.0) - 0.5) * 0.35;
			// воксельная маска нужна только там, где дорогу выкопали; у целого края (rv ≈ 1) она не должна рвать чёткую границу
			// выкопано/засыпано: поверхность отошла от исходной высоты дороги (road_c.ba) — покрытия там нет,
			// край рваный по шуму. Не зависит от вокселей 1 м (верхний «асфальтовый» слой вокселей толщиной 1 м,
			// поэтому неглубокая яма по материалу всё ещё дорога, и асфальт растягивался по её склонам полосами)
			float h_ref = (round(cv.b * 255.0) * 256.0 + round(cv.a * 255.0)) / 100.0 - 50.0;
			float dh = abs(wpos.y - h_ref);
			float dug = cv.b + cv.a > 0.0 ? smoothstep(0.4 + (thr - 0.5) * 0.3, 0.52 + (thr - 0.5) * 0.3, dh) : 0.0;
			float broken_rim = dug * (1.0 - dug) * 4.0;   // узкая полоса у края выкопанного: тёмный скол покрытия
			cover *= 1.0 - dug;
			cover *= smoothstep(0.84, 0.95, up_r);   // на крутых стенках ям плоская проекция дороги растягивается в полосы			// придорожная грязь за краем
			// вытоптанная трава полосой у края дороги (дальше — обычная трава, ближе к краю — грязь)
			float tramp = (1.0 - smoothstep(0.6, 2.35, fo)) * (1.0 - cover) * clamp(wg / sum, 0.0, 1.0);
			if (tramp > 0.01) {
				col = mix(col, tri2(tex_tramp, p * grass_scale, b, dx * grass_scale, dy * grass_scale), tramp * 0.9);
			}
			float dirt_zone = (1.0 - smoothstep(-0.2, 2.6, fo)) * smoothstep(0.15, 0.7, gnoise(wp * 0.8 + 4.0));
			dirt_zone *= (1.0 - cover) * (0.4 + 0.6 * Bk.g);
			if (dirt_zone > 0.01) {
				vec3 dtx = tri(tex_dirtroad, p, b, dx, dy);
				col = mix(col, dtx * 0.9, dirt_zone * 0.8);
			}
			d_cover = cover;
			d_kmix = kmix;
			if (cover > 0.002) {
				// вес тротуара: размытый признак (конец тротуара — плавный) и сторона бордюра (кромка остаётся чёткой)
				float sw_w = smoothstep(0.25, 0.75, curb_s) * smoothstep(-0.02, 0.02, fp);
				vec2 gxu = dFdx(wp * road_tile);   // производные — от несдвинутой точки (без разрывов мипмапов)
				vec2 gyu = dFdy(wp * road_tile);
				// POM вблизи (галочка в настройках графики): текстуры покрытия берутся из сдвинутой по рельефу точки
				float pom_lit = 1.0;
				if (use_pom) {
					float pd = length(wpos - CAMERA_POSITION_WORLD);
					float pf = (1.0 - smoothstep(8.0, 18.0, pd)) * smoothstep(0.92, 0.98, up_r) * smoothstep(0.3, 0.6, cover);
					if (pf > 0.01) {
						int pm = sw_w > 0.5 ? 2 : ((kind_a == 1 || kind_a == 5) ? 1 : ((kind_a == 0 || kind_a == 7) ? 0 : -1));
						if (pm >= 0) {
							float dm = (pm == 0 ? 0.045 : (pm == 1 ? 0.02 : 0.03)) * pf;
							wp = pom_shift(wp, normalize(CAMERA_POSITION_WORLD - wpos), pm, dm);
							pom_lit = mix(1.0, pom_shadow(wp, pm, dm, pom_sun), 0.55 * pf);
						}
					}
				}
				vec2 uvw = wp * road_tile;
				float n1 = fbm(wp * 0.35);
				float n2 = fbm(wp * 1.7 + 11.0);
				float sp = vnoise(wp * 22.0) * 0.5 + vnoise(wp * 47.0) * 0.5;
				// проезжая часть/площадка: два типа покрытия смешиваются по высоте
				vec3 rk = vec3(0.3);
				float rrk = 0.88;
				vec3 nk = vec3(0.0);
				float hk = 0.0;
				float deck = 0.0;   // доля покрытия, на котором уместны декали (асфальт/бетон)
				if (sw_w < 0.996 && (perf_skip & 16) == 0) {
					vec3 c1; float r1; vec3 o1; float h1;
					road_material(kind_a, false, wp, uvw, gxu, gyu, p, b, dx, dy, lat, along, hw, wear, mark, jf, n1, n2, sp, c1, r1, o1, h1);
					float d1 = (kind_a == 0 || kind_a == 1 || kind_a == 5 || kind_a == 7) ? 1.0 : 0.0;
					if (kmix > 0.004) {
						vec3 c2; float r2; vec3 o2; float h2;
						road_material(kind_b, false, wp, uvw, gxu, gyu, p, b, dx, dy, lat, along, hw, wear, mark, jf, n1, n2, sp, c2, r2, o2, h2);
						float d2 = (kind_b == 0 || kind_b == 1 || kind_b == 5 || kind_b == 7) ? 1.0 : 0.0;
						vec2 bw = hblend(1.0 - kmix, h1, kmix, h2);
						rk = c1 * bw.x + c2 * bw.y;
						rrk = r1 * bw.x + r2 * bw.y;
						nk = o1 * bw.x + o2 * bw.y;
						hk = h1 * bw.x + h2 * bw.y;
						deck = d1 * bw.x + d2 * bw.y;
					} else {
						rk = c1; rrk = r1; nk = o1; hk = h1; deck = d1;
					}
				}
				vec3 rc = rk;
				float rr = rrk;
				vec3 noff = nk;
				float decw = deck;
				if (sw_w > 0.004 && (perf_skip & 16) == 0) {
					vec3 cs; float rs; vec3 os; float hs;
					road_material(1, true, wp, uvw, gxu, gyu, p, b, dx, dy, lat, along, hw, wear, mark, jf, n1, n2, sp, cs, rs, os, hs);
					vec2 bw = sw_w >= 0.996 ? vec2(0.0, 1.0) : hblend(1.0 - sw_w, hk, sw_w, hs);
					rc = rk * bw.x + cs * bw.y;
					rr = rrk * bw.x + rs * bw.y;
					noff = nk * bw.x + os * bw.y;
					decw = deck * bw.x + bw.y;
				}
				// декали дефектов (трещины, ямы, вскрытый асфальт, пятна, люки) — в мировых координатах
				if (use_decals && wear > 0.04 && decw > 0.01 && (perf_skip & 1) == 0) {
					vec2 gxd = clamp(dFdx(wp), vec2(-0.6), vec2(0.6));
					vec2 gyd = clamp(dFdy(wp), vec2(-0.6), vec2(0.6));
					road_decals_w(rc, rr, wp, wear, decw * (1.0 - broken_rim), sw_w > 0.5, gxd, gyd);
				}
				// пыль на покрытии
				float drift = smoothstep(0.62, 0.86, fbm(wp * 0.18 + 31.0)) * wear * 0.3;
				rc = mix(rc, vec3(0.5, 0.43, 0.33) * 0.85, drift);
				// бордюр: затемнение кромки и псевдорельеф по градиенту поля
				if (curb) {
					float dpx = 1.0 / atlas_n;
					float gxp = (texture(road_a, auv + vec2(dpx, 0.0)).r - texture(road_a, auv - vec2(dpx, 0.0)).r) / (2.0 * atlas_step);
					float gzp = (texture(road_a, auv + vec2(0.0, dpx)).r - texture(road_a, auv - vec2(0.0, dpx)).r) / (2.0 * atlas_step);
					float u = clamp(fp / 0.22, 0.0, 1.0);
					float dh = 0.14 * 6.0 * u * (1.0 - u) / 0.22 * step(0.0, fp) * step(fp, 0.22);
					curb_off = vec3(-gxp * dh, 0.0, -gzp * dh);
					float edge_dark = (1.0 - smoothstep(0.0, 0.1, abs(fp))) * 0.35;
					rc *= 1.0 - edge_dark;
				}
				rc *= 1.0 - broken_rim * 0.45;
				rc *= pom_lit;
				col = mix(col, rc, cover);
				rough = mix(rough, rr, cover);
				g_off = mix(g_off, noff * 0.9 / max(nfade, 0.05), cover);
			}
		}
	}
	if (debug_mode == 1) { vec4 d1 = texture(road_c, auv); vec4 d2 = texture(road_a, auv); col = vec3(d1.g, clamp(1.0 - d2.g * 0.1, 0.0, 1.0), rv); }
	if (debug_mode == 3) { col = vec3(wa.r, wa.g, wa.b + wa.a); }
	if (debug_mode == 4) { col = vec3(up, wl, w_base); }
	if (debug_mode == 6) { col = vec3(max(d_cover, 0.0), up_r, rv); }
	if (debug_mode == 5) { col = vec3(gnoise(wpos.xz * 0.06 + 2.0), gnoise(wpos.xz * 0.031 + 17.0), gnoise(wpos.xz * 0.045 + 3.0)); }
	nbump = normalize(n + g_off * nfade + curb_off);
	ALBEDO = col;
	ROUGHNESS = rough;
	// трава и земля почти без блика неба (иначе тёмная трава под голубым небом сереет плёнкой); дороги — как были
	SPECULAR = mix(0.5, 0.12, clamp(natural / sum, 0.0, 1.0) * (1.0 - max(d_cover, 0.0)));
	if (nbump != n) {
		NORMAL = normalize((VIEW_MATRIX * vec4(nbump, 0.0)).xyz);
	}
}
