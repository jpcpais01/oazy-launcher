// Animated backdrop: two drifting aurora ribbons over a deep base, a soft
// glow orb, twinkling star dust, vignette and dithering. Roughly a dozen
// cheap ALU ops and four value-noise lookups per pixel, no textures.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.027, 0.031, 0.051, 1.0);
uniform vec4 accent : source_color = vec4(0.486, 0.424, 1.0, 1.0);
uniform vec4 accent2 : source_color = vec4(0.2, 0.75, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float speed : hint_range(0.0, 4.0) = 1.0;
uniform float stars : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.7778;
uniform float focus_center : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * 0.03 * speed;

	vec2 q = vec2(vnoise(p * 1.3 + vec2(t, -t * 0.7)), vnoise(p * 1.3 + vec2(-t * 0.8, t) + 7.3));
	float n = vnoise(p * 2.1 + q * 1.7 + vec2(t * 0.6, 0.0));

	float y1 = uv.y - 0.30 - 0.11 * sin(p.x * 1.25 + t * 5.0 + q.x * 2.6);
	float y2 = uv.y - 0.64 - 0.09 * sin(p.x * 1.7 - t * 4.2 + q.y * 3.1);
	float band1 = exp(-(y1 * y1) * 18.0);
	float band2 = exp(-(y2 * y2) * 26.0);

	vec3 col = base_color.rgb;
	col += accent.rgb * band1 * (0.3 + 0.7 * n) * 0.42 * intensity;
	col += accent2.rgb * band2 * (0.25 + 0.75 * q.y) * 0.26 * intensity;

	// Big soft orb, top right (or centred for the loading screen).
	vec2 orb_pos = mix(vec2(aspect * 0.86, 0.02), vec2(aspect * 0.5, 0.5), focus_center);
	vec2 od = (p - orb_pos) * vec2(0.75, 1.0);
	float orb = max(0.0, 1.0 - length(od) * 1.15);
	col += mix(accent.rgb, accent2.rgb, 0.35) * orb * orb * 0.32 * intensity;

	// Star dust: one hashed point per cell, most cells empty.
	if (stars > 0.0) {
		vec2 sp = p * 55.0 + vec2(TIME * 0.15, 0.0);
		vec2 cell = floor(sp);
		float h = hash21(cell);
		if (h > 0.982) {
			vec2 off = vec2(hash21(cell + 3.1), hash21(cell + 7.7)) - 0.5;
			float d = length(fract(sp) - 0.5 - off * 0.6);
			float tw = 0.55 + 0.45 * sin(TIME * (0.8 + h * 2.5) + h * 40.0);
			col += vec3(0.85, 0.9, 1.0) * smoothstep(0.09, 0.0, d) * tw * 0.55 * stars * (1.0 - uv.y * 0.5);
		}
	}

	// Vignette and a hair of grain/dither so gradients never band.
	vec2 vc = uv - 0.5;
	col *= 1.0 - dot(vc, vc) * 0.85;
	col += (hash21(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * (1.6 / 255.0);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
