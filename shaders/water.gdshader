shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Вода: реки, озёра, море. Прозрачность растёт с глубиной, мягкий берег, рябь, лёгкое течение.

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.38, 0.42);
uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.2);
uniform float flow_speed = 0.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ripple(vec2 p) {
	float t = TIME * flow_speed;
	return vnoise(p * 0.9 + vec2(t, t * 0.7)) * 0.6 + vnoise(p * 2.3 - vec2(t * 1.3, t)) * 0.4;
}

void fragment() {
	float e = 0.12;
	vec2 p = wpos.xz;
	float h0 = ripple(p);
	float hx = ripple(p + vec2(e, 0.0));
	float hz = ripple(p + vec2(0.0, e));
	float amp = 0.9 / (1.0 + length(VERTEX) * 0.05);
	vec3 nw = normalize(vec3((h0 - hx) * amp, 1.0, (h0 - hz) * amp));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float diff = max((-view.z) - (-VERTEX.z), 0.0);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float t = clamp(diff * 0.45, 0.0, 1.0);
	ALBEDO = mix(shallow_color, deep_color, t);
	ALPHA = clamp(mix(0.12, 0.88, t) + fres * 0.3, 0.0, 0.95);
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
