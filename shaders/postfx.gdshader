shader_type canvas_item;
// Постобработка «постапокалипсис»: цветокоррекция (холодные тени, тёплые света, обесцвечивание), виньетка, плёночное зерно,
// лёгкая хроматическая аберрация по краям. Дёшево: один проход по экрану.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float vignette = 0.3;
uniform float grain = 0.03;
uniform float aberration = 0.0012;
uniform float desat = 0.05;
uniform vec3 tint = vec3(1.0);   // цветовая гамма (профиль атмосферы)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + TIME * 3.7) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 ab = d * aberration * r2 * 6.0;
	vec3 c;
	c.r = texture(screen_tex, uv + ab).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - ab).b;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat);
	// сплит-тонирование: тени в холодный сине-зелёный, света в тёплый
	c += vec3(-0.010, 0.006, 0.014) * (1.0 - smoothstep(0.0, 0.5, l));
	c += vec3(0.020, 0.010, -0.012) * smoothstep(0.45, 1.0, l);
	c *= tint;
	c *= 1.0 - vignette * smoothstep(0.18, 0.95, r2 * 2.2);
	c += (hash(uv * vec2(1920.0, 1080.0)) - 0.5) * grain * (1.0 - l * 0.6);
	COLOR = vec4(c, 1.0);
}