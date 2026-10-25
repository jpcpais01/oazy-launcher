class_name Taskbar
extends Control
## The floating glass taskbar. Left: the Start orb and search. Middle: pinned
## and running apps, real Windows windows and Oazy's own side by side. Right:
## updates, the clock and a sliver that shows the desktop.

signal start_pressed
signal search_pressed

const HEIGHT := 66.0
const MARGIN := 10.0

var main: Node
var layer: WindowLayer
var preview: TaskPreview
var orb: StartOrb
var _glass: GlassPanel
var _apps: HBoxContainer
var _buttons := {}
var _clock: Label
var _date: Label
var _update_btn: FxButton
var _battery: Label
var _hover_btn: TaskbarButton
var _hover_timer: Timer
var _leave_timer: Timer
var _menu: PopupMenu
var _menu_btn: TaskbarButton
var _rebuild_queued := false
var _built_once := false
var _last_minute := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = MARGIN
	offset_right = -MARGIN
	offset_top = -(HEIGHT + MARGIN)
	offset_bottom = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: App.pointer_on_bar = true)
	mouse_exited.connect(func() -> void: App.pointer_on_bar = false)

	_glass = GlassPanel.new(true, 22.0, GlassPanel.TINT_BAR)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.set_shadow_strength(0.45, 30, 10.0)
	add_child(_glass)

	var row := Kit.hbox(10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -6
	add_child(row)

	orb = StartOrb.new()
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orb.pressed.connect(func() -> void: start_pressed.emit())
	row.add_child(orb)
	row.add_child(_search_pill())
	row.add_child(Kit.spacer(0, 0, true))

	_update_btn = FxButton.make("Update", "download", FxButton.Style.ACCENT, 38)
	_update_btn.visible = false
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.focus_mode = Control.FOCUS_NONE
	_update_btn.pressed.connect(func() -> void: main.show_update())
	row.add_child(_update_btn)

	_battery = Kit.label("", 14, 600, App.TEXT_DIM)
	_battery.visible = false
	_battery.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_battery)

	var clock := Kit.vbox(0)
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	clock.custom_minimum_size.x = 92
	row.add_child(clock)
	_clock = Kit.label("", 17, 700, App.TEXT, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_child(_clock)
	_date = Kit.label("", 12, 500, App.TEXT_DIM)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_child(_date)
	row.add_child(_desktop_sliver())

	# Apps sit dead centre regardless of what's on either side.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_apps = Kit.hbox(4)
	center.add_child(_apps)

	_hover_timer = _timer(0.45, _on_hover_timeout)
	_leave_timer = _timer(0.28, func() -> void:
		_hover_btn = null
		preview.hide_preview()
	)
	_timer(1.0, _tick, true)
	_tick()

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	Catalog.pins_changed.connect(queue_rebuild)
	Catalog.apps_changed.connect(queue_rebuild)
	Host.windows_changed.connect(queue_rebuild)
	Library.changed.connect(queue_rebuild)
	Updater.state_changed.connect(_on_update_state)
	layer.changed.connect(queue_rebuild)
	preview.hover_changed.connect(func(on: bool) -> void:
		if on:
			_leave_timer.stop()
		else:
			_leave_timer.start()
	)
	rebuild()


func _timer(wait: float, cb: Callable, auto: bool = false) -> Timer:
	var t := Timer.new()
	t.wait_time = wait
	t.one_shot = not auto
	t.autostart = auto
	t.timeout.connect(cb)
	add_child(t)
	return t


func _search_pill() -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.text = "Search apps and games"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = Icons.tex("search", 18, Color(1, 1, 1, 0.75))
	b.add_theme_font_override("font", Kit.font(500))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.85))
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.07), 999, Color(1, 1, 1, 0.08), 1, 16, 0))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.12), 999, Color(1, 1, 1, 0.16), 1, 16, 0))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.16), 999, Color(1, 1, 1, 0.2), 1, 16, 0))
	b.pressed.connect(func() -> void: search_pressed.emit())
	return b


func _desktop_sliver() -> Control:
	var s := Button.new()
	s.custom_minimum_size = Vector2(10, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = "Show desktop"
	s.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.0), 6))
	s.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.16), 6, Color(1, 1, 1, 0.2), 1))
	s.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.24), 6))
	s.pressed.connect(func() -> void: main.show_desktop())
	return s


# --- Groups -------------------------------------------------------------------------

func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	var order: Array[String] = []
	var groups := {}
	for ref in Catalog.pins():
		_group(groups, order, ref)
	for win in layer.windows():
		if not win._closing:
			_group(groups, order, win.app_ref)["shell"] = win
	for w in Host.windows:
		var ref := Catalog.ref_for_window(w)
		var g := _group(groups, order, ref)
		g["windows"].append(w)
		if ref.begins_with("win:"):
			g["item"]["name"] = Catalog.window_group_name(w)
	var active_shell := layer.active_window()
	var keep := {}
	for i in order.size():
		var ref := order[i]
		var g: Dictionary = groups[ref]
		var btn: TaskbarButton = _buttons.get(ref)
		if btn == null:
			btn = TaskbarButton.new().setup(ref, g["item"])
			btn.clicked.connect(_on_click)
			btn.middle_clicked.connect(func(b: TaskbarButton) -> void: _launch(b))
			btn.context.connect(_on_context)
			btn.hover_changed.connect(_on_hover)
			_apps.add_child(btn)
			_buttons[ref] = btn
			if _built_once:
				btn.intro(0.0)
		elif str(btn.item.get("name", "")) != str(g["item"]["name"]):
			btn.set_item(g["item"])
		_apps.move_child(btn, i)
		btn.windows.assign(g["windows"])
		btn.shell_window = g["shell"]
		var running: bool = btn.window_count() > 0
		var active := false
		if Host.self_foreground:
			active = g["shell"] != null and g["shell"] == active_shell
		else:
			for w in btn.windows:
				if int(w["hwnd"]) == Host.foreground:
					active = true
		btn.set_state(running, active)
		keep[ref] = true
	for ref in _buttons.keys():
		if not keep.has(ref):
			var gone: TaskbarButton = _buttons[ref]
			_buttons.erase(ref)
			if gone == _hover_btn:
				preview.hide_preview()
			var t := gone.create_tween().set_parallel(true)
			t.tween_property(gone, "modulate:a", 0.0, 0.18)
			t.tween_property(gone, "scale", Vector2.ONE * 0.6, 0.18)
			t.chain().tween_callback(gone.queue_free)
	if not _built_once and _apps.get_child_count() > 0:
		_built_once = true


func _group(groups: Dictionary, order: Array[String], ref: String) -> Dictionary:
	if not groups.has(ref):
		groups[ref] = {"item": Catalog.item(ref), "windows": [], "shell": null}
		order.append(ref)
	return groups[ref]


## The part of the screen the taskbar's layer keeps (see Shell).
func shell_shape() -> Array[Rect2]:
	return [get_global_rect().grow(MARGIN)]


func button_for(ref: String) -> TaskbarButton:
	return _buttons.get(ref)


func button_center(ref: String) -> Vector2:
	var b: TaskbarButton = _buttons.get(ref)
	if b and is_instance_valid(b):
		return b.get_global_rect().get_center()
	return get_global_rect().get_center()


func intro() -> void:
	var i := 0
	for b in _apps.get_children():
		if b is TaskbarButton:
			b.intro(0.25 + 0.04 * i)
			i += 1
	var start_y := position.y
	position.y += 90.0
	var t := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", start_y, 0.7).set_delay(0.1)


# --- Interaction --------------------------------------------------------------------------

func _on_click(btn: TaskbarButton) -> void:
	_hover_timer.stop()
	if btn.shell_window != null and btn.windows.is_empty():
		preview.hide_preview()
		main.toggle_shell_window(btn.shell_window)
	elif btn.windows.size() == 1 and btn.shell_window == null:
		preview.hide_preview()
		Host.toggle(int(btn.windows[0]["hwnd"]))
	elif btn.window_count() > 1:
		_hover_btn = btn
		preview.show_for(btn)
	else:
		preview.hide_preview()
		_launch(btn)


func _launch(btn: TaskbarButton) -> void:
	if Catalog.launch(btn.ref) and not btn.ref.begins_with("oazy:"):
		if not (btn.ref.begins_with("lib:") and btn.item.get("kind") == "game"):
			btn.start_launching()
		Sfx.play(&"select")


func _on_hover(btn: TaskbarButton, on: bool) -> void:
	if on:
		_hover_btn = btn
		_leave_timer.stop()
		if preview.is_showing():
			preview.show_for(btn)
		else:
			_hover_timer.start()
	else:
		_hover_timer.stop()
		_leave_timer.start()


func _on_hover_timeout() -> void:
	if _hover_btn and is_instance_valid(_hover_btn) and _hover_btn.get_global_rect().has_point(get_global_mouse_position()):
		preview.show_for(_hover_btn)


func _on_context(btn: TaskbarButton, at: Vector2) -> void:
	_hover_timer.stop()
	preview.hide_preview()
	_menu_btn = btn
	_menu.clear()
	_menu.add_item(str(btn.item.get("name", "")), 99)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	var running := btn.window_count() > 0
	if btn.ref.begins_with("oazy:"):
		_menu.add_icon_item(Icons.tex("window", 18), "Open", 0)
	else:
		_menu.add_icon_item(Icons.tex("plus" if running else "play", 18), "New window" if running else "Open", 0)
	if btn.ref.begins_with("lib:"):
		_menu.add_icon_item(Icons.tex("info", 18), "Details", 4)
	main.add_favorite_item(_menu, btn.ref, 5)
	var pinned := Catalog.is_pinned(btn.ref)
	_menu.add_icon_item(Icons.tex("unpin" if pinned else "pin", 18), "Unpin from taskbar" if pinned else "Pin to taskbar", 1)
	if running:
		_menu.add_separator()
		_menu.add_icon_item(Icons.tex("close", 18, App.DANGER.lightened(0.2)), "Close all windows" if btn.window_count() > 1 else "Close window", 2)
	_menu.reset_size()
	var vp := Shell.view_size()
	_menu.position = Vector2i(int(clampf(at.x - _menu.size.x / 2.0, 8.0, vp.x - _menu.size.x - 8.0)), int(get_global_rect().position.y - _menu.size.y - 10.0))
	Shell.popup(_menu)
	Sfx.play(&"open")


func _on_menu(id: int) -> void:
	var btn := _menu_btn
	if btn == null or not is_instance_valid(btn):
		return
	match id:
		0:
			if btn.ref.begins_with("oazy:") and btn.shell_window:
				main.focus_shell_window(btn.shell_window)
			else:
				_launch(btn)
		1:
			Catalog.set_pinned(btn.ref, not Catalog.is_pinned(btn.ref))
		2:
			for w in btn.windows:
				Host.close_window(int(w["hwnd"]))
			if btn.shell_window:
				btn.shell_window.close()
		4:
			main.focus_entry(btn.ref.substr(4))
		5:
			main.toggle_favorite(btn.ref)


# --- Tray ----------------------------------------------------------------------------------

func _tick() -> void:
	var t := Time.get_datetime_dict_from_system()
	if int(t["minute"]) == _last_minute:
		return
	_last_minute = int(t["minute"])
	_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	_date.text = Fmt.short_date(t)


func set_battery(percent: int, charging: bool) -> void:
	_battery.visible = percent >= 0
	_battery.text = ("⚡ " if charging else "") + "%d%%" % percent


func _on_update_state(state: StringName) -> void:
	var show := state in [&"available", &"downloading", &"ready"]
	_update_btn.visible = show
	match state:
		&"downloading":
			_update_btn.text = "Downloading"
		&"ready":
			_update_btn.text = "Restart to update"
		_:
			_update_btn.text = "Update"
