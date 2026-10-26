// The desktop clock's face: white at the top melting into a cool, faintly
// accent-tinted glass tone at the bottom, with a slow sheen passing through.
shader_type canvas_item;

uniform float height = 160.0;
uniform vec4 tone : source_color = vec4(0.78, 0.95, 0.94, 0.9);
uniform float speed = 1.0;

varying float local_y;
varying float local_x;

void vertex() {
	local_y = VERTEX.y;
	local_x = VERTEX.x;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float k = clamp(local_y / height, 0.0, 1.0);
	vec3 face = mix(vec3(1.0), tone.rgb, smoothstep(0.25, 1.0, k));
	// A diagonal sheen every ~14 s, barely there.
	float s = fract(TIME * 0.07 * speed) * 3.0 - 1.0;
	float band = local_x / (height * 2.6) + k * 0.35 - s;
	face += vec3(0.16) * exp(-band * band * 60.0);
	c.rgb *= face;
	c.a *= mix(1.0, tone.a, smoothstep(0.4, 1.0, k));
	COLOR = c;
}
