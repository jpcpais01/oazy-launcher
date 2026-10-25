class_name HomeTile
extends Control
## One tile in the Home carousel. Real entries show their cover; special tiles
## ("__add", "__library") show an icon card.

signal clicked(tile: HomeTile)
signal double_clicked(tile: HomeTile)
signal context(tile: HomeTile, at: Vector2)

var entry_id := ""
var focused := false
var cover: CoverArt
var _special: Panel
var _move_tween: Tween
var _focus_tween: Tween
var _focus_amount := 0.0


func setup(id: String) -> HomeTile:
	entry_id = id
	return self


func is_special() -> bool:
	return entry_id.begins_with("__")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if is_special():
		_special = Panel.new()
		_special.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_special.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_special)
		var icon := Kit.icon_rect("plus" if entry_id == "__add" else "grid", 34, Color(1, 1, 1, 0.9))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_special.add_child(icon)
		_style_special()
	else:
		cover = CoverArt.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(cover)
		cover.setup(entry_id, 18.0)
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func _style_special() -> void:
	var s := Kit.box(Color(1, 1, 1, 0.05 + _focus_amount * 0.07), 20, Color(1, 1, 1, 0.14 + _focus_amount * 0.7), 2)
	if _focus_amount > 0.01:
		Kit.shadowed(s, Color(App.accent, 0.45 * _focus_amount), 22, Vector2(0, 6))
	_special.add_theme_stylebox_override("panel", s)


func move_to(rect: Rect2, alpha: float, instant: bool = false) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if instant:
		position = rect.position
		size = rect.size
		modulate.a = alpha
		return
	_move_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", rect.position, 0.42)
	_move_tween.tween_property(self, "size", rect.size, 0.42)
	_move_tween.tween_property(self, "modulate:a", alpha, 0.3)


func set_focused(on: bool) -> void:
	if on == focused:
		return
	focused = on
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_method(_set_focus_amount, _focus_amount, 1.0 if on else 0.0, 0.35)
	if on and cover:
		cover.sweep(0.12)


func _set_focus_amount(v: float) -> void:
	_focus_amount = v
	if cover:
		cover.focus_amount = v
		cover.set_dim(0.22 * (1.0 - v))
	elif _special:
		_style_special()


func refresh_dim() -> void:
	_set_focus_amount(_focus_amount)


func intro(delay: float) -> void:
	var final_pos := position
	var final_a := modulate.a
	position.y += 34.0
	modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position", final_pos, 0.7).set_delay(delay)
	t.tween_property(self, "modulate:a", final_a, 0.5).set_delay(delay)


func bump(direction: int) -> void:
	var base := position
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:x", base.x + 8.0 * direction, 0.08)
	t.tween_property(self, "position:x", base.x, 0.22).set_trans(Tween.TRANS_BACK)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				double_clicked.emit(self)
			else:
				clicked.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context.emit(self, get_global_mouse_position())
			accept_event()
