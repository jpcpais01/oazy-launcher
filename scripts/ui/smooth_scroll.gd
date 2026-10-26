class_name SmoothScroll
extends Node
## Smooth, inertial scrolling for any ScrollContainer or RichTextLabel. Wheel
## and touchpad steps glide to where they lead instead of jumping, quick
## flicks build up speed, and keyboard or gamepad focus moving off screen
## glides the view along too. Scrollbar drags stay direct.
##
## Every scroll view gets one automatically (App.watch_scrolling); nothing has
## to opt in.

## Logical pixels per wheel notch.
const STEP := 110.0
## How quickly the view catches up with where it's heading (higher = snappier).
const SHARPNESS := 15.0
## Notches in quick succession speed up, up to this much.
const MAX_BOOST := 3.0
const BOOST_WINDOW_MS := 140

var view: Control
var _target := Vector2.ZERO
var _pos := Vector2.ZERO
var _active := false
var _boost := 1.0
var _last_wheel := 0
## The scroll values we last set, to notice changes made by anything else.
var _set := Vector2(-1, -1)


static func attach(c: Control) -> void:
	if c.has_meta("smooth_scroll"):
		return
	var s := SmoothScroll.new()
	s.view = c
	c.set_meta("smooth_scroll", true)
	c.add_child(s, false, Node.INTERNAL_MODE_BACK)


func _ready() -> void:
	set_process(false)
	view.gui_input.connect(_on_input)
	if view is ScrollContainer and (view as ScrollContainer).follow_focus:
		# Handled here instead, so it glides.
		(view as ScrollContainer).follow_focus = false
		view.get_viewport().gui_focus_changed.connect(_on_focus)


func _bars() -> Array:
	if view is ScrollContainer:
		var sc := view as ScrollContainer
		return [sc.get_h_scroll_bar(), sc.get_v_scroll_bar()]
	if view is RichTextLabel:
		return [null, (view as RichTextLabel).get_v_scroll_bar()]
	return [null, null]


static func _limit(bar: ScrollBar) -> float:
	if bar == null:
		return 0.0
	return maxf(0.0, bar.max_value - bar.page)


func _current() -> Vector2:
	var b := _bars()
	return Vector2(b[0].value if b[0] else 0.0, b[1].value if b[1] else 0.0)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var dir := Vector2.ZERO
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				dir.y = -1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				dir.y = 1.0
			MOUSE_BUTTON_WHEEL_LEFT:
				dir.x = -1.0
			MOUSE_BUTTON_WHEEL_RIGHT:
				dir.x = 1.0
			_:
				return
		var b := _bars()
		var can_v := _scrollable(b[1], 1)
		var can_h := _scrollable(b[0], 0)
		if dir.y != 0.0 and (mb.shift_pressed or not can_v) and can_h:
			dir = Vector2(dir.y, 0.0)
		if (dir.y != 0.0 and not can_v) or (dir.x != 0.0 and not can_h):
			return
		var factor := mb.factor if mb.factor > 0.0 else 1.0
		var now := Time.get_ticks_msec()
		_boost = minf(_boost * 1.35, MAX_BOOST) if now - _last_wheel < BOOST_WINDOW_MS else 1.0
		_last_wheel = now
		var step := STEP
		if b[1] and dir.y != 0.0:
			# Never more than most of a page, so short lists stay readable.
			step = minf(step, b[1].page * 0.8)
		_glide_by(dir * step * factor * _boost)
		view.accept_event()
	elif event is InputEventPanGesture:
		# Touchpads: follow the fingers directly, just smoothed.
		var pg := event as InputEventPanGesture
		_glide_by(pg.delta * 18.0)
		view.accept_event()


func _scrollable(bar: ScrollBar, axis: int) -> bool:
	if bar == null or _limit(bar) <= 0.0:
		return false
	if view is ScrollContainer:
		var sc := view as ScrollContainer
		var mode := sc.vertical_scroll_mode if axis == 1 else sc.horizontal_scroll_mode
		return mode != ScrollContainer.SCROLL_MODE_DISABLED
	return true


func _glide_by(delta: Vector2) -> void:
	if not _active:
		_pos = _current()
		_target = _pos
	_glide_to(_target + delta)


func _glide_to(to: Vector2) -> void:
	var b := _bars()
	if not _active:
		_pos = _current()
	_target = Vector2(clampf(to.x, 0.0, _limit(b[0])), clampf(to.y, 0.0, _limit(b[1])))
	_active = true
	set_process(true)


func _process(delta: float) -> void:
	var b := _bars()
	var now := _current()
	if _set.x >= 0.0 and now.distance_to(_set) > 1.5:
		# Something else moved it (a scrollbar drag, a list reset): it wins.
		_stop()
		return
	# Content may have shrunk while gliding.
	_target = Vector2(minf(_target.x, _limit(b[0])), minf(_target.y, _limit(b[1])))
	var k := 1.0 - exp(-SHARPNESS * delta)
	_pos = _pos.lerp(_target, k)
	if _pos.distance_to(_target) < 0.5:
		_pos = _target
	if b[0]:
		b[0].value = _pos.x
	if b[1]:
		b[1].value = _pos.y
	_set = _current()
	if _pos == _target:
		_stop()


func _stop() -> void:
	_active = false
	_set = Vector2(-1, -1)
	set_process(false)


## Keeps the focused control in view, gliding to it (follow_focus's job).
func _on_focus(c: Control) -> void:
	if c == null or not is_instance_valid(view) or not view.is_visible_in_tree() or not view.is_ancestor_of(c):
		return
	var b := _bars()
	var vr := view.get_global_rect()
	var cr := c.get_global_rect()
	var scale := view.get_global_transform().get_scale()
	var margin := 24.0
	var to := _target if _active else _current()
	if b[1]:
		if cr.position.y - margin < vr.position.y:
			to.y -= (vr.position.y - cr.position.y + margin) / scale.y
		elif cr.end.y + margin > vr.end.y:
			to.y += (cr.end.y + margin - vr.end.y) / scale.y
	if b[0] and _scrollable(b[0], 0):
		if cr.position.x - margin < vr.position.x:
			to.x -= (vr.position.x - cr.position.x + margin) / scale.x
		elif cr.end.x + margin > vr.end.x:
			to.x += (cr.end.x + margin - vr.end.x) / scale.x
	if to != (_target if _active else _current()):
		_glide_to(to)
