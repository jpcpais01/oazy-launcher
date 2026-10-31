// A soft frosted veil behind Claude on the orb popup's roof: what's behind it,
// blurred and lightly smoked, strongest where it meets the glass and fading to
// nothing toward the top and the sides, so the jelly reads over any desktop.
// Same sources as glass.gdshader:
//   source 1: the screen behind (reuses the popup glass's back buffer copy)
//   source 2: the wallpaper behind, computed (shell mode)
//   source 0: just the smoke (eco)
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/wall.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 rect_size = vec2(468.0, 82.0);
uniform vec4 tint : source_color = vec4(0.055, 0.065, 0.085, 0.58);
uniform int source = 1;
uniform vec2 screen_px = vec2(1920.0, 1080.0);
// How far in from each side it fades out (the glass's corners curve away).
uniform float side = 44.0;

void fragment() {
	vec2 q = UV * rect_size;
	// Bottom up: an eased ramp so the very top is all but clear.
	float v = pow(smoothstep(0.0, 1.0, UV.y), 1.3);
	float h = smoothstep(0.0, side, q.x) * smoothstep(0.0, side, rect_size.x - q.x);
	float k = v * h;

	vec3 col = tint.rgb;
	if (source == 1) {
		// Blur grows with the veil: sharper up where it's thin anyway.
		float lod = mix(2.5, 5.0, v);
		vec2 o = SCREEN_PIXEL_SIZE * exp2(lod) * 0.7;
		vec3 acc = textureLod(screen_tex, SCREEN_UV, lod).rgb * 2.0;
		acc += textureLod(screen_tex, SCREEN_UV + vec2(o.x, o.y), lod).rgb;
		acc += textureLod(screen_tex, SCREEN_UV + vec2(-o.x, o.y), lod).rgb;
		acc += textureLod(screen_tex, SCREEN_UV + vec2(o.x, -o.y), lod).rgb;
		acc += textureLod(screen_tex, SCREEN_UV + vec2(-o.x, -o.y), lod).rgb;
		col = mix(acc / 6.0, tint.rgb, 0.4 * v);
	} else if (source == 2) {
		col = mix(wall_color(FRAGCOORD.xy / screen_px, TIME), tint.rgb, 0.4 * v);
	} else {
		k *= 0.6;
	}

	COLOR = vec4(col, k * 0.94 * COLOR.a);
}
