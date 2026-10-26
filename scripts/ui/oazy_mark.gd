class_name OazyMark
extends Control
## Oazy's mark, drawn as vectors so it is crisp at any size: an open ring with
## round ends and a drop resting just outside the gap. It floats inside the
## water orb (UpdateOrb), and the two together are the Oazy icon.

## Ring radius (to the middle of the stroke) as a fraction of the control's size.
var ring := 0.21
var color := Color.WHITE
var shadow := Color(0.0, 0.08, 0.12, 0.28)


func _init(ring_fraction: float = 0.21) -> void:
	ring = ring_fraction
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := s * ring
	var c := size / 2.0 + Vector2(-0.04, 0.09) * r
	_draw_mark(c + Vector2(0.0, maxf(r * 0.07, 1.0)), r, shadow)
	_draw_mark(c, r, color)


func _draw_mark(c: Vector2, r: float, col: Color) -> void:
	var w := r * 0.4
	var a0 := deg_to_rad(-37.0)
	var a1 := deg_to_rad(265.0)
	draw_arc(c, r, a0, a1, 64, col, w, true)
	draw_circle(c + Vector2.from_angle(a0) * r, w * 0.5, col, true, -1.0, true)
	draw_circle(c + Vector2.from_angle(a1) * r, w * 0.5, col, true, -1.0, true)
	draw_circle(c + Vector2.from_angle(deg_to_rad(-62.0)) * r * 1.24, r * 0.3, col, true, -1.0, true)


## The Oazy icon, live: the water orb, full and turning slowly, with the mark
## floating in it. `orb_size` is the orb's radius as part of the half size.
static func icon(px: float, orb_size: float = 0.9, swirl: float = -0.35) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(px, px)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var orb := UpdateOrb.new(px, orb_size)
	orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orb.snap(1.0)
	orb.mat.set_shader_parameter("swirl", swirl)
	orb.mat.set_shader_parameter("waves", 0.4)
	orb.mat.set_shader_parameter("ripples", 0.0)
	box.add_child(orb)
	var mark := OazyMark.new(0.21 * orb_size)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(mark)
	box.set_meta("orb", orb)
	box.set_meta("mark", mark)
	return box
