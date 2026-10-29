class_name TradeTape
extends Control
## The latest trades, newest on top: price in the buyer's or seller's colour,
## size and time. A new trade lights its row for a moment, then settles.

const ROW_H := 23.0
const HEAD_H := 26.0
const FLASH_MS := 700.0

var up := Color("4fdc9b")
var down := Color("ff6b81")
var trades: Array = []
var sz_decimals := 4
var coin := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	resized.connect(queue_redraw)


func set_trades(list: Array, decimals: int, c: String) -> void:
	trades = list
	sz_decimals = decimals
	coin = c
	queue_redraw()
	set_process(_flashing())


func _flashing() -> bool:
	var now := Time.get_ticks_msec()
	for t in trades.slice(0, 8):
		if int(t["seen"]) > 0 and now - int(t["seen"]) < FLASH_MS:
			return true
	return false


func _process(_d: float) -> void:
	queue_redraw()
	if not _flashing():
		set_process(false)


func _draw() -> void:
	var f := DesktopBelow._num_font(500)
	var fb := DesktopBelow._num_font(600)
	var w := size.x
	var c2 := w * 0.68
	draw_string(f, Vector2(0, 16), "Price", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, App.TEXT_MUTE)
	draw_string(f, Vector2(0, 16), "Size" + (" (%s)" % coin if coin != "" else ""), HORIZONTAL_ALIGNMENT_RIGHT, c2, 11, App.TEXT_MUTE)
	draw_string(f, Vector2(0, 16), "Time", HORIZONTAL_ALIGNMENT_RIGHT, w, 11, App.TEXT_MUTE)
	if trades.is_empty():
		draw_string(f, Vector2(0, size.y * 0.5), "Waiting for trades…", HORIZONTAL_ALIGNMENT_CENTER, w, 14, App.TEXT_MUTE)
		return
	var n := mini(trades.size(), floori((size.y - HEAD_H) / ROW_H))
	var now := Time.get_ticks_msec()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	# Big prints stand out a little: anything in the top tenth by value.
	var values := []
	for t in trades:
		values.append(float(t["px"]) * float(t["sz"]))
	values.sort()
	var big: float = values[int(values.size() * 0.9)] if values.size() >= 10 else INF
	for i in n:
		var t: Dictionary = trades[i]
		var y := HEAD_H + i * ROW_H
		var tone := up if str(t["side"]) == "B" else down
		var seen := int(t["seen"])
		if seen > 0 and now - seen < FLASH_MS:
			var k := 1.0 - (now - seen) / FLASH_MS
			draw_style_box(Kit.box(Color(tone, 0.14 * k * k), 6), Rect2(-6, y, w + 12.0, ROW_H))
		var base := y + ROW_H * 0.5 + 5.0
		var heavy := float(t["px"]) * float(t["sz"]) >= big
		draw_string(fb, Vector2(0, base), Hyperliquid.fmt_px(float(t["px"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tone)
		draw_string(fb if heavy else f, Vector2(0, base), Hyperliquid.fmt_sz(float(t["sz"]), sz_decimals), HORIZONTAL_ALIGNMENT_RIGHT, c2, 12, App.TEXT if heavy else App.TEXT_DIM)
		var d := Time.get_datetime_dict_from_unix_time(int(t["time"]) / 1000 + bias)
		draw_string(f, Vector2(0, base), "%02d:%02d:%02d" % [int(d["hour"]), int(d["minute"]), int(d["second"])], HORIZONTAL_ALIGNMENT_RIGHT, w, 12, App.TEXT_MUTE)
