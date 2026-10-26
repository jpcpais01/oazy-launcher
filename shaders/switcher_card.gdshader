// One card of the Alt+Tab carousel: a rounded pane with a hairline rim, a soft
// drop shadow and, on the selected card, a thin focus ring just outside.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 size = vec2(400.0, 260.0);
uniform float pad = 60.0;
uniform float radius = 18.0;
uniform vec4 fill : source_color = vec4(0.07, 0.08, 0.1, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 1.0, 1.0, 0.07);
// The ring around the selected card: its colour (alpha 0 for none), width
// and gap from the card, in card pixels.
uniform vec4 ring : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float ring_w = 2.0;
uniform float ring_gap = 5.0;
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
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = inside * (1.0 - smoothstep(1.0 - aa, 1.0 + aa, -d));
	vec3 col = mix(fill.rgb, rim.rgb, edge * rim.a);
	float a = fill.a * inside;
	float rd = abs(d - ring_gap - ring_w * 0.5) - ring_w * 0.5;
	float r = ring.a * (1.0 - smoothstep(-aa, aa, rd));
	float sd = sd_box(p - size * 0.5 - vec2(0.0, shadow_drop), size * 0.5, radius);
	float s = shadow_a * exp(-max(sd, 0.0) / max(shadow_size, 1.0) * 2.2) * (1.0 - inside) * (1.0 - r);
	vec3 out_col = (col * a + ring.rgb * r) / max(a + r, 0.0001);
	float out_a = a + r + s * (1.0 - a - r);
	out_col = out_col * (a + r) / max(out_a, 0.0001);
	COLOR = vec4(out_col, out_a * COLOR.a);
}
