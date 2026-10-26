// The Oazy wallpapers as one function, shared by the wallpaper itself and by
// glass in shell mode, which draws the bit of wallpaper behind it instead of
// reading the screen (Oazy's layers are separate windows there).
//
// Every style paints with the same palette (which follows the time of day)
// and moves very slowly; `wall_style` picks one:
//   0 Oasis   a few large, soft pools of colour: water, sand and sky
//   1 Aurora  silk ribbons of light drifting across a deep sky
//   2 Tide    layered sheets of liquid glass, each with a lit crest
//   3 Drift   a handful of large glass bubbles floating in soft light
//   4 Ripple  slow rings spreading over still water
//   5 Bloom   a flower of tinted glass petals turning very slowly
//   6 Shallows sunlight falling in shafts through clear water onto sand
//
// Motion is built from whole cycles per hour. Godot's TIME wraps every hour,
// and this way the wrap lands exactly where it started, so nothing ever jumps.

uniform vec4 wall_base : source_color = vec4(0.03, 0.05, 0.08, 1.0);
uniform vec4 wall_a : source_color = vec4(0.1, 0.2, 0.36, 1.0);
uniform vec4 wall_b : source_color = vec4(0.05, 0.3, 0.32, 1.0);
uniform vec4 wall_c : source_color = vec4(0.5, 0.36, 0.26, 1.0);
uniform vec4 wall_glow : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.2, 0.82, 0.76, 1.0);
uniform float aspect = 1.7778;
uniform float focus_center : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 4.0) = 1.0;
uniform int wall_style = 0;
// While switching styles: the old one, and how far the new one has faded in.
uniform int wall_from = 0;
uniform float wall_fade : hint_range(0.0, 1.0) = 1.0;

// A slow wave: `per_hour` cycles an hour (scaled by speed, kept whole; a
// negative count runs the other way).
float wall_wave(float ph, float per_hour, float offset) {
	float n = max(1.0, floor(abs(per_hour) * speed + 0.5));
	return sin(ph * n * sign(per_hour) + offset);
}

float wall_pool(vec2 p, vec2 c, float r) {
	vec2 d = (p - c) / r;
	return exp(-dot(d, d));
}

vec3 wall_vignette(vec3 col, vec2 uv) {
	vec2 vc = uv - vec2(0.5, 0.45);
	col *= 1.0 - dot(vc, vc) * 0.45;
	// A soft, wide scrim behind the desktop's clock and left column keeps
	// white type legible on bright skies without shadows under the text.
	vec2 sc = (uv - vec2(0.1, 0.24)) / vec2(0.42, 0.36);
	return col * (1.0 - 0.16 * exp(-dot(sc, sc)));
}

vec3 wall_oasis(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	// A gentle warp keeps the pools organic rather than perfectly round.
	p += 0.05 * vec2(wall_wave(ph, 57.0, p.y * 2.3), wall_wave(ph, -45.0, p.x * 1.9 + 1.5708));
	vec3 col = wall_base.rgb;
	vec2 ca = vec2(aspect * (0.22 + 0.05 * wall_wave(ph, 30.0, 0.0)), 0.28 + 0.06 * wall_wave(ph, 24.0, 1.5708));
	vec2 cb = vec2(aspect * (0.78 + 0.05 * wall_wave(ph, 27.0, 1.5708)), 0.32 + 0.07 * wall_wave(ph, 39.0, 1.0));
	vec2 cc = vec2(aspect * (0.52 + 0.08 * wall_wave(ph, 21.0, 2.0)), 1.02 + 0.04 * wall_wave(ph, 30.0, 1.5708));
	vec2 cd = vec2(aspect * (0.08 + 0.04 * wall_wave(ph, 18.0, 1.5708)), 0.95);
	ca = mix(ca, vec2(aspect * 0.5, 0.42), focus_center * 0.6);
	col = mix(col, wall_a.rgb, wall_pool(p, ca, 0.62) * 0.85);
	col = mix(col, wall_b.rgb, wall_pool(p, cb, 0.58) * 0.8);
	col = mix(col, wall_c.rgb, wall_pool(p, cc, 0.55) * 0.55);
	col = mix(col, accent.rgb * 0.55, wall_pool(p, cd, 0.4) * 0.35);
	// The oasis, barely there: a band of light on a far horizon, and below
	// it a slow, faint shimmer like sun on still water.
	float hy = 0.6 + 0.012 * wall_wave(ph, 46.0, p.x * 1.4);
	float hd = (uv.y - hy) * 6.5;
	vec3 sheen = mix(wall_glow.rgb, accent.rgb, 0.45);
	col += sheen * exp(-hd * hd) * 0.045;
	float below = smoothstep(hy, 1.0, uv.y);
	float w1 = wall_wave(ph, 29.0, p.x * 7.0 + wall_wave(ph, 57.0, p.y * 9.0) * 1.4);
	float w2 = wall_wave(ph, -46.0, p.y * 23.0 + wall_wave(ph, -11.0, p.x * 4.0) * 1.6);
	col += sheen * smoothstep(0.55, 1.0, w1 * w2) * below * (1.0 - below) * 0.05;
	// Soft light from above.
	col += wall_glow.rgb * exp(-uv.y * uv.y * 5.0) * 0.035;
	return wall_vignette(col, uv);
}

// One silk ribbon: a fine lit upper edge, its light hanging below like a
// curtain, with faint threads along it and a glow that swells and fades
// along its length.
vec3 wall_ribbon(vec2 p, float ph, float y0, float tilt, float w, float o, vec3 silk) {
	float y = y0 + tilt * p.x + 0.075 * wall_wave(ph, 40.0, p.x * 1.25 + o) + 0.03 * wall_wave(ph, -64.0, p.x * 2.8 + o * 1.7);
	float d = p.y - y;
	float sheet = d < 0.0 ? exp(-d * d / (w * w * 0.02)) : exp(-d / w);
	float threads = 0.93 + 0.07 * sin(d * 160.0 + p.x * 2.0);
	float along = 0.25 + 0.75 * smoothstep(-0.7, 0.9, wall_wave(ph, 36.0, p.x * 1.6 + o));
	float crest = exp(-d * d * 40000.0);
	return (silk * sheet * threads * 0.42 + wall_glow.rgb * crest * 0.06) * along;
}

vec3 wall_aurora(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = wall_base.rgb;
	col = mix(col, wall_a.rgb, wall_pool(p, vec2(aspect * (0.3 + 0.04 * wall_wave(ph, 20.0, 0.0)), -0.1), 0.85) * 0.55);
	col = mix(col, wall_c.rgb * 0.6, wall_pool(p, vec2(aspect * 0.92, 1.12), 0.6) * 0.3);
	vec3 silk_a = mix(wall_b.rgb, accent.rgb, 0.45);
	vec3 silk_b = mix(wall_a.rgb, wall_glow.rgb, 0.3);
	vec3 silk_c = mix(wall_b.rgb, wall_c.rgb, 0.55);
	col += wall_ribbon(p, ph, 0.24, 0.2, 0.15, 0.0, silk_a);
	col += wall_ribbon(p, ph, 0.4, 0.13, 0.11, 2.1, silk_b) * 0.75;
	col += wall_ribbon(p, ph, 0.1, 0.27, 0.09, 4.4, silk_c) * 0.5;
	return wall_vignette(col, uv);
}

vec3 wall_tide(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = wall_base.rgb;
	col = mix(col, wall_a.rgb, wall_pool(p, vec2(aspect * 0.68, 0.0), 1.05) * 0.7);
	vec3 haze = mix(wall_glow.rgb, accent.rgb, 0.3);
	col += haze * exp(-pow((uv.y - 0.5) * 4.5, 2.0)) * 0.035;
	// Back to front: hazier and lighter far away, deeper and clearer near.
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float k = fi / 3.0;
		float base = 0.53 + fi * 0.105;
		float amp = 0.03 + fi * 0.01;
		float y = base + amp * wall_wave(ph, 50.0 + fi * 12.0, p.x * (1.15 + fi * 0.3) + fi * 1.7)
			+ amp * 0.45 * wall_wave(ph, -(70.0 + fi * 8.0), p.x * (2.6 - fi * 0.35) + fi * 3.1);
		float d = uv.y - y;
		float inside = smoothstep(-0.0012, 0.0012, d);
		vec3 sheet = mix(mix(wall_a.rgb, wall_b.rgb, 0.6), mix(wall_base.rgb, wall_b.rgb, 0.45), k);
		// Light gathers just under the crest and fades with depth, like
		// looking into thick glass.
		sheet *= 1.0 - 0.45 * smoothstep(0.0, 0.32, d);
		sheet += haze * exp(-max(d, 0.0) * 30.0) * 0.06;
		col = mix(col, sheet, inside * (0.6 + 0.3 * k));
		float lit = 0.4 + 0.6 * smoothstep(-0.8, 1.0, wall_wave(ph, 45.0, p.x * 1.6 + fi * 2.4));
		col += vec3(0.92, 0.97, 1.0) * (exp(-d * d * 400000.0) * 0.1 + exp(-d * d * 6000.0) * 0.015) * lit;
	}
	return wall_vignette(col, uv);
}

// A glass bubble: clear in the middle, a little brighter toward its rim, with
// a soft window of light on the upper left and light bounced on the lower right.
vec3 wall_bubble(vec3 col, vec2 p, vec2 c, float r, float soft) {
	vec2 q = (p - c) / r;
	float d = length(q);
	float inside = 1.0 - smoothstep(1.0 - soft, 1.0, d);
	if (inside <= 0.0) {
		return col;
	}
	vec2 ld = vec2(-0.6, -0.8);
	float facing = dot(q, ld);
	col = mix(col, col * 1.06 + wall_a.rgb * 0.05, inside);
	float rim = smoothstep(0.6, 1.0, d) * inside;
	col += mix(wall_glow.rgb, accent.rgb, 0.3) * rim * rim * (0.04 + 0.1 * max(facing, 0.0));
	vec2 h = q - ld * 0.52;
	col += wall_glow.rgb * exp(-dot(h, h) * 10.0) * 0.05 * inside;
	col += accent.rgb * smoothstep(0.78, 1.0, d) * inside * max(-facing, 0.0) * 0.06;
	return col;
}

vec3 wall_drift(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = wall_base.rgb;
	col = mix(col, wall_a.rgb, wall_pool(p, vec2(aspect * 0.25, 0.2), 0.75) * 0.8);
	col = mix(col, wall_b.rgb, wall_pool(p, vec2(aspect * 0.85, 0.75), 0.65) * 0.65);
	col = mix(col, wall_c.rgb, wall_pool(p, vec2(aspect * 0.55, 1.15), 0.5) * 0.35);
	col += wall_glow.rgb * exp(-uv.y * uv.y * 5.0) * 0.03;
	// Far bubbles are small and sharp, near ones large and out of focus.
	col = wall_bubble(col, p, vec2(aspect * (0.62 + 0.06 * wall_wave(ph, 34.0, 0.0)), 0.3 + 0.05 * wall_wave(ph, 46.0, 1.0)), 0.06, 0.04);
	col = wall_bubble(col, p, vec2(aspect * (0.38 + 0.07 * wall_wave(ph, 26.0, 2.0)), 0.72 + 0.06 * wall_wave(ph, 38.0, 0.5)), 0.1, 0.05);
	col = wall_bubble(col, p, vec2(aspect * (0.88 + 0.05 * wall_wave(ph, 22.0, 4.0)), 0.18 + 0.06 * wall_wave(ph, 31.0, 2.5)), 0.13, 0.08);
	col = wall_bubble(col, p, vec2(aspect * (0.13 + 0.05 * wall_wave(ph, 17.0, 1.2)), 0.88 + 0.05 * wall_wave(ph, 24.0, 3.0)), 0.22, 0.1);
	col = wall_bubble(col, p, vec2(aspect * (0.74 + 0.05 * wall_wave(ph, 13.0, 5.0)), 0.92 + 0.04 * wall_wave(ph, 19.0, 0.7)), 0.34, 0.12);
	return wall_vignette(col, uv);
}

// How many whole cycles an hour, at the current speed.
float wall_cycles(float per_hour) {
	return max(1.0, floor(per_hour * speed + 0.5));
}

vec3 wall_ripple(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = wall_base.rgb;
	col = mix(col, wall_a.rgb, wall_pool(p, vec2(aspect * 0.3, 0.05), 0.9) * 0.75);
	col = mix(col, wall_b.rgb, wall_pool(p, vec2(aspect * 0.75, 0.85), 0.75) * 0.7);
	col = mix(col, wall_c.rgb, wall_pool(p, vec2(aspect * 0.2, 1.1), 0.5) * 0.3);
	// Seen at a slant, so the rings are wide ellipses. Three at a time, each
	// spreading and fading over a minute and a half.
	vec2 c = vec2(aspect * (0.66 + 0.03 * wall_wave(ph, 7.0, 0.0)), 0.6 + 0.02 * wall_wave(ph, 9.0, 1.0));
	float r = length((p - c) * vec2(1.0, 2.3));
	float n = wall_cycles(40.0) / 6.2831853;
	float rings = 0.0;
	for (int k = 0; k < 3; k++) {
		float age = fract(ph * n + float(k) / 3.0);
		float d = r - age * 1.25;
		float fade = pow(1.0 - age, 1.4) * smoothstep(0.0, 0.12, age);
		// A lit crest with a soft trough behind it, like a lens in the water.
		rings += (exp(-d * d * 700.0) - 0.6 * exp(-(d + 0.035) * (d + 0.035) * 700.0)) * fade;
	}
	vec3 sheen = mix(wall_glow.rgb, accent.rgb, 0.35);
	col += sheen * rings * 0.11;
	// The still surface catches a faint band of sky.
	float band = (uv.y - 0.36 - 0.01 * wall_wave(ph, 23.0, p.x * 2.0)) * 7.0;
	col += wall_glow.rgb * exp(-band * band) * 0.025;
	return wall_vignette(col, uv);
}

// Long petals of tinted glass fanning out from just past the lower right
// corner, turning very slowly, so only their sweep shows.
vec3 wall_bloom(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = wall_base.rgb;
	col = mix(col, wall_a.rgb, wall_pool(p, vec2(aspect * 0.25, 0.1), 0.9) * 0.75);
	col = mix(col, wall_b.rgb * 0.85, wall_pool(p, vec2(aspect * 0.6, 0.95), 0.7) * 0.45);
	vec2 c = vec2(aspect * 0.98, 1.12);
	col += mix(wall_glow.rgb, accent.rgb, 0.4) * wall_pool(p, c, 0.7) * 0.06;
	float turn = 0.35 * wall_wave(ph, 8.0, 0.0);
	vec3 rim_col = mix(wall_glow.rgb, accent.rgb, 0.25);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float a = 3.45 + turn + fi * 0.34 + 0.06 * wall_wave(ph, 22.0, fi * 1.9);
		vec2 q = p - c;
		q = vec2(cos(a) * q.x + sin(a) * q.y, -sin(a) * q.x + cos(a) * q.y);
		float len = 0.62 + 0.09 * mod(fi * 3.0, 4.0);
		vec2 e = (q - vec2(len * 0.92, 0.0)) / vec2(len, 0.17);
		float d = length(e);
		float inside = 1.0 - smoothstep(0.985, 1.0, d);
		vec3 tint = mix(wall_b.rgb, mix(wall_a.rgb, accent.rgb, 0.45), mod(fi, 2.0));
		// Tinted glass: what's behind shows through, a little deeper.
		col = mix(col, col * 0.88 + tint * 0.22, inside * 0.45);
		// Its rim catches the light on one side.
		float lit = 0.3 + 0.7 * smoothstep(-0.6, 0.8, -e.y);
		col += rim_col * smoothstep(0.86, 1.0, d) * inside * 0.08 * lit;
	}
	return wall_vignette(col, uv);
}

vec3 wall_shallows(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(wall_a.rgb, wall_b.rgb, smoothstep(0.0, 0.85, uv.y));
	col = mix(col, wall_base.rgb, 0.35 * (1.0 - wall_pool(p, vec2(aspect * 0.45, 0.35), 0.9)));
	// Warm sand far below.
	vec3 sand = mix(wall_c.rgb, wall_glow.rgb, 0.15);
	col = mix(col, sand, smoothstep(0.62, 1.15, uv.y + 0.03 * wall_wave(ph, 11.0, p.x * 2.2)) * 0.4);
	// Shafts of sun, slanting and drifting sideways.
	float s = p.x + uv.y * 0.38;
	float sh = pow(0.5 + 0.5 * wall_wave(ph, 30.0, s * 4.3), 16.0);
	sh += 0.7 * pow(0.5 + 0.5 * wall_wave(ph, -22.0, s * 7.1 + 1.3), 22.0);
	sh += 0.5 * pow(0.5 + 0.5 * wall_wave(ph, 41.0, s * 2.6 + 2.6), 12.0);
	float fall = (1.0 - smoothstep(0.0, 0.95, uv.y)) * smoothstep(-0.05, 0.12, uv.y);
	vec3 sun = mix(wall_glow.rgb, accent.rgb, 0.2);
	col += sun * sh * fall * 0.13;
	// Light from the surface, and a faint shimmer of it on the sand.
	col += sun * exp(-uv.y * uv.y * 9.0) * 0.06;
	// Caustics: a soft net of light where two warped waves cross.
	vec2 q = p * vec2(7.0, 14.0);
	float ca = wall_wave(ph, 37.0, q.x + wall_wave(ph, 23.0, q.y * 0.8) * 1.2);
	float cb = wall_wave(ph, -29.0, q.y * 1.3 + wall_wave(ph, -17.0, q.x * 0.7) * 1.2);
	float net = pow(1.0 - abs(ca + cb) * 0.5, 9.0);
	col += sun * net * smoothstep(0.62, 1.0, uv.y) * 0.07;
	return wall_vignette(col, uv);
}

vec3 wall_style_color(int style, vec2 uv, float ph) {
	if (style == 1) {
		return wall_aurora(uv, ph);
	} else if (style == 2) {
		return wall_tide(uv, ph);
	} else if (style == 3) {
		return wall_drift(uv, ph);
	} else if (style == 4) {
		return wall_ripple(uv, ph);
	} else if (style == 5) {
		return wall_bloom(uv, ph);
	} else if (style == 6) {
		return wall_shallows(uv, ph);
	}
	return wall_oasis(uv, ph);
}

vec3 wall_color(vec2 uv, float time) {
	float ph = time * (6.2831853 / 3600.0);
	vec3 col = wall_style_color(wall_style, uv, ph);
	if (wall_fade < 1.0) {
		col = mix(wall_style_color(wall_from, uv, ph), col, wall_fade);
	}
	return col;
}
