// The Oazy wallpaper (see wall.gdshaderinc): calm pools of colour that follow
// the time of day, plus a hair of grain so the gradients never band.
shader_type canvas_item;

#include "res://shaders/wall.gdshaderinc"

float grain(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 col = wall_color(UV, TIME);
	col += (grain(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * (1.8 / 255.0);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
