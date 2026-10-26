class_name Modal
extends Control
## Base for dialogs: dims the app, pops a card in with a spring, closes on Esc
## or a click outside. Subclasses fill `content` in `_build()`.

signal closed

var card: PanelContainer
var content: VBoxContainer
var width := 620.0
var dismissable := true
var _dim: ColorRect
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.025, 0.04, 0.5)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if dismissable and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.custom_minimum_size.x = width
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	var glass := GlassPanel.new(true, 28.0, GlassPanel.TINT_WINDOW)
	glass.set_shadow_strength(0.36, 36, 14.0)
	card.add_child(glass)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 32)
	card.add_child(pad)
	content = Kit.vbox(16)
	pad.add_child(content)
	_build()
	Sfx.play(&"open")
	modulate.a = 0.0
	card.scale = Vector2.ONE * 0.97
	await get_tree().process_frame
	card.pivot_offset = card.size / 2.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_focus_first()


func _build() -> void:
	pass


func _focus_first() -> void:
	pass


func close() -> void:
	if _closing:
		return
	_closing = true
	remove_from_group("modal")
	Sfx.play(&"back")
	card.pivot_offset = card.size / 2.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate:a", 0.0, 0.18)
	t.tween_property(card, "scale", Vector2.ONE * 0.97, 0.18)
	t.chain().tween_callback(queue_free)
	closed.emit()


func title_block(title: String, subtitle: String = "", icon_name: String = "") -> void:
	var row := Kit.hbox(14)
	if icon_name != "":
		var bubble := PanelContainer.new()
		bubble.add_theme_stylebox_override("panel", Kit.box(Color(App.accent, 0.22), 999, Color(App.accent, 0.4), 1, 10, 10))
		bubble.add_child(Kit.icon_rect(icon_name, 22, Color.WHITE))
		bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bubble)
	var col := Kit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Kit.label(title, 26, 700, Color.WHITE, true))
	if subtitle != "":
		var s := Kit.label(subtitle, 15, 500, App.TEXT_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(s)
	row.add_child(col)
	content.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not is_top():
		return
	if dismissable and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Only the topmost modal reacts to keys.
func is_top() -> bool:
	var list := get_tree().get_nodes_in_group("modal")
	return not list.is_empty() and list[list.size() - 1] == self
