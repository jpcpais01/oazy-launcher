// One window of the Alt+Tab stack, drawn in perspective: the node covers the
// card's footprint on screen, and every pixel is mapped back onto the tilted
// card (inverse homography) to find what it shows there. Rounded corners,
// the picture (or the app's icon on a quiet pane) and a soft shadow, all in
// the card's own plane so they lean with it.
shader_type canvas_item;

uniform mat3 hinv;
uniform vec2 origin;
uniform vec2 size = vec2(400.0, 250.0);
uniform float radius = 14.0;
uniform vec4 fill : source_color = vec4(0.075, 0.082, 0.095, 1.0);
uniform sampler2D pic : source_color, filter_linear_mipmap;
uniform float has_pic = 0.0;
uniform sampler2D glyph : source_color, filter_linear;
uniform vec2 glyph_size = vec2(160.0, 140.0);
uniform float has_glyph = 0.0;
uniform float shade = 1.0;
uniform float shadow_a = 0.3;
uniform float shadow_size = 30.0;
uniform float shadow_drop = 14.0;
// A faint wash of light across the glass, brightest at the top-left.
uniform float sheen = 0.05;

varying vec2 local;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec3 q = hinv * vec3(origin + local, 1.0);
	if (q.z <= 0.0) {
		discard;
	}
	vec2 p = q.xy / q.z;
	vec2 half_size = size * 0.5;
	float d = sd_box(p - half_size, half_size, radius);
	float aa = clamp(fwidth(d), 0.5, 3.0);
	float a = 1.0 - smoothstep(-aa, aa, d);
	vec3 col = fill.rgb;
	vec2 uv = clamp(p / size, 0.0, 1.0);
	if (has_pic > 0.5) {
		col = texture(pic, uv).rgb;
	} else if (has_glyph > 0.5) {
		vec2 g = (p - (half_size - glyph_size * 0.5)) / glyph_size;
		if (g.x >= 0.0 && g.y >= 0.0 && g.x <= 1.0 && g.y <= 1.0) {
			vec4 gc = texture(glyph, g);
			col = mix(col, gc.rgb, gc.a);
		}
	}
	col += sheen * (1.0 - smoothstep(0.0, 0.75, (uv.x + uv.y) * 0.5));
	col *= shade;
	float sd = sd_box(p - half_size - vec2(0.0, shadow_drop), half_size, radius);
	float s = shadow_a * exp(-max(sd, 0.0) / max(shadow_size, 1.0) * 2.2);
	float out_a = a + s * (1.0 - a);
	COLOR = vec4(col * a / max(out_a, 0.0001), out_a * COLOR.a);
}
