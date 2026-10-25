class_name CalendarFlyout
extends Flyout
## The clock's flyout: today's full date and a month you can page through,
## weeks starting on Monday, today ringed in the accent colour.

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var _today: Label
var _month: Label
var _grid: GridContainer
var _year := 2000
var _mon := 1


func _init() -> void:
	width = 340.0


func _build() -> void:
	_today = Kit.label("", 17, 700, App.TEXT, true)
	content.add_child(_today)
	var head := Kit.hbox(4)
	content.add_child(head)
	_month = Kit.label("", 15, 600, App.TEXT_DIM)
	_month.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_month)
	var back := FxButton.icon_only("chevron_left", "Previous month", 18, 34)
	back.pressed.connect(func() -> void: _page(-1))
	var fwd := FxButton.icon_only("chevron_right", "Next month", 18, 34)
	fwd.pressed.connect(func() -> void: _page(1))
	for b in [back, fwd]:
		b.focus_mode = Control.FOCUS_NONE
		head.add_child(b)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	content.add_child(_grid)


func _on_open() -> void:
	var t := Time.get_datetime_dict_from_system()
	_year = int(t["year"])
	_mon = int(t["month"])
	_today.text = Fmt.long_date(t)
	_fill()


func _page(by: int) -> void:
	_mon += by
	if _mon < 1:
		_mon = 12
		_year -= 1
	elif _mon > 12:
		_mon = 1
		_year += 1
	_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_month.text = "%s %d" % [MONTHS[_mon - 1], _year]
	for d in DAYS:
		var l := Kit.label(d, 12, 600, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(38, 22)
		_grid.add_child(l)
	var now := Time.get_datetime_dict_from_system()
	var lead := first_weekday(_year, _mon)
	for i in lead:
		_grid.add_child(Kit.spacer(38, 34))
	for day in range(1, days_in_month(_year, _mon) + 1):
		var is_today := day == int(now["day"]) and _mon == int(now["month"]) and _year == int(now["year"])
		var l := Kit.label(str(day), 14, 700 if is_today else 500, Color.WHITE if is_today else App.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(38, 34)
		if is_today:
			l.add_theme_stylebox_override("normal", Kit.box(App.accent, 999))
		elif (lead + day - 1) % 7 >= 5:
			l.add_theme_color_override("font_color", App.TEXT_DIM)
		_grid.add_child(l)
	# Always six rows so paging months doesn't make the card jump.
	var cells := lead + days_in_month(_year, _mon)
	for i in 42 - cells:
		_grid.add_child(Kit.spacer(38, 34))


static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31


## 0 = Monday … 6 = Sunday, for the 1st of the month.
static func first_weekday(year: int, month: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1, "hour": 12, "minute": 0, "second": 0})
	var wd := int(Time.get_datetime_dict_from_unix_time(unix)["weekday"])  # 0 = Sunday
	return (wd + 6) % 7
