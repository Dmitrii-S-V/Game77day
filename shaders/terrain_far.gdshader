shader_type spatial;
// Дальний ландшафт (LOD): тот же вид, что у ближнего (трава / земля / камень / песок), но дешевле.
// Внутри радиуса, где уже есть более детальный ландшафт, сетка проседает вниз и не пробивается.

uniform vec3 grass_tint = vec3(1.0);   // как у ближнего ландшафта (terrain.gdshader)
uniform vec3 grass_color = vec3(0.05, 0.085, 0.022);
uniform float grass_recolor = 0.0;
uniform sampler2D tex_grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass2 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_grass3 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_dirt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_stone : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tile = 0.2;
uniform sampler2D biome_mask : filter_linear, repeat_disable;   // BiomeMap: R — степень выжженности
uniform float biome_world = 2048.0;
uniform bool has_biome = false;
uniform sampler2D road_mask : filter_linear_mipmap, repeat_disable;   // RoadOverview: R покрытие, G материал, B тротуар, A площадка
uniform float road_ppm = 1.0;
uniform float road_px = 2048.0;
uniform bool has_roads = false;
uniform float near_radius = 0.0;   // радиус вокруг камеры, где ближний ландшафт уже построен целиком (дальняя плитка там скрыта)
varying float skirt;
uniform float sink_radius = 86.0;
uniform float sink_fade = 40.0;
uniform float sink_amount = 3.5;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wa;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(wp.xz, CAMERA_POSITION_WORLD.xz);
	float sunk = sink_amount * (1.0 - smoothstep(sink_radius, sink_radius + sink_fade, d)) * max(1.0 - UV.x, 0.0);
	// у воды (UV.y = уровень) плитка не проседает ниже воды: иначе вода парит над ней тёмной плитой
	if (UV.y > -500.0) {
		sunk = min(sunk, max(VERTEX.y - (UV.y - 0.3), 0.0));
	}
	VERTEX.y -= sunk;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	skirt = UV.x;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wa = COLOR;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 ghash(vec2 p) {
	float a = hash(p) * 6.2831853;
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
void fragment() {
	// внутри радиуса детального ландшафта дальняя плитка не рисуется совсем: иначе при копании вниз
	// игрок упирается в «плоскую текстуру» — её подпол
	if (distance(wpos.xz, CAMERA_POSITION_WORLD.xz) < min(sink_radius * 0.75, near_radius)) {
		discard;
	}
	vec3 n = normalize(wnrm);
	vec3 p = wpos * tile;
	float wg = wa.r;
	float wd = wa.g;
	float ws = wa.b;
	float wsa = wa.a;
	float up = clamp(n.y, 0.0, 1.0);
	float grass_ok = smoothstep(0.6, 0.85, up);
	wd += wg * (1.0 - grass_ok);
	wg *= grass_ok;
	float steep = 1.0 - smoothstep(0.5, 0.78, up);
	ws += (wg + wd + wsa) * steep;
	wg *= 1.0 - steep;
	wd *= 1.0 - steep;
	wsa *= 1.0 - steep;
	wg = smoothstep(0.02, 0.98, wg);
	wd = smoothstep(0.02, 0.98, wd);
	ws = smoothstep(0.02, 0.98, ws);
	wsa = smoothstep(0.02, 0.98, wsa);
	float sum = wg + wd + ws + wsa + 0.0001;
	// на расстоянии трипланар не нужен: достаточно проекции сверху и со стороны по доминирующей оси
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 col = vec3(0.0);
	// те же три травы и тот же шум, что у ближнего ландшафта — цвет на стыке уровней не прыгает
	vec2 q = p.xz;
	float m1 = smoothstep(0.25, 0.75, gnoise(wpos.xz * 0.06 + 2.0));
	float m2 = smoothstep(0.45, 0.95, gnoise(wpos.xz * 0.031 + 17.0));
	vec3 g = mix(mix(mix(texture(tex_grass, q).rgb, texture(tex_grass, q * 0.29 + 0.13).rgb, 0.35),
		mix(texture(tex_grass2, q * 0.77 + 0.31).rgb, texture(tex_grass2, q * 0.22 + 0.2).rgb, 0.35), m1),
		mix(texture(tex_grass3, q * 0.9 + 0.57).rgb, texture(tex_grass3, q * 0.26 + 0.4).rgb, 0.35), m2 * 0.85);
	g *= grass_tint;
	if (grass_recolor > 0.0) {
		float lref = mix(mix(0.048, 0.205, m1), 0.208, m2 * 0.85);
		float sh = clamp(dot(g, vec3(0.299, 0.587, 0.114)) / (lref * dot(grass_tint, vec3(0.333))), 0.45, 1.7);
		g = mix(g, grass_color * sh, grass_recolor);
	}
	vec3 d = mix(texture(tex_dirt, q).rgb, texture(tex_dirt, q * 0.29 + 0.13).rgb, 0.35);
	vec3 s = texture(tex_stone, p.zy).rgb * b.x + texture(tex_stone, p.xz).rgb * b.y + texture(tex_stone, p.xy).rgb * b.z;
	vec3 sa = texture(tex_sand, p.xz).rgb;
	col = (g * wg + d * wd + s * ws + sa * wsa) / sum;
	float macro = mix(0.78, 1.15, gnoise(wpos.xz * 0.045 + 3.0) * 0.6 + gnoise(wpos.xz * 0.2 + 9.0) * 0.4);
	col *= macro;
	if (has_biome && skirt < 0.05) {
		float bn = texture(biome_mask, wpos.xz / biome_world).r;
		if (bn > 0.01) {
			float l = dot(col, vec3(0.299, 0.587, 0.114));
			float soot = gnoise(wpos.xz * 0.23 + 40.0) * 0.6 + gnoise(wpos.xz * 1.3) * 0.4;
			vec3 ash = vec3(l) * vec3(0.62, 0.57, 0.53) * mix(0.6, 1.15, soot);
			ash = mix(ash, vec3(0.025, 0.022, 0.02), smoothstep(0.62, 0.8, gnoise(wpos.xz * 0.11 + 9.0)) * 0.8);
			col = mix(col, ash, clamp(bn * 0.92, 0.0, 1.0));
		}
	}
	float rough = 0.95;
	if (has_roads && skirt < 0.05) {
		vec2 ruv = wpos.xz * road_ppm / road_px;
		if (ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0) {
			vec4 rm = textureLod(road_mask, ruv, 0.0);
			float cover = smoothstep(0.3, 0.7, max(rm.r, rm.a));
			float walk = smoothstep(0.3, 0.7, rm.b) * (1.0 - cover);
			if (cover > 0.001 || walk > 0.001) {
				float n1 = gnoise(wpos.xz * 0.35);
				float n2 = gnoise(wpos.xz * 1.7 + 11.0);
				float k = rm.g * 3.0;
				vec3 asph = vec3(0.11, 0.112, 0.118) * (0.8 + 0.5 * n1);
				vec3 conc = vec3(0.40, 0.375, 0.33) * (0.85 + 0.3 * n2);
				vec3 grav = vec3(0.20, 0.185, 0.165) * (0.8 + 0.5 * n1);
				vec3 sand = vec3(0.24, 0.19, 0.13) * (0.8 + 0.5 * n1);
				vec3 rc = k < 0.5 ? asph : (k < 1.5 ? conc : (k < 2.5 ? grav : sand));
				if (rm.a > rm.r) rc = conc;
				col = mix(col, vec3(0.38, 0.36, 0.32) * (0.85 + 0.3 * n2), walk * 0.9);
				col = mix(col, rc, cover);
				rough = mix(rough, 0.82, cover);
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
