// The Oazy wallpaper: a calm sky that follows the time of day, silky Aero
// light ribbons, low dunes catching the light on the horizon and a few glass
// bubbles drifting up. Everything is procedural (no textures): a handful of
// sines, three value-noise lookups and one hashed grid per pixel.
shader_type canvas_item;

uniform vec4 sky_top : source_color = vec4(0.03, 0.13, 0.2, 1.0);
uniform vec4 sky_mid : source_color = vec4(0.05, 0.33, 0.4, 1.0);
uniform vec4 horizon : source_color = vec4(0.85, 0.62, 0.42, 1.0);
uniform vec4 ground : source_color = vec4(0.05, 0.1, 0.12, 1.0);
uniform vec4 accent : source_color = vec4(0.2, 0.82, 0.76, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float horizon_glow : hint_range(0.0, 2.0) = 0.6;
uniform float ribbons : hint_range(0.0, 2.0) = 1.0;
uniform float bubbles : hint_range(0.0, 1.0) = 1.0;
uniform float speed : hint_range(0.0, 4.0) = 1.0;
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
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// A silk ribbon: soft body plus a crisp bright lip on its upper edge.
vec3 ribbon(float y, float center, float width, vec3 tint_col, float strength) {
	float dy = y - center;
	float body = exp(-(dy * dy) / (width * width));
	float lip = exp(-pow((dy + width * 0.55) / (width * 0.09), 2.0));
	return tint_col * (body * 0.55 + lip * 0.6) * strength;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * 0.02 * speed;

	// Sky: top -> mid -> warm horizon band.
	vec3 col = mix(sky_top.rgb, sky_mid.rgb, smoothstep(0.0, 0.72, uv.y));
	float hz = exp(-pow((uv.y - 0.8) / 0.14, 2.0));
	col = mix(col, horizon.rgb, hz * 0.55 * horizon_glow);

	// Soft sun / moon bloom, top left (centred on the boot screen).
	vec2 sun = mix(vec2(aspect * 0.22, 0.16), vec2(aspect * 0.5, 0.46), focus_center);
	float sd = length((p - sun) * vec2(0.8, 1.0));
	col += sun_color.rgb * (exp(-sd * sd * 9.0) * 0.16 + exp(-sd * sd * 70.0) * 0.06);

	// Gentle large-scale variation so the sky never looks flat.
	float n = vnoise(p * 1.4 + vec2(t * 2.0, -t));
	col *= 0.94 + 0.12 * n;

	// Aero light ribbons sweeping across.
	float w1 = vnoise(vec2(p.x * 0.9 + t * 3.0, 3.1));
	float w2 = vnoise(vec2(p.x * 1.2 - t * 2.4, 7.7));
	float c1 = 0.42 + 0.13 * sin(p.x * 1.15 + t * 6.0 + 0.6) + 0.07 * (w1 - 0.5);
	float c2 = 0.53 + 0.11 * sin(p.x * 1.55 - t * 5.0 + 2.1) + 0.06 * (w2 - 0.5);
	float c3 = 0.36 + 0.16 * sin(p.x * 0.8 + t * 3.6 + 4.0);
	vec3 ribbon_a = mix(accent.rgb, vec3(0.75, 1.0, 0.98), 0.25);
	vec3 ribbon_b = mix(accent.rgb, sky_mid.rgb * 2.0, 0.5);
	col += ribbon(uv.y, c1, 0.055 + 0.02 * sin(p.x * 2.0 + t * 4.0), ribbon_a, 0.16 * ribbons);
	col += ribbon(uv.y, c2, 0.035, ribbon_b, 0.12 * ribbons);
	col += ribbon(uv.y, c3, 0.09, vec3(0.9, 0.97, 1.0), 0.035 * ribbons);

	// Dunes: two low rolling layers, crest lit by the horizon light.
	float d1 = 0.83 + 0.03 * sin(p.x * 1.9 + 1.3) + 0.018 * sin(p.x * 4.3 + 0.4);
	float d2 = 0.9 + 0.025 * sin(p.x * 2.6 + 4.1) + 0.012 * sin(p.x * 6.1);
	float m1 = smoothstep(d1 - 0.004, d1 + 0.004, uv.y);
	float m2 = smoothstep(d2 - 0.004, d2 + 0.004, uv.y);
	vec3 dune1 = mix(ground.rgb, horizon.rgb, 0.22);
	vec3 dune2 = ground.rgb;
	col = mix(col, mix(col, dune1, 0.55), m1);
	col = mix(col, mix(col, dune2, 0.7), m2);
	col += horizon.rgb * exp(-pow((uv.y - d1) / 0.006, 2.0)) * 0.12 * horizon_glow;
	col += horizon.rgb * exp(-pow((uv.y - d2) / 0.005, 2.0)) * 0.07 * horizon_glow;

	// Glass bubbles drifting upwards (Frutiger Aero), one per lucky grid cell.
	if (bubbles > 0.0) {
		vec2 bp = p * vec2(5.0, 5.0) + vec2(0.0, TIME * 0.035 * speed);
		vec2 cell = floor(bp);
		float h = hash21(cell);
		if (h > 0.8) {
			vec2 c = vec2(hash21(cell + 3.1), hash21(cell + 7.7)) * 0.6 + 0.2;
			c.x += 0.08 * sin(TIME * 0.2 * speed + h * 30.0);
			float rad = 0.08 + 0.14 * hash21(cell + 1.9);
			float dist = length(fract(bp) - c);
			float ring = smoothstep(rad, rad - 0.03, dist) * smoothstep(rad - 0.09, rad - 0.01, dist);
			float fill = smoothstep(rad, rad * 0.2, dist);
			vec2 spec_pos = c + vec2(-0.35, -0.35) * rad;
			float spec = smoothstep(rad * 0.28, 0.0, length(fract(bp) - spec_pos));
			float fade = smoothstep(0.95, 0.35, uv.y) * (0.5 + 0.5 * h);
			col += (vec3(0.8, 1.0, 1.0) * ring * 0.16 + accent.rgb * fill * 0.04 + vec3(1.0) * spec * 0.18) * fade * bubbles;
		}
	}

	// Vignette and a hair of grain so gradients never band.
	vec2 vc = uv - vec2(0.5, 0.45);
	col *= 1.0 - dot(vc, vc) * 0.55;
	col += (hash21(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * (1.6 / 255.0);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
