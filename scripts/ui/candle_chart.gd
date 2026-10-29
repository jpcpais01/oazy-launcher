class_name CandleChart
extends Control
## A candlestick chart, drawn in one pass: quiet price grid on the right, the
## times along the bottom, volume as a low tide under the candles and a dashed
## line at the latest price with its tag on the axis. Hovering shows a
## crosshair with the price and time. `marks` lay your own
## prices over it: entry, liquidation, take profit, stop loss, open orders.

const AXIS_W := 84.0
const TIME_H := 26.0
const VOL_SHARE := 0.16
const GRID := Color(1, 1, 1, 0.045)
## Round spans between time labels: 15m up to four weeks.
const LABEL_STEPS := [900, 1800, 3600, 7200, 10800, 21600, 43200, 86400, 172800, 345600, 604800, 1209600, 2419200]

var up := Color("4fdc9b")
var down := Color("ff6b81")
## [t (s), open, high, low, close, volume], oldest first.
var rows: Array = []
## Seconds per candle (for the time labels).
var step_s := 3600
var empty_text := "Loading chart…"
## [{px, text, color}] drawn as quiet lines with a label, when in view.
var marks: Array = []
## When above 0, every row is shown from the left edge, with room kept for
## this many candles (the Today view fills toward the close).
var session_slots := 0
## A reference price drawn as a dotted grey line and kept in range (the last
## trading day's close in the Today view); 0 for none.
var ref_px := 0.0

var _hover := Vector2(-1, -1)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		_hover = Vector2(-1, -1)
		queue_redraw()
	)
	resized.connect(queue_redraw)


func set_rows(r: Array, seconds: int) -> void:
	rows = r
	step_s = seconds
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = (event as InputEventMouseMotion).position
		queue_redraw()


func _font(weight: int = 500) -> Font:
	return DesktopBelow._num_font(weight)


## How many candles fit, and how wide each slot is.
func _fit(plot_w: float) -> Array:
	var n := rows.size()
	if session_slots > 0:
		return [n, plot_w / maxf(n, session_slots)]
	var slot := clampf(plot_w / 110.0, 6.0, 18.0)
	var count := mini(n, floori(plot_w / slot))
	if count > 0 and count == n:
		slot = minf(18.0, plot_w / maxf(count, 60.0))
	return [count, slot]


func _draw() -> void:
	var plot := Rect2(0, 8, size.x - AXIS_W, size.y - TIME_H - 8)
	if rows.size() < 2 or plot.size.x < 40.0 or plot.size.y < 40.0:
		var f := _font(500)
		draw_string(f, Vector2(0, size.y * 0.5), empty_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, App.TEXT_MUTE)
		return
	var fit := _fit(plot.size.x)
	var count: int = fit[0]
	var slot: float = fit[1]
	var first := rows.size() - count
	var x0 := plot.position.x if session_slots > 0 else plot.end.x - count * slot
	var lo := INF
	var hi := -INF
	var vmax := 0.0
	for i in range(first, rows.size()):
		var r: Array = rows[i]
		lo = minf(lo, float(r[3]))
		hi = maxf(hi, float(r[2]))
		vmax = maxf(vmax, float(r[5]))
	if ref_px > 0.0:
		lo = minf(lo, ref_px)
		hi = maxf(hi, ref_px)
	var pad := maxf((hi - lo) * 0.08, absf(hi) * 0.0005)
	lo -= pad
	hi += pad
	var price_h := plot.size.y * (1.0 - VOL_SHARE * 0.35)
	var y_of := func(v: float) -> float: return plot.position.y + (hi - v) / (hi - lo) * price_h

	# Grid and the price axis.
	var f12 := _font(500)
	# Where the axis tags will sit, so grid labels don't hide behind them.
	var tag_ys := [y_of.call(float(rows[rows.size() - 1][4]))]
	for m in marks:
		if float(m["px"]) > lo and float(m["px"]) < hi:
			tag_ys.append(y_of.call(float(m["px"])))
	if ref_px > 0.0:
		tag_ys.append(y_of.call(ref_px))
	var tick := _nice_step((hi - lo) / 5.0)
	var v := ceilf(lo / tick) * tick
	while v < hi:
		var y := roundf(y_of.call(v)) + 0.5
		draw_line(Vector2(0, y), Vector2(plot.end.x, y), GRID, 1.0)
		if not tag_ys.any(func(ty: float) -> bool: return absf(ty - y) < 16.0):
			draw_string(f12, Vector2(plot.end.x + 12.0, y + 4.0), Hyperliquid.fmt_px(v), HORIZONTAL_ALIGNMENT_LEFT, AXIS_W - 12.0, 12, App.TEXT_MUTE)
		v += tick

	# Time labels, about every 150 px, on round clock times.
	var gap_s := ceili(150.0 / slot) * step_s
	var label_s: int = LABEL_STEPS[LABEL_STEPS.size() - 1]
	for c in LABEL_STEPS:
		if c >= gap_s:
			label_s = c
			break
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	for i in range(first, rows.size()):
		var t := int(rows[i][0])
		if (t + bias) % label_s != 0:
			continue
		var x := x0 + (i - first + 0.5) * slot
		if x < 30.0 or x > plot.end.x - 30.0:
			continue
		draw_line(Vector2(roundf(x) + 0.5, plot.position.y), Vector2(roundf(x) + 0.5, plot.end.y), Color(1, 1, 1, 0.025), 1.0)
		draw_string(f12, Vector2(x - 50.0, size.y - 6.0), _time_label(t + bias), HORIZONTAL_ALIGNMENT_CENTER, 100.0, 12, App.TEXT_MUTE)

	# Volume, low along the bottom.
	var vol_h := plot.size.y * VOL_SHARE
	var body_w := maxf(1.0, floorf(slot * 0.64))
	for i in range(first, rows.size()):
		var r: Array = rows[i]
		var tone := up if float(r[4]) >= float(r[1]) else down
		var x := x0 + (i - first) * slot + (slot - body_w) * 0.5
		if vmax > 0.0:
			var h := maxf(1.0, float(r[5]) / vmax * vol_h)
			draw_rect(Rect2(roundf(x), plot.end.y - h, body_w, h), Color(tone, 0.16))

	# Candles.
	for i in range(first, rows.size()):
		var r: Array = rows[i]
		var o := float(r[1])
		var c := float(r[4])
		var tone := up if c >= o else down
		var cx := roundf(x0 + (i - first + 0.5) * slot) + 0.5
		draw_line(Vector2(cx, y_of.call(float(r[2]))), Vector2(cx, y_of.call(float(r[3]))), Color(tone, 0.75), 1.0)
		var top: float = y_of.call(maxf(o, c))
		var bot: float = y_of.call(minf(o, c))
		draw_rect(Rect2(roundf(cx - body_w * 0.5), roundf(top), body_w, maxf(1.0, roundf(bot - top))), Color(tone, 0.92))

	# The reference price: a quiet dotted line with its tag on the axis.
	if ref_px > 0.0:
		var ry := roundf(y_of.call(ref_px)) + 0.5
		draw_dashed_line(Vector2(0, ry), Vector2(plot.end.x, ry), Color(1, 1, 1, 0.32), 1.0, 2.0)
		if absf(ry - float(tag_ys[0])) >= 22.0:
			_tag(Vector2(plot.end.x + 4.0, ry), Hyperliquid.fmt_px(ref_px), Color(0.62, 0.66, 0.7, 0.85), Color(0.03, 0.05, 0.07))

	# Your prices: a fine line, a label at the left, a tag on the axis.
	for m in marks:
		var px := float(m["px"])
		if px <= lo or px >= hi:
			continue
		var my := roundf(y_of.call(px)) + 0.5
		if my > plot.position.y + price_h:
			continue
		var mc: Color = m["color"]
		draw_dashed_line(Vector2(0, my), Vector2(plot.end.x, my), Color(mc, 0.55), 1.0, 6.0)
		var label := str(m["text"])
		var lw := f12.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
		var lr := Rect2(8.0, my - 10.0, lw, 20.0)
		draw_style_box(Kit.box(Color(0.04, 0.06, 0.09, 0.88), 6, Color(mc, 0.6), 1), lr)
		draw_string(f12, Vector2(lr.position.x, lr.position.y + 14.0), label, HORIZONTAL_ALIGNMENT_CENTER, lw, 11, mc)
		# The latest price's tag wins when the two would overlap.
		if absf(my - float(tag_ys[0])) >= 22.0:
			_tag(Vector2(plot.end.x + 4.0, my), Hyperliquid.fmt_px(px), Color(mc, 0.9), Color(0.02, 0.04, 0.06))

	# The latest price: a dashed line and its tag on the axis.
	var last: Array = rows[rows.size() - 1]
	var last_tone := up if float(last[4]) >= float(last[1]) else down
	var ly := roundf(y_of.call(float(last[4]))) + 0.5
	draw_dashed_line(Vector2(0, ly), Vector2(plot.end.x, ly), Color(last_tone, 0.45), 1.0, 3.0)
	_tag(Vector2(plot.end.x + 4.0, ly), Hyperliquid.fmt_px(float(last[4])), last_tone, Color(0.02, 0.04, 0.06))

	# Crosshair.
	var shown := last
	if plot.has_point(_hover):
		var i := clampi(first + floori((_hover.x - x0) / slot), first, rows.size() - 1)
		shown = rows[i]
		var cx := roundf(x0 + (i - first + 0.5) * slot) + 0.5
		var hy := roundf(_hover.y) + 0.5
		draw_dashed_line(Vector2(cx, plot.position.y), Vector2(cx, plot.end.y), Color(1, 1, 1, 0.22), 1.0, 3.0)
		draw_dashed_line(Vector2(0, hy), Vector2(plot.end.x, hy), Color(1, 1, 1, 0.22), 1.0, 3.0)
		var hv := hi - (_hover.y - plot.position.y) / price_h * (hi - lo)
		if _hover.y - plot.position.y <= price_h:
			_tag(Vector2(plot.end.x + 4.0, hy), Hyperliquid.fmt_px(hv), Color(0.85, 0.9, 0.95, 0.92), Color(0.03, 0.05, 0.07))
		var tl := _time_label(int(shown[0]) + bias, true)
		var tw := f12.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
		var tr := Rect2(clampf(cx - tw * 0.5, 0.0, plot.end.x - tw), size.y - TIME_H + 2.0, tw, 22.0)
		draw_style_box(Kit.box(Color(0.85, 0.9, 0.95, 0.92), 6), tr)
		draw_string(f12, Vector2(tr.position.x, tr.position.y + 15.0), tl, HORIZONTAL_ALIGNMENT_CENTER, tw, 12, Color(0.03, 0.05, 0.07))


## A rounded tag on the price axis, centred on `at.y`.
func _tag(at: Vector2, text: String, bg: Color, fg: Color) -> void:
	var f := _font(600)
	var w := minf(AXIS_W - 6.0, f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0)
	var r := Rect2(at.x, roundf(at.y - 11.0), w, 22.0)
	draw_style_box(Kit.box(bg, 6), r)
	draw_string(f, Vector2(r.position.x, r.position.y + 15.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, fg)


func _time_label(local_t: int, full: bool = false) -> String:
	var d := Time.get_datetime_dict_from_unix_time(local_t)
	var day := "%d %s" % [int(d["day"]), DesktopBelow.MONTHS[int(d["month"]) - 1].substr(0, 3)]
	var hm := "%02d:%02d" % [int(d["hour"]), int(d["minute"])]
	if step_s >= 86400:
		return day
	if full:
		return day + "  " + hm
	if int(d["hour"]) == 0 and int(d["minute"]) == 0:
		return day
	return hm


## 1, 2, 2.5 or 5 times a power of ten, at least `raw`.
static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var p := pow(10.0, floorf(log(raw) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if p * m >= raw:
			return p * m
	return p * 10.0
