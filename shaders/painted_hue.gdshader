shader_type spatial;
// Крашеный предмет (скамейка): насыщенные (окрашенные) участки текстуры перекрашиваются в оттенок hue
// (на экземпляр: от синего 0.6 до зелёного 0.33), дерево и грязь остаются как есть.

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform float roughness_v = 0.85;
instance uniform float hue = 0.5;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(tex_albedo, UV).rgb;
	vec3 hsv = rgb2hsv(c);
	float painted = smoothstep(0.15, 0.32, hsv.y);
	vec3 rec = hsv2rgb(vec3(hue, hsv.y, hsv.z));
	ALBEDO = mix(c, rec, painted);
	ROUGHNESS = roughness_v;
	if (has_normal) {
		NORMAL_MAP = texture(tex_normal, UV).rgb;
	}
}
