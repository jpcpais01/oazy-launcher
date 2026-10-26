class_name Sparkline
extends Control
## A day's prices as one smooth line with a soft fade under it, a faint
## dotted rule at the previous close and a small dot where it is now.

var points: PackedFloat32Array = []
var base := NAN
var color := Color.WHITE
## Line thickness, and how strong the fade under it starts.
var width := 1.5
var fill := 0.16
## Quiet the tick-by-tick jitter with a short moving average (0 = raw).
var smooth := 1
## The scale always reaches down to `floor` and up to `ceil` (NAN: just the
## data), so a meter like CPU load doesn't blow small wiggles up into peaks.
var floor_v := NAN
var ceil_v := NAN


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(values: Array, prev: float, c: Color) -> void:
	points = PackedFloat32Array(values)
	if smooth > 0 and points.size() > smooth * 2 + 2:
		var soft := PackedFloat32Array()
		soft.resize(points.size())
		for i in points.size():
			var sum := 0.0
			var n := 0
			for j in range(maxi(0, i - smooth), mini(points.size(), i + smooth + 1)):
				sum += points[j]
				n += 1
			soft[i] = sum / n
		# The latest price stays exact: the dot is where it is now.
		soft[soft.size() - 1] = points[points.size() - 1]
		points = soft
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
	if not is_nan(floor_v):
		lo = minf(lo, floor_v)
	if not is_nan(ceil_v):
		hi = maxf(hi, ceil_v)
	var span := maxf(hi - lo, absf(hi) * 0.002 + 0.0001)
	var pad := 4.0
	var right := 4.0
	var h := size.y - pad * 2.0
	var w := size.x - right
	var line := PackedVector2Array()
	var n := points.size()
	for i in n:
		line.append(Vector2(w * i / float(n - 1), pad + h * (1.0 - (points[i] - lo) / span)))
	# The fade under the line, as a strip of trapezoids (always convex), from
	# `fill` at the line down to nothing at the bottom.
	var top := Color(color, fill)
	var bottom := Color(color, 0.0)
	for i in n - 1:
		var p0 := line[i]
		var p1 := line[i + 1]
		draw_primitive(
			PackedVector2Array([p0, p1, Vector2(p1.x, size.y), Vector2(p0.x, size.y)]),
			PackedColorArray([top.lerp(bottom, p0.y / size.y * 0.7), top.lerp(bottom, p1.y / size.y * 0.7), bottom, bottom]),
			PackedVector2Array())
	if not is_nan(base):
		var y := roundf(pad + h * (1.0 - (base - lo) / span)) + 0.5
		draw_dashed_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.14), 1.0, 2.0)
	draw_polyline(line, color, width, true)
	var end := line[n - 1]
	draw_circle(end, width + 2.2, Color(color, 0.22), true, -1.0, true)
	draw_circle(end, width + 0.6, color, true, -1.0, true)
