// A liquid glass orb that fills with water as an update downloads: two wave
// layers for depth, caustics, rising bubbles, a bright meniscus and a curved
// glass shell. Around it, slow ripples spread over still water, and `pulse`
// sends one bright shockwave out when the download completes.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_a : source_color = vec4(0.22, 0.84, 0.77, 1.0);
uniform vec4 color_b : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform vec4 warn : source_color = vec4(1.0, 0.71, 0.28, 1.0);
// Surface motion: 1 while downloading, lower once it settles.
uniform float waves : hint_range(0.0, 1.0) = 1.0;
// Installing: the water turns into a slow glowing vortex.
uniform float swirl : hint_range(0.0, 1.0) = 0.0;
uniform float error : hint_range(0.0, 1.0) = 0.0;
uniform float ripples : hint_range(0.0, 1.0) = 1.0;
// Timeline of the completion shockwave, 0..1. Negative means off.
uniform float pulse = -1.0;
// Orb radius as a fraction of the rect's half size; the rest is ripples.
uniform float orb = 0.56;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float R = orb;
	float px = max(fwidth(r), 0.0001);
	float t = TIME;
	vec3 wa = mix(color_a.rgb, warn.rgb, error);
	vec3 wb = mix(color_b.rgb, warn.rgb * vec3(1.0, 0.62, 0.45), error);
	vec3 mid = mix(wa, wb, 0.4);

	// --- Around the orb ------------------------------------------------------
	float outside = smoothstep(R - px, R + px, r);
	float fade = 1.0 - smoothstep(0.72, 1.0, r);
	float halo = exp(-max(r - R, 0.0) * 10.0) * (0.18 + 0.32 * progress + 0.4 * swirl);
	float rip = 0.0;
	for (int i = 0; i < 3; i++) {
		float ph = fract(t * 0.2 + float(i) / 3.0);
		float rr = R + ph * (1.0 - R);
		float w = 1.0 - smoothstep(0.0, 0.006 + 0.03 * ph, abs(r - rr));
		rip += w * (1.0 - ph) * (1.0 - ph) * 0.32;
	}
	rip *= ripples * (0.5 + 0.5 * progress);
	float shock = 0.0;
	if (pulse >= 0.0 && pulse < 1.0) {
		float sr = R + pulse * (1.02 - R);
		float sw = 0.012 + 0.05 * pulse;
		shock = exp(-pow((r - sr) / sw, 2.0)) * (1.0 - pulse) * 1.3;
	}
	vec3 around_rgb = mix(mid, vec3(1.0), clamp(shock * 0.6, 0.0, 0.7));
	float around_a = clamp((halo + rip + shock) * fade, 0.0, 1.0) * outside;

	// --- The orb ---------------------------------------------------------------
	vec2 q = p / R;
	float qr = min(length(q), 1.0);
	float z = sqrt(max(1.0 - qr * qr, 0.0));
	// Through a curved shell the water bends towards the rim.
	vec2 wq = q * (0.82 + 0.18 * z);
	if (swirl > 0.0) {
		float ang = swirl * ((1.0 - qr) * 2.6 + t * 1.4);
		float cs = cos(ang);
		float sn = sin(ang);
		wq = vec2(wq.x * cs - wq.y * sn, wq.x * sn + wq.y * cs);
	}
	// y grows downwards, so the water is everything below the surface line.
	float level = mix(1.04, -1.14, progress);
	float amp = 0.07 * waves * (0.35 + 0.65 * sin(3.14159 * clamp(progress, 0.05, 0.95)));
	float front = level + amp * (0.6 * sin(wq.x * 4.6 + t * 2.3) + 0.4 * sin(wq.x * 8.7 - t * 3.3));
	float back = level - 0.035 + amp * (0.6 * sin(wq.x * 3.7 - t * 1.8 + 1.7) + 0.4 * sin(wq.x * 6.9 + t * 2.7));
	float aa = max(fwidth(wq.y) * 1.2, 0.002);
	float in_front = smoothstep(front - aa, front + aa, wq.y);
	float in_back = smoothstep(back - aa, back + aa, wq.y);

	// Empty glass: deep and faintly tinted.
	vec3 col = vec3(0.025, 0.05, 0.07) + mid * 0.06 * (1.0 - qr);
	float depth = clamp((wq.y - front) / 1.8, 0.0, 1.0);
	vec3 water = mix(wa * 1.08, wb * 0.5, depth);
	// Caustics: two folded sine fields, sharpened.
	vec2 cq = wq * 3.2;
	float c = sin(cq.x * 2.1 + t * 1.1 + sin(cq.y * 1.7 - t * 0.8))
		+ sin(cq.y * 2.6 - t * 0.9 + sin(cq.x * 1.3 + t * 0.6));
	c = pow(clamp(1.0 - abs(c) * 0.55, 0.0, 1.0), 6.0);
	water += vec3(0.85, 1.0, 1.0) * c * (0.16 + 0.2 * swirl) * (1.0 - depth * 0.7);
	// Bubbles rising from the bottom to the surface.
	float bub = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ph = fract(t * (0.16 + hash(fi + 3.1) * 0.22) + hash(fi));
		vec2 bp = vec2(mix(-0.6, 0.6, hash(fi + 7.7)) + 0.05 * sin(t * 2.0 + fi * 3.0), mix(1.0, max(level, -1.0), ph));
		float rad = 0.022 + hash(fi + 1.3) * 0.03;
		float d = length(wq - bp);
		float b = 1.0 - smoothstep(rad - aa, rad + aa, d);
		bub += b * (0.25 + 0.75 * smoothstep(rad * 0.4, rad, d)) * (1.0 - ph * ph);
	}
	bub *= smoothstep(0.0, 0.08, progress);
	col = mix(col, mid * 0.5 + vec3(0.02, 0.04, 0.05), in_back * (1.0 - in_front) * 0.9);
	col = mix(col, water, in_front);
	col += vec3(1.0) * bub * 0.3 * in_front;
	// Meniscus: a bright line along the crest of the front wave.
	float crest = exp(-pow((wq.y - front) / (aa * 1.5 + 0.01), 2.0));
	col += mix(wa, vec3(1.0), 0.65) * crest * 0.6 * step(0.001, progress);

	// The glass shell.
	float fres = pow(1.0 - z, 2.5);
	col += vec3(0.75, 0.9, 1.0) * fres * 0.32;
	col += wa * pow(max(q.y, 0.0), 3.0) * fres * 0.5 * in_front;
	vec2 h = q - vec2(-0.34, -0.5);
	h = vec2(h.x * 0.8 + h.y * 0.6, -h.x * 0.6 + h.y * 0.8);
	col += vec3(1.0) * exp(-(h.x * h.x * 3.2 + h.y * h.y * 14.0)) * 0.24;
	col += vec3(1.0) * exp(-dot(q - vec2(-0.46, -0.6), q - vec2(-0.46, -0.6)) * 260.0) * 0.75;
	float line = 1.0 - smoothstep(0.0, 1.6 * px, abs(r - R + px));
	float facing = dot(normalize(p + 0.0001), normalize(vec2(-0.55, -1.0)));
	col += vec3(1.0) * line * mix(0.12, 0.6, facing * facing);
	col += wa * swirl * 0.18 * (1.0 - qr);

	float inside = 1.0 - outside;
	vec3 rgb = mix(around_rgb, col, inside);
	float a = max(around_a, inside);
	COLOR = vec4(rgb, a * COLOR.a);
}
