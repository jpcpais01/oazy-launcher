// Circular progress ring with a gradient sweep, glowing head and soft halo.
// indeterminate > 0 turns it into a spinner.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.075;
uniform vec4 color_a : source_color = vec4(0.486, 0.424, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform vec4 track : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform float indeterminate : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.x, -p.y) / 6.28318;
	a = a < 0.0 ? a + 1.0 : a;

	float radius = 1.0 - thickness - 0.06;
	float dist = abs(r - radius);
	float aa = fwidth(r) * 1.2;
	float band = 1.0 - smoothstep(thickness * 0.5 - aa, thickness * 0.5 + aa, dist);

	float start = 0.0;
	float len = progress;
	if (indeterminate > 0.0) {
		start = fract(TIME * 0.65);
		len = 0.22 + 0.16 * sin(TIME * 2.1);
	}
	float rel = fract(a - start);
	float on = step(rel, len) * step(0.0005, len);

	vec3 grad = mix(color_a.rgb, color_b.rgb, clamp(rel / max(len, 0.001), 0.0, 1.0));
	vec4 col = vec4(track.rgb, track.a * band);
	col = mix(col, vec4(grad, 1.0), band * on);

	// Halo around the filled arc.
	float halo = exp(-dist * dist * 160.0) * on * 0.35 * glow;
	col.rgb += grad * halo;
	col.a = max(col.a, halo);

	// Bright head at the end of the arc.
	float head_a = (start + len) * 6.28318;
	vec2 head = vec2(sin(head_a), -cos(head_a)) * radius;
	float hd = length(p - head);
	float head_glow = exp(-hd * hd * 260.0) * step(0.001, len) * glow;
	col.rgb += vec3(1.0) * head_glow * 0.8;
	col.a = max(col.a, head_glow * 0.8);

	COLOR = vec4(col.rgb, col.a * COLOR.a);
}
