// Full-screen backdrop for the Alt+Tab switcher: the screen quietly sinks into
// a neutral dusk, a touch deeper towards the edges.
shader_type canvas_item;
render_mode unshaded;

uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 c = UV - 0.5;
	float vignette = smoothstep(0.15, 0.85, length(c * vec2(1.0, 1.3)));
	vec3 col = mix(vec3(0.02, 0.028, 0.036), vec3(0.008, 0.01, 0.014), vignette);
	float a = mix(0.88, 0.94, vignette);
	COLOR = vec4(col, a * amount * COLOR.a);
}
