class_name WindowLayer
extends Control
## Holds Oazy's own windows: stacking order, which one is active, the work
## area (everything above the taskbar) and the snap preview while dragging.

signal changed

var main: Node
var reserved_bottom := 92.0
var _ghost: Panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost = Panel.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.08), 22, Color(1, 1, 1, 0.35), 2))
	_ghost.visible = false
	add_child(_ghost)
	resized.connect(_fit_windows)
	var surface := Shell.surface_of(self)
	if surface:
		# Shell mode: these windows share one OS window, which comes and goes
		# from the front as you switch between them and other apps.
		surface.focus_entered.connect(func() -> void:
			if active_window() == null:
				activate(top_window())
		)
		surface.focus_exited.connect(deactivate_all)


## The part of the screen this layer keeps in shell mode: each open window
## plus room for its shadow, and the snap preview while dragging.
func shell_shape() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w in windows():
		if w.visible and w.modulate.a > 0.01:
			out.append(w.shell_rect())
	if _ghost.visible:
		out.append(_ghost.get_global_rect())
	return out


func _input(event: InputEvent) -> void:
	# In one-window mode main routes clicks; in shell mode the layer does.
	if Shell.native and event is InputEventMouseButton and event.pressed:
		press_at(event.position)


func windows() -> Array[ShellWindow]:
	var out: Array[ShellWindow] = []
	for c in get_children():
		if c is ShellWindow and not c.is_queued_for_deletion():
			out.append(c)
	return out


func find(ref: String) -> ShellWindow:
	for w in windows():
		if w.app_ref == ref:
			return w
	return null


func work_rect() -> Rect2:
	return Rect2(Vector2(10, 10), Vector2(size.x - 20.0, size.y - 10.0 - reserved_bottom))


func open_window(win: ShellWindow, want: Vector2) -> ShellWindow:
	win.layer = self
	add_child(win)
	var w := work_rect()
	var sz := want.min(w.size)
	# Cascade new windows a little so they never stack exactly.
	var offset := Vector2(28, 24) * float(windows().size() - 1)
	var pos := w.position + (w.size - sz) / 2.0 + offset
	pos = pos.clamp(w.position, w.end - sz)
	win.set_rect(Rect2(pos, sz))
	win.restore_rect = Rect2(pos, sz)
	win.closed.connect(func(_w: ShellWindow) -> void:
		var top := top_window()
		if top:
			activate(top)
		changed.emit()
	)
	win.state_changed.connect(func(_w: ShellWindow) -> void: changed.emit())
	win.play_open()
	activate(win)
	Sfx.play(&"open")
	return win


func activate(win: ShellWindow) -> void:
	if win == null:
		return
	if win.minimized:
		win.unminimize()
	move_child(win, get_child_count() - 1)
	move_child(_ghost, get_child_count() - 1)
	for w in windows():
		w.set_active(w == win)
	changed.emit()


func deactivate_all() -> void:
	for w in windows():
		w.set_active(false)
	changed.emit()


func active_window() -> ShellWindow:
	for w in windows():
		if w.active and not w.minimized:
			return w
	return null


func top_window() -> ShellWindow:
	var list := windows()
	for i in range(list.size() - 1, -1, -1):
		if list[i].visible and not list[i].minimized and not list[i]._closing:
			return list[i]
	return null


## Activates the window under a click, if any. Returns true when one was hit.
func press_at(global_pos: Vector2) -> bool:
	var list := windows()
	for i in range(list.size() - 1, -1, -1):
		var w := list[i]
		if w.visible and not w.minimized and w.get_global_rect().grow(4.0).has_point(global_pos):
			if not w.active:
				activate(w)
			return true
	if active_window():
		deactivate_all()
	return false


func minimize_target(ref: String) -> Vector2:
	if main and main.taskbar:
		return main.taskbar.button_center(ref) - global_position
	return Vector2(size.x / 2.0, size.y + 40.0)


func show_snap_preview(r: Rect2) -> void:
	if r.has_area():
		if not _ghost.visible:
			_ghost.position = r.position + r.size / 2.0
			_ghost.size = Vector2.ZERO
			_ghost.visible = true
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(_ghost, "position", r.position, 0.22)
		t.tween_property(_ghost, "size", r.size, 0.22)
	else:
		_ghost.visible = false


func minimize_all() -> void:
	for w in windows():
		if not w.minimized:
			w.minimize()


func _fit_windows() -> void:
	var w := work_rect()
	for win in windows():
		if win.maximized:
			win.set_rect(w)
		elif not win.minimized:
			var r := Rect2(win.position, win.size.min(w.size))
			r.position = r.position.clamp(w.position, w.end - Vector2(120, 60))
			win.set_rect(r)
