class_name OrderBookView
extends Control
## The order book, drawn in one pass so it can redraw every update for free:
## asks above (worst on top, best nearest the middle), the mid price and the
## spread across the middle, bids below. A soft bar behind each level shows
## the depth piled up to it. Clicking a level offers its price (`picked`).

signal picked(price: float)

const ROW_H := 23.0
const HEAD_H := 26.0
const MID_H := 48.0

var up := Color("4fdc9b")
var down := Color("ff6b81")
var bids: Array = []
var asks: Array = []
var sz_decimals := 4
var coin := ""
## Which way the last trade went, to tint the mid price (1 up, -1 down, 0 none).
var last_dir := 0

var _hover := -1.0
## [top y, price] of each level drawn, for clicks.
var _levels: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		_hover = -1.0
		queue_redraw()
	)
	resized.connect(queue_redraw)


func set_book(b: Dictionary, decimals: int, c: String) -> void:
	bids = b.get("bids", [])
	asks = b.get("asks", [])
	sz_decimals = decimals
	coin = c
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = (event as InputEventMouseMotion).position.y
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var y := (event as InputEventMouseButton).position.y
		for l in _levels:
			if y >= float(l[0]) and y < float(l[0]) + ROW_H:
				picked.emit(float(l[1]))
				accept_event()
				return


## Levels shown on each side at this height.
func per_side() -> int:
	return clampi(floori((size.y - HEAD_H - MID_H) / 2.0 / ROW_H), 1, 20)


func _draw() -> void:
	var f := DesktopBelow._num_font(500)
	var fb := DesktopBelow._num_font(600)
	var w := size.x
	var c1 := w * 0.36
	var c2 := w * 0.7
	draw_string(f, Vector2(0, 16), "Price", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, App.TEXT_MUTE)
	draw_string(f, Vector2(0, 16), "Size" + (" (%s)" % coin if coin != "" else ""), HORIZONTAL_ALIGNMENT_RIGHT, c2 - 4.0, 11, App.TEXT_MUTE)
	draw_string(f, Vector2(0, 16), "Total", HORIZONTAL_ALIGNMENT_RIGHT, w, 11, App.TEXT_MUTE)
	if bids.is_empty() or asks.is_empty():
		draw_string(f, Vector2(0, size.y * 0.5), "Loading the book…", HORIZONTAL_ALIGNMENT_CENTER, w, 14, App.TEXT_MUTE)
		return
	_levels.clear()
	var n := per_side()
	var a := asks.slice(0, n)
	var b := bids.slice(0, n)
	var cum_a := []
	var cum_b := []
	var t := 0.0
	for l in a:
		t += float(l[1])
		cum_a.append(t)
	t = 0.0
	for l in b:
		t += float(l[1])
		cum_b.append(t)
	var most := maxf(cum_a[cum_a.size() - 1], cum_b[cum_b.size() - 1])
	var asks_top := HEAD_H + (n - a.size()) * ROW_H
	# Asks: worst at the top, best just above the middle.
	for i in a.size():
		var y := asks_top + (a.size() - 1 - i) * ROW_H
		_row(y, a[i], float(cum_a[i]), most, down, f, fb, c1, c2)
	var mid_y := HEAD_H + n * ROW_H
	var best_bid := float(b[0][0])
	var best_ask := float(a[0][0])
	var mid := (best_bid + best_ask) * 0.5
	draw_line(Vector2(0, mid_y + 0.5), Vector2(w, mid_y + 0.5), Color(1, 1, 1, 0.05), 1.0)
	draw_line(Vector2(0, mid_y + MID_H - 0.5), Vector2(w, mid_y + MID_H - 0.5), Color(1, 1, 1, 0.05), 1.0)
	var mid_c := App.TEXT if last_dir == 0 else (up if last_dir > 0 else down)
	draw_string(DesktopBelow._num_font(600), Vector2(0, mid_y + MID_H * 0.5 + 7.0), Hyperliquid.fmt_px(mid), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, mid_c)
	var spread := best_ask - best_bid
	var spread_t := "Spread  %s  ·  %.3f%%" % [Hyperliquid.group(spread, Hyperliquid.px_digits(mid)), spread / mid * 100.0 if mid > 0.0 else 0.0]
	draw_string(f, Vector2(0, mid_y + MID_H * 0.5 + 5.0), spread_t, HORIZONTAL_ALIGNMENT_RIGHT, w, 12, App.TEXT_MUTE)
	for i in b.size():
		_row(mid_y + MID_H + i * ROW_H, b[i], float(cum_b[i]), most, up, f, fb, c1, c2)


func _row(y: float, level: Array, cum: float, most: float, tone: Color, f: Font, fb: Font, _c1: float, c2: float) -> void:
	var w := size.x
	_levels.append([y, float(level[0])])
	var bar := roundf(cum / most * w) if most > 0.0 else 0.0
	draw_style_box(Kit.box(Color(tone, 0.085), 4), Rect2(w - bar, y + 2.0, bar, ROW_H - 4.0))
	if _hover >= y and _hover < y + ROW_H:
		draw_style_box(Kit.box(Color(1, 1, 1, 0.045), 6), Rect2(-6, y, w + 12.0, ROW_H))
	var base := y + ROW_H * 0.5 + 5.0
	draw_string(fb, Vector2(0, base), Hyperliquid.fmt_px(float(level[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tone)
	draw_string(f, Vector2(0, base), Hyperliquid.fmt_sz(float(level[1]), sz_decimals), HORIZONTAL_ALIGNMENT_RIGHT, c2 - 4.0, 12, App.TEXT_DIM)
	draw_string(f, Vector2(0, base), Hyperliquid.fmt_sz(cum, sz_decimals), HORIZONTAL_ALIGNMENT_RIGHT, w, 12, Color(App.TEXT_DIM, 0.75))
