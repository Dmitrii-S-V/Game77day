shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Жидкость в сосуде: всё, что выше горизонтальной плоскости (в мировых координатах), отсекается.
// Так уровень воды остаётся горизонтальным, как бы ни наклонялась бутылка.

uniform vec3 plane_point = vec3(0.0);
uniform vec3 plane_normal = vec3(0.0, 1.0, 0.0);
uniform vec4 liquid_color : source_color = vec4(0.28, 0.55, 0.78, 0.62);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = dot(wpos - plane_point, normalize(plane_normal));
	if (d > 0.0) {
		discard;
	}
	// у самой поверхности — светлая кромка
	float edge = smoothstep(0.006, 0.0, -d);
	ALBEDO = mix(liquid_color.rgb, vec3(0.75, 0.9, 1.0), edge * 0.7);
	ALPHA = mix(liquid_color.a, 0.9, edge);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.8;
}
