// Rounded artwork tile. Crops the texture to fill (like CSS object-fit: cover),
// or paints a soft gradient cover when there is no art. Adds a focus ring and
// a light sweep. Drawn on a plain ColorRect.
shader_type canvas_item;

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_art = false;
uniform vec2 art_size = vec2(600.0, 900.0);
uniform vec2 rect_size = vec2(200.0, 300.0);
uniform float radius = 16.0;
uniform vec4 color_a : source_color = vec4(0.45, 0.35, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.05, 0.55, 0.9, 1.0);
uniform float seed = 0.0;
uniform float focus : hint_range(0.0, 1.0) = 0.0;
uniform float sweep = -1.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform float zoom : hint_range(0.0, 0.2) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec4 vcol = COLOR;
	vec2 uv = UV;
	vec2 px = uv * rect_size;
	float d = sd_round_box(px - rect_size * 0.5, rect_size * 0.5, radius);
	float alpha = clamp(0.5 - d, 0.0, 1.0);

	vec3 col;
	if (has_art) {
		float ra = rect_size.x / rect_size.y;
		float ta = art_size.x / max(art_size.y, 1.0);
		vec2 sc = ra > ta ? vec2(1.0, ta / ra) : vec2(ra / ta, 1.0);
		vec2 tuv = (uv - 0.5) * sc * (1.0 - zoom) + 0.5;
		col = texture(art, tuv).rgb;
	} else {
		float wave = 0.12 * sin(uv.x * 5.0 + seed * 6.28);
		col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, uv.y * 0.85 + uv.x * 0.25 + wave));
		vec2 c1 = vec2(0.72 + 0.12 * sin(seed * 9.0), 0.22 + 0.08 * cos(seed * 5.0));
		float blob = max(0.0, 1.0 - length((uv - c1) * vec2(rect_size.x / rect_size.y, 1.0)) * 2.2);
		col += vec3(1.0) * blob * blob * 0.12;
		col *= 1.0 - smoothstep(0.55, 1.0, uv.y) * 0.35;
	}

	// Light sweep moving diagonally across.
	float sw = 1.0 - smoothstep(0.0, 0.1, abs((uv.x + uv.y * 0.6) - sweep));
	col += vec3(1.0) * sw * 0.22;

	col *= 1.0 - dim;

	// Focus ring hugging the rounded edge.
	float ring = (1.0 - smoothstep(1.0, 2.6, abs(d + 2.2))) * focus;
	col = mix(col, ring_color.rgb, ring);

	COLOR = vec4(col * vcol.rgb, alpha * vcol.a);
}
