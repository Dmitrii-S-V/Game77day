shader_type spatial;
// Растения: цвета вершин (листва, кусты, камни) + текстура коры на «коричневых» вершинах (стволы, ветки).

uniform sampler2D tex_bark : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_bark_n : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool has_bark_n = false;
uniform float bark_scale = 1.1;
uniform vec3 tint = vec3(1.0);    // множитель цвета (обугленные деревья)
uniform float far_cut = 0.0;
uniform float far_end = 0.0;   // >0: не рисуется дальше far_end м (передаёт эстафету следующему уровню LOD)   // >0: дальняя версия (FarProps) — не рисуется ближе far_cut м (там стоит обычное дерево)
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

varying vec3 lp;
varying vec3 ln;
varying vec4 vc;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vc = COLOR;
	vdist = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz, CAMERA_POSITION_WORLD.xz);
}

void fragment() {
	if ((far_cut > 0.0 || far_end > 0.0) && !lod_keep(vdist, far_cut, far_end, lod_noise(FRAGCOORD.xy))) {
		discard;
	}
	vec3 col = pow(vc.rgb, vec3(2.2));
	float trunk = smoothstep(0.0, 0.07, vc.r - vc.g) * smoothstep(0.0, 0.05, vc.r - vc.b);
	if (trunk > 0.01) {
		vec3 n = abs(normalize(ln));
		vec3 b = pow(n, vec3(4.0));
		b /= (b.x + b.y + b.z);
		vec3 p = lp * bark_scale;
		vec3 bark = texture(tex_bark, p.zy).rgb * b.x + texture(tex_bark, p.xz).rgb * b.y + texture(tex_bark, p.xy).rgb * b.z;
		col = mix(col, bark * (0.45 + vc.r * 1.1), trunk);
		if (has_bark_n) {
			// трипланарная карта нормалей коры (в координатах модели): рельеф борозд
			vec3 nn = normalize(ln);
			vec2 nx = texture(tex_bark_n, p.zy).xy * 2.0 - 1.0;
			vec2 ny = texture(tex_bark_n, p.xz).xy * 2.0 - 1.0;
			vec2 nz = texture(tex_bark_n, p.xy).xy * 2.0 - 1.0;
			vec3 off = vec3(0.0, nx.y, nx.x) * b.x + vec3(ny.x, 0.0, ny.y) * b.y + vec3(nz.x, nz.y, 0.0) * b.z;
			vec3 nobj = normalize(nn + off * 1.1 * trunk);
			NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nobj, 0.0)).xyz);
		}
	}
	ALBEDO = col * tint;
	ROUGHNESS = 0.95;
}
