shader_type spatial;
// Дальние упрощённые LOD (деревья, камни, здания, столбы): цвет в вершинах, без текстур.
// Рядом с игроком (ближе cut) рисуется обычная модель, здесь фрагменты отбрасываются.
//   MultiMesh (деревья): центр — начало инстанса, тон крон — INSTANCE_CUSTOM.rgb (вес — COLOR.a)
//   Слитые меши (здания, столбы): центр объекта (x, z) хранится в UV

uniform float cut = 90.0;
uniform float far_end = 0.0;
uniform float fade_w = 16.0;   // ширина полосы плавного перехода между уровнями LOD (м); переход — стохастическим дизерингом

float lod_noise(vec2 fc) {
	return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
}

// Доля непрозрачности уровня на расстоянии d: нарастает на [cut, cut+fade_w], спадает на [end-fade_w, end].
float lod_alpha(float d, float cut_, float end_) {
	float a = 1.0;
	if (cut_ > 0.0) a *= smoothstep(cut_, cut_ + fade_w, d);
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
uniform bool uv_center = false;

varying vec2 cen;
varying vec3 tint;
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
	if (uv_center) {
		cen = UV;
		tint = vec3(1.0);
	} else {
		cen = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
		tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
	}
}

void fragment() {
	if (!lod_keep(distance(CAMERA_POSITION_WORLD.xz, cen), cut, far_end, lod_noise(FRAGCOORD.xy))) {
		discard;
	}
	ALBEDO = pow(vcol.rgb, vec3(2.2)) * tint;
	ROUGHNESS = 0.92;
}
