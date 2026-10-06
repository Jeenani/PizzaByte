shader_type canvas_item;

uniform float thickness : hint_range(0.5, 2.0) = 1.0;
uniform vec4 dough_modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 center = vec2(0.5, 0.32);
    vec2 diff = UV - center;
    diff.y *= 2.2;
    float dist = length(diff);

    // Эффект выпуклости (bulge) при толстом тесте
    float bulge = (thickness - 1.0) * 0.10 * (1.0 - smoothstep(0.0, 0.7, dist));
    vec2 uv = center + (UV - center) * (1.0 - bulge);

    vec4 col = texture(TEXTURE, uv);
    if (col.a < 0.01) {
        discard;
    }

    // Псевдо-3D светотень объема (свет падает сверху от ТЭНов печи)
    float light = 1.0;
    if (dist < 0.65) {
        float ny = -(UV.y - center.y) * 2.5;
        light += ny * (thickness - 0.8) * 0.25;
    }

    col.rgb *= light;
    col *= dough_modulate;
    COLOR = col;
}
