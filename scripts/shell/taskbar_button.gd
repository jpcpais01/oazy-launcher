class_name TaskbarButton
extends Control
## One app on the taskbar: its icon, a soft glow in the icon's own colour on
## hover (like Windows 7's superbar), and an indicator for running / active.

signal clicked(button: TaskbarButton)
signal middle_clicked(button: TaskbarButton)
signal context(button: TaskbarButton, at: Vector2)
signal hover_changed(button: TaskbarButton, on: bool)

const SIZE := 42.0
const ICON := 28.0

var ref := ""
var item: Dictionary = {}
## Real windows ({hwnd, title, ...}) in this group.
var windows: Array[Dictionary] = []
## Oazy's own window for this app, if open.
var shell_window: ShellWindow
var running := false
var active := false
var launching := false

var _hover_bg: Panel
var _icon: AppIcon
var _dots: Control
var _hot := false
var _tween: Tween
var _launch_tween: Tween


func setup(r: String, it: Dictionary) -> TaskbarButton:
	ref = r
	item = it
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = Vector2(SIZE, SIZE) / 2.0
	_hover_bg = Panel.new()
	_hover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hover_bg.modulate.a = 0.0
	add_child(_hover_bg)
	_icon = AppIcon.new()
	_icon.position = Vector2((SIZE - ICON) / 2.0, (SIZE - ICON) / 2.0 - 2.0)
	_icon.size = Vector2(ICON, ICON)
	_icon.pivot_offset = Vector2(ICON, ICON) / 2.0
	_icon.set_item(item)
	add_child(_icon)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dots.draw.connect(_draw_dots)
	add_child(_dots)
	mouse_entered.connect(_set_hot.bind(true))
	mouse_exited.connect(_set_hot.bind(false))
	Catalog.icon_ready.connect(func(_k: String) -> void: _style_hover())
	App.accent_changed.connect(func(_c: Color) -> void: _dots.queue_redraw())
	_style_hover()
	tooltip_text = ""


func set_item(it: Dictionary) -> void:
	item = it
	if _icon:
		_icon.set_item(it)
		_style_hover()


func set_state(is_running: bool, is_active: bool) -> void:
	if is_running and launching:
		stop_launching()
	running = is_running
	active = is_active
	_dots.queue_redraw()
	if not _hot:
		var t := create_tween()
		t.tween_property(_hover_bg, "modulate:a", 0.0, 0.25)


func window_count() -> int:
	return windows.size() + (1 if shell_window != null else 0)


## A gentle bounce while an app starts, until its window shows up.
func start_launching() -> void:
	launching = true
	if _launch_tween and _launch_tween.is_valid():
		_launch_tween.kill()
	_launch_tween = create_tween().set_loops(6)
	_launch_tween.tween_property(_icon, "position:y", _icon.position.y - 5.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_launch_tween.tween_property(_icon, "position:y", (SIZE - ICON) / 2.0 - 2.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_launch_tween.tween_interval(0.25)
	_launch_tween.finished.connect(stop_launching)


func stop_launching() -> void:
	launching = false
	if _launch_tween and _launch_tween.is_valid():
		_launch_tween.kill()
	if _icon:
		_icon.position.y = (SIZE - ICON) / 2.0 - 2.0


func intro(delay: float) -> void:
	scale = Vector2.ONE * 0.4
	modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	t.tween_property(self, "modulate:a", 1.0, 0.2).set_delay(delay)


func _style_hover() -> void:
	var glow := Catalog.icon_color(str(item.get("icon_key", "")))
	if glow.a <= 0.0:
		glow = App.accent
	var s := Kit.box(Color(glow, 0.13), SIZE / 2.0 - 4.0, Color(1, 1, 1, 0.1), 1)
	Kit.shadowed(s, Color(glow, 0.16), 8, Vector2.ZERO)
	_hover_bg.add_theme_stylebox_override("panel", s)


func _draw_dots() -> void:
	if not running and not launching:
		return
	var c := App.accent.lightened(0.25) if active else Color(1, 1, 1, 0.55)
	var w := 14.0 if active else 5.0
	var y := SIZE - 3.0
	var x := SIZE / 2.0
	var n := mini(window_count(), 3)
	if active or n <= 1:
		_dots.draw_line(Vector2(x - w / 2.0, y), Vector2(x + w / 2.0, y), c, 2.5, true)
		if active:
			_dots.draw_line(Vector2(x - w / 2.0, y), Vector2(x + w / 2.0, y), Color(c, 0.25), 8.0, true)
	else:
		for i in n:
			var cx := x + (float(i) - float(n - 1) / 2.0) * 6.0
			_dots.draw_circle(Vector2(cx, y), 1.6, c)


func _set_hot(on: bool) -> void:
	if on == _hot:
		return
	_hot = on
	hover_changed.emit(self, on)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_hover_bg, "modulate:a", 1.0 if on else 0.0, 0.18)
	_tween.tween_property(_icon, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.2).set_trans(Tween.TRANS_QUART)
	if on:
		Sfx.play(&"move", 1.25)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var t := create_tween()
				t.tween_property(_icon, "scale", Vector2.ONE * 0.92, 0.06)
				t.tween_property(_icon, "scale", Vector2.ONE * (1.05 if _hot else 1.0), 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				clicked.emit(self)
			MOUSE_BUTTON_MIDDLE:
				middle_clicked.emit(self)
			MOUSE_BUTTON_RIGHT:
				context.emit(self, get_global_mouse_position())
		accept_event()
