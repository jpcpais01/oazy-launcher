class_name TopBar
extends Control
## Header: brand, page tabs with a sliding pill, update badge, clock, settings
## and custom window controls. Doubles as the drag handle of the borderless window.

signal tab_selected(page: StringName)
signal settings_pressed
signal update_pressed

const HEIGHT := 76

var current: StringName = &"home"
var _tabs := {}
var _pill: Panel
var _tab_box: HBoxContainer
var _clock: Label
var _update_btn: FxButton
var _max_btn: FxButton
var _settings_btn: FxButton
var _dragging := false
var _drag_from := Vector2i.ZERO
var _win_from := Vector2i.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size.y = HEIGHT
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP

	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.02, 0.04, 0.55))
	grad.set_color(1, Color(0.02, 0.02, 0.04, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := Kit.hbox(6)
	margin.add_child(row)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(32, 32)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(logo)
	row.add_child(Kit.spacer(6))
	var word := Kit.label("OAZY", 21, 800, Color.WHITE, true)
	var wv := FontVariation.new()
	wv.base_font = Kit.font(800, true)
	wv.spacing_glyph = 4
	word.add_theme_font_override("font", wv)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(word)
	row.add_child(Kit.spacer(40))

	var tabs_holder := Control.new()
	tabs_holder.custom_minimum_size = Vector2(0, 44)
	tabs_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tabs_holder)
	_pill = Panel.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.12), 999, Color(1, 1, 1, 0.08)))
	tabs_holder.add_child(_pill)
	_tab_box = Kit.hbox(4)
	tabs_holder.add_child(_tab_box)
	for spec in [[&"home", "Home", "home"], [&"library", "Library", "grid"]]:
		var b := FxButton.make(spec[1], spec[2], FxButton.Style.PLAIN, 44)
		b.add_theme_font_override("font", Kit.font(600))
		b.add_theme_font_size_override("font_size", 16)
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(s, Kit.empty(18, 8))
		b.pressed.connect(func() -> void: tab_selected.emit(spec[0]))
		_tab_box.add_child(b)
		_tabs[spec[0]] = b
	_tab_box.resized.connect(func() -> void: tabs_holder.custom_minimum_size.x = _tab_box.size.x)

	row.add_child(Kit.spacer(0, 0, true))

	_update_btn = FxButton.make("Update", "download", FxButton.Style.ACCENT, 38)
	_update_btn.visible = false
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.tooltip_text = "A new version of Oazy is ready"
	_update_btn.pressed.connect(func() -> void: update_pressed.emit())
	row.add_child(_update_btn)
	row.add_child(Kit.spacer(14))

	_clock = Kit.label("", 17, 600, App.TEXT)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock)
	row.add_child(Kit.spacer(10))

	_settings_btn = FxButton.icon_only("settings", "Settings", 20, 42)
	_settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings_btn.pressed.connect(func() -> void: settings_pressed.emit())
	row.add_child(_settings_btn)

	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.1)
	sep.custom_minimum_size = Vector2(1, 22)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(Kit.spacer(8))
	row.add_child(sep)
	row.add_child(Kit.spacer(8))

	var min_btn := FxButton.icon_only("minimize", "Minimize", 18, 38)
	min_btn.pressed.connect(func() -> void: get_window().mode = Window.MODE_MINIMIZED)
	_max_btn = FxButton.icon_only("maximize", "Maximize", 16, 38)
	_max_btn.pressed.connect(toggle_maximize)
	var close_btn := FxButton.icon_only("close", "Close", 18, 38)
	close_btn.add_theme_stylebox_override("hover", Kit.box(Color(1.0, 0.33, 0.42, 0.9), 999))
	close_btn.add_theme_stylebox_override("pressed", Kit.box(Color(1.0, 0.33, 0.42, 1.0), 999))
	close_btn.pressed.connect(_close)
	for b in [min_btn, _max_btn, close_btn]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		row.add_child(b)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)
	_tick()
	get_window().size_changed.connect(_sync_max_icon)
	Updater.state_changed.connect(_on_update_state)
	select(&"home", false)


func select(page: StringName, animate: bool = true) -> void:
	current = page
	for key in _tabs.keys():
		var b: FxButton = _tabs[key]
		var on: bool = key == page
		b.add_theme_color_override("font_color", Color.WHITE if on else App.TEXT_DIM)
		b.add_theme_color_override("icon_normal_color", Color.WHITE if on else App.TEXT_DIM)
	_settings_btn.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.12 if page == &"settings" else 0.0), 999))
	await get_tree().process_frame
	_move_pill(animate)


func _move_pill(animate: bool) -> void:
	if not _tabs.has(current):
		var t0 := create_tween()
		t0.tween_property(_pill, "modulate:a", 0.0, 0.2)
		return
	var b: FxButton = _tabs[current]
	var target_pos := b.position
	var target_size := b.size
	if not animate or _pill.modulate.a < 0.05:
		_pill.position = target_pos
		_pill.size = target_size
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_pill, "position", target_pos, 0.45)
	t.tween_property(_pill, "size", target_size, 0.45)
	t.tween_property(_pill, "modulate:a", 1.0, 0.2)


func _tick() -> void:
	var t := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]


func _on_update_state(state: StringName) -> void:
	var show := state in [&"available", &"downloading", &"ready"]
	if show and not _update_btn.visible:
		_update_btn.visible = true
		_update_btn.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(_update_btn, "modulate:a", 1.0, 0.4)
		_pulse()
	elif not show:
		_update_btn.visible = false
	match state:
		&"downloading":
			_update_btn.text = "Downloading"
		&"ready":
			_update_btn.text = "Restart to update"
		_:
			_update_btn.text = "Update"


func _pulse() -> void:
	var t := create_tween().set_loops(3)
	t.tween_property(_update_btn, "scale", Vector2.ONE * 1.08, 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(_update_btn, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)


func _close() -> void:
	Settings.save()
	get_tree().quit()


func toggle_maximize() -> void:
	var w := get_window()
	if w.mode == Window.MODE_MAXIMIZED or w.mode == Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	else:
		w.mode = Window.MODE_MAXIMIZED
	_sync_max_icon()


func _sync_max_icon() -> void:
	var maxed := get_window().mode == Window.MODE_MAXIMIZED or get_window().mode == Window.MODE_FULLSCREEN
	_max_btn.icon = Icons.tex("restore" if maxed else "maximize", 16, Color.WHITE)
	_max_btn.tooltip_text = "Restore" if maxed else "Maximize"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			toggle_maximize()
			accept_event()
		elif event.pressed:
			if get_window().mode == Window.MODE_FULLSCREEN:
				return
			if DisplayServer.has_method("window_start_drag"):
				DisplayServer.call("window_start_drag")
			else:
				_dragging = true
				_drag_from = DisplayServer.mouse_get_position()
				_win_from = get_window().position
			accept_event()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		get_window().position = _win_from + (DisplayServer.mouse_get_position() - _drag_from)
