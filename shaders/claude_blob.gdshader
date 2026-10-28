// Claude's avatar in the orb popup: a small jelly of the same water as
// Oazy's orb, sitting on the popup's roof. One rect, drawn in pixels from
// the ground point up, so it stays crisp at any size. Everything that moves
// (squash, lean, wobble, face) is a uniform eased on the CPU by ClaudeBlob;
// the shader only draws the pose it is given.
shader_type canvas_item;

uniform vec2 box = vec2(96.0, 84.0);
// Pixels below the ground point, for the shadow.
uniform float ground = 9.0;
uniform float radius = 22.0;
// How far it has jumped off the floor, in pixels.
uniform float lift = 0.0;
// > 0 wider and flatter, < 0 taller and thinner; volume is kept.
uniform float squash = 0.0;
// The top leans this far sideways for each pixel up (a shear).
uniform float lean = 0.0;
uniform float wobble = 0.3;
// Integrated on the CPU, so speed changes never jump the shape.
uniform float wob_phase = 0.0;
// Where it looks, -1..1 each way (y up), and how far the face turns with it.
uniform vec2 gaze = vec2(0.0);
uniform float blink = 0.0;
// -1 closes the left eye, +1 the right (a wink).
uniform float wink = 0.0;
// Happy eyes: 1 turns them into soft arcs.
uniform float joy = 0.0;
// Heavy upper lids: focused, sleepy, thinking.
uniform float lid = 0.0;
// Inner corners up: worried, sorry.
uniform float worry = 0.0;
uniform float eye_size = 1.0;
// -1 frown .. 1 smile.
uniform float smile = 0.3;
uniform float mouth_open = 0.0;
uniform float mouth_w = 1.0;
uniform float blush = 0.0;
uniform vec4 color_a : source_color = vec4(0.22, 0.84, 0.77, 1.0);
uniform vec4 color_b : source_color = vec4(0.25, 0.55, 1.0, 1.0);
// Errors tint the water warm, like the orb's.
uniform vec4 warn : source_color = vec4(1.0, 0.71, 0.28, 1.0);
uniform float error = 0.0;

float ellipse(vec2 p, vec2 r) {
	// Good enough near the edge, which is all antialiasing needs.
	float k = length(p / r);
	return (k - 1.0) * min(r.x, r.y);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// One eye in its own space: < 0 inside.
float eye(vec2 e, vec2 r, float open, float side) {
	e = rot(e, -worry * 0.38 * side);
	vec2 rr = vec2(r.x, r.y * max(open, 0.12));
	float d = ellipse(e, rr);
	// Happy: an arc, cut from below by a wider copy.
	float cut = ellipse(e + vec2(0.0, r.y * mix(3.2, 0.62, joy)), vec2(r.x * 1.35, r.y * 1.05));
	d = max(d, -cut);
	// Heavy lid: flat across the top.
	d = max(d, e.y - rr.y * (1.0 - lid * 1.1));
	return d;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * box.x, (1.0 - UV.y) * box.y - ground);
	float aa = max(fwidth(p.x), 0.35);
	float R = radius;
	vec3 wa = mix(color_a.rgb, warn.rgb, error);
	vec3 wb = mix(color_b.rgb, warn.rgb * vec3(1.0, 0.62, 0.45), error);

	// --- Shadow on the floor ----------------------------------------------------
	float up = clamp(lift / (R * 1.6), 0.0, 1.0);
	vec2 sp = (p - vec2(lean * R * 0.3, 0.0)) / vec2(R * (1.05 + squash * 0.5) * (1.0 - up * 0.35), R * 0.2 * (1.0 - up * 0.3));
	float shadow = exp(-dot(sp, sp) * 1.6) * 0.26 * (1.0 - up * 0.65);

	// --- Body ---------------------------------------------------------------------
	float sx = 1.0 + squash;
	float sy = 1.0 / sx;
	vec2 b = p - vec2(0.0, lift);
	b.x -= lean * b.y;
	b = b / vec2(sx, sy) - vec2(0.0, R);
	// A gumdrop: settled at the bottom, a touch narrower up top.
	if (b.y < 0.0) {
		b.y *= 1.0 + 0.2 * smoothstep(0.0, -R, b.y);
	}
	b.x *= 1.0 + 0.07 * clamp(b.y / R, 0.0, 1.0);
	float th = atan(b.y, b.x);
	float rr = R * (1.0 + wobble * (0.03 * sin(2.0 * th + wob_phase) + 0.022 * sin(3.0 * th - wob_phase * 1.37) + 0.012 * sin(5.0 * th + wob_phase * 0.7)));
	float d = length(b) - rr;
	float body = 1.0 - smoothstep(-aa, aa, d);

	vec2 n = b / rr;
	float nr = min(length(n), 1.0);
	float z = sqrt(max(1.0 - nr * nr, 0.0));
	float fres = pow(1.0 - z, 2.2);
	// Water seen through jelly: lighter up top, deeper below, a slow caustic.
	vec3 col = mix(wa * 1.02, wb * 0.62, clamp(0.5 - n.y * 0.55, 0.0, 1.0));
	vec2 cq = n * 2.6 + gaze * 0.15;
	float c = sin(cq.x * 2.3 + wob_phase * 0.5 + sin(cq.y * 1.9 - TIME * 0.6)) + sin(cq.y * 2.7 - TIME * 0.7 + sin(cq.x * 1.4 + wob_phase * 0.3));
	c = pow(clamp(1.0 - abs(c) * 0.55, 0.0, 1.0), 5.0);
	col += vec3(0.85, 1.0, 1.0) * c * 0.1 * z;
	// Light comes through at the bottom.
	col += wa * 0.22 * exp(-dot(n - vec2(0.0, -0.62), n - vec2(0.0, -0.62)) * 4.0);
	col += vec3(0.78, 0.92, 1.0) * fres * 0.38;
	// Glossy highlights, as on the orb.
	vec2 h = rot(n - vec2(-0.36, 0.5), 0.6);
	col += vec3(1.0) * exp(-(h.x * h.x * 3.4 + h.y * h.y * 15.0)) * 0.22;
	col += vec3(1.0) * exp(-dot(n - vec2(-0.5, 0.56), n - vec2(-0.5, 0.56)) * 220.0) * 0.6;
	float rim = 1.0 - smoothstep(0.0, 1.4 * aa, abs(d + 0.6 * aa));
	float facing = clamp(dot(normalize(n + 0.0001), normalize(vec2(-0.5, 1.0))), 0.0, 1.0);
	col += vec3(1.0) * rim * mix(0.1, 0.42, facing * facing);
	float alpha = mix(0.62, 0.9, fres) * body;

	// --- Face -----------------------------------------------------------------------
	// It turns a little towards where it looks, so it reads as round.
	vec2 face = b - vec2(gaze.x * R * 0.2, R * 0.06 + gaze.y * R * 0.1);
	float es = eye_size;
	vec2 er = vec2(R * 0.13, R * 0.2) * es;
	float spread = R * 0.36 * (1.0 - abs(gaze.x) * 0.08);
	float open_l = (1.0 - blink) * (1.0 - clamp(-wink, 0.0, 1.0));
	float open_r = (1.0 - blink) * (1.0 - clamp(wink, 0.0, 1.0));
	vec2 el = face - vec2(-spread, 0.0) - gaze * vec2(R * 0.06, R * 0.04);
	vec2 erp = face - vec2(spread, 0.0) - gaze * vec2(R * 0.06, R * 0.04);
	float dl = eye(el, er, open_l, -1.0);
	float dr = eye(erp, er, open_r, 1.0);
	float eyes = 1.0 - smoothstep(-aa, aa, min(dl, dr));
	// A small glint while the eyes are round and open.
	float gl = (1.0 - joy) * min(open_l, open_r) * (1.0 - lid);
	vec2 go = vec2(-er.x * 0.32, er.y * 0.38);
	float glint = max(1.0 - smoothstep(er.x * 0.3 - aa, er.x * 0.3 + aa, length(el - go)), 1.0 - smoothstep(er.x * 0.3 - aa, er.x * 0.3 + aa, length(erp - go))) * gl;

	// Mouth: between a lip curve and a lower one that opens.
	vec2 m = face - vec2(0.0, -R * 0.3);
	float mw = R * 0.19 * mouth_w;
	float k = clamp(m.x / mw, -1.0, 1.0);
	float upper = smile * R * 0.12 * (k * k - 0.35);
	float lower = upper - mouth_open * R * 0.26 * (1.0 - k * k);
	float dy = m.y > upper ? m.y - upper : (m.y < lower ? lower - m.y : 0.0);
	float dm = length(vec2(max(abs(m.x) - mw, 0.0), dy)) - R * 0.05;
	float mouth = 1.0 - smoothstep(-aa, aa, dm);

	vec2 ck = vec2(abs(face.x) - spread * 1.25, face.y + R * 0.3);
	float cheeks = exp(-dot(ck / vec2(R * 0.16, R * 0.08), ck / vec2(R * 0.16, R * 0.08))) * blush * 0.35;

	vec3 ink = vec3(0.035, 0.06, 0.11);
	col = mix(col, vec3(1.0, 0.62, 0.6), cheeks * body);
	float features = max(eyes, mouth) * body;
	col = mix(col, ink, features * 0.94);
	alpha = max(alpha, features * 0.95);
	col = mix(col, vec3(1.0), glint * body * 0.9);

	// Over the shadow.
	vec3 rgb = col;
	float a = alpha + shadow * (1.0 - alpha);
	rgb = a > 0.0 ? (col * alpha) / a : col;
	COLOR = vec4(rgb, a * COLOR.a);
}
