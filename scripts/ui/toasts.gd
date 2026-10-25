class_name Toasts
extends Control
## Small notifications that slide in bottom-right and dismiss themselves.

var _stack: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = Kit.vbox(10)
	_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_right = -24
	_stack.offset_bottom = -(Taskbar.HEIGHT + Taskbar.MARGIN * 2.0 + 14.0)
	_stack.alignment = BoxContainer.ALIGNMENT_END
	add_child(_stack)


func shell_shape() -> Array[Rect2]:
	if _stack.get_child_count() == 0:
		return []
	return [_stack.get_global_rect().grow(20.0)]


func show_toast(text: String, kind: StringName = &"info", action: Callable = Callable()) -> void:
	var color := App.accent
	var icon := "info"
	match kind:
		&"success":
			color = App.SUCCESS
			icon = "check"
		&"error":
			color = App.DANGER
			icon = "alert"
		&"update":
			icon = "sparkles"
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var glass := GlassPanel.new(true, 18.0, GlassPanel.TINT_POPUP)
	glass.set_shadow_strength(0.4, 24, 10.0)
	card.add_child(glass)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad)
	card.mouse_filter = Control.MOUSE_FILTER_STOP if action.is_valid() else Control.MOUSE_FILTER_PASS
	if action.is_valid():
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				action.call()
				_dismiss(card)
		)
	var row := Kit.hbox(12)
	pad.add_child(row)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", Kit.box(Color(color, 0.2), 999, Color(0, 0, 0, 0), 0, 7, 7))
	bubble.add_child(Kit.icon_rect(icon, 16, color.lightened(0.3)))
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bubble)
	var l := Kit.label(text, 15, 600, App.TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = mini(text.length() * 8 + 20, 380)
	row.add_child(l)
	if action.is_valid():
		var go := Kit.icon_rect("chevron_right", 16, App.TEXT_DIM)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
	_stack.add_child(card)
	while _stack.get_child_count() > 4:
		_stack.get_child(0).queue_free()
	card.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2.ONE * 0.92
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "modulate:a", 1.0, 0.25)
	t.tween_property(card, "scale", Vector2.ONE, 0.4)
	await get_tree().create_timer(6.0 if action.is_valid() else 3.6).timeout
	_dismiss(card)


func _dismiss(card: Control) -> void:
	if not is_instance_valid(card) or card.has_meta("leaving"):
		return
	card.set_meta("leaving", true)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(card, "modulate:a", 0.0, 0.25)
	t.tween_property(card, "scale", Vector2.ONE * 0.95, 0.25)
	t.chain().tween_callback(card.queue_free)
