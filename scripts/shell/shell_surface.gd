class_name ShellSurface
extends Window
## One of Oazy's layers as its own OS window, in shell mode (see Shell). It
## covers the screen, is transparent, and is cut to the shape of whatever it
## shows right now, so clicks everywhere else go to the apps underneath.
##
## While it has nothing to show it is parked rather than hidden: the OS window
## stays, cut down to nothing and no longer drawn. Hiding a Godot window
## destroys it, and making a new window (and its GL surface) every time Start
## or a menu opened was what made them hitch. Showing a parked layer is just a
## new shape and one more viewport to draw.

## Kept hidden while true (the taskbar while a game is fullscreen).
var suppressed := false
## Stops above Oazy's taskbar instead of covering the whole screen.
var work_area := false
## Passed to the companion to style the window ("taskbar", "start", ...).
var kind := ""
var root: Root
## A shape entirely outside the window: nothing drawn, nothing clickable.
## (An empty polygon would mean the opposite, the whole window.)
const PARKED := [Vector2(-8, -8), Vector2(-2, -8), Vector2(-2, -2), Vector2(-8, -2)]
## Up as an OS window but showing nothing (see the class notes).
var parked := false
var _poly := PackedVector2Array([Vector2(-1, -1)])
var _styled_id := DisplayServer.INVALID_WINDOW_ID
## Frames left to draw after parking, so the buffer that comes back on screen
## next time is a clear one.
var _park_frames := 0
var _shown_at := 0
## True between the OS telling us this window got focus and lost it.
## (Window.has_focus() turns true as soon as focus is asked for.)
var os_focused := false
## Frames to stay on screen even with nothing to show (a menu is about to open).
var _hold := 0
## Kept on screen while a menu waits to open in it.
var _pins := 0


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
	# Menus close on their own when you go elsewhere (Godot's popups close
	# when the app or a window above them in the tree gains focus); hiding
	# them here as well raced with menus that were still opening.
	focus_entered.connect(func() -> void: os_focused = true)
	focus_exited.connect(func() -> void: os_focused = false)
	visibility_changed.connect(func() -> void:
		if not visible:
			os_focused = false
			parked = false
		if visible:
			_shown_at = Time.get_ticks_msec()
			_on_new_window()
	)


## Every new OS window (first show, or after being really hidden) needs the
## companion's styling again, and must not wait for vsync on its own: the
## main window already paces the frame, and each extra window waiting for the
## next refresh in turn would divide the frame rate.
func _on_new_window() -> void:
	var id := get_window_id()
	if id == DisplayServer.INVALID_WINDOW_ID or id == _styled_id:
		return
	_styled_id = id
	if App.is_windows():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, id)
	_style.call_deferred()


## Parking needs the companion to hand focus back when a focused layer empties
## (Windows would otherwise keep typing going to an invisible window). Without
## it, layers are hidden the old way.
static func can_park() -> bool:
	return App.is_windows() and Host.available


## Makes the OS window now, parked, so the first time it is needed costs no
## more than any other time. Returns true if a window was made.
func precreate() -> bool:
	if visible or suppressed:
		return false
	parked = true
	_park_frames = 2
	_poly = PackedVector2Array(PARKED)
	mouse_passthrough_polygon = _poly
	visible = true
	return true


func is_up() -> bool:
	return visible and not parked


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
	var want := not suppressed and (full or not rects.is_empty() or _hold > 0 or _pins > 0)
	if not want and visible and not parked and not suppressed and can_park():
		_park()
		return
	if parked:
		if _park_frames > 0:
			_park_frames -= 1
			if _park_frames == 0:
				RenderingServer.viewport_set_active(get_viewport_rid(), false)
		if not want:
			if suppressed:
				visible = false
			return
		_unpark()
	var poly := PackedVector2Array() if full else Shell.union_polygon(rects, Shell.scale)
	if not full and poly.is_empty():
		# Up but empty (held for a menu): an empty polygon would mean "the
		# whole window takes clicks", so keep a single pixel instead.
		poly = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	if poly != _poly:
		_poly = poly
		mouse_passthrough_polygon = poly
	if want != visible:
		visible = want


func _park() -> void:
	parked = true
	# Draw a couple more (now empty) frames before stopping.
	_park_frames = 2
	_poly = PackedVector2Array(PARKED)
	mouse_passthrough_polygon = _poly
	if os_focused or has_focus():
		# Let Windows activate whatever is next in line, as it did when the
		# window closed.
		Host.release_focus(hwnd())


func _unpark() -> void:
	parked = false
	_park_frames = 0
	RenderingServer.viewport_set_active(get_viewport_rid(), true)
	_shown_at = Time.get_ticks_msec()
	if unfocusable:
		# Newly made windows used to come up above the other layers; a parked
		# one keeps its old place, so lift it (without taking focus).
		Host.raise_window(hwnd())


func pin(on: bool) -> void:
	_pins = maxi(0, _pins + (1 if on else -1))
	if on:
		_update_shape(true)


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
