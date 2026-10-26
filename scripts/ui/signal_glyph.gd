class_name SignalGlyph
extends Control
## Wi-Fi strength as the familiar arcs, lit up to `level` (0-3) with the rest
## kept faint, so a weak network still reads as Wi-Fi. `off` strikes it through.
## Drawn rather than an icon so every level stays crisp at any size.

var level := 3:
	set(v):
		level = v
		queue_redraw()
var off := false:
	set(v):
		off = v
		queue_redraw()
var color := Color(1, 1, 1, 0.9):
	set(v):
		color = v
		queue_redraw()

const RADII := [5.0, 10.0, 15.0]
## Half the sweep of each arc, matching the stroke icons (Icons "wifi").
const HALF := [0.776, 0.776, 0.73]


func _init(px: int = 18) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	# Drawn at its own size, centred in whatever box it's given.
	var s := minf(minf(size.x, size.y), custom_minimum_size.x) / 24.0
	var o := (size - Vector2(24.0, 24.0) * s) / 2.0
	# The glyph spans y 5-21 of its 24 grid: nudge it up to sit centred.
	var c := o + Vector2(12.0, 20.5) * s
	var w := maxf(1.6, 2.0 * s)
	var faint := Color(color, color.a * 0.26)
	var lit := faint if off else color
	draw_circle(c, 1.35 * s, color if not off else faint)
	for i in 3:
		var a: float = HALF[i]
		draw_arc(c, RADII[i] * s, -PI / 2.0 - a, -PI / 2.0 + a, 20, lit if level > i else faint, w, true)
	if off:
		draw_line(o + Vector2(3.5, 4.0) * s, o + Vector2(20.5, 21.0) * s, color, w, true)
