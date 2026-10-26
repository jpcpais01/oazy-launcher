// Shade over the desktop's game banner: dark on the left where the words sit
// and along the bottom where the covers sit, clipped to the rounded card.
shader_type canvas_item;

uniform vec2 rect_size = vec2(600.0, 250.0);
uniform float radius = 28.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 hs = rect_size * 0.5;
	float d = sd_box(UV * rect_size - hs, hs, min(radius, min(hs.x, hs.y)));
	float mask = clamp(0.5 - d / max(fwidth(d), 0.0001), 0.0, 1.0);
	float left = 0.8 * pow(1.0 - smoothstep(0.0, 0.78, UV.x), 1.3);
	float bottom = 0.6 * smoothstep(0.5, 1.0, UV.y);
	float a = 1.0 - (1.0 - left) * (1.0 - bottom);
	// Times COLOR.a so the shade fades with the desktop instead of popping off.
	COLOR = vec4(0.01, 0.03, 0.05, a * mask * COLOR.a);
}
