// The launch screen's backdrop: the game's art, already blurred on the CPU,
// darkened towards a deep tint with a soft vignette and a calmer centre so the
// logo always reads. Dithered so the smooth gradients never band.
shader_type canvas_item;

uniform float darken : hint_range(0.0, 1.0) = 0.4;
uniform vec4 tint : source_color = vec4(0.02, 0.035, 0.05, 1.0);

void fragment() {
	vec3 col = mix(texture(TEXTURE, UV).rgb, tint.rgb, darken);
	vec2 s = (SCREEN_UV - 0.5) * vec2(1.0, 1.25);
	float r = length(s);
	col *= mix(1.0, 0.5, smoothstep(0.3, 0.9, r));
	// A wide, faint pool of shade behind the logo and status line.
	col *= 1.0 - 0.14 * (1.0 - smoothstep(0.0, 0.4, r));
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) / 255.0;
	COLOR = vec4(col, COLOR.a);
}
