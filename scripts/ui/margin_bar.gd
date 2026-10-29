class_name MarginBar
extends Control
## Your account as one bar: margin already in use, what the order you're
## typing would add, and what stays free. Shares of `total`.

var total := 0.0
var used := 0.0
## The order being typed; 0 when there's none.
var order := 0.0
var used_color := Color(1, 1, 1, 0.42)
var order_color := Color("4fdc9b")
## Over the free money: the order part turns this colour.
var over_color := Color("ff6b81")


func _init() -> void:
	custom_minimum_size.y = 8
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_values(t: float, u: float, o: float) -> void:
	if is_equal_approx(t, total) and is_equal_approx(u, used) and is_equal_approx(o, order):
		return
	total = t
	used = u
	order = o
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := int(size.y * 0.5)
	draw_style_box(Kit.box(Color(1, 1, 1, 0.07), rad), r)
	if total <= 0.0:
		return
	var w_used := clampf(used / total, 0.0, 1.0) * size.x
	var w_order := clampf(order / total, 0.0, 1.0) * size.x
	var over := used + order > total
	w_order = minf(w_order, size.x - w_used)
	if w_used + w_order > 0.5:
		# One rounded shape for both, the order drawn on top of its share.
		draw_style_box(Kit.box(over_color if over else order_color, rad), Rect2(0, 0, maxf(size.y, w_used + w_order), size.y))
	if w_used > 0.5:
		draw_style_box(Kit.box(used_color, rad), Rect2(0, 0, maxf(size.y, w_used), size.y))
