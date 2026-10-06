shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.02, 0.25) = 0.12;
uniform vec4 edge_color : source_color = vec4(1.8, 1.1, 0.3, 1.0);
uniform vec4 edge_color_inner : source_color = vec4(2.0, 0.5, 0.1, 1.0);

uniform float thickness : hint_range(0.5, 2.0) = 1.0;
uniform vec4 dough_modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 center = vec2(0.5, 0.32);
    vec2 diff = UV - center;
    diff.y *= 2.2;
    float dist = length(diff);

    // Эффект выпуклости (bulge) при толстом тесте
    float bulge = (thickness - 1.0) * 0.10 * (1.0 - smoothstep(0.0, 0.7, dist));
    vec2 uv = center + (UV - center) * (1.0 - bulge);

    vec4 tex_color = texture(TEXTURE, uv);
    if (tex_color.a < 0.01) {
        discard;
    }

    // Псевдо-3D светотень объема (свет падает сверху от ТЭНов печи)
    float light = 1.0;
    if (dist < 0.65) {
        float ny = -(UV.y - center.y) * 2.5;
        light += ny * (thickness - 0.8) * 0.25;
    }
    tex_color.rgb *= light;
    tex_color *= dough_modulate;

    // Огненная волна запекания
    float n = noise(UV * 12.0) * 0.18;
    float threshold = dist + n;
    float current_val = progress * 1.35;

    if (current_val <= 0.001) {
        COLOR = vec4(0.0);
    } else if (threshold > current_val + edge_width) {
        COLOR = vec4(0.0);
    } else if (threshold > current_val) {
        float edge_t = (threshold - current_val) / edge_width;
        vec4 fire_color = mix(edge_color, edge_color_inner, edge_t);
        COLOR = vec4(mix(tex_color.rgb * 1.5, fire_color.rgb, 0.75), tex_color.a);
    } else {
        COLOR = tex_color;
    }
}
