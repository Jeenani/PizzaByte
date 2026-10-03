shader_type canvas_item;

uniform sampler2D tex_off : hint_default_black;
uniform vec4 seg_p1 = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 seg_p2 = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 seg_p3 = vec2(1.0, 1.0);
uniform float global_power = 1.0;

float seg_w(float px, float x0, float x1, float f) {
	return smoothstep(x0 - f, x0 + f, px) * (1.0 - smoothstep(x1 - f, x1 + f, px));
}

void fragment() {
	vec4 c_on = texture(TEXTURE, UV);
	vec4 c_off = texture(tex_off, UV);
	
	float px = UV.x * 550.0;
	float p = 1.0;
	
	// Вклад каждого сегмента с мягким переходом:
	// 0: Slice (54..195)
	p += (seg_p1.x - 1.0) * seg_w(px, 54.0, 195.0, 4.0);
	// 1: P (200..235)
	p += (seg_p1.y - 1.0) * seg_w(px, 200.0, 235.0, 3.0);
	// 2: I (235..255)
	p += (seg_p1.z - 1.0) * seg_w(px, 235.0, 255.0, 3.0);
	// 3: Z1 (255..295)
	p += (seg_p1.w - 1.0) * seg_w(px, 255.0, 295.0, 3.0);
	// 4: Z2 (295..335)
	p += (seg_p2.x - 1.0) * seg_w(px, 295.0, 335.0, 3.0);
	// 5: A (335..368)
	p += (seg_p2.y - 1.0) * seg_w(px, 335.0, 368.0, 3.0);
	// 6: B (372..410)
	p += (seg_p2.z - 1.0) * seg_w(px, 372.0, 410.0, 3.0);
	// 7: Y (410..430)
	p += (seg_p2.w - 1.0) * seg_w(px, 410.0, 430.0, 3.0);
	// 8: T (430..480)
	p += (seg_p3.x - 1.0) * seg_w(px, 430.0, 480.0, 3.0);
	// 9: E (480..515)
	p += (seg_p3.y - 1.0) * seg_w(px, 480.0, 515.0, 3.0);
	
	p *= global_power;
	p = clamp(p, 0.0, 1.2);
	vec4 col = mix(c_off, c_on, p);

	// Мягкое размытие/растворение краев прямоугольника в фон корпуса автомата
	float edge_fade_x = smoothstep(0.0, 0.04, UV.x) * (1.0 - smoothstep(0.96, 1.0, UV.x));
	float edge_fade_y = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	col.a *= edge_fade_x * edge_fade_y;

	COLOR = col;
}
