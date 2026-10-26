// A picture with rounded corners (window pictures in the Alt+Tab switcher).
shader_type canvas_item;

uniform vec2 size = vec2(400.0, 250.0);
uniform float radius = 12.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * size;
	float d = sd_box(p - size * 0.5, size * 0.5, radius);
	COLOR.a *= 1.0 - smoothstep(-0.8, 0.8, d);
}
