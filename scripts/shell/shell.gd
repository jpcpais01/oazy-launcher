class_name Shell
extends RefCounted
## Where Oazy's layers live.
##
## Shell mode (Windows, "Use Oazy as your desktop"): the main window is the
## wallpaper and desktop, kept at the very bottom of the screen. Every layer on
## top of it (Oazy's own windows, the taskbar, Start, dialogs) is its own
## transparent, screen-sized OS window cut to the shape of what it shows, so it
## sits among or above other apps instead of behind them. Opening Chrome never
## takes you out of Oazy: it opens on Oazy's desktop, under Oazy's taskbar.
##
## Everywhere else (Linux dev runs, tests, screenshots, shell mode off) each
## layer is a plain full-screen Control inside the main window.
##
## Either way every layer uses the main window's coordinates, so components
## position themselves exactly as they would in one window.

## True while the layers are separate OS windows.
static var native := false
static var main: Control
## Physical pixels per logical pixel, and where the screen starts.
static var scale := 1.0
static var origin := Vector2i.ZERO
static var screen_px := Vector2i(1600, 900)
## Logical pixels kept free at the bottom for Oazy's taskbar.
static var reserve := 0.0
static var _layers := {}
static var _precreated := false


static func setup(m: Control, use_native: bool, reserve_bottom: float) -> void:
	main = m
	native = use_native
	reserve = reserve_bottom
	_layers.clear()


## A layer to add components to. opts:
##   top    - stays above other apps (taskbar, Start, dialogs)
##   focus  - can take keyboard focus (Start, dialogs, Oazy's windows)
##   work   - stops above the taskbar instead of covering the whole screen
static func layer(name: String, opts: Dictionary = {}) -> Control:
	var holder: Control
	if native:
		var s := ShellSurface.new()
		s.name = name.to_pascal_case() + "Surface"
		s.always_on_top = bool(opts.get("top", false))
		s.unfocusable = not bool(opts.get("focus", false))
		s.work_area = bool(opts.get("work", false))
		s.kind = name
		main.add_child(s)
		holder = s.root
	else:
		holder = Control.new()
		holder.name = name.to_pascal_case() + "Layer"
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main.add_child(holder)
	_layers[name] = holder
	return holder


static func surface_of(node: Node) -> ShellSurface:
	if not native or node == null or not node.is_inside_tree():
		return null
	var w := node.get_window()
	return w as ShellSurface


## Brings a component's layer to the front with keyboard focus. In one-window
## mode this is a no-op apart from keeping Oazy itself in front.
static func focus(node: Node) -> void:
	var s := surface_of(node)
	if s:
		s.bring_to_front()


## Opens a menu that lives in one of the layers, bringing the layer up first.
##
## Godot closes an open menu as soon as the window it sits in (or the desktop
## under it) gains focus, and the OS reports focus a moment late. Opened
## straight away, a menu would show and vanish again, so it waits until its
## layer really has focus. A layer's window must also have been on screen
## for a frame before a menu can open in it.
static func popup(menu: Popup) -> void:
	var s := surface_of(menu.get_parent())
	if s == null:
		menu.popup()
		return
	var tree := menu.get_tree()
	s.pin(true)
	if s.unfocusable:
		var was_up := s.is_up()
		s.reveal()
		if not was_up:
			await tree.process_frame
	elif not s.os_focused:
		s.bring_to_front()
		var until := Time.get_ticks_msec() + 600
		while is_instance_valid(s) and not s.os_focused and Time.get_ticks_msec() < until:
			await tree.process_frame
		# Let the focus change the click itself caused settle too.
		await tree.process_frame
		await tree.process_frame
	if not is_instance_valid(s):
		return
	s.pin(false)
	if not is_instance_valid(menu):
		return
	menu.popup()
	if not menu.visible:
		# The first menu in a freshly shown window only registers it with
		# that window; it opens from the second try on.
		await tree.process_frame
		if is_instance_valid(menu) and not menu.visible:
			menu.popup()


## Hides or shows a whole layer (the taskbar while a game is fullscreen).
static func set_layer_visible(name: String, on: bool) -> void:
	var holder: Control = _layers.get(name)
	if holder == null:
		return
	var s := surface_of(holder)
	if s:
		s.suppressed = not on
	else:
		holder.visible = on


static func layer_hwnd(name: String) -> int:
	var holder: Control = _layers.get(name)
	var s := surface_of(holder) if holder else null
	return s.hwnd() if s else 0


## The OS window a component draws in (0 means Oazy's main window).
static func hwnd_of(node: Node) -> int:
	var s := surface_of(node)
	return s.hwnd() if s else 0


## Makes every layer's OS window up front (parked, showing nothing), one per
## frame, so opening Start, a menu or a dialog never has to create one. Called
## once Oazy has loaded (and the companion is up), while the desktop has
## focus; focus goes back to the main window afterwards, since
## Windows hands it to each new window.
static func precreate_layers() -> void:
	if _precreated or not native or main == null or not ShellSurface.can_park():
		return
	# Each new window takes focus, so only while Oazy has it anyway.
	if not DisplayServer.window_is_focused(DisplayServer.MAIN_WINDOW_ID):
		return
	_precreated = true
	var tree := main.get_tree()
	for holder in _layers.values():
		var s := holder.get_parent() as ShellSurface
		if s and s.precreate():
			await tree.process_frame
	# Back to the top layer that is showing something (a welcome dialog), else
	# the desktop.
	var back: ShellSurface = null
	for holder in _layers.values():
		var s := holder.get_parent() as ShellSurface
		if s and s.is_up() and not s.unfocusable:
			back = s
	if back:
		back.bring_to_front()
	else:
		DisplayServer.window_move_to_foreground(DisplayServer.MAIN_WINDOW_ID)


## Recomputes scale and size after the main window settled on the screen.
static func sync_metrics() -> void:
	if main == null:
		return
	var root := main.get_tree().root
	scale = maxf(root.get_final_transform().get_scale().x, 0.01)
	if native:
		var scr := root.current_screen
		origin = DisplayServer.screen_get_position(scr)
		screen_px = DisplayServer.screen_get_size(scr)
	else:
		screen_px = root.size
	for holder in _layers.values():
		var s := surface_of(holder)
		if s:
			s.fit()


## The logical size of the whole screen (same as the main window's).
static func logical_size() -> Vector2:
	return Vector2(screen_px) / scale


## What components lay themselves out against: the whole screen, in the main
## window's logical pixels.
static func view_size() -> Vector2:
	if native or main == null:
		return logical_size()
	return main.get_viewport_rect().size


## Shell mode is on for this run: Windows, the real app (not a test) and the
## setting on. `--shell-native` forces it for development runs.
static func wanted() -> bool:
	if OS.get_cmdline_user_args().has("--shell-native"):
		return true
	return App.is_windows() and not App.smoke_test and bool(Settings.get_value("shell_mode"))


## A union of rectangles as one polygon (in window pixels), the shape a layer's
## window is cut to. Overlapping rectangles are merged first so the polygon's
## even-odd fill never punches holes.
static func union_polygon(rects: Array[Rect2], px_scale: float) -> PackedVector2Array:
	var merged: Array[Rect2] = []
	for r in rects:
		if r.has_area():
			merged.append(r)
	var again := true
	while again:
		again = false
		for i in merged.size():
			for j in range(i + 1, merged.size()):
				if merged[i].grow(1.0).intersects(merged[j]):
					merged[i] = merged[i].merge(merged[j])
					merged.remove_at(j)
					again = true
					break
			if again:
				break
	var poly := PackedVector2Array()
	if merged.is_empty():
		return poly
	# Each rectangle hangs off a shared anchor; the bridges to it are walked
	# there and back, so they add no area.
	var anchor := Vector2.ZERO
	for r in merged:
		var a := (r.position * px_scale).floor()
		var b := (r.end * px_scale).ceil()
		poly.append(anchor)
		poly.append(a)
		poly.append(Vector2(b.x, a.y))
		poly.append(b)
		poly.append(Vector2(a.x, b.y))
		poly.append(a)
	poly.append(anchor)
	return poly
