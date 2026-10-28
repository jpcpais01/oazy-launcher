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
//   7 Music   the music wallpaper: glass bars lit from behind on a celestial
//             sky, moving with what's playing (see Music, which feeds
//             the music_* globals below)
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

// What's playing, from the Music autoload (globals, so every glass panel
// mirroring the wallpaper moves with it for free).
global uniform vec4 music_bands0;
global uniform vec4 music_bands1;
global uniform vec4 music_bands2;
global uniform vec4 music_bands3;
global uniform vec4 music_slow0;
global uniform vec4 music_slow1;
global uniform vec4 music_slow2;
global uniform vec4 music_slow3;
// level, bass, mids, highs
global uniform vec4 music_level;
// kick pulse, onset flash, presence (0 in silence), beat phase
global uniform vec4 music_beat;
// Seconds since each of the last four kicks, and how hard each was.
global uniform vec4 music_rings;
global uniform vec4 music_ring_power;
// Flow phases in radians, wrapped: use them only times whole numbers.
global uniform vec4 music_phase;
// The vibe's palette: base, a, b, c, glow.
global uniform vec4 music_base;
global uniform vec4 music_a;
global uniform vec4 music_b;
global uniform vec4 music_c;
global uniform vec4 music_glow;

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

// One of the 16 spectrum bands (s 0 = lowest, 1 = highest), eased between them.
float music_spec(vec4 b0, vec4 b1, vec4 b2, vec4 b3, float s) {
	float f = clamp(s, 0.0, 1.0) * 15.0;
	float v[16] = {b0.x, b0.y, b0.z, b0.w, b1.x, b1.y, b1.z, b1.w, b2.x, b2.y, b2.z, b2.w, b3.x, b3.y, b3.z, b3.w};
	int i = int(f);
	float t = f - float(i);
	return mix(v[i], v[min(i + 1, 15)], t * t * (3.0 - 2.0 * t));
}

float music_hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float music_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(music_hash(i), music_hash(i + vec2(1.0, 0.0)), f.x),
		mix(music_hash(i + vec2(0.0, 1.0)), music_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Soft nebula: three octaves of value noise.
float music_cloud(vec2 p) {
	return music_noise(p) * 0.55 + music_noise(p * 2.03 + 7.1) * 0.3 + music_noise(p * 4.1 + 3.7) * 0.15;
}

// A field of tiny stars, one per cell, each twinkling at its own pace.
float music_stars(vec2 p, float cell, float ph, float sharp) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	float r = music_hash(id);
	vec2 at = vec2(music_hash(id + 3.1), music_hash(id + 7.7)) * 0.8 + 0.1;
	float d = length(fract(g) - at);
	float tw = 0.55 + 0.45 * sin(ph * floor(20.0 + r * 60.0) + r * 40.0);
	return exp(-d * d * sharp) * pow(r, 6.0) * tw;
}

// The light behind the glass, coloured along the row: the vibe's three
// lights, with a faint prism shimmer.
vec3 music_light(float x) {
	vec3 c = mix(music_b.rgb, music_a.rgb, smoothstep(0.0, 0.5, x));
	c = mix(c, music_c.rgb, smoothstep(0.55, 1.0, x));
	return c;
}

// The bar at column `i` of `n`: its centre and half size.
vec4 music_bar(float i, float n, float w, float cx, float cy, float pitch) {
	float x = cx + (i - (n - 1.0) * 0.5) * pitch;
	float s = clamp(abs(i - (n - 1.0) * 0.5) / ((n - 1.0) * 0.5), 0.0, 1.0);
	// Left and right read the spectrum a little differently, quick and slow,
	// so it's never a mirror image.
	float side = i < (n - 1.0) * 0.5 ? 0.0 : 1.0;
	float quick = music_spec(music_bands0, music_bands1, music_bands2, music_bands3, s * 0.92 + side * 0.04);
	float calm = music_spec(music_slow0, music_slow1, music_slow2, music_slow3, s * 0.92 + (1.0 - side) * 0.04);
	float k = 0.5 + 0.5 * sin(i * 2.39);
	float v = mix(quick, calm, k * 0.6);
	// At rest the row still breathes, a slow wave from the middle out.
	float idle = 0.035 + 0.025 * (0.5 + 0.5 * sin(s * 9.0 - music_phase.x * 2.0 + side));
	float h = mix(idle, 0.05 + 0.36 * v, music_beat.z) * (1.0 - 0.6 * s * s) + 0.012;
	float yo = 0.012 * sin(i * 1.7 + music_phase.y) * (1.0 - s);
	return vec4(x, cy + yo, w * 0.5, h * 0.5);
}

float music_box(vec2 p, vec4 b, float r) {
	vec2 q = abs(p - b.xy) - b.zw + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The light behind the row at `p`: a wide soft core and rays fanning out,
// in the vibe's colours. The glass samples it again where it bends the view.
vec3 music_back(vec2 p, float cx, float cy, float power, vec4 fp) {
	vec2 dc = p - vec2(cx, cy);
	float lx = clamp((p.x - cx) / (aspect * 0.8) + 0.5, 0.0, 1.0);
	vec3 light = music_light(lx);
	vec2 cq = dc * vec2(0.85, 4.5);
	vec3 c = mix(light, music_glow.rgb, 0.25) * exp(-dot(cq, cq) * 1.6) * 0.38 * power;
	float ang = atan(dc.y, dc.x * 0.55);
	float rd = length(dc * vec2(0.6, 1.0));
	float rays = pow(0.5 + 0.5 * sin(ang * 7.0 + fp.z), 8.0) * 0.55 + pow(0.5 + 0.5 * sin(ang * 13.0 - 2.0 * fp.z + 1.3), 14.0) * 0.35;
	rays += pow(0.5 + 0.5 * sin(ang * 4.0 - fp.w + 0.7), 5.0) * 0.3;
	// A touch of prism: each ray's hue shifts with its angle.
	vec3 prism = 0.6 + 0.4 * cos(6.2831853 * (vec3(0.0, 0.33, 0.67) + ang * 0.35 + lx * 0.5));
	vec3 ray_col = mix(light, prism * mix(light, music_glow.rgb, 0.5), 0.45);
	float flat_ = abs(cos(ang));
	c += ray_col * rays * exp(-rd * 2.4) * smoothstep(0.02, 0.3, rd) * (0.36 * power) * (0.3 + 0.7 * flat_ * flat_);
	return c;
}

// A row of thin glass bars dancing to the music, lit from behind by soft
// coloured light that spills through them as rays and haze, in front of a
// pale celestial sky with nebulae and stars. The bars are the spectrum,
// bass in the middle; the light swells with the level and every kick, and
// the colours are the vibe.
vec3 wall_music(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	float lvl = music_level.x;
	float kick = music_beat.x;
	float flash = music_beat.y;
	float on = music_beat.z;
	vec4 fp = music_phase;
	vec3 glow = music_glow.rgb;
	float cx = aspect * 0.5;
	float cy = 0.47;

	// Sky: deep at the top, paler toward the light, a warm glow low right.
	vec3 col = mix(music_base.rgb * 0.6, music_base.rgb * 1.2 + music_a.rgb * 0.1, smoothstep(0.0, 0.75, uv.y));
	col = mix(col, music_c.rgb * 0.75 + glow * 0.1, wall_pool(p, vec2(aspect * 0.92, 1.05), 0.75) * 0.55);
	col = mix(col, music_b.rgb * 0.6, wall_pool(p, vec2(aspect * 0.1, 0.35), 0.6) * 0.35);
	// Nebulae drifting slowly, brighter near the light.
	vec2 np = p * 1.6 + vec2(0.18 * sin(fp.x), 0.12 * cos(fp.y));
	float neb = music_cloud(np);
	float wisp = smoothstep(0.45, 0.85, music_cloud(np * 1.7 + 4.0 + 0.1 * sin(fp.z)));
	vec2 dc = p - vec2(cx, cy);
	float near = exp(-dot(dc * vec2(0.9, 2.2), dc * vec2(0.9, 2.2)) * 2.2);
	col += mix(music_a.rgb, music_b.rgb, neb) * smoothstep(0.3, 0.85, neb) * (0.14 + 0.2 * near);
	col += mix(glow, music_c.rgb, 0.4) * wisp * (0.04 + 0.08 * near) * (1.0 - smoothstep(0.75, 1.0, uv.y));

	// Stars: fine and sparse, more of them around the bars.
	col += glow * music_stars(p, 0.035, ph, 900.0) * (0.5 + 0.8 * near);
	col += glow * music_stars(p + 0.5, 0.017, ph, 2600.0) * (0.25 + 1.4 * near) * (0.7 + 0.6 * music_level.w);

	// The light behind the row: a wide soft core, and rays fanning out.
	float lx = clamp((p.x - cx) / (aspect * 0.8) + 0.5, 0.0, 1.0);
	vec3 light = music_light(lx);
	float power = 0.45 + 0.55 * on * (0.4 + lvl) + 0.25 * kick;
	vec3 back = music_back(p, cx, cy, power, fp);
	col += back;

	// The glass bars.
	const float N = 41.0;
	float pitch = aspect * 0.78 / N;
	float w = pitch * 0.58;
	float rad = w * 0.32;
	float fi = floor((p.x - cx) / pitch + (N - 1.0) * 0.5 + 0.5);
	float halo = 0.0;
	vec3 glass = vec3(0.0);
	float inside = 0.0;
	float spill = 0.0;
	for (int j = -1; j <= 1; j++) {
		float i = fi + float(j);
		if (i < 0.0 || i > N - 1.0) {
			continue;
		}
		vec4 b = music_bar(i, N, w, cx, cy, pitch);
		float d = music_box(p, b, rad);
		// Light scattered by the glass into the air around it: a soft haze
		// that clings to each bar, strongest where the light crosses the row.
		halo = max(halo, exp(-max(d, 0.0) * 70.0) * (0.25 + b.w * 2.0) * (0.45 + 0.55 * exp(-pow((p.y - cy) * 5.0, 2.0))));
		// A little of the light carried along the glass leaks out past each
		// end, a faint glow that fades a short way into the sky.
		if (j == 0) {
			float dx = (p.x - b.x) / b.z;
			float past = max(abs(p.y - b.y) - b.w, 0.0);
			spill = exp(-dx * dx * 1.5) * exp(-past * 38.0) * step(0.0001, past);
		}
		if (j == 0 && d < 0.002) {
			vec2 lq = (p - b.xy) / b.zw;
			float a = 1.0 - smoothstep(-0.0012, 0.0012, d);
			inside = a;
			// Each bar holds a little gradient of the lights behind it, shifted
			// bar to bar, so the row reads as many panes of tinted glass.
			float bx = clamp((b.x - cx) / (aspect * 0.8) + 0.5 + 0.16 * sin(i * 1.31), 0.0, 1.0);
			vec3 lc = mix(music_light(clamp(bx - 0.35, 0.0, 1.0)), music_light(clamp(bx + 0.35, 0.0, 1.0)), smoothstep(-0.8, 0.8, lq.y));
			// A rounded glass rod: looking through it, the view bends more
			// the nearer the edge, so the light behind is drawn in from the
			// side (and flipped), and the edges catch whatever bright light
			// sits beside the bar. Nothing here is a drawn outline.
			float ax = abs(lq.x);
			float cosv = sqrt(max(1.0 - ax * ax, 0.0));
			float bend = lq.x / max(cosv, 0.18);
			vec2 pr = p - vec2(bend * b.z * 1.6, lq.y * b.w * 0.03);
			vec3 seen = col - back + music_back(pr, cx, cy, power, fp) * (1.0 + 0.2 * cosv);
			// The glass is faintly tinted by the lights behind it, deeper where
			// it's thicker, and lets a little of that light glow inside.
			float through = 0.3 + 0.7 * exp(-pow((p.y - cy) * 6.0, 2.0));
			vec3 tint = mix(vec3(1.0), lc / max(max(lc.r, max(lc.g, lc.b)), 0.001), 0.18 * cosv);
			vec3 body = seen * 0.92 * tint;
			// Light entering the glass scatters inside it, so the bar glows
			// faintly in the lights' colours, most where the light is behind;
			// the rounded front gathers some into a soft line down the middle.
			body += lc * (0.04 + 0.15 * through) * (0.55 + 0.5 * power);
			body += (back + lc * 0.05) * 0.7 * pow(cosv, 10.0);
			// Close to the edge the view hits the inside of the glass too
			// steeply to pass through and reflects back in, so a rod shows a
			// thin darker band just inside its rim.
			body *= 1.0 - 0.32 * smoothstep(0.8, 0.93, ax) * (1.0 - smoothstep(0.95, 0.995, ax));
			// Fresnel: the glass reflects more at a glancing angle, and what it
			// reflects is the light around it, so dim surroundings give a dim edge.
			float fres = 0.04 + 0.96 * pow(1.0 - cosv, 5.0);
			vec3 around = col * 0.95 + back * 0.9 + lc * 0.06;
			body = mix(body, around, fres * 0.85);
			// The rounded ends do the same.
			float endv = 1.0 - smoothstep(0.0, 0.8, (1.0 - abs(lq.y)) * b.w / b.z);
			body = mix(body, around, endv * 0.35);
			glass = body;
		}
	}
	vec3 halo_col = mix(light, glow, 0.3);
	col += halo_col * halo * 0.06 * (0.5 + power);
	col += halo_col * spill * 0.05 * power;
	col = mix(col, glass, inside);

	// Sparkles drifting around the bars, brighter on the highs.
	float sp = music_stars(p + vec2(0.0, 0.02 * sin(fp.y)), 0.022, ph * 2.0, 3200.0);
	float band = exp(-pow((p.y - cy) / 0.24, 2.0)) * smoothstep(aspect * 0.45, aspect * 0.15, abs(p.x - cx));
	col += glow * sp * band * (0.8 + 1.6 * music_level.w + 1.2 * flash) * 1.4;

	col *= 1.0 + 0.04 * kick;
	// A soft shoulder above 0.75, so the light never clips to flat white.
	vec3 over = max(col - 0.75, 0.0);
	col = min(col, 0.75) + 0.25 * (1.0 - exp(-over * 4.0));
	return wall_vignette(col, uv);
}

vec3 wall_style_color(int style, vec2 uv, float ph) {
	if (style == 7) {
		return wall_music(uv, ph);
	} else if (style == 1) {
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
