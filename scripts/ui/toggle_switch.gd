class_name ToggleSwitch
extends Button
## iOS/PS5-style switch with an animated knob, keyboard and gamepad friendly.

var _t := 0.0
var _tween: Tween


func _init() -> void:
	toggle_mode = true
	custom_minimum_size = Vector2(54, 30)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())


func _ready() -> void:
	_t = 1.0 if button_pressed else 0.0
	toggled.connect(_on_toggled)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	App.accent_changed.connect(func(_c: Color) -> void: queue_redraw())


func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	_t = 1.0 if on else 0.0
	queue_redraw()


func _on_toggled(on: bool) -> void:
	Sfx.play(&"toggle", 1.1 if on else 0.9)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_t, _t, 1.0 if on else 0.0, 0.22)


func _set_t(v: float) -> void:
	_t = v
	queue_redraw()


func _draw() -> void:
	var w := 54.0
	var h := 30.0
	var origin := Vector2(size.x - w, (size.y - h) / 2.0)
	var track_rect := Rect2(origin, Vector2(w, h))
	var off := Color(1, 1, 1, 0.16 if is_hovered() else 0.12)
	var track := Kit.box(off.lerp(App.accent, clampf(_t, 0.0, 1.0)), 15)
	track.draw(get_canvas_item(), track_rect)
	if has_focus():
		var ring := Kit.box(Color(0, 0, 0, 0), 18, Color(1, 1, 1, 0.85), 2)
		ring.draw(get_canvas_item(), track_rect.grow(3))
	var k := 24.0
	var kx := lerpf(3.0, w - k - 3.0, _t)
	var knob := Kit.box(Color.WHITE, 12)
	Kit.shadowed(knob, Color(0, 0, 0, 0.3), 4, Vector2(0, 1))
	knob.draw(get_canvas_item(), Rect2(origin + Vector2(kx, 3.0), Vector2(k, k)))
