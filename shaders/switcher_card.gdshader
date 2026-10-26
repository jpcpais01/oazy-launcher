// One card of the Alt+Tab carousel: a rounded pane with a hairline rim, a
// soft shadow (or accent glow when selected) and a clear window where the
// live preview shows. Windows draws previews under a layer's own pixels, so
// the pane has to leave that spot see-through.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 size = vec2(400.0, 260.0);
uniform float pad = 60.0;
uniform float radius = 24.0;
uniform vec4 fill : source_color = vec4(0.07, 0.09, 0.11, 0.97);
uniform vec4 rim : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform float rim_w = 1.0;
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.45);
uniform float glow_size = 26.0;
uniform float glow_drop = 12.0;
// x, y, w, h in card pixels; w = 0 means no preview.
uniform vec4 hole = vec4(0.0);
uniform float hole_radius = 12.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * (size + 2.0 * pad) - pad;
	float d = sd_box(p - size * 0.5, size * 0.5, radius);
	float aa = max(fwidth(d), 0.6);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = inside * (1.0 - smoothstep(rim_w - aa, rim_w + aa, -d));
	vec3 col = mix(fill.rgb, rim.rgb, edge * rim.a);
	float a = max(fill.a, edge * rim.a) * inside;
	if (hole.z > 0.0) {
		float hd = sd_box(p - (hole.xy + hole.zw * 0.5), hole.zw * 0.5, hole_radius);
		a *= smoothstep(-aa, aa, hd);
	}
	float gd = sd_box(p - size * 0.5 - vec2(0.0, glow_drop), size * 0.5, radius);
	float g = glow.a * exp(-max(gd, 0.0) / max(glow_size, 1.0) * 2.2) * (1.0 - inside);
	vec3 out_col = (col * a + glow.rgb * g) / max(a + g, 0.0001);
	COLOR = vec4(out_col, a + g);
}
