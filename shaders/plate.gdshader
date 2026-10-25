// Glossy rounded plate for app icons without artwork and for Oazy's own apps:
// a vertical gradient, an Aero gloss reflection over the top half and a soft
// rim light. Drawn on a plain ColorRect.
shader_type canvas_item;

uniform vec2 rect_size = vec2(48.0, 48.0);
uniform float radius = 12.0;
uniform vec4 color_a : source_color = vec4(0.25, 0.85, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.05, 0.35, 0.5, 1.0);
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
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, UV.y));
	// Gloss: an ellipse catching the light over the top half.
	vec2 g = (UV - vec2(0.5, 0.0)) * vec2(1.0, 1.7);
	float shine = smoothstep(0.62, 0.5, length(g)) * (1.0 - smoothstep(0.0, 0.5, UV.y));
	col += vec3(1.0) * shine * 0.22 * gloss;
	// Rim light and a little depth at the bottom.
	float line = 1.0 - smoothstep(0.0, 1.5 * px, abs(d + 0.8 * px));
	col += vec3(1.0) * line * mix(0.35, 0.05, UV.y);
	col *= 1.0 - smoothstep(0.6, 1.0, UV.y) * 0.12;
	COLOR = vec4(col, alpha * COLOR.a);
}
