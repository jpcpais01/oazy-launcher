// The Cleaner's glass orb: a bubble of liquid glass filled to `level` with
// gently moving water, light caustics and rising bubbles, a rim of light and
// an outer ring that sweeps while scanning. One pass, a handful of sines.
shader_type canvas_item;

uniform float level : hint_range(0.0, 1.0) = 0.6;
uniform float scanning : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_a : source_color = vec4(0.22, 0.84, 0.77, 1.0);
uniform vec4 color_b : source_color = vec4(0.16, 0.45, 0.95, 1.0);
uniform float calm : hint_range(0.0, 1.0) = 0.0;

float hash(float n) { return fract(sin(n * 91.345) * 47453.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float px = fwidth(r);
	float t = TIME * mix(1.0, 0.35, calm);
	float R = 0.78;

	// Liquid inside the sphere.
	float fill = mix(0.86, -0.86, clamp(level, 0.0, 1.0));
	float wave = sin(p.x * 4.6 + t * 1.7) * 0.035 + sin(p.x * 9.0 - t * 2.4) * 0.014;
	wave *= mix(1.0, 2.2, scanning);
	float surf = fill + wave;
	float inside = 1.0 - smoothstep(R - px, R + px, r);
	float water = smoothstep(surf - px * 1.5, surf + px * 1.5, p.y) * inside;

	float depth = clamp((p.y - surf) / max(0.001, 1.0 - surf), 0.0, 1.0);
	vec3 liquid = mix(color_a.rgb * 1.15, color_b.rgb * 0.7, depth);
	// Caustics: two crossing ripples, brighter near the surface.
	float c = sin(p.x * 11.0 + t * 1.3 + sin(p.y * 7.0 - t)) * sin(p.y * 13.0 - t * 1.1 + sin(p.x * 5.0));
	liquid += vec3(0.9, 1.0, 1.0) * smoothstep(0.55, 1.0, c) * 0.14 * (1.0 - depth * 0.6);
	// The meniscus catches the light.
	float line = 1.0 - smoothstep(0.0, 0.035, abs(p.y - surf));
	liquid += vec3(1.0) * line * 0.55 * inside;

	// A few bubbles drifting up.
	float bub = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float speed = 0.09 + hash(fi) * 0.08;
		float y = 0.85 - fract(t * speed + hash(fi + 3.0)) * 1.7;
		float x = (hash(fi + 7.0) - 0.5) * 1.0 + sin(t * 1.4 + fi) * 0.04;
		float s = 0.018 + hash(fi + 11.0) * 0.022;
		float d = length(p - vec2(x, y));
		bub += (1.0 - smoothstep(s - px, s + px, d)) * (0.35 + 0.65 * smoothstep(s * 0.4, s, d)) * step(surf, y);
	}
	liquid += vec3(1.0) * bub * 0.35;

	// Empty glass above the water: a faint tint and depth.
	vec3 glass = mix(vec3(0.75, 0.9, 1.0), color_a.rgb, 0.3) * 0.08;
	vec3 col = mix(glass, liquid, water);
	float alpha = inside * mix(0.22, 0.92, water);

	// Rim light and specular highlight make it read as a sphere.
	float rim = smoothstep(R * 0.72, R, r) * inside;
	col += vec3(0.85, 0.95, 1.0) * rim * 0.32;
	alpha = max(alpha, rim * 0.5);
	vec2 hp = (p - vec2(-0.3, -0.38)) * vec2(1.0, 1.6);
	float spec = exp(-dot(hp, hp) * 26.0);
	col += vec3(1.0) * spec * 0.55;
	alpha = max(alpha, spec * 0.6 * inside);
	float edge = 1.0 - smoothstep(0.0, px * 1.6, abs(r - R));
	col = mix(col, vec3(1.0), edge * 0.35);
	alpha = max(alpha, edge * 0.45);

	// Outer ring: the level as an arc, or a sweeping comet while scanning.
	float ring_r = 0.93;
	float dist = abs(r - ring_r);
	float band = 1.0 - smoothstep(0.012 - px, 0.012 + px, dist);
	float a = atan(p.x, -p.y) / 6.28318;
	a = a < 0.0 ? a + 1.0 : a;
	float arc = step(a, level);
	float sweep = pow(fract(a - t * 0.55), 6.0);
	float lit = mix(arc, sweep, scanning);
	vec3 ring_col = mix(color_a.rgb, color_b.rgb, a);
	vec4 ring = vec4(mix(vec3(1.0), ring_col, lit), band * mix(0.08, 1.0, lit));
	float halo = exp(-dist * dist * 900.0) * lit * 0.4;
	col = mix(col, ring.rgb, ring.a * (1.0 - inside));
	alpha = max(alpha, ring.a);
	col += ring_col * halo * (1.0 - inside);
	alpha = max(alpha, halo);

	// Soft glow under the sphere.
	float glow = exp(-pow(max(r - R, 0.0) * 7.0, 2.0)) * (1.0 - inside) * 0.22 * (0.5 + 0.5 * level);
	col += color_a.rgb * glow;
	alpha = max(alpha, glow);

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0) * COLOR.a);
}
