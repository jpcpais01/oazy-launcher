// One card of the Alt+Tab carousel: a rounded pane with a soft drop shadow.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 size = vec2(400.0, 260.0);
uniform float pad = 60.0;
uniform float radius = 18.0;
uniform vec4 fill : source_color = vec4(0.07, 0.08, 0.1, 1.0);
uniform float shadow_a = 0.34;
uniform float shadow_size = 32.0;
uniform float shadow_drop = 12.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * (size + 2.0 * pad) - pad;
	float d = sd_box(p - size * 0.5, size * 0.5, radius);
	float aa = max(fwidth(d), 0.6);
	float a = fill.a * (1.0 - smoothstep(-aa, aa, d));
	float sd = sd_box(p - size * 0.5 - vec2(0.0, shadow_drop), size * 0.5, radius);
	float s = shadow_a * exp(-max(sd, 0.0) / max(shadow_size, 1.0) * 2.2);
	float out_a = a + s * (1.0 - a);
	COLOR = vec4(fill.rgb * a / max(out_a, 0.0001), out_a * COLOR.a);
}
