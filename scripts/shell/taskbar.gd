class_name Taskbar
extends Control
## The glass taskbar. Left: the Start orb and search. Middle: pinned and
## running apps, real Windows windows and Oazy's own side by side, with a
## liquid "lens" that glides to whichever one is active. Right: updates,
## the network (Wi-Fi and cable), sound (quick settings), the weather, the
## clock (calendar) and an invisible corner that shows the desktop.
## Over the desktop it floats as a capsule; when an app is maximised it melts
## into a full-width shelf, so the strip under the bar never shows wallpaper.

signal start_pressed
signal search_pressed

const HEIGHT := 48.0
const MARGIN := 6.0
## The strip at the bottom of the screen the taskbar keeps for itself.
const RESERVE := HEIGHT + MARGIN * 2.0

var main: Node
var layer: WindowLayer
var preview: TaskPreview
var quick: QuickSettings
var calendar: CalendarFlyout
var weather: WeatherFlyout
var network: NetworkFlyout
var orb: StartOrb
var _glass: GlassPanel
var _apps: HBoxContainer
var _buttons := {}
var _clock: Label
var _date: Label
var _update_btn: FxButton
var _battery: Label
var _sound: Button
var _net: Button
var _net_glyph: SignalGlyph
var _net_wired: TextureRect
var _clock_btn: Button
var _weather_btn: Button
var _weather_icon: TextureRect
var _weather_temp: Label
var _hover_btn: TaskbarButton
var _hover_timer: Timer
var _leave_timer: Timer
var _menu: PopupMenu
var _menu_btn: TaskbarButton
var _rebuild_queued := false
var _built_once := false
var _last_minute := -1
var _lens: Control
var _lens_btn: TaskbarButton
var _lens_x := 0.0
var _lens_v := 0.0
var _docked := false
var _dock_tween: Tween
var _desk_hit: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = MARGIN
	offset_right = -MARGIN
	offset_top = -(HEIGHT + MARGIN)
	offset_bottom = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: App.pointer_on_bar = true)
	mouse_exited.connect(func() -> void: App.pointer_on_bar = false)

	_glass = GlassPanel.new(true, HEIGHT / 2.0, GlassPanel.TINT_BAR)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A tight shadow: the strip above the taskbar belongs to apps in shell mode.
	_glass.set_shadow_strength(0.4, 14, 5.0)
	add_child(_glass)

	var row := Kit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5
	row.offset_right = -8
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

	row.add_child(_network_button())

	_sound = _tray_button(Vector2(36, 36), "Sound and quick settings")
	_sound.icon = Icons.tex("volume", 18, Color(1, 1, 1, 0.85))
	_sound.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sound.pressed.connect(func() -> void:
		if quick:
			_close_flyouts(quick)
			quick.toggle(_sound)
	)
	_sound.gui_input.connect(_on_sound_input)
	row.add_child(_sound)

	row.add_child(_weather_chip())

	_clock_btn = _tray_button(Vector2(88, 40), "")
	_clock_btn.pressed.connect(func() -> void:
		if calendar:
			_close_flyouts(calendar)
			calendar.toggle(_clock_btn)
	)
	row.add_child(_clock_btn)
	var clock := Kit.vbox(0)
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	clock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock.offset_right = -6
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_btn.add_child(clock)
	_clock = Kit.label("", 15, 700, App.TEXT, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(_clock)
	_date = Kit.label("", 11, 500, App.TEXT_DIM)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(_date)
	row.add_child(_desktop_sliver())

	_lens = Control.new()
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens.modulate.a = 0.0
	_lens.draw.connect(_draw_lens)
	add_child(_lens)
	App.accent_changed.connect(func(_c: Color) -> void: _lens.queue_redraw())

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
	# The sound icon follows changes made elsewhere (keyboard volume keys).
	_timer(4.0, func() -> void:
		if quick and Host.available and not quick.is_open:
			quick.refresh()
	, true)

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
	b.custom_minimum_size = Vector2(210, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.text = "Search apps and games"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = Icons.tex("search", 16, Color(1, 1, 1, 0.75))
	b.add_theme_font_override("font", Kit.font(500))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.85))
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.07), 999, Color(1, 1, 1, 0.08), 1, 16, 0))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.12), 999, Color(1, 1, 1, 0.16), 1, 16, 0))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.16), 999, Color(1, 1, 1, 0.2), 1, 16, 0))
	b.pressed.connect(func() -> void: search_pressed.emit())
	return b


## The show desktop corner. Nothing is drawn: a button runs from the end of the
## bar out to the screen's bottom-right corner, so throwing the mouse into the
## corner and clicking shows the desktop.
func _desktop_sliver() -> Control:
	# Keeps the corner's share of the bar; the button is placed from it.
	var spot := Control.new()
	spot.custom_minimum_size = Vector2(18, 34)
	spot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var s := Button.new()
	s.flat = true
	s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = "Show desktop (Ctrl + Alt + D)"
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		s.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	s.pressed.connect(func() -> void: main.show_desktop())
	add_child(s)
	_desk_hit = s
	# The button covers the spot and everything to the right of it and below
	# the top of the bar, down to the screen's corner.
	var place := func() -> void:
		var x := spot.get_global_rect().position.x - get_global_rect().position.x - 4.0
		s.position = Vector2(x, 0)
		s.size = Vector2(size.x + MARGIN - x, size.y + MARGIN)
	spot.item_rect_changed.connect(place)
	resized.connect(place)
	return spot


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
	var lit: TaskbarButton = null
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
		if active:
			lit = btn
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
	_aim_lens(lit)
	_set_docked(_any_maximized())


func _group(groups: Dictionary, order: Array[String], ref: String) -> Dictionary:
	if not groups.has(ref):
		groups[ref] = {"item": Catalog.item(ref), "windows": [], "shell": null}
		order.append(ref)
	return groups[ref]


# --- Lens and dock -------------------------------------------------------------------

## The lens: one drop of brighter glass behind the active app. It springs from
## button to button and stretches with its speed, so switching apps feels fluid.
func _aim_lens(btn: TaskbarButton) -> void:
	if btn == _lens_btn:
		return
	var was := _lens_btn
	_lens_btn = btn
	var t := _lens.create_tween()
	t.tween_property(_lens, "modulate:a", 1.0 if btn else 0.0, 0.22)
	if btn and was == null:
		# Appear in place rather than flying in from wherever it last was.
		_lens_x = -1.0
	set_process(true)


func _process(delta: float) -> void:
	if _lens_btn == null or not is_instance_valid(_lens_btn):
		set_process(_lens.modulate.a > 0.0)
		return
	var r := _lens_btn.get_global_rect()
	r.position -= get_global_position()
	var goal := r.get_center().x
	if _lens_x < 0.0:
		_lens_x = goal
		_lens_v = 0.0
	# A slightly underdamped spring: a hint of wobble, then still.
	var k := 260.0
	var c := 24.0
	_lens_v += ((goal - _lens_x) * k - _lens_v * c) * delta
	_lens_x += _lens_v * delta
	var stretch := minf(absf(_lens_v) * 0.035, 26.0)
	var w := r.size.x + 4.0 + stretch
	var h := r.size.y - 2.0 - stretch * 0.12
	_lens.position = Vector2(_lens_x - w / 2.0, r.get_center().y - h / 2.0)
	_lens.size = Vector2(w, h)
	_lens.queue_redraw()
	if absf(goal - _lens_x) < 0.3 and absf(_lens_v) < 1.0:
		_lens_x = goal
		set_process(false)


func _draw_lens() -> void:
	var r := Rect2(Vector2.ZERO, _lens.size)
	var rad := minf(r.size.x, r.size.y) / 2.0 - 2.0
	var tint := App.accent
	var body := Kit.box(Color(tint.lightened(0.15), 0.2), rad, Color(1, 1, 1, 0.2), 1)
	Kit.shadowed(body, Color(tint, 0.38), 12, Vector2.ZERO)
	_lens.draw_style_box(body, r)
	# The bright meniscus along the top edge, like light caught in a droplet.
	var shine := Kit.box(Color(1, 1, 1, 0.13), rad)
	_lens.draw_style_box(shine, Rect2(r.position + Vector2(5, 2), Vector2(r.size.x - 10.0, r.size.y * 0.42)))


func _any_maximized() -> bool:
	for w in Host.windows:
		if bool(w.get("max", false)) and not bool(w.get("min", false)):
			return true
	return false


## Floating capsule <-> full-width shelf. The glass grows out to the screen
## edges and its bottom corners slide offscreen; the buttons never move.
func _set_docked(on: bool) -> void:
	if on == _docked:
		return
	_docked = on
	if _dock_tween and _dock_tween.is_valid():
		_dock_tween.kill()
	var m := MARGIN if on else 0.0
	var rad := HEIGHT / 2.0
	_dock_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_dock_tween.tween_property(_glass, "offset_left", -m, 0.4)
	_dock_tween.tween_property(_glass, "offset_right", m, 0.4)
	_dock_tween.tween_property(_glass, "offset_top", -m, 0.4)
	_dock_tween.tween_property(_glass, "offset_bottom", m + (rad if on else 0.0), 0.4)
	_dock_tween.tween_property(_glass, "radius", 14.0 if on else rad, 0.4)
	_glass.set_shadow_strength(0.25 if on else 0.4, 10 if on else 14, 0.0 if on else 5.0)


func is_docked() -> bool:
	return _docked


## The part of the screen the taskbar's layer keeps (see Shell).
func shell_shape() -> Array[Rect2]:
	var shape: Array[Rect2] = [_glass.shadow_rect()]
	if _desk_hit:
		shape.append(_desk_hit.get_global_rect())
	return shape


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
	if Catalog.launch(btn.ref) and (not btn.ref.begins_with("oazy:") or Catalog.is_own_window_app(btn.ref)):
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
	if btn.ref.begins_with("oazy:") and not Catalog.is_own_window_app(btn.ref):
		_menu.add_icon_item(Icons.tex("window", 18), "Open", 0)
	else:
		_menu.add_icon_item(Icons.tex("plus" if running else "play", 18), "New window" if running else "Open", 0)
	if btn.ref.begins_with("lib:"):
		_menu.add_icon_item(Icons.tex("info", 18), "Details", 4)
	main.add_favorite_item(_menu, btn.ref, 5)
	var pinned := Catalog.is_pinned(btn.ref)
	_menu.add_icon_item(Icons.tex("unpin" if pinned else "pin", 18), "Unpin from taskbar" if pinned else "Pin to taskbar", 1)
	main.add_library_item(_menu, btn.ref, 6)
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
		6:
			main.toggle_library(btn.ref)


# --- Tray ----------------------------------------------------------------------------------

func _tick() -> void:
	var t := Time.get_datetime_dict_from_system()
	if int(t["minute"]) == _last_minute:
		return
	_last_minute = int(t["minute"])
	_update_weather()
	_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	_date.text = Fmt.short_date(t)


func set_battery(percent: int, charging: bool) -> void:
	_battery.visible = percent >= 0
	_battery.text = ("⚡ " if charging else "") + "%d%%" % percent
	if quick:
		quick.set_battery(percent, charging)


## Wires the tray to its flyouts (they live in Start's layer, above apps).
func attach_flyouts(q: QuickSettings, c: CalendarFlyout) -> void:
	quick = q
	calendar = c
	quick.volume_changed.connect(_on_volume)
	Host.status_changed.connect(func(ok: bool) -> void:
		if ok:
			quick.refresh()
	)
	if Host.available:
		quick.refresh()


## The weather chip beside the clock: a colour icon and the temperature.
func _weather_chip() -> Button:
	_weather_btn = _tray_button(Vector2(0, 40), "")
	_weather_btn.visible = false
	_weather_btn.pressed.connect(func() -> void:
		if weather:
			_close_flyouts(weather)
			weather.toggle(_weather_btn)
	)
	var row := Kit.hbox(6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -10
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_btn.add_child(row)
	_weather_icon = WeatherIcons.rect("partly", true, 24)
	_weather_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_weather_icon)
	_weather_temp = Kit.label("", 14, 700, App.TEXT)
	_weather_temp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weather_temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_weather_temp)
	# Keep the button exactly as wide as what it shows.
	row.minimum_size_changed.connect(func() -> void:
		_weather_btn.custom_minimum_size.x = row.get_combined_minimum_size().x + 18.0
	)
	Weather.changed.connect(_update_weather)
	return _weather_btn


func _update_weather() -> void:
	if _weather_btn == null:
		return
	var now := Weather.current()
	_weather_btn.visible = not now.is_empty()
	if now.is_empty():
		return
	var code := int(now["code"])
	_weather_icon.texture = WeatherIcons.tex(Weather.kind_for(code), bool(now["day"]), 24)
	_weather_temp.text = Weather.temp(now["temp"])
	var tip := Weather.describe(code)
	if Weather.city() != "":
		tip += " in " + Weather.city()
	if Weather.offline:
		tip += " (offline)"
	_weather_btn.tooltip_text = tip


## The weather flyout lives in Start's layer with the others.
func attach_weather(w: WeatherFlyout) -> void:
	weather = w
	_update_weather()


## The network flyout lives in Start's layer with the others.
func attach_network(n: NetworkFlyout) -> void:
	network = n


## Every tray flyout but `keep` closes, so only one is ever up.
func _close_flyouts(keep: Flyout) -> void:
	for f in [quick, calendar, weather, network]:
		if f and f != keep:
			f.close()


## Wi-Fi strength (or a cable) in the tray; opens the network flyout.
func _network_button() -> Button:
	_net = _tray_button(Vector2(36, 36), "Network")
	_net.pressed.connect(func() -> void:
		if network:
			_close_flyouts(network)
			network.toggle(_net)
	)
	_net_glyph = SignalGlyph.new(18)
	_net_glyph.color = Color(1, 1, 1, 0.85)
	_net_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_net.add_child(_net_glyph)
	_net_wired = Kit.icon_rect("ethernet", 18, Color(1, 1, 1, 0.85))
	_net_wired.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_net_wired.visible = false
	_net.add_child(_net_wired)
	Network.changed.connect(_update_network)
	_update_network()
	return _net


func _update_network() -> void:
	var cur := Network.current()
	var cables := Network.wired()
	var online := Network.internet()
	# A cable shows when Wi-Fi isn't connected, like Windows' own icon.
	var wired := cur.is_empty() and not cables.is_empty()
	_net_wired.visible = wired
	_net_glyph.visible = not wired
	_net_glyph.off = cur.is_empty() and not Network.status.is_empty()
	_net_glyph.level = Network.bars(int(cur.get("signal", 0))) if not cur.is_empty() else 3
	var tip := "Network"
	if not cur.is_empty():
		tip = "%s\n%s" % [cur.get("ssid", ""), "Internet access" if online else "No internet"]
	elif wired:
		tip = "Ethernet\n%s" % ("Internet access" if online else "No internet")
	elif Network.has_wifi() and not Network.radio_on():
		tip = "Wi-Fi is off"
	elif not Network.status.is_empty():
		tip = "Not connected"
	_net.tooltip_text = tip


func _on_volume(level: float, muted: bool) -> void:
	_sound.icon = Icons.tex(QuickSettings.icon_for(level, muted), 20, Color(1, 1, 1, 0.85))
	_sound.tooltip_text = "Muted" if muted else "Volume %d%%" % int(roundf(level * 100.0))


func _on_sound_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed) or quick == null:
		return
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			quick.nudge(0.02)
		MOUSE_BUTTON_WHEEL_DOWN:
			quick.nudge(-0.02)
		MOUSE_BUTTON_MIDDLE:
			quick.set_muted(not quick.muted)
		_:
			return
	_sound.accept_event()


func _tray_button(min_size: Vector2, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.0), 14))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.1), 14, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.16), 14, Color(1, 1, 1, 0.14), 1))
	b.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.16), 14, Color(1, 1, 1, 0.14), 1))
	return b


func _on_update_state(state: StringName) -> void:
	# A (re)check leaves the button as it was, so it never blinks away
	# while Oazy looks for an even newer update.
	if state == &"checking":
		return
	var show := state in [&"available", &"downloading", &"ready"]
	_update_btn.visible = show
	match state:
		&"downloading":
			_update_btn.text = "Downloading"
		&"ready":
			_update_btn.text = "Restart to update"
		_:
			_update_btn.text = "Update"
