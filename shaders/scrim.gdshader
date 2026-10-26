// Full-screen backdrop for the Alt+Tab switcher: the screen sinks into a deep,
// cool dusk with a soft pool of accent light behind the selected window. It
// leaves clear holes where live previews show (Windows draws them under the
// layer's own pixels).
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 480.0);
uniform vec2 glow_size = vec2(700.0, 380.0);
uniform vec4 accent : source_color = vec4(0.22, 0.84, 0.77, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// x, y, w, h in screen pixels, plus the corner radius of each in radii.
uniform vec4 holes[8];
uniform float radii[8];
uniform int hole_count = 0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * rect_size;
	// Darker towards the edges, like a lens.
	vec2 c = UV - 0.5;
	float vignette = smoothstep(0.2, 0.85, length(c * vec2(1.0, 1.25)));
	vec2 f = (p - focus) / glow_size;
	float pool = exp(-dot(f, f) * 1.6);
	vec3 base = mix(vec3(0.012, 0.03, 0.045), vec3(0.0, 0.006, 0.012), vignette);
	vec3 col = base + accent.rgb * pool * 0.14;
	float a = mix(0.9, 0.96, vignette) - pool * 0.04;
	for (int i = 0; i < 8; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 h = holes[i];
		float hd = sd_box(p - (h.xy + h.zw * 0.5), h.zw * 0.5, radii[i]);
		a *= smoothstep(-0.8, 0.8, hd);
	}
	COLOR = vec4(col, a * amount);
}
