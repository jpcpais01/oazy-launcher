class_name ShellSurface
extends Window
## One of Oazy's layers as its own OS window, in shell mode (see Shell). It
## covers the screen, is transparent, and is cut to the shape of whatever it
## shows right now, so clicks everywhere else go to the apps underneath. It
## hides itself while it has nothing to show.

## Kept hidden while true (the taskbar while a game is fullscreen).
var suppressed := false
## Stops above Oazy's taskbar instead of covering the whole screen.
var work_area := false
## Passed to the companion to style the window ("taskbar", "start", ...).
var kind := ""
var root: Root
var _poly := PackedVector2Array([Vector2(-1, -1)])
var _styled := false
var _shown_at := 0
## Frames to stay on screen even with nothing to show (a menu is about to open).
var _hold := 0


func _init() -> void:
	add_to_group("shell_surface")
	visible = false
	force_native = true
	borderless = true
	transparent = true
	transparent_bg = true
	transient = false
	wrap_controls = false
	gui_embed_subwindows = true
	root = Root.new()
	add_child(root)


func _ready() -> void:
	fit()
	# Menus inside a layer close when you go to another window.
	focus_exited.connect(func() -> void:
		for w in get_embedded_subwindows():
			if w is Popup and w.visible:
				w.hide()
	)
	visibility_changed.connect(func() -> void:
		if visible:
			_shown_at = Time.get_ticks_msec()
			if not _styled:
				_styled = true
				_style.call_deferred()
	)


func fit() -> void:
	var px := Shell.screen_px
	if work_area:
		px.y -= int(round(Shell.reserve * Shell.scale))
	position = Shell.origin
	size = px
	content_scale_factor = Shell.scale
	root.position = Vector2.ZERO
	root.size = Shell.logical_size()


func hwnd() -> int:
	if get_window_id() == DisplayServer.INVALID_WINDOW_ID:
		return 0
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())


## Shown for less than `ms` milliseconds (focus changes while opening).
func just_shown(ms: int = 250) -> bool:
	return Time.get_ticks_msec() - _shown_at < ms


func _style() -> void:
	var h := hwnd()
	if h != 0:
		Host.style_window(h, kind)


func _process(_delta: float) -> void:
	_update_shape(false)


func _update_shape(force_show: bool) -> void:
	var full := false
	var rects: Array[Rect2] = []
	for c in root.get_children():
		if not (c is CanvasItem) or not c.visible:
			continue
		if c.has_method("shell_shape"):
			var got: Variant = c.call("shell_shape")
			if got == null:
				full = true
			else:
				rects.append_array(got)
		elif c is Control:
			rects.append((c as Control).get_global_rect())
	for w in get_embedded_subwindows():
		if w.visible:
			if w is PopupMenu:
				# A menu is open: clicking anywhere else should close it.
				full = true
			else:
				rects.append(Rect2(w.position, w.size))
	if force_show:
		_hold = 3
	elif _hold > 0:
		_hold -= 1
	var want := not suppressed and (full or not rects.is_empty() or _hold > 0)
	var poly := PackedVector2Array() if full else Shell.union_polygon(rects, Shell.scale)
	if poly != _poly:
		_poly = poly
		mouse_passthrough_polygon = poly
	if want != visible:
		visible = want


## Shows the layer right away, without taking focus.
func reveal() -> void:
	_update_shape(true)


## Shows the layer in front of other apps with keyboard focus.
func bring_to_front() -> void:
	if suppressed:
		return
	_update_shape(true)
	# Not grab_focus(): that would route through the main window, which still
	# counts as this window's embedder even though it is a real OS window.
	if get_window_id() != DisplayServer.INVALID_WINDOW_ID:
		DisplayServer.window_move_to_foreground(get_window_id())
	_focus_os.call_deferred()


func _focus_os() -> void:
	# Windows only lets the foreground app take focus, so ask the companion
	# (which holds the right) when Oazy isn't in front.
	var h := hwnd()
	if h != 0 and not has_focus():
		Host.focus(h)


## The layer's content root. Keys nothing inside used go to Oazy's shortcuts,
## as they would in the single-window layout.
class Root extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and Shell.main and Shell.main.has_method("handle_key"):
			if Shell.main.handle_key(event, get_window()):
				get_viewport().set_input_as_handled()
