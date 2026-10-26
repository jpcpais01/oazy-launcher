// Liquid glass. Shows what is behind it, softly blurred and bent near the
// rounded edge like a thick lens, under a light tint, with a hairline rim that
// catches the light on two opposite corners.
//   source 1: the screen behind (one window: blurs Oazy's own windows too)
//   source 2: the wallpaper behind, computed (shell mode, where each layer is
//             its own window and can't see the others)
//   source 0: just the tint (eco)
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/wall.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 rect_size = vec2(400.0, 300.0);
uniform float radius = 22.0;
uniform vec4 tint : source_color = vec4(0.06, 0.07, 0.09, 0.5);
uniform float blur : hint_range(0.0, 6.0) = 4.0;
uniform float refraction = 5.0;
uniform float bevel = 8.0;
uniform float rim : hint_range(0.0, 2.0) = 1.0;
uniform float saturation = 1.25;
uniform int source = 1;
// Screen size in pixels, for source 2.
uniform vec2 screen_px = vec2(1920.0, 1080.0);
uniform vec4 glow_color : source_color = vec4(0.35, 0.95, 0.88, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// Optional tail under the pane pointing down at what opened it (the task
// manager's taskbar button): its tip's x in pixels (< 0: none), its height
// (the bottom strip of the rect it hangs in) and its half width.
uniform float tail_x = -1.0;
uniform float tail_h = 0.0;
uniform float tail_w = 11.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Inigo Quilez's isosceles triangle: tip at the origin, base at y = q.y.
float sd_tri(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// The pane's shape at pixel `q` of the rect: a rounded box, plus the tail
// melted into its bottom edge when there is one.
float shape(vec2 q) {
	float th = tail_x >= 0.0 ? tail_h : 0.0;
	vec2 hs = vec2(rect_size.x, rect_size.y - th) * 0.5;
	float r = min(radius, min(hs.x, hs.y));
	float d = sd_box(q - hs, hs, r);
	if (tail_x >= 0.0) {
		// Its tip is rounded off, and it joins the pane in a soft fillet.
		float round_r = 2.5;
		vec2 tp = vec2(q.x - tail_x, rect_size.y - round_r - q.y);
		float t = sd_tri(tp, vec2(tail_w, th + 4.0)) - round_r;
		float k = 7.0;
		float h = max(k - abs(d - t), 0.0) / k;
		d = min(d, t) - h * h * k * 0.25;
	}
	return d;
}

void fragment() {
	vec2 q = UV * rect_size;
	float d = shape(q);
	float px = max(fwidth(d), 0.0001);
	float alpha = clamp(0.5 - d / px, 0.0, 1.0);

	vec2 n = vec2(
		shape(q + vec2(0.5, 0.0)) - shape(q - vec2(0.5, 0.0)),
		shape(q + vec2(0.0, 0.5)) - shape(q - vec2(0.0, 0.5)));
	n = n / max(length(n), 0.0001);
	float edge = clamp(1.0 + d / bevel, 0.0, 1.0);
	float lens = edge * edge * edge;

	vec3 col = tint.rgb;
	if (source == 1) {
		vec2 uv = SCREEN_UV - n * lens * refraction * SCREEN_PIXEL_SIZE;
		vec2 o = SCREEN_PIXEL_SIZE * exp2(blur) * 0.7;
		vec3 acc = textureLod(screen_tex, uv, blur).rgb * 2.0;
		acc += textureLod(screen_tex, uv + vec2(o.x, o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(-o.x, o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(o.x, -o.y), blur).rgb;
		acc += textureLod(screen_tex, uv + vec2(-o.x, -o.y), blur).rgb;
		col = acc / 6.0;
	} else if (source == 2) {
		vec2 uv = (FRAGCOORD.xy - n * lens * refraction * 2.0) / screen_px;
		col = wall_color(uv, TIME);
	}
	if (source != 0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(l), col, saturation);
		col = mix(col, tint.rgb, tint.a);
	}

	// Light gathered in the thick edge of the glass.
	col += vec3(0.9, 0.96, 1.0) * lens * 0.02 * rim;
	// Hairline rim, brightest where it faces the light (top-left) and its
	// reflection (bottom-right), quiet along the sides in between.
	float line = 1.0 - smoothstep(0.0, 1.3 * px, abs(d + 0.8 * px));
	float facing = abs(dot(n, normalize(vec2(-0.55, -1.0))));
	col += vec3(1.0) * line * mix(0.06, 0.24, facing * facing * facing) * rim;
	// Optional accent glow on the edge (focused windows, hot buttons).
	col += glow_color.rgb * glow * (1.0 - smoothstep(0.0, 2.5 * px, abs(d + 1.0 * px))) * 0.5;

	COLOR = vec4(col, alpha * COLOR.a);
}
