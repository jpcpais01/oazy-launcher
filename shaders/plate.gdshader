// Rounded plate for app icons without artwork and for Oazy's own apps: a soft
// diagonal gradient with a hairline rim of light along the top. Drawn on a
// plain ColorRect.
shader_type canvas_item;

uniform vec2 rect_size = vec2(48.0, 48.0);
uniform float radius = 12.0;
uniform vec4 color_a : source_color = vec4(0.25, 0.85, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.05, 0.35, 0.5, 1.0);
// Kept for callers; the plate no longer has a glossy highlight.
uniform float gloss : hint_range(0.0, 1.0) = 1.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 hs = rect_size * 0.5;
	vec2 p = UV * rect_size - hs;
	float d = sd_box(p, hs, min(radius, min(hs.x, hs.y)));
	float px = max(fwidth(d), 0.0001);
	float alpha = clamp(0.5 - d / px, 0.0, 1.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, UV.y * 0.75 + UV.x * 0.25));
	float line = 1.0 - smoothstep(0.0, 1.4 * px, abs(d + 0.8 * px));
	col += vec3(1.0) * line * mix(0.28, 0.0, smoothstep(0.0, 0.6, UV.y));
	COLOR = vec4(col, alpha * COLOR.a);
}
