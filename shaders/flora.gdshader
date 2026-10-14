shader_type spatial;
render_mode cull_disabled;
// Флора из декалей природы: карточки (растения, камни) и плоские пятна на земле. Атлас 8x4 (assets/textures/flora.png).
// INSTANCE_CUSTOM.w — номер ячейки / 31, .x — оттенок (0.85..1.15). Дальше fade_start карточки уменьшаются до нуля.

uniform sampler2D tex_flora : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform float fade_start = 40.0;
uniform float fade_end = 56.0;
uniform float cutoff = 0.42;
uniform float sway = 1.0;       // 0 — для плоских пятен
uniform float ground_mix = 0.0; // подмешать цвет земли для пятен (0..1)

varying float vh;
varying float vt;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.w * 31.0 + 0.5);
	vec2 c = vec2(mod(cell, 8.0), floor(cell / 8.0));
	vh = 1.0 - UV.y;
	UV = (UV + c) * vec2(0.125, 0.25);
	vt = INSTANCE_CUSTOM.x;
	vec3 wo = MODEL_MATRIX[3].xyz;
	float d = distance(wo.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	if (sway > 0.0) {
		VERTEX.y *= fade;
		VERTEX.xz *= mix(0.6, 1.0, fade);
		float t = TIME;
		vec3 off = vec3(sin(t * 1.5 + wo.x * 0.8 + wo.z * 0.6), 0.0, cos(t * 1.2 + wo.z * 0.7 + wo.x * 0.4)) * 0.07 * vh * vh * fade * sway;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	} else {
		VERTEX.xz *= mix(0.4, 1.0, fade);
	}
}

void fragment() {
	vec4 tx = texture(tex_flora, UV);
	if (tx.a < cutoff) {
		discard;
	}
	vec3 col = tx.rgb * vt;
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.4, vh));
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.1;
	if (sway > 0.0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}
