shader_type spatial;
render_mode cull_disabled;
// Осока: перекрёстные карточки с альфой (атлас 4x2 кустиков). Данные инстанса (INSTANCE_CUSTOM):
//   x — «зелёность» (0 сухая, 1 живая), w — номер ячейки атласа / 7.
// Дальше fade_start кусты уменьшаются до нуля (без «выскакивания»), на ветру качаются верхушки.

uniform sampler2D tex_sedge : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
// средний цвет земной травы — те же текстуры и тот же шум, что в terrain.gdshader
uniform sampler2D tex_g1 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_g2 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_g3 : source_color, repeat_enable, filter_linear_mipmap;
uniform float fade_start = 44.0;
uniform float fade_end = 58.0;
uniform float cutoff = 0.4;
uniform float bright = 1.0;   // множитель яркости (кустики на газоне построек темнее травы ландшафта)
uniform vec2 grid = vec2(4.0, 2.0);   // ячейки атласа (столбцы, ряды)
uniform float true_color = 0.0;       // 1 — собственный цвет текстуры кустов (чёткая трава), 0 — перекраска под землю
uniform vec3 grass_color = vec3(0.05, 0.085, 0.022);   // общий цвет травы (как у земли, terrain.gdshader)
uniform float grass_recolor = 0.0;      // доля перекраски кустов в grass_color (сухие прожилки частично остаются)
uniform float tex_lum = 0.18;           // средняя яркость атласа кустов (линейная)
uniform float blade_light = 1.05;       // травинки чуть светлее земли под ними
uniform float dens_near = 1.0e6;   // до этого расстояния — все кусты
uniform float dens_far = 2.0e6;    // здесь доля кустов — dens_min
uniform float dens_min = 1.0;
uniform bool use_shapes = false;   // формы кустов (GrassField.TUFT_SHAPES): COLOR.r вершины — маска форм плоскости
uniform float mip_alpha = 0.0;        // вдали (мелкие мипмапы) альфа сильнее — травинки не тают и не слипаются в «месиво»

varying float vg;
varying float vburn;
varying float vh;
varying vec2 vwp;

vec2 ghash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float a = fract((p3.x + p3.y) * p3.z) * 6.2831853;
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

void vertex() {
	float cell = mod(floor(INSTANCE_CUSTOM.w * 255.0 + 0.5), grid.x * grid.y);
	vec2 c = vec2(mod(cell, grid.x), floor(cell / grid.x));
	vh = 1.0 - UV.y;
	// не брать кромки ячейки: в мелких мипмапах туда протекают соседние кусты атласа (полосы над кустами вдали)
	UV = (clamp(UV, vec2(0.006, 0.02), vec2(0.994, 0.994)) + c) / grid;
	vg = INSTANCE_CUSTOM.x;
	vburn = INSTANCE_CUSTOM.y;
	vec3 wo = MODEL_MATRIX[3].xyz;
	vwp = wo.xz;
	float d = distance(wo.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	// плотность по расстоянию: куст с рангом (INSTANCE_CUSTOM.z) выше плотности здесь — не виден; на границе плавно
	// «вырастает» из земли. Оставшиеся вдали кусты чуть шире — поле не редеет на глаз.
	float dens = mix(1.0, dens_min, smoothstep(dens_near, dens_far, d));
	float grow = clamp((dens - INSTANCE_CUSTOM.z) / 0.05, 0.0, 1.0);
	fade *= grow;
	VERTEX.y *= fade;
	VERTEX.xz *= mix(0.6, 1.0, fade) * (1.0 + 0.6 * (1.0 - dens));
	float t = TIME;
	vec3 off = vec3(sin(t * 1.8 + wo.x * 0.9 + wo.z * 0.7), 0.0, cos(t * 1.4 + wo.z * 0.8 + wo.x * 0.5)) * 0.13 * vh * vh * fade;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	if (use_shapes) {
		int shape = int(floor(floor(INSTANCE_CUSTOM.w * 255.0 + 0.5) / 16.0));
		int mask = int(round(COLOR.r * 255.0));
		if (((mask >> shape) & 1) == 0) {
			VERTEX = vec3(0.0);   // плоскость не этой формы — схлопнуть
		}
	}
}

void fragment() {
	vec4 tx = texture(tex_sedge, UV);
	float a = tx.a * 1.3;
	if (mip_alpha > 0.0) {
		// уровень мипмапа по экранной плотности текселей: на каждом уровне усреднение «размывает» альфу тонких
		// травинок ниже порога — поднимаем её пропорционально уровню (так держат густоту травы в 7DTD/UE)
		vec2 tsz = vec2(textureSize(tex_sedge, 0));
		vec2 dx = dFdx(UV * tsz);
		vec2 dy = dFdy(UV * tsz);
		float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
		a *= 1.0 + lod * mip_alpha;
	}
	if (a < cutoff) {
		discard;
	}
	// цвет подгоняем под ландшафт: оттенок — средний цвет земной травы в этой точке, светотень — от кустика
	float m1 = smoothstep(0.25, 0.75, gnoise(vwp * 0.06 + 2.0));
	float m2 = smoothstep(0.45, 0.95, gnoise(vwp * 0.031 + 17.0));
	vec3 gc = mix(mix(textureLod(tex_g1, vec2(0.5), 9.0).rgb, textureLod(tex_g2, vec2(0.5), 9.0).rgb, m1),
		textureLod(tex_g3, vec2(0.5), 9.0).rgb, m2 * 0.85);
	float macro = mix(0.78, 1.15, gnoise(vwp * 0.045 + 3.0) * 0.6 + gnoise(vwp * 0.2 + 9.0) * 0.4);
	float l = dot(tx.rgb, vec3(0.333));
	vec3 shade = mix(tx.rgb, vec3(l), 0.45);
	// яркость — относительно среднего тона листа (≈0.4), цвет — земной травы; часть кустиков суше и светлее
	float rel = pow(clamp(dot(shade, vec3(0.333)) / 0.4, 0.4, 1.8), 1.5);
	vec3 col = gc * vec3(0.95, 1.12, 0.92) * rel * 1.9;
	vec3 dry = gc * vec3(1.2, 1.1, 0.8) * rel * 2.1;
	col = mix(dry, col, vg);
	col = mix(vec3(dot(col, vec3(0.333))), col, 0.5) * vec3(0.9, 1.02, 0.98) * 1.85;   // ландшафт серее и светлее
	// чёткая трава: свой цвет текстуры (с лёгким уводом в цвет земли, чтобы куст не «отрывался» от поверхности),
	// сухие кусты желтее, у корня темнее
	vec3 own = mix(tx.rgb, tx.rgb * gc / max(dot(gc, vec3(0.333)), 0.05) * 0.42, 0.18);
	if (grass_recolor > 0.0) {
		float sh = clamp(dot(tx.rgb, vec3(0.299, 0.587, 0.114)) / tex_lum, 0.35, 2.0);
		own = mix(own, grass_color * blade_light * sh, grass_recolor);
	}
	own = mix(own * vec3(1.06, 1.0, 0.84), own, mix(0.5, 1.0, vg));   // сухие места — чуть желтее
	// без «салатовости»: красный канал (жёлто-зелёный оттенок) приглушён, цвет к тёмно- и сине-зелёному
	own *= vec3(0.82, 0.95, 1.0);
	col = mix(col, own * 0.98, true_color);
	// выжженная земля: обугленные кусты (INSTANCE_CUSTOM.y — степень выжженности)
	float lb = dot(col, vec3(0.333));
	col = mix(col, vec3(lb) * vec3(0.55, 0.5, 0.46) * 0.7, smoothstep(0.2, 0.7, vburn));
	col *= macro;
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.45, vh));   // у корня темнее
	ALBEDO = col * bright;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // мягкое освещение «сверху»
	BACKLIGHT = col * 0.3;
}
