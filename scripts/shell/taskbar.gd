class_name Taskbar
extends Control
## The glass taskbar. Left: the Start orb and search. Middle: pinned and
## running apps, real Windows windows and Oazy's own side by side, with a
## liquid "lens" that glides to whichever one is active. Drag an app to
## reorder; its neighbours ease aside and the order is kept. Right: the
## network (Wi-Fi and cable), sound (quick settings), the weather, the
## clock (calendar) and an invisible corner that shows the desktop.
## The task manager always has a button among the apps; it opens as a card
## rising from that button rather than as a window.
## Over the desktop it floats as a capsule; when an app is maximised it melts
## into a full-width shelf, so the strip under the bar never shows wallpaper.

## The orb (or the corner past it): Claude.
signal start_pressed
## The orb right-clicked: Start.
signal start_alt_pressed
signal search_pressed

const HEIGHT := 48.0
const MARGIN := 6.0
## The strip at the bottom of the screen the taskbar keeps for itself.
const RESERVE := HEIGHT + MARGIN * 2.0
const FLOAT_SHADOW := 0.14
const DOCK_SHADOW := 0.08
const APP_GAP := 4.0

var main: Node
var layer: WindowLayer
var preview: TaskPreview
var quick: QuickSettings
var calendar: CalendarFlyout
var weather: WeatherFlyout
var network: NetworkFlyout
var tasks: TasksFlyout
var orb: StartOrb
var _glass: GlassPanel
var _apps: Control
var _buttons := {}
## Buttons left to right, as laid out (removed ones fading out aren't here).
var _order: Array[TaskbarButton] = []
var _drag_btn: TaskbarButton
var _drag_grab := 0.0
var _reflowing := false
var _clock: Label
var _date: Label
var _battery: Label
var _sound: Button
var _net: Button
var _net_glyph: SignalGlyph
var _net_wired: TextureRect
var _clock_btn: Button
var _weather_btn: Button
var _weather_icon: TextureRect
var _weather_temp: Label
## Hover intent for the window previews (see _step_preview).
var _hover_btn: TaskbarButton
## How long the pointer has been on _hover_btn, and how long it has held still
## (within REST_SLOP of where it came to rest, _last_pointer).
var _dwell := 0.0
var _still := 0.0
var _last_pointer := Vector2.INF
## How long the pointer has been off the preview's button, the card and the way between.
var _away := 0.0
## Where the pointer last was on the preview's button: the tip of the path up to the card.
var _anchor := Vector2.ZERO
## Clicked or right-clicked: no preview for it until the pointer leaves it.
var _hush: TaskbarButton
var _closed_at := -100000
## The preview open now was opened from here (tests open it by hand).
var _managing := false
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
var _start_hit: CornerHit


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
	# A faint, diffuse lift rather than a dark band. Kept tight: the strip
	# above the taskbar belongs to apps in shell mode.
	_glass.set_shadow_strength(FLOAT_SHADOW, 16, 4.0)
	add_child(_glass)

	var row := Kit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5
	row.offset_right = -8
	add_child(row)

	orb = StartOrb.new()
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orb.pressed.connect(func() -> void: start_pressed.emit())
	orb.alt_pressed.connect(func() -> void: start_alt_pressed.emit())
	row.add_child(orb)
	_start_corner()
	row.add_child(_search_pill())
	row.add_child(Kit.spacer(0, 0, true))

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

	# Apps sit dead centre regardless of what's on either side. They're laid
	# out by hand (see _step_apps) so every move eases, drags included.
	_apps = Control.new()
	_apps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apps.resized.connect(_snap_apps)
	add_child(_apps)

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
	gui_input.connect(_on_bar_input)

	Catalog.pins_changed.connect(queue_rebuild)
	Catalog.apps_changed.connect(queue_rebuild)
	Host.windows_changed.connect(queue_rebuild)
	Library.changed.connect(queue_rebuild)
	layer.changed.connect(queue_rebuild)
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


## An invisible button for a screen corner. It leaves a hole where a real
## control sits, so that control keeps its own hover and clicks.
class CornerHit extends Button:
	var hole := Rect2()

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func _has_point(point: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).has_point(point) and not hole.has_point(point)


## The orb's corner, like the show desktop one on the right: throwing the mouse
## into the screen's bottom-left corner and clicking does what the orb does
## (opens Claude). The button
## covers the orb's end of the bar out to the corner, minus the orb itself.
func _start_corner() -> void:
	var s := CornerHit.new()
	s.tooltip_text = "Claude (Ctrl + Space)"
	s.pressed.connect(func() -> void: start_pressed.emit())
	add_child(s)
	_start_hit = s
	var place := func() -> void:
		var orb_r := orb.get_global_rect()
		var w := orb_r.end.x - get_global_rect().position.x + MARGIN
		s.position = Vector2(-MARGIN, 0)
		s.size = Vector2(w, size.y + MARGIN)
		s.hole = Rect2(orb_r.position - s.get_global_rect().position, orb_r.size)
	orb.item_rect_changed.connect(place)
	resized.connect(place)


# --- Groups -------------------------------------------------------------------------

func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	var natural: Array[String] = []
	var groups := {}
	for ref in Catalog.pins():
		_group(groups, natural, ref)
	for win in layer.windows():
		if not win._closing:
			_group(groups, natural, win.app_ref)["shell"] = win
	for w in Host.windows:
		var ref := Catalog.ref_for_window(w)
		var g := _group(groups, natural, ref)
		g["windows"].append(w)
		if ref.begins_with("win:"):
			g["item"]["name"] = Catalog.window_group_name(w)
	var order := _saved_order(natural)
	var active_shell := layer.active_window()
	var keep := {}
	var fresh: Array[TaskbarButton] = []
	_order.clear()
	var lit: TaskbarButton = null
	for i in order.size():
		var ref := order[i]
		var g: Dictionary = groups[ref]
		var btn: TaskbarButton = _buttons.get(ref)
		if btn == null:
			btn = TaskbarButton.new().setup(ref, g["item"])
			btn.clicked.connect(_on_click)
			btn.middle_clicked.connect(func(b: TaskbarButton) -> void:
				if b.ref == TasksFlyout.REF:
					toggle_tasks()
				else:
					_launch(b)
			)
			btn.context.connect(_on_context)
			btn.hover_changed.connect(_on_hover)
			btn.drag_started.connect(_on_drag_started)
			btn.drag_moved.connect(_on_drag_moved)
			btn.drag_ended.connect(_on_drag_ended)
			_apps.add_child(btn)
			_buttons[ref] = btn
			fresh.append(btn)
			if _built_once:
				btn.intro(0.0)
		elif str(btn.item.get("name", "")) != str(g["item"]["name"]):
			btn.set_item(g["item"])
		_order.append(btn)
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
		if ref == TasksFlyout.REF:
			# Lit while its card is up: the lens joins the button to it.
			active = tasks != null and tasks.is_open
		btn.set_state(running, active)
		if active:
			lit = btn
		keep[ref] = true
	for ref in _buttons.keys():
		if not keep.has(ref):
			var gone: TaskbarButton = _buttons[ref]
			_buttons.erase(ref)
			if gone == preview.button:
				preview.hide_preview()
			if gone == _hover_btn:
				_hover_btn = null
			gone.cancel_drag()
			gone.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var t := gone.create_tween().set_parallel(true)
			t.tween_property(gone, "modulate:a", 0.0, 0.18)
			t.tween_property(gone, "scale", Vector2.ONE * 0.6, 0.18)
			t.chain().tween_callback(gone.queue_free)
	if _drag_btn:
		_order.erase(_drag_btn)
		_order.insert(_drag_slot(), _drag_btn)
	# New buttons start in their slot; everyone else eases over to make room.
	for b in fresh:
		b.position = Vector2(_slot_x(_order.find(b)), _app_y())
	_reflow()
	if not _built_once and _apps.get_child_count() > 0:
		_built_once = true
	_aim_lens(lit)
	_set_docked(_any_maximized())


func _group(groups: Dictionary, order: Array[String], ref: String) -> Dictionary:
	if not groups.has(ref):
		groups[ref] = {"item": Catalog.item(ref), "windows": [], "shell": null}
		order.append(ref)
	return groups[ref]


## Puts refs in left-to-right order. Buttons already on the bar keep their
## place (on first build, the place they were dragged to). A new pin lands
## after the pin before it; a newly opened app always joins the right end.
## Unpinned apps that closed are forgotten, so reopening one adds it at the end.
func _saved_order(natural: Array[String]) -> Array[String]:
	var present := {}
	for r in natural:
		present[r] = true
	var pinned := {}
	for r in Catalog.pins():
		pinned[r] = true
	var saved: Array = Settings.get_value("taskbar_order")
	var pruned: Array[String] = []
	for r in saved:
		if present.has(str(r)) or pinned.has(str(r)):
			pruned.append(str(r))
	if pruned.size() != saved.size():
		Settings.set_value("taskbar_order", pruned)
	var src: Array = []
	for b in _order:
		src.append(b.ref)
	if src.is_empty():
		src = pruned
	var out: Array[String] = []
	for r in src:
		if present.has(str(r)) and not out.has(str(r)):
			out.append(str(r))
	var prev := ""
	for r in natural:
		if not out.has(r):
			if pinned.has(r):
				out.insert(out.find(prev) + 1 if prev != "" else 0, r)
			else:
				out.append(r)
		prev = r
	return out


## Saves the order on screen. Apps that aren't showing right now keep their
## place relative to the ones that are, for when they come back.
func _save_order() -> void:
	var out: Array[String] = []
	for b in _order:
		out.append(b.ref)
	var prev := ""
	for r in Settings.get_value("taskbar_order"):
		var ref := str(r)
		if not out.has(ref):
			out.insert(out.find(prev) + 1 if prev != "" else 0, ref)
		prev = ref
	Settings.set_value("taskbar_order", out.slice(0, 96))


# --- Layout and dragging -------------------------------------------------------------

func _app_y() -> float:
	return (_apps.size.y - TaskbarButton.SIZE) / 2.0


func _slot_x(i: int) -> float:
	var n := _order.size()
	var step := TaskbarButton.SIZE + APP_GAP
	var width := n * step - APP_GAP if n > 0 else 0.0
	return roundf((_apps.size.x - width) / 2.0) + i * step


## Where the dragged button would drop, from its centre.
func _drag_slot() -> int:
	var step := TaskbarButton.SIZE + APP_GAP
	var left := _slot_x(0)
	var at := roundf((_drag_btn.position.x - left) / step)
	return clampi(int(at), 0, maxi(_order.size() - 1, 0))


## Straight to the slots, no easing (the bar itself changed size).
func _snap_apps() -> void:
	for i in _order.size():
		if _order[i] != _drag_btn:
			_order[i].position = Vector2(_slot_x(i), _app_y())


func _reflow() -> void:
	_reflowing = true
	set_process(true)


## Eases every button towards its slot; returns true while any is moving.
func _step_apps(delta: float) -> bool:
	var busy := false
	var k := 1.0 - exp(-delta * 16.0)
	for i in _order.size():
		var b := _order[i]
		if b == _drag_btn:
			continue
		var goal := Vector2(_slot_x(i), _app_y())
		if b.position.distance_to(goal) < 0.4:
			b.position = goal
		else:
			b.position = b.position.lerp(goal, k)
			busy = true
	return busy or _drag_btn != null


func _on_drag_started(btn: TaskbarButton) -> void:
	_close_preview()
	_drag_btn = btn
	_drag_grab = get_global_mouse_position().x - btn.global_position.x
	btn.set_lifted(true)
	_reflow()


func _on_drag_moved(btn: TaskbarButton) -> void:
	if btn != _drag_btn:
		return
	var x := get_global_mouse_position().x - _drag_grab - _apps.global_position.x
	btn.position.x = clampf(x, _slot_x(0) - 12.0, _slot_x(_order.size() - 1) + 12.0)
	var slot := _drag_slot()
	if _order.find(btn) != slot:
		_order.erase(btn)
		_order.insert(slot, btn)
		Sfx.play(&"move", 1.1)


func _on_drag_ended(btn: TaskbarButton) -> void:
	if btn != _drag_btn:
		return
	_drag_btn = null
	btn.set_lifted(false)
	if _order.has(btn):
		_save_order()
	_reflow()


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
	if _drag_btn and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# The release went somewhere else (another window took the pointer).
		_drag_btn.cancel_drag()
	if _reflowing:
		_reflowing = _step_apps(delta)
	var lens := _step_lens(delta)
	var hover := _step_preview(delta)
	set_process(_reflowing or lens or hover)


## Springs the lens after the active button; returns true while it moves.
func _step_lens(delta: float) -> bool:
	if _lens_btn == null or not is_instance_valid(_lens_btn):
		return _lens.modulate.a > 0.0
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
	if absf(goal - _lens_x) < 0.3 and absf(_lens_v) < 1.0 and not _reflowing:
		_lens_x = goal
		return false
	return true


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
	_glass.set_shadow_strength(DOCK_SHADOW if on else FLOAT_SHADOW, 12 if on else 16, 0.0 if on else 4.0)


func is_docked() -> bool:
	return _docked


## The part of the screen the taskbar's layer keeps (see Shell).
func shell_shape() -> Array[Rect2]:
	var shape: Array[Rect2] = [_glass.shadow_rect()]
	if _desk_hit:
		shape.append(_desk_hit.get_global_rect())
	if _start_hit:
		shape.append(_start_hit.get_global_rect())
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
	if btn.ref == TasksFlyout.REF:
		_close_preview(btn)
		toggle_tasks()
		return
	if btn.shell_window != null and btn.windows.is_empty():
		_close_preview(btn)
		main.toggle_shell_window(btn.shell_window)
	elif btn.windows.size() == 1 and btn.shell_window == null:
		_close_preview(btn)
		Host.toggle(int(btn.windows[0]["hwnd"]))
	elif btn.window_count() > 1:
		_open_preview(btn, get_global_mouse_position())
	else:
		_close_preview(btn)
		_launch(btn)


func _launch(btn: TaskbarButton) -> void:
	if Catalog.launch(btn.ref) and (not btn.ref.begins_with("oazy:") or Catalog.is_own_window_app(btn.ref)):
		if not (btn.ref.begins_with("lib:") and btn.item.get("kind") == "game"):
			btn.start_launching()
		Sfx.play(&"select")


func _on_hover(_btn: TaskbarButton, _on: bool) -> void:
	# The preview follows the pointer itself (see _step_preview); this only
	# wakes it up.
	set_process(true)


# --- Window previews ------------------------------------------------------------------
# One card that follows the pointer along the taskbar. It opens after the
# pointer rests on an app and moves to another app once the pointer settles on
# that one's button, so a quick sweep along the bar doesn't flick it through
# every app on the way. It stays while the pointer heads up to it: from where
# it left the button, anywhere inside the triangle up to the card's bottom
# corners counts as on the way, even across other apps' buttons. It closes a
# moment after the pointer is off the buttons, the card and that path. All of
# this is worked out from where the pointer is each frame, not from enter and
# leave events, so a fast sweep can't leave it confused.

const OPEN_DELAY := 0.4
## How far under the card still counts as just below it.
const GAP_SLACK := TaskPreview.GAP + 4.0
## Reopening right after it closed (sweeping back) is immediate.
const REOPEN_WINDOW := 400
const CLOSE_DELAY := 0.45
## With the card up, another app takes it once the pointer has been on its
## button this long...
const SWITCH_DWELL := 0.1
## ...or, on the way up to the card, once the pointer rests there this long.
const SWITCH_REST := 0.2
## Moving less than this (in pixels) still counts as resting, however many
## frames it's spread over.
const REST_SLOP := 3.0


func _step_preview(delta: float) -> bool:
	if _drag_btn or _menu.visible or not is_visible_in_tree() or (tasks and tasks.is_open):
		_hover_btn = null
		if preview.open and tasks and tasks.is_open:
			_close_preview()
		return false
	var p := get_global_mouse_position()
	if _last_pointer == Vector2.INF or p.distance_to(_last_pointer) > REST_SLOP:
		_last_pointer = p
		_still = 0.0
	else:
		_still += delta
	var over := _button_at(p)
	if over != _hover_btn:
		_hover_btn = over
		_dwell = 0.0
	else:
		_dwell += delta
	if _hush and over != _hush:
		_hush = null
	if not preview.open:
		if over and over != _hush and (_dwell >= OPEN_DELAY or Time.get_ticks_msec() - _closed_at < REOPEN_WINDOW):
			_open_preview(over, p)
		return over != null
	if not _managing:
		return false
	var target := preview.button
	if target == null or not is_instance_valid(target):
		_close_preview()
		return false
	if over == target:
		_anchor = p
		_away = 0.0
		return true
	if preview.covers(p, 6.0):
		_away = 0.0
		return true
	var heading := _heading_to_preview(p)
	if over and over != _hush:
		# On another app: it takes the card once the pointer settles there.
		var settled := (_still >= SWITCH_REST) if heading else (_dwell >= SWITCH_DWELL)
		if settled:
			_open_preview(over, p)
		else:
			_away = 0.0
		return true
	if heading:
		_away = 0.0
		return true
	_away += delta
	if _away >= CLOSE_DELAY:
		_close_preview()
	return true


func _open_preview(btn: TaskbarButton, at: Vector2) -> void:
	_managing = true
	_anchor = at
	_away = 0.0
	preview.show_for(btn)
	set_process(true)


## Closes the card; `hush` keeps it from reopening for that button until the pointer leaves it.
func _close_preview(hush: TaskbarButton = null) -> void:
	if hush:
		_hush = hush
	if preview.open:
		_closed_at = Time.get_ticks_msec()
	_managing = false
	preview.hide_preview()


func _button_at(p: Vector2) -> TaskbarButton:
	for b in _order:
		if is_instance_valid(b) and b.visible and b.get_global_rect().grow(2.0).has_point(p):
			return b
	return null


## The pointer is on its way from the button up to the card (where the card is
## going, if it's still gliding there): inside the triangle from where it left
## the button to the card's bottom corners, or in the strip right under the card.
func _heading_to_preview(p: Vector2) -> bool:
	var r := preview.aim_rect()
	var bottom := r.end.y
	if p.y < bottom - 2.0:
		return false
	var left := Vector2(r.position.x - 20.0, bottom)
	var right := Vector2(r.end.x + 20.0, bottom)
	if Geometry2D.point_is_inside_triangle(p, _anchor, left, right):
		return true
	return p.x >= r.position.x and p.x <= r.end.x and p.y <= bottom + GAP_SLACK


func _on_context(btn: TaskbarButton, at: Vector2) -> void:
	_close_preview(btn)
	_menu_btn = btn
	_menu.clear()
	_menu.add_item(str(btn.item.get("name", "")), 99)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	var running := btn.window_count() > 0
	if btn.ref == TasksFlyout.REF:
		_menu.add_icon_item(Icons.tex("activity", 18), "Open", 0)
		_menu.add_icon_item(Icons.tex("external", 18), "Windows Task Manager", 3)
		_popup_menu(at)
		return
	if btn.ref.begins_with("oazy:") and not Catalog.is_own_window_app(btn.ref):
		_menu.add_icon_item(Icons.tex("window", 18), "Open", 0)
	elif str(btn.item.get("kind", "")) == "game":
		# A game runs once: Play while it's closed, nothing to add while it runs.
		if not running:
			_menu.add_icon_item(Icons.tex("play", 18), "Play", 0)
	else:
		_menu.add_icon_item(Icons.tex("plus" if running else "play", 18), "New window" if running else "Open", 0)
	main.add_ref_actions(_menu, btn.ref, false)
	if running:
		_menu.add_separator()
		_menu.add_icon_item(Icons.tex("close", 18, App.DANGER.lightened(0.2)), "Close all windows" if btn.window_count() > 1 else "Close window", 2)
	_popup_menu(at)


func _popup_menu(at: Vector2) -> void:
	_menu.reset_size()
	var vp := Shell.view_size()
	_menu.position = Vector2i(int(clampf(at.x - _menu.size.x / 2.0, 8.0, vp.x - _menu.size.x - 8.0)), int(get_global_rect().position.y - _menu.size.y - 10.0))
	Shell.popup(_menu)
	Sfx.play(&"open")


## Right-clicking the bar itself (between its buttons): the task manager and
## the taskbar's settings.
func _on_bar_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT):
		return
	accept_event()
	_close_preview()
	_menu_btn = null
	_menu.clear()
	_menu.add_icon_item(Icons.tex("activity", 18), "Task manager", 10)
	_menu.add_icon_item(Icons.tex("settings", 18), "Taskbar settings", 11)
	_popup_menu(get_global_mouse_position())


func _on_menu(id: int) -> void:
	match id:
		10:
			open_tasks()
			return
		11:
			main.open_settings("desktop")
			return
		3:
			if App.is_windows():
				OS.create_process("taskmgr.exe", [])
			return
	var btn := _menu_btn
	if btn == null or not is_instance_valid(btn):
		return
	match id:
		0:
			if btn.ref == TasksFlyout.REF:
				open_tasks()
			elif btn.ref.begins_with("oazy:") and btn.shell_window:
				main.focus_shell_window(btn.shell_window)
			else:
				_launch(btn)
		2:
			for w in btn.windows:
				Host.close_window(int(w["hwnd"]))
			if btn.shell_window:
				btn.shell_window.close()
		_:
			main.run_ref_action(btn.ref, id)


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


## Opens the network flyout from its tray button (Settings' Choose a network).
func open_network() -> void:
	if network and _net:
		_close_flyouts(network)
		if not network.is_open:
			network.toggle(_net)


## The task manager card lives in Start's layer with the tray's flyouts.
func attach_tasks(t: TasksFlyout) -> void:
	tasks = t
	tasks.opened_changed.connect(func(_open: bool) -> void: queue_rebuild())


func toggle_tasks() -> void:
	if tasks == null:
		return
	if tasks.is_open:
		tasks.close()
	else:
		open_tasks()


## Opens the task manager over its button (from Start, search, a right-click).
func open_tasks() -> void:
	if tasks == null:
		return
	_close_flyouts(tasks)
	if tasks.is_open:
		return
	if _rebuild_queued:
		rebuild()
	tasks.open(_buttons.get(TasksFlyout.REF))


## Every tray flyout but `keep` closes, so only one is ever up.
func _close_flyouts(keep: Flyout) -> void:
	for f in [quick, calendar, weather, network, tasks]:
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
