shader_type spatial;
// Покрытие земли под постройкой (GroundTypes): фото-текстура по мировым координатам, у внешнего края —
// рваная граница по шуму (альфа вершины = доля закрашенных соседних ячеек), без квадратов по клеткам.
render_mode cull_disabled;

uniform sampler2D tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool use_n = false;
uniform float tile = 3.0;
uniform float rough = 0.9;
uniform float desat = 0.0;    // приглушить насыщенность (трава — под тон травы ландшафта)
uniform float gain = 1.0;

varying vec3 wp;
varying float ea;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ea = COLOR.a;
}

void fragment() {
	if (ea < 0.999) {
		float n = vnoise(wp.xz * 1.6) * 0.6 + vnoise(wp.xz * 5.1 + 7.0) * 0.4;
		if (ea < n * 0.55 + 0.25) {
			discard;
		}
	}
	vec2 uv = wp.xz / tile;
	vec3 c = texture(tex, uv).rgb;
	c = mix(c, vec3(dot(c, vec3(0.333))), desat) * gain;
	ALBEDO = c * mix(0.86, 1.06, vnoise(wp.xz * 0.27 + 3.0));
	ROUGHNESS = rough;
	if (use_n) {
		NORMAL_MAP = texture(tex_n, uv).rgb;
	}
}
