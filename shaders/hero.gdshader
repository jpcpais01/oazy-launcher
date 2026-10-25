// Full-screen hero artwork, faded into the backdrop on the left and bottom so
// text always stays readable. Masks use SCREEN_UV, so any crop works.
shader_type canvas_item;

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float darken : hint_range(0.0, 1.0) = 0.18;
uniform vec4 tint : source_color = vec4(0.07, 0.07, 0.12, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 s = SCREEN_UV;
	float left = smoothstep(0.02, 0.62, s.x);
	float bottom = 1.0 - smoothstep(0.42, 0.98, s.y);
	float top = smoothstep(0.0, 0.12, s.y);
	float mask = mix(0.22, 1.0, left) * mix(0.12, 1.0, bottom) * mix(0.6, 1.0, top);
	vec3 col = mix(tex.rgb, tint.rgb, darken);
	COLOR = vec4(col, tex.a * mask * fade * COLOR.a);
}
