// Thin progress bar with an animated shimmer, used on the loading screen.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_a : source_color = vec4(0.486, 0.424, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform vec2 rect_size = vec2(320.0, 4.0);

void fragment() {
	vec2 px = UV * rect_size;
	float r = rect_size.y * 0.5;
	vec2 q = abs(px - rect_size * 0.5) - (rect_size * 0.5 - r);
	float d = length(max(q, 0.0)) - r;
	float alpha = clamp(0.5 - d, 0.0, 1.0);
	float filled = step(UV.x, progress);
	vec3 col = mix(color_a.rgb, color_b.rgb, UV.x);
	float shimmer = 1.0 - smoothstep(0.0, 0.08, abs(fract(TIME * 0.45) * 1.4 - 0.2 - UV.x));
	col += vec3(shimmer * 0.5);
	vec4 track = vec4(1.0, 1.0, 1.0, 0.08);
	vec4 outc = mix(track, vec4(col, 1.0), filled);
	COLOR = vec4(outc.rgb, outc.a * alpha * COLOR.a);
}
