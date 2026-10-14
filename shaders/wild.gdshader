shader_type spatial;
render_mode cull_disabled;
// Дикие растения из атласов (tools/cut_flora.gd): трава разных видов, цветы, сухие кусты и трава, борщевик.
// Перекрёстные карточки; ячейка атласа — INSTANCE_CUSTOM.w * 255, оттенок — .x, «сухость» — .y (желтит зелёное).
// Дальше fade_start карточки уменьшаются до нуля (без «выскакивания»), на ветру качаются верхушки.

uniform sampler2D tex_atlas : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform vec2 grid = vec2(9.0, 8.0);
uniform float fade_start = 40.0;
uniform float fade_end = 56.0;
uniform float cutoff = 0.45;
uniform float sway = 0.1;

varying float vh;
varying float vt;
varying float vdry;
varying float vburn;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.w * 255.0 + 0.5);
	vec2 c = vec2(mod(cell, grid.x), floor(cell / grid.x));
	vh = 1.0 - UV.y;
	UV = (UV + c) / grid;
	vt = INSTANCE_CUSTOM.x;
	vdry = INSTANCE_CUSTOM.y;
	vburn = INSTANCE_CUSTOM.z;
	vec3 wo = MODEL_MATRIX[3].xyz;
	float d = distance(wo.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX.y *= fade;
	VERTEX.xz *= mix(0.6, 1.0, fade);
	float t = TIME;
	vec3 off = vec3(sin(t * 1.6 + wo.x * 0.8 + wo.z * 0.6), 0.0, cos(t * 1.3 + wo.z * 0.7 + wo.x * 0.4)) * sway * vh * vh * fade;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	vec4 tx = texture(tex_atlas, UV);
	if (tx.a < cutoff) {
		discard;
	}
	vec3 col = tx.rgb;
	// белая кайма от фона исходной картинки: почти белые малонасыщенные пиксели — прочь
	float mxc = max(col.r, max(col.g, col.b));
	float mnc = min(col.r, min(col.g, col.b));
	if (mnc > 0.6 && (mxc - mnc) < 0.22 * mxc) {
		discard;
	}
	// пожухлость: зелёное уходит в солому (у обочин и в сухих местах)
	float l = dot(col, vec3(0.333));
	col = mix(col, vec3(l * 1.15, l * 1.0, l * 0.68), vdry * 0.55);
	// выжженная земля: обугленные растения — тёмные серо-бурые, как пепел вокруг (не оранжевые)
	float lb = dot(col, vec3(0.333));
	col = mix(col, vec3(lb) * vec3(0.55, 0.5, 0.46) * 0.7, smoothstep(0.2, 0.7, vburn));
	col *= vt;
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.35, vh));   // у корня темнее
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // мягкое освещение «сверху»
	BACKLIGHT = col * 0.25;
}
