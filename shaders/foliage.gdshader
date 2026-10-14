shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Листва: карточки с альфой (атласы 4x2 из присланных листов), нормали от центра кроны,
// лёгкий просвет на солнце и покачивание на ветру (вес — альфа цвета вершины).

uniform sampler2D tex_leaf : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform float cutoff = 0.42;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;
uniform float far_cut = 0.0;
uniform float far_end = 0.0;   // >0: не рисуется дальше far_end м (передаёт эстафету следующему уровню LOD)
varying float vdist;
uniform float fade_w = 16.0;   // ширина полосы плавного перехода между уровнями LOD (м); переход — стохастическим дизерингом

float lod_noise(vec2 fc) {
	return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
}

// Доля непрозрачности уровня на расстоянии d: нарастает на [cut, cut+fade_w], спадает на [end-fade_w, end].
float lod_alpha(float d, float cut, float end_) {
	float a = 1.0;
	if (cut > 0.0) a *= smoothstep(cut, cut + fade_w, d);
	if (end_ > 0.0) a *= 1.0 - smoothstep(end_ - fade_w, end_, d);
	return a;
}

// Видимость пикселя при дизерной эстафете LOD: появляющийся уровень (рост после cut) берёт ИНВЕРТИРОВАННЫЙ шум,
// уходящий (спад к end) — обычный. На стыке двух уровней их пиксели взаимно дополняют друг друга: каждый пиксель
// рисует ровно один уровень (с одинаковым шумом на 50% оба рисовали одни и те же пиксели — дерево просвечивало «сеткой»).
bool lod_keep(float d, float cut_, float end_, float n) {
	float a_in = cut_ > 0.0 ? smoothstep(cut_, cut_ + fade_w, d) : 1.0;
	float a_out = end_ > 0.0 ? 1.0 - smoothstep(end_ - fade_w, end_, d) : 1.0;
	return (1.0 - n) < a_in && n < a_out;
}

varying float sway;

void vertex() {
	sway = COLOR.a;
	vdist = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz, CAMERA_POSITION_WORLD.xz);
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = wp.x * 0.37 + wp.z * 0.53;
	float t = TIME * 1.6 + ph;
	VERTEX += vec3(sin(t) + 0.5 * sin(t * 2.3 + VERTEX.y), 0.15 * sin(t * 1.7), cos(t * 0.9) + 0.5 * sin(t * 2.9 + VERTEX.x)) * 0.045 * sway * wind;
}

void fragment() {
	if ((far_cut > 0.0 || far_end > 0.0) && !lod_keep(vdist, far_cut, far_end, lod_noise(FRAGCOORD.xy))) {
		discard;
	}
	vec4 tx = texture(tex_leaf, UV);
	if (tx.a < cutoff) {
		discard;
	}
	vec3 col = tx.rgb * COLOR.rgb * tint;
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	// вершинные нормали направлены от центра кроны; обратная сторона карточки освещается так же
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	BACKLIGHT = col * 0.35;
}
