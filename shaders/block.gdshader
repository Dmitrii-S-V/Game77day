shader_type spatial;
// Материалы блоков построек: узор выводится по координатам в пространстве здания.
// COLOR = (id/32, вариация блока, ambient occlusion, оттенок здания/4).

varying vec3 lp;
varying vec3 ln;
varying vec4 vc;
varying vec2 vuv;
varying vec2 vuv2;

uniform sampler2DArray tex_blocks : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_nr : filter_linear_mipmap_anisotropic, repeat_enable;   // RGB — нормаль (OpenGL), A — шероховатость
uniform float normal_strength = 1.0;
uniform sampler2DArray tex_decals : source_color, filter_linear_mipmap, repeat_disable;   // спрайты декалей (грязь, знаки, пробоины…)
uniform vec4 decal_info[128];   // x — сторона спрайта в метрах, y — 1: можно вращать, z — сила, w — запас
uniform float decal_gain = 1.0;

const vec3 BASE[19] = vec3[](
	vec3(0.0), vec3(0.55, 0.42, 0.28), vec3(0.58, 0.28, 0.20), vec3(0.55, 0.55, 0.53), vec3(0.50, 0.55, 0.58),
	vec3(0.55, 0.75, 0.85), vec3(0.28, 0.22, 0.20), vec3(0.50, 0.36, 0.22), vec3(0.75, 0.75, 0.72), vec3(0.80, 0.76, 0.68),
	vec3(0.42, 0.28, 0.17), vec3(0.45, 0.45, 0.43), vec3(0.45, 0.30, 0.18), vec3(0.60, 0.20, 0.20), vec3(0.50, 0.13, 0.10),
	vec3(0.40, 0.42, 0.45), vec3(0.35, 0.40, 0.45), vec3(0.75, 0.65, 0.30), vec3(0.50, 0.38, 0.22));
const vec3 TINT[4] = vec3[](vec3(1.0), vec3(0.86, 0.92, 1.06), vec3(1.1, 0.95, 0.85), vec3(0.9, 1.06, 0.92));

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vc = COLOR;
	vuv = UV;
	vuv2 = UV2;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	int id = int(floor(vc.r * 255.0 + 0.5));
	float var_h = vc.g;
	float ao = vc.b;
	int ti = int(floor(vc.a * 4.0 + 0.5));
	vec3 n = normalize(ln);
	vec2 uv;
	if (abs(n.x) > 0.5) {
		uv = vec2(lp.z, lp.y);
	} else if (abs(n.y) > 0.5) {
		uv = lp.xz;
	} else {
		uv = vec2(lp.x, lp.y);
	}
	if (id >= 32) {
		// новые блоки: текстура из массива (слой в UV2.x), режим в UV2.y: 0 куб, 1 каркас, 2 UV грани, 3 UV грани светящийся
		vec2 tuv = vuv2.y > 1.5 ? vuv : uv * vuv.x;   // vuv.x у кубов = 1 / размер повтора текстуры в метрах
		vec4 tx = texture(tex_blocks, vec3(tuv, vuv2.x));
		vec4 nr = texture(tex_nr, vec3(tuv, vuv2.x));
		// прозрачные текстуры (паутина, рабица): на дальних мипах тонкие нити усредняются с фоном и пропали бы
		// при пороге 0.5 — альфа усиливается с уровнем мипа (сохраняет «покрытие»)
		float ta = tx.a;
		if (ta < 0.999) {
			vec2 tdx = dFdx(tuv) * float(textureSize(tex_blocks, 0).x);
			vec2 tdy = dFdy(tuv) * float(textureSize(tex_blocks, 0).x);
			float lod = max(0.0, 0.5 * log2(max(dot(tdx, tdx), dot(tdy, tdy))));
			ta *= 1.0 + lod * 0.35;
		}
		if (ta < 0.5) {
			discard;
		}
		if (abs(vuv2.y - 1.0) < 0.5) {
			vec2 cl = fract(uv / 1.0);
			float e = min(min(cl.x, 1.0 - cl.x), min(cl.y, 1.0 - cl.y));
			if (e > 0.09) {
				discard;
			}
		}
		ALBEDO = tx.rgb * mix(0.45, 1.0, ao) * (0.94 + 0.12 * var_h);
		ROUGHNESS = nr.a;
		if (vuv2.y < 1.5) {
			// нормаль из карты: касательные по раскладке UV граней (u, v — в метрах объекта; v растёт вниз по картинке)
			vec3 tn = n;
			vec3 T;
			vec3 Bt;
			if (abs(n.x) > 0.5) { T = vec3(0.0, 0.0, 1.0); Bt = vec3(0.0, -1.0, 0.0); }
			else if (abs(n.y) > 0.5) { T = vec3(1.0, 0.0, 0.0); Bt = vec3(0.0, 0.0, -1.0); }
			else { T = vec3(1.0, 0.0, 0.0); Bt = vec3(0.0, -1.0, 0.0); }
			vec3 m = vec3((nr.rg * 2.0 - 1.0) * normal_strength, nr.b * 2.0 - 1.0);
			vec3 no = normalize(T * m.x + Bt * m.y + n * max(m.z, 0.05));
			NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(no, 0.0)).xyz);
		}
		if (vuv2.y > 2.5) {
			ALBEDO = tx.rgb;
			EMISSION = tx.rgb * 2.5;
		}
	} else {
	vec3 col = BASE[clamp(id, 0, 18)];
	float pat = 1.0;
	float rough = 0.9;
	float noise = vnoise(uv * 11.0) * 0.5 + vnoise(uv * 27.0) * 0.5;
	if (id == 1) {
		// горизонтальные доски
		float row = floor(uv.y / 0.14);
		float f = fract(uv.y / 0.14);
		float joint = smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f);
		pat = (0.78 + 0.22 * hash(vec2(row, 3.0))) * mix(0.55, 1.0, joint) * (0.9 + 0.2 * vnoise(vec2(uv.x * 3.0, row * 7.0)));
	} else if (id == 2) {
		// кирпич 0.25 x 0.075 со смещением
		float row = floor(uv.y / 0.075);
		float off = mod(row, 2.0) * 0.125;
		vec2 b = vec2(fract((uv.x + off) / 0.25), fract(uv.y / 0.075));
		float mortar = smoothstep(0.0, 0.07, b.x) * smoothstep(1.0, 0.93, b.x) * smoothstep(0.0, 0.14, b.y) * smoothstep(1.0, 0.86, b.y);
		float bh = hash(vec2(floor((uv.x + off) / 0.25), row));
		col = mix(vec3(0.62, 0.6, 0.56), col * (0.8 + 0.4 * bh), mortar);
		pat = 0.9 + 0.2 * noise;
	} else if (id == 3 || id == 11) {
		pat = 0.85 + 0.3 * noise;
		float seam = smoothstep(0.0, 0.02, abs(fract(uv.y / 1.0) - 0.5) - 0.48 + 0.02);
		pat *= mix(0.7, 1.0, 1.0 - seam * 0.0);
		if (id == 11) {
			vec2 c = floor(uv / 0.3);
			pat *= 0.8 + 0.4 * hash(c);
		}
	} else if (id == 4 || id == 15) {
		float rib = 0.85 + 0.15 * sin(uv.x * 38.0);
		pat = rib * (0.9 + 0.2 * noise);
		rough = 0.5;
		if (id == 15) pat *= 0.9 + 0.2 * sin(uv.y * 0.0 + uv.x * 38.0);
	} else if (id == 6) {
		float row = floor(uv.y / 0.16);
		float f = fract(uv.y / 0.16);
		float x = fract((uv.x + mod(row, 2.0) * 0.12) / 0.24);
		float edge = smoothstep(0.0, 0.1, f) * smoothstep(0.0, 0.06, x) * smoothstep(1.0, 0.94, x);
		pat = mix(0.6, 1.0, edge) * (0.8 + 0.4 * hash(vec2(floor((uv.x + mod(row, 2.0) * 0.12) / 0.24), row)));
	} else if (id == 7) {
		float board = floor(uv.x / 0.12);
		float f = fract(uv.x / 0.12);
		pat = mix(0.6, 1.0, smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f)) * (0.8 + 0.4 * hash(vec2(board, floor(uv.y / 1.1))));
	} else if (id == 8) {
		vec2 g = floor(uv / 0.3);
		float chk = mod(g.x + g.y, 2.0);
		vec2 f = fract(uv / 0.3);
		float grout = smoothstep(0.0, 0.04, min(f.x, f.y)) * smoothstep(1.0, 0.96, max(f.x, f.y));
		col = mix(col, col * 0.55 + vec3(0.1, 0.1, 0.12), chk);
		pat = mix(0.55, 1.0, grout) * (0.9 + 0.1 * noise);
		rough = 0.4;
	} else if (id == 9) {
		pat = 0.92 + 0.14 * noise;
	} else if (id == 10) {
		float f = fract(uv.y / 0.25);
		float round_ = sin(f * 3.14159);
		pat = (0.55 + 0.45 * round_) * (0.85 + 0.3 * vnoise(vec2(uv.x * 4.0, floor(uv.y / 0.25) * 3.0)));
	} else if (id == 14) {
		float f = fract(uv.x / 0.18);
		pat = mix(0.6, 1.0, smoothstep(0.0, 0.07, f) * smoothstep(1.0, 0.93, f)) * (0.85 + 0.2 * noise);
	} else if (id == 17) {
		pat = 0.7 + 0.5 * vnoise(vec2(uv.x * 40.0, uv.y * 6.0));
	} else if (id == 18) {
		vec2 f = fract(uv / 0.5);
		float frame = smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		pat = mix(1.0, 0.65, 1.0 - frame) * (0.9 + 0.2 * noise);
	} else if (id == 13) {
		pat = 0.85 + 0.2 * vnoise(uv * 60.0);
		rough = 1.0;
	} else {
		pat = 0.9 + 0.2 * noise;
	}
	vec3 tint = TINT[clamp(ti, 0, 3)];
	float tint_amount = (id == 1 || id == 2 || id == 9 || id == 3) ? 1.0 : 0.0;
	ALBEDO = col * pat * mix(vec3(1.0), tint, tint_amount) * mix(0.45, 1.0, ao) * (0.92 + 0.16 * var_h);
	ROUGHNESS = rough;
	}
	// декаль на грани куба: UV.y = упакованные параметры (слой 8 бит, поворот 2, зеркало 1, смещение x/y по 6 бит)
	int dpk = int(vuv.y + 0.5);
	if (vuv2.y < 1.5 && dpk > 0) {
		int dl = dpk & 255;
		int drot = (dpk >> 8) & 3;
		int dflip = (dpk >> 10) & 1;
		vec2 doff = vec2(float((dpk >> 11) & 63), float((dpk >> 17) & 63)) / 63.0 - 0.5;
		vec4 inf = decal_info[dl];
		vec2 fl = fract(uv);                       // координаты в пределах грани 0..1 (ячейка 1 м)
		bool flip_u = n.x > 0.5 || n.z < -0.5;
		if (flip_u) fl.x = 1.0 - fl.x;
		if (abs(n.y) < 0.5) fl.y = 1.0 - fl.y;     // картинка «вверх» = вверх по стене
		vec2 q = (fl - (vec2(0.5) + doff * 0.4)) / inf.x + 0.5;
		if (dflip == 1) q.x = 1.0 - q.x;
		vec2 r = q - 0.5;
		if (drot == 1) r = vec2(-r.y, r.x);
		else if (drot == 2) r = -r;
		else if (drot == 3) r = vec2(r.y, -r.x);
		q = r + 0.5;
		if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
			vec4 dc = texture(tex_decals, vec3(q, float(dl)));
			float da = dc.a * inf.z * decal_gain;
			ALBEDO = mix(ALBEDO, dc.rgb * mix(0.6, 1.0, ao), clamp(da, 0.0, 1.0));
			ROUGHNESS = mix(ROUGHNESS, 0.85, clamp(da, 0.0, 1.0));
		}
	}
}
