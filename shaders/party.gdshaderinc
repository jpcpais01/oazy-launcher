// Party mode: the music wallpaper's celebration (style 8, see Music.party).
//
// The same glass bars, now standing on a still lake at dusk and lit from
// behind by a warm horizon, while fine fireworks open in the sky above them
// on the beat, a few soft beams sway from behind the row and golden glints
// drift up into the night. The lake mirrors all of it, rippling gently.
// Included by wall.gdshaderinc after the music helpers it builds on.

// Each of four bursts: its age in seconds (9 = spent), a seed that picks
// where it opens, how big and in which colours, and how hard it was hit.
global uniform vec4 music_burst;
global uniform vec4 music_burst_seed;
global uniform vec4 music_burst_power;

// The horizon, where the bars stand and the lake begins (uv.y, 0 = top).
const float PARTY_HORIZON = 0.665;

vec3 party_gold() {
	return vec3(1.0, 0.8, 0.52);
}

// One firework: several dozen fine sparks flying out from a point, slowing
// as they go and sinking under their own weight, so each trail curves down
// like a willow's; they twinkle out at the end. Each spark lives in its own
// slice of angle around the centre, so a pixel only ever looks at one.
vec3 party_burst(vec2 p, float age, float seed, float power) {
	if (age > 3.4) {
		return vec3(0.0);
	}
	vec2 c = vec2(aspect * (0.5 + (fract(seed * 7.13) - 0.5) * 0.7), 0.1 + 0.2 * fract(seed * 3.71));
	float big = (0.15 + 0.09 * fract(seed * 5.31)) * (0.8 + 0.35 * power);
	const float DRAG = 3.0;
	const float FALL = 0.028;
	vec2 q0 = p - c;
	vec2 qb = q0 - vec2(0.0, FALL * age * age * 0.6);
	if (dot(qb, qb) > big * big * 2.0) {
		return vec3(0.0);
	}
	// When a spark would have passed this far out, and how far it had sunk
	// by then: undoing that bends the straight spokes into falling arcs.
	float k = 1.0 - exp(-age * DRAG);
	float r0 = length(q0 - vec2(0.0, FALL * age * age * 0.5));
	float t = min(-log(max(1.0 - r0 / big, 0.02)) / DRAG, age);
	vec2 q = q0 - vec2(0.0, FALL * t * t);
	float r = length(q);
	float n = 56.0 + floor(fract(seed * 11.7) * 24.0);
	float u = (atan(q.y, q.x) / 6.2831853 + 0.5) * n;
	float id = floor(u);
	float rs = music_hash(vec2(id, seed * 91.0));
	float jit = (music_hash(vec2(id + 13.0, seed * 37.0)) - 0.5) * 0.4;
	float across = r * sin((fract(u) - 0.5 - jit) * 6.2831853 / n);
	float head = big * k * (0.78 + 0.22 * rs);
	float trail = big * (0.12 + 0.45 * (1.0 - k));
	float along = clamp((r - (head - trail)) / trail, 0.0, 1.0) * step(r, head);
	float line = exp(-across * across / 1.1e-6) * along * along * along;
	float dh = r - head;
	float spark = exp(-(across * across + dh * dh) / 4.0e-6);
	float life = 1.0 - smoothstep(1.4, 3.2, age + rs * 0.6);
	// Late in life the sparks twinkle out, each at its own pace.
	float tw = mix(1.0, 0.3 + 0.7 * (0.5 + 0.5 * sin(age * (24.0 + rs * 22.0) + rs * 30.0)), smoothstep(1.0, 2.0, age));
	// Colour: a champagne-white head over a trail in one of the vibe's lights.
	float pick = fract(seed * 17.3);
	vec3 hue = pick < 0.3 ? music_a.rgb : (pick < 0.55 ? music_b.rgb : (pick < 0.8 ? music_c.rgb : party_gold()));
	hue = mix(hue, party_gold(), 0.2);
	vec3 white = vec3(1.0, 0.96, 0.9);
	vec3 trail_col = mix(white, hue * 1.15, smoothstep(0.0, 0.35, age) * (0.75 + 0.25 * (1.0 - along)));
	vec3 col = (trail_col * line * 0.75 + mix(white, hue * 1.1, smoothstep(0.35, 1.4, age)) * spark * 1.2) * life * tw;
	// The moment it opens, a soft bloom of light around the centre.
	col += white * exp(-dot(q0, q0) / (big * big * 0.04)) * 0.45 * (1.0 - smoothstep(0.0, 0.35, age));
	// And while it burns, a faint glow in the sky around it.
	col += hue * exp(-length(q0) / (big * 0.55)) * 0.04 * life * (0.6 + 0.4 * power);
	return col;
}

// A soft beam of light from behind the row, swaying slowly.
float party_beam(vec2 p, vec2 o, float tilt) {
	vec2 d = vec2(sin(tilt), -cos(tilt));
	vec2 q = p - o;
	float along = dot(q, d);
	float off = q.x * d.y - q.y * d.x;
	float wdt = 0.006 + along * 0.05;
	return exp(-off * off / (wdt * wdt)) * smoothstep(0.0, 0.08, along) * exp(-along * 1.6);
}

// Golden glints drifting up from the horizon, one per cell, each column at
// its own whole-number pace so the climb wraps without a jump.
float party_glints(vec2 p, float rise) {
	const float CELL = 0.05;
	vec2 g = p / CELL;
	float col_id = floor(g.x);
	float n = 5.0 + floor(music_hash(vec2(col_id, 4.2)) * 4.0);
	g.y += rise * n;
	vec2 id = vec2(col_id, mod(floor(g.y), n));
	float r = music_hash(id + 2.7);
	vec2 at = vec2(0.5 + 0.28 * sin(6.2831853 * fract(g.y) + r * 6.0), 0.5);
	vec2 f = vec2(fract(g.x), fract(g.y)) - at;
	return exp(-dot(f, f) * 1300.0) * smoothstep(0.55, 1.0, r);
}

// Everything above the water at `p`: sky, beams, fireworks, glints, bars.
vec3 party_scene(vec2 p, float ph, float bright) {
	float lvl = music_level.x;
	float kick = music_beat.x;
	float on = music_beat.z;
	vec4 fp = music_phase;
	vec3 glow = music_glow.rgb;
	float cx = aspect * 0.5;
	float hy = PARTY_HORIZON;
	vec2 dc = p - vec2(cx, hy);
	float power = 0.5 + 0.5 * on * (0.4 + lvl) + 0.3 * kick;

	// Dusk: a deep sky that warms toward the horizon, warmest behind the row.
	float up = clamp((hy - p.y) / hy, 0.0, 1.0);
	// Twilight: the top leans to deep indigo, against the warm horizon.
	vec3 deep = mix(music_base.rgb * 0.55, vec3(0.035, 0.04, 0.11), 0.35);
	vec3 warm = mix(music_a.rgb, party_gold(), 0.45);
	vec3 col = mix(music_base.rgb * 1.05 + warm * 0.08, deep, smoothstep(0.0, 0.8, up));
	float dawn = exp(-pow(dc.x / (aspect * 0.42), 2.0)) * exp(-up * 7.0);
	col += warm * dawn * (0.32 + 0.22 * power);
	col += mix(music_c.rgb, warm, 0.5) * exp(-up * 3.0) * exp(-pow(dc.x / aspect, 2.0) * 2.0) * 0.08;
	// A hint of nebula, high up.
	float neb = music_cloud(p * 1.4 + vec2(0.15 * sin(fp.x), 0.1 * cos(fp.y)));
	col += mix(music_b.rgb, music_c.rgb, neb) * smoothstep(0.45, 0.9, neb) * 0.08 * smoothstep(0.2, 0.8, up);
	// Fine stars, fading out in the warm light.
	col += glow * music_stars(p, 0.035, ph, 900.0) * smoothstep(0.25, 0.75, up) * 0.8;

	// Beams from behind the row, swaying with the music.
	float sway = 0.25 * on + 0.08;
	float beams = party_beam(p, vec2(cx - aspect * 0.2, hy), -0.42 + sway * sin(fp.x * 2.0))
		+ party_beam(p, vec2(cx, hy), 0.18 * sin(fp.y * 3.0 + 1.0) * (0.5 + sway))
		+ party_beam(p, vec2(cx + aspect * 0.2, hy), 0.42 + sway * sin(fp.z * 2.0 + 2.0));
	col += mix(warm, glow, 0.5) * beams * (0.05 + 0.05 * power) * step(p.y, hy);

	// Fireworks.
	vec3 fw = party_burst(p, music_burst.x, music_burst_seed.x, music_burst_power.x)
		+ party_burst(p, music_burst.y, music_burst_seed.y, music_burst_power.y)
		+ party_burst(p, music_burst.z, music_burst_seed.z, music_burst_power.z)
		+ party_burst(p, music_burst.w, music_burst_seed.w, music_burst_power.w);
	col += fw * bright;

	// Glints rising out of the warm light.
	float gl = party_glints(p, fp.w / 6.2831853);
	col += mix(party_gold(), glow, 0.4) * gl * smoothstep(0.0, 0.06, hy - p.y) * exp(-up * 2.2) * (0.5 + 0.9 * music_level.w) * bright;

	// The glass bars, standing on the water.
	const float N = 41.0;
	float pitch = aspect * 0.78 / N;
	float w = pitch * 0.58;
	float rad = w * 0.32;
	float fi = floor((p.x - cx) / pitch + (N - 1.0) * 0.5 + 0.5);
	float halo = 0.0;
	vec3 glass = vec3(0.0);
	float inside = 0.0;
	for (int j = -1; j <= 1; j++) {
		float i = fi + float(j);
		if (i < 0.0 || i > N - 1.0) {
			continue;
		}
		vec4 b = music_bar(i, N, w, cx, 0.0, pitch);
		b.w *= 0.95;
		b.y = hy - b.w - 0.006;
		float d = music_box(p, b, rad);
		halo = max(halo, exp(-max(d, 0.0) * 60.0) * (0.3 + b.w * 2.5));
		if (j == 0 && d < 0.002) {
			vec2 lq = (p - b.xy) / b.zw;
			inside = 1.0 - smoothstep(-0.0012, 0.0012, d);
			float bx = clamp((b.x - cx) / (aspect * 0.8) + 0.5 + 0.16 * sin(i * 1.31), 0.0, 1.0);
			vec3 lc = mix(music_light(clamp(bx - 0.3, 0.0, 1.0)), warm, smoothstep(-0.6, 1.0, lq.y) * 0.6);
			// Lit from below and behind: brightest at the foot of each bar.
			float foot = 0.4 + 0.6 * smoothstep(-1.0, 1.0, lq.y);
			vec3 body = col * 0.72 + lc * (0.16 + 0.3 * foot) * (0.7 + 0.5 * power) + glow * 0.03;
			body += mix(glow, lc, 0.3) * pow(abs(lq.x), 6.0) * 0.3;
			body += glow * exp(-pow((lq.x + 0.5) / 0.12, 2.0)) * 0.12;
			body += glow * exp(-(1.0 - abs(lq.y)) * b.w / 0.005) * 0.3 * step(lq.y, 0.0);
			body += glow * exp(-d * d * 3.0e6) * 0.4;
			glass = body;
		}
	}
	col += mix(warm, glow, 0.3) * halo * 0.1 * (0.5 + power);
	col = mix(col, glass, inside * 0.92);
	return col;
}

vec3 wall_party(vec2 uv, float ph) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	float hy = PARTY_HORIZON;
	vec3 col;
	if (p.y < hy) {
		col = party_scene(p, ph, 1.0);
	} else {
		// The lake: the scene mirrored, darker and cooler, broken into
		// ripples that crowd together toward the horizon.
		vec4 fp = music_phase;
		float dy = p.y - hy;
		float z = 1.0 / (dy + 0.015);
		float rip = sin(z * 0.9 + p.x * 2.0 + fp.y * 2.0) * 0.55 + sin(z * 1.9 - p.x * 5.0 + fp.x * 3.0) * 0.3 + sin(z * 3.7 + p.x * 13.0 - fp.z * 2.0) * 0.15;
		vec2 m = vec2(p.x + rip * (0.0015 + 0.012 * dy), hy - dy * 1.04 + rip * 0.003 * dy * 6.0);
		vec3 refl = party_scene(m, ph, 0.8);
		vec3 water = music_base.rgb * 0.35;
		float fres = 0.55 - 0.35 * smoothstep(0.0, 0.3, dy);
		col = mix(water, refl, fres);
		// Light glancing off the ripple crests, under the brightest sky.
		float crest = smoothstep(0.6, 1.0, rip) * exp(-dy * 9.0);
		col += refl * crest * 0.25;
		// The waterline itself, a fine bright seam.
		col += music_glow.rgb * exp(-pow(dy / 0.0022, 2.0)) * 0.08;
	}
	col *= 1.0 + 0.04 * music_beat.x;
	vec3 over = max(col - 0.75, 0.0);
	col = min(col, 0.75) + 0.25 * (1.0 - exp(-over * 4.0));
	return wall_vignette(col, uv);
}
