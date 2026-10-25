// The Oazy wallpaper as a function, shared by the wallpaper itself and by glass
// in shell mode, which draws the bit of wallpaper behind it instead of reading
// the screen (Oazy's layers are separate windows there).
//
// A deep base colour with a few large, soft pools of colour drifting very
// slowly: water, sand and sky, never busy.

uniform vec4 wall_base : source_color = vec4(0.03, 0.05, 0.08, 1.0);
uniform vec4 wall_a : source_color = vec4(0.1, 0.2, 0.36, 1.0);
uniform vec4 wall_b : source_color = vec4(0.05, 0.3, 0.32, 1.0);
uniform vec4 wall_c : source_color = vec4(0.5, 0.36, 0.26, 1.0);
uniform vec4 wall_glow : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.2, 0.82, 0.76, 1.0);
uniform float aspect = 1.7778;
uniform float focus_center : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 4.0) = 1.0;

float wall_pool(vec2 p, vec2 c, float r) {
	vec2 d = (p - c) / r;
	return exp(-dot(d, d));
}

vec3 wall_color(vec2 uv, float time) {
	float t = time * 0.02 * speed;
	vec2 p = vec2(uv.x * aspect, uv.y);
	// A gentle warp keeps the pools organic rather than perfectly round.
	p += 0.05 * vec2(sin(p.y * 2.3 + t * 1.7), cos(p.x * 1.9 - t * 1.3));
	vec3 col = wall_base.rgb;
	vec2 ca = vec2(aspect * (0.22 + 0.05 * sin(t * 0.9)), 0.28 + 0.06 * cos(t * 0.7));
	vec2 cb = vec2(aspect * (0.78 + 0.05 * cos(t * 0.8)), 0.32 + 0.07 * sin(t * 1.1 + 1.0));
	vec2 cc = vec2(aspect * (0.52 + 0.08 * sin(t * 0.6 + 2.0)), 1.02 + 0.04 * cos(t * 0.9));
	vec2 cd = vec2(aspect * (0.08 + 0.04 * cos(t * 0.5)), 0.95);
	ca = mix(ca, vec2(aspect * 0.5, 0.42), focus_center * 0.6);
	col = mix(col, wall_a.rgb, wall_pool(p, ca, 0.62) * 0.85);
	col = mix(col, wall_b.rgb, wall_pool(p, cb, 0.58) * 0.8);
	col = mix(col, wall_c.rgb, wall_pool(p, cc, 0.55) * 0.55);
	col = mix(col, accent.rgb * 0.55, wall_pool(p, cd, 0.4) * 0.35);
	// Soft light from above.
	col += wall_glow.rgb * exp(-uv.y * uv.y * 5.0) * 0.035;
	vec2 vc = uv - vec2(0.5, 0.45);
	col *= 1.0 - dot(vc, vc) * 0.45;
	return col;
}
