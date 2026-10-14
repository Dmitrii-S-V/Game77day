shader_type spatial;
// Валуны: фототекстура породы (цвет + нормаль) трипланарно в координатах модели — рисунок «прилипает» к камню
// и не плывёт; сверху — мох/земля по нормали, снизу у земли — затемнение. Вершинный цвет модели слегка тонирует.

uniform sampler2D tex_rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rock_n : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_moss : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float rock_scale = 0.55;
uniform float far_cut = 0.0;
uniform float far_end = 0.0;
uniform float fade_w = 16.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 wn;
varying vec4 vc;
varying float vdist;
varying vec3 seedv;

float lod_noise(vec2 fc) {
	return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
}

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

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vc = COLOR;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	seedv = fract(o * vec3(0.137, 0.0, 0.291));
	vdist = distance(o.xz, CAMERA_POSITION_WORLD.xz);
}

void fragment() {
	if ((far_cut > 0.0 || far_end > 0.0) && !lod_keep(vdist, far_cut, far_end, lod_noise(FRAGCOORD.xy))) {
		discard;
	}
	vec3 n = normalize(ln);
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	// сдвиг по экземпляру: у соседних камней разный участок текстуры
	vec3 p = lp * rock_scale + seedv * 7.0;
	vec3 c = texture(tex_rock, p.zy).rgb * b.x + texture(tex_rock, p.xz).rgb * b.y + texture(tex_rock, p.xy).rgb * b.z;
	vec3 c2 = texture(tex_rock, p.zy * 0.31 + 0.2).rgb * b.x + texture(tex_rock, p.xz * 0.31 + 0.2).rgb * b.y + texture(tex_rock, p.xy * 0.31 + 0.2).rgb * b.z;
	vec3 col = mix(c, c2, 0.3);
	float tone = dot(pow(vc.rgb, vec3(2.2)), vec3(0.333));
	col *= clamp(0.95 + tone * 1.4, 0.95, 1.3);
	// мох и пыль на верхних гранях, тёмная влажная кромка у земли
	float top = smoothstep(0.55, 0.9, normalize(wn).y);
	vec3 moss = texture(tex_moss, p.xz * 0.8).rgb * vec3(0.8, 0.9, 0.7);
	float mmask = top * smoothstep(0.35, 0.7, texture(tex_rock, p.xz * 0.17).g + 0.15);
	col = mix(col, moss, mmask * 0.55);
	col *= mix(0.6, 1.0, smoothstep(-0.05, 0.35, lp.y));
	vec2 nx = texture(tex_rock_n, p.zy).xy * 2.0 - 1.0;
	vec2 ny = texture(tex_rock_n, p.xz).xy * 2.0 - 1.0;
	vec2 nz = texture(tex_rock_n, p.xy).xy * 2.0 - 1.0;
	vec3 off = vec3(0.0, nx.y, nx.x) * b.x + vec3(ny.x, 0.0, ny.y) * b.y + vec3(nz.x, nz.y, 0.0) * b.z;
	vec3 nobj = normalize(n + off * 1.2);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nobj, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.95, mmask);
}
