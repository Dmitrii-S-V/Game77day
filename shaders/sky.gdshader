shader_type sky;
// Небо: градиент по времени суток, солнечный и лунный диски с ореолом, звёзды (по ночам), облачная дымка у горизонта.
uniform vec3 top_color : source_color = vec3(0.34, 0.40, 0.46);
uniform vec3 horizon_color : source_color = vec3(0.58, 0.62, 0.64);
uniform vec3 ground_color : source_color = vec3(0.2, 0.22, 0.24);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float night = 0.0;       // 0 день .. 1 глубокая ночь
uniform float sun_power = 1.0;
// профиль атмосферы (Atmosphere, панель F6)
uniform float sky_curve = 0.42;
uniform float stars = 1.0;
uniform float sun_size = 1.0;
uniform float sun_glow = 1.0;
uniform float moon_size = 1.0;
uniform float moon_glow = 1.0;
uniform vec3 moon_tint : source_color = vec3(0.82, 0.86, 0.95);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		// выраженный градиент: светлая дымка у горизонта быстро уходит в насыщенный цвет зенита
		col = mix(horizon_color, top_color, smoothstep(0.0, 1.0, pow(clamp(h, 0.0, 1.0), sky_curve)));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.35, -h));
	}
	// звёзды
	if (stars > 0.01 && h > -0.05) {
		vec3 sp = floor(d * 380.0);
		float s = hash13(sp);
		float star = step(0.9965, s) * (0.5 + 0.5 * hash13(sp + 7.0));
		col += vec3(0.85, 0.9, 1.0) * star * stars * smoothstep(0.0, 0.25, h) * 1.6;
	}
	// солнце
	float sd = dot(d, normalize(sun_dir));
	// чёткий диск, тёплый ореол и широкое мягкое свечение вокруг солнца
	// размер диска: угол ~ sqrt(1 - cos); масштаб размера — по углу
	float sr = 1.0 - sd;
	float disk = 1.0 - smoothstep(0.00025 * sun_size * sun_size, 0.00045 * sun_size * sun_size, sr);
	col += vec3(1.0, 0.92, 0.78) * disk * 14.0 * sun_power;
	col += vec3(1.0, 0.86, 0.62) * (pow(max(sd, 0.0), 600.0) * 1.2 + pow(max(sd, 0.0), 60.0) * 0.45 + pow(max(sd, 0.0), 8.0) * 0.12) * sun_power * sun_glow;
	// луна: диск с лёгким рельефом и ореол
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	if (mdot > 0.0) {
		float mr = 1.0 - mdot;
		float disk = 1.0 - smoothstep(0.00035 * moon_size * moon_size, 0.00065 * moon_size * moon_size, mr);
		vec3 up = abs(md.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 tx = normalize(cross(up, md));
		vec3 ty = cross(md, tx);
		vec2 q = vec2(dot(d, tx), dot(d, ty)) * 38.0 / moon_size;
		float maria = 0.75 + 0.25 * sin(q.x * 4.0 + sin(q.y * 5.0) * 1.5) * sin(q.y * 3.0 + 1.0);
		col += moon_tint * disk * maria * 3.2 * night;
		col += moon_tint * vec3(0.45, 0.55, 0.75) * pow(mdot, 120.0 / (moon_size * moon_size)) * 0.55 * night * moon_glow;
	}
	COLOR = col;
}