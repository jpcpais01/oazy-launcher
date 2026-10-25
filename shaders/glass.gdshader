// Liquid glass panel. Blurs whatever is behind it (screen texture mipmaps plus
// a few taps), bends it near the rounded edge like a thick lens, then adds an
// Aero-style top sheen and a rim light that catches from the top-left.
// One screen read per tap, everything else is ALU on a single quad.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 rect_size = vec2(400.0, 300.0);
uniform float radius = 22.0;
uniform vec4 tint : source_color = vec4(0.03, 0.09, 0.12, 0.5);
uniform float blur : hint_range(0.0, 6.0) = 3.6;
uniform float refraction = 12.0;
uniform float bevel = 18.0;
uniform float rim : hint_range(0.0, 2.0) = 1.0;
uniform float sheen : hint_range(0.0, 2.0) = 1.0;
uniform float saturation = 1.3;
uniform float use_screen : hint_range(0.0, 1.0) = 1.0;
uniform vec4 glow_color : source_color = vec4(0.35, 0.95, 0.88, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 hs = rect_size * 0.5;
	vec2 p = UV * rect_size - hs;
	float r = min(radius, min(hs.x, hs.y));
	float d = sd_box(p, hs, r);
	float px = max(fwidth(d), 0.0001);
	float alpha = clamp(0.5 - d / px, 0.0, 1.0);

	vec2 n = vec2(
		sd_box(p + vec2(0.5, 0.0), hs, r) - sd_box(p - vec2(0.5, 0.0), hs, r),
		sd_box(p + vec2(0.0, 0.5), hs, r) - sd_box(p - vec2(0.0, 0.5), hs, r));
	n = n / max(length(n), 0.0001);
	float edge = clamp(1.0 + d / bevel, 0.0, 1.0);
	float lens = edge * edge * edge;

	vec3 col = tint.rgb;
	if (use_screen > 0.5) {
		vec2 uv = SCREEN_UV - n * lens * refraction * SCREEN_PIXEL_SIZE;
		vec2 o = SCREEN_PIXEL_SIZE * exp2(blur) * 0.7;
		vec3 acc = textureLod(screen_tex, uv, blur).rgb * 2.0;
		acc += textureLod(screen_tex, uv + vec2(o.x, o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(-o.x, o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(o.x, -o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(-o.x, -o.y), blur).rgb;
		col = acc / 6.0;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(l), col, saturation);
		col = mix(col, tint.rgb, tint.a);
	}

	// Aero sheen: a soft reflection across the top, fading out by mid-panel.
	float top = UV.y * rect_size.y;
	col += vec3(1.0) * (1.0 - smoothstep(0.0, min(rect_size.y * 0.55, 70.0), top)) * 0.055 * sheen;
	// Light gathered in the thick edge of the glass.
	col += vec3(0.85, 0.97, 1.0) * lens * 0.07 * rim;
	// Rim: a hairline that is bright where it faces the light (top-left).
	float line = 1.0 - smoothstep(0.0, 1.4 * px, abs(d + 0.9 * px));
	float facing = clamp(dot(-n, normalize(vec2(0.45, 1.0))) * 0.5 + 0.5, 0.0, 1.0);
	col += vec3(1.0) * line * mix(0.07, 0.5, facing * facing) * rim;
	// Optional accent glow on the edge (focused windows, hot buttons).
	col += glow_color.rgb * glow * (1.0 - smoothstep(0.0, 5.0 * px, abs(d + 1.5 * px))) * 0.55;

	COLOR = vec4(col, alpha * COLOR.a);
}
