class_name Sparkline
extends Control
## A day's prices as one smooth line with a soft fade under it, and a faint
## dotted rule at the previous close.

var points: PackedFloat32Array = []
var base := NAN
var color := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(values: Array, prev: float, c: Color) -> void:
	points = PackedFloat32Array(values)
	base = prev
	color = c
	queue_redraw()


func _draw() -> void:
	if points.size() < 2 or size.x < 4.0:
		return
	var lo := points[0]
	var hi := points[0]
	for v in points:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if not is_nan(base):
		lo = minf(lo, base)
		hi = maxf(hi, base)
	var span := maxf(hi - lo, absf(hi) * 0.002 + 0.0001)
	var pad := 2.0
	var h := size.y - pad * 2.0
	var line := PackedVector2Array()
	var n := points.size()
	for i in n:
		line.append(Vector2(size.x * i / float(n - 1), pad + h * (1.0 - (points[i] - lo) / span)))
	# The fade under the line, as a strip of trapezoids (always convex).
	var top := Color(color, 0.16)
	var bottom := Color(color, 0.0)
	for i in n - 1:
		var p0 := line[i]
		var p1 := line[i + 1]
		draw_primitive(
			PackedVector2Array([p0, p1, Vector2(p1.x, size.y), Vector2(p0.x, size.y)]),
			PackedColorArray([top.lerp(bottom, p0.y / size.y * 0.6), top.lerp(bottom, p1.y / size.y * 0.6), bottom, bottom]),
			PackedVector2Array())
	if not is_nan(base):
		var y := pad + h * (1.0 - (base - lo) / span)
		draw_dashed_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.18), 1.0, 3.0)
	draw_polyline(line, color, 1.6, true)
	draw_circle(line[n - 1], 2.4, color, true, -1.0, true)
