// Full-screen backdrop for the Alt+Tab switcher: the screen sinks into a deep,
// cool dusk with a soft pool of accent light behind the selected window.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 480.0);
uniform vec2 glow_size = vec2(700.0, 380.0);
uniform vec4 accent : source_color = vec4(0.22, 0.84, 0.77, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * rect_size;
	// Darker towards the edges, like a lens.
	vec2 c = UV - 0.5;
	float vignette = smoothstep(0.2, 0.85, length(c * vec2(1.0, 1.25)));
	float pool = exp(-dot((p - focus) / glow_size, (p - focus) / glow_size) * 1.6);
	vec3 base = mix(vec3(0.012, 0.03, 0.045), vec3(0.0, 0.006, 0.012), vignette);
	vec3 col = base + accent.rgb * pool * 0.16;
	float a = mix(0.86, 0.95, vignette) - pool * 0.08;
	COLOR = vec4(col, a * amount);
}
