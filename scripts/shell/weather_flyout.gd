class_name WeatherFlyout
extends Flyout
## The weather chip's flyout: what it's like now, the next twelve hours and the
## week ahead, each day's range drawn against the whole week's.

const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const RAIN := Color("6cc8ff")

var _body: VBoxContainer
var _status: Label
var _unit: FxButton
var _refresh: FxButton


func _init() -> void:
	width = 400.0


func _build() -> void:
	_body = Kit.vbox(16)
	content.add_child(_body)
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Kit._line_box())
	content.add_child(line)
	var foot := Kit.hbox(6)
	content.add_child(foot)
	_status = Kit.label("", 12, 500, App.TEXT_MUTE)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_status)
	_unit = FxButton.make("°C", "", FxButton.Style.CHIP, 30)
	_unit.tooltip_text = "Switch between Celsius and Fahrenheit"
	_unit.focus_mode = Control.FOCUS_NONE
	_unit.pressed.connect(func() -> void:
		Settings.set_value("weather_unit", "c" if Weather.fahrenheit() else "f")
		Weather.changed.emit()
	)
	foot.add_child(_unit)
	_refresh = FxButton.icon_only("refresh", "Refresh", 16, 30)
	_refresh.focus_mode = Control.FOCUS_NONE
	_refresh.pressed.connect(func() -> void: Weather.refresh())
	foot.add_child(_refresh)
	Weather.changed.connect(func() -> void:
		if is_open:
			_fill()
	)


func _on_open() -> void:
	_fill()
	# Opening it is a good moment to catch up if the data is getting old.
	if Time.get_unix_time_from_system() - Weather.updated > 10 * 60 and not App.smoke_test and App.screenshot_dir == "":
		Weather.refresh()


func _fill() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_unit.text = "°F" if Weather.fahrenheit() else "°C"
	_status.text = _status_text()
	_refresh.disabled = Weather.busy
	var now := Weather.current()
	if now.is_empty():
		_empty()
		return
	var days := Weather.days()
	_header(now, days[0] if not days.is_empty() else {})
	_stats(now)
	_hours()
	if not days.is_empty():
		_week(days, float(now["temp"]))


func _status_text() -> String:
	if Weather.busy and Weather.updated == 0:
		return "Finding your weather…"
	if Weather.busy:
		return "Updating…"
	if Weather.updated == 0:
		return "Offline" if Weather.offline else ""
	var when := Fmt.ago(Weather.updated).to_lower()
	if Weather.offline:
		return "Offline · forecast from %s" % when
	return "Updated %s · Open-Meteo" % when


func _empty() -> void:
	var col := Kit.vbox(8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size.y = 180
	_body.add_child(col)
	var ic := WeatherIcons.rect("cloudy", true, 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.modulate.a = 0.75
	col.add_child(ic)
	var title := Kit.label("Can't reach the weather right now" if Weather.offline and not Weather.busy else "Checking the sky…", 16, 700, App.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if Weather.offline and not Weather.busy:
		var sub := Kit.label("Oazy will try again in a few minutes.", 13, 500, App.TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)


func _header(now: Dictionary, today: Dictionary) -> void:
	var row := Kit.hbox(12)
	_body.add_child(row)
	var col := Kit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if Weather.city() != "":
		var where := Kit.hbox(5)
		col.add_child(where)
		var pin := Kit.icon_rect("location", 14, Color(1, 1, 1, 0.7))
		pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		where.add_child(pin)
		where.add_child(Kit.label(Weather.city(), 14, 600, App.TEXT_DIM))
	col.add_child(Kit.label(Weather.temp(now["temp"]), 56, 500, App.TEXT, true))
	col.add_child(Kit.label(Weather.describe(int(now["code"])), 16, 600, App.TEXT))
	if not today.is_empty():
		col.add_child(Kit.label("H %s   L %s" % [Weather.temp(today["max"]), Weather.temp(today["min"])], 13, 500, App.TEXT_DIM))
	var icon := WeatherIcons.rect(Weather.kind_for(int(now["code"])), bool(now["day"]), 108)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)


func _stats(now: Dictionary) -> void:
	var items := []
	if not is_nan(float(now["feels"])):
		items.append(["thermometer", "Feels like", Weather.temp(now["feels"])])
	if int(now["humidity"]) >= 0:
		items.append(["droplet", "Humidity", "%d%%" % int(now["humidity"])])
	if float(now["wind"]) >= 0.0:
		items.append(["wind", "Wind", Weather.wind(now["wind"])])
	if items.is_empty():
		return
	var row := Kit.hbox(8)
	_body.add_child(row)
	for it in items:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.07), 1, 12, 9))
		row.add_child(p)
		var col := Kit.vbox(2)
		p.add_child(col)
		var head := Kit.hbox(5)
		col.add_child(head)
		var ic := Kit.icon_rect(it[0], 13, Color(1, 1, 1, 0.55))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
		head.add_child(Kit.label(it[1], 11, 600, App.TEXT_MUTE))
		col.add_child(Kit.label(it[2], 15, 700, App.TEXT))


func _hours() -> void:
	var list := Weather.hours(7, 2)
	if list.size() < 2:
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), 16, Color(1, 1, 1, 0.06), 1, 8, 12))
	_body.add_child(p)
	var row := Kit.hbox(0)
	p.add_child(row)
	for i in list.size():
		var h: Dictionary = list[i]
		var col := Kit.vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var t := Kit.label("Now" if i == 0 else str(h["time"]).substr(11, 5), 12, 600, App.TEXT if i == 0 else App.TEXT_DIM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
		var ic := WeatherIcons.rect(Weather.kind_for(int(h["code"])), bool(h["day"]), 32)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		var rain := Kit.label("%d%%" % int(h["rain"]) if int(h["rain"]) >= 20 else "", 10, 700, RAIN)
		rain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rain.custom_minimum_size.y = 12
		col.add_child(rain)
		var temp := Kit.label(Weather.temp(h["temp"]), 14, 700, App.TEXT)
		temp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(temp)


func _week(days: Array, now_temp: float) -> void:
	var lo := INF
	var hi := -INF
	for d in days:
		lo = minf(lo, float(d["min"]))
		hi = maxf(hi, float(d["max"]))
	var col := Kit.vbox(2)
	_body.add_child(col)
	for i in days.size():
		var d: Dictionary = days[i]
		var row := Kit.hbox(8)
		row.custom_minimum_size.y = 34
		col.add_child(row)
		var name := Kit.label("Today" if i == 0 else _weekday(str(d["date"])), 14, 600, App.TEXT)
		name.custom_minimum_size.x = 52
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name)
		var ic := WeatherIcons.rect(Weather.kind_for(int(d["code"])), true, 26)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var rain := Kit.label("%d%%" % int(d["rain"]) if int(d["rain"]) >= 20 else "", 11, 700, RAIN)
		rain.custom_minimum_size.x = 34
		rain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rain)
		var low := Kit.label(Weather.temp(d["min"]), 14, 600, App.TEXT_DIM)
		low.custom_minimum_size.x = 38
		low.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		low.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(low)
		var bar := TempBar.new()
		bar.setup(lo, hi, float(d["min"]), float(d["max"]), now_temp if i == 0 else NAN)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var high := Kit.label(Weather.temp(d["max"]), 14, 700, App.TEXT)
		high.custom_minimum_size.x = 38
		high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		high.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(high)


static func _weekday(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	return DAYS[int(Time.get_datetime_dict_from_unix_time(unix)["weekday"])]


## A day's low to high, placed on the week's scale and coloured by how warm
## it is, with a dot for right now on today's.
class TempBar extends Control:
	var _lo := 0.0
	var _hi := 1.0
	var _a := 0.0
	var _b := 1.0
	var _now := NAN

	func setup(week_lo: float, week_hi: float, lo: float, hi: float, now: float) -> void:
		_lo = week_lo
		_hi = maxf(week_hi, week_lo + 0.1)
		_a = lo
		_b = hi
		_now = now
		custom_minimum_size = Vector2(80, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _x(t: float) -> float:
		return clampf((t - _lo) / (_hi - _lo), 0.0, 1.0) * size.x

	func _draw() -> void:
		var h := 6.0
		var y := (size.y - h) * 0.5
		draw_style_box(Kit.box(Color(1, 1, 1, 0.08), 999), Rect2(0, y, size.x, h))
		var x0 := _x(_a)
		var x1 := maxf(_x(_b), x0 + h)
		var c0 := TempBar.color_for(_a)
		var c1 := TempBar.color_for(_b)
		var r := h * 0.5
		draw_circle(Vector2(x0 + r, y + r), r, c0)
		draw_circle(Vector2(x1 - r, y + r), r, c1)
		draw_polygon(
			PackedVector2Array([Vector2(x0 + r, y), Vector2(x1 - r, y), Vector2(x1 - r, y + h), Vector2(x0 + r, y + h)]),
			PackedColorArray([c0, c1, c1, c0]))
		if not is_nan(_now):
			var p := Vector2(clampf(_x(_now), r, size.x - r), y + r)
			draw_circle(p, 5.0, Color(0.05, 0.07, 0.1, 0.9))
			draw_circle(p, 3.4, Color.WHITE)

	static func color_for(c: float) -> Color:
		var stops := [[-5.0, Color("8fb8ff")], [5.0, Color("6cd3ff")], [13.0, Color("4fe0c0")], [20.0, Color("c7e86a")], [26.0, Color("ffc548")], [33.0, Color("ff7a45")]]
		if c <= stops[0][0]:
			return stops[0][1]
		for i in range(1, stops.size()):
			if c <= stops[i][0]:
				var t: float = (c - stops[i - 1][0]) / (stops[i][0] - stops[i - 1][0])
				return (stops[i - 1][1] as Color).lerp(stops[i][1], t)
		return stops[-1][1]
