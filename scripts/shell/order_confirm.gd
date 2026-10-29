class_name OrderConfirm
extends Modal
## The last look before real money moves: what, how much, at what price, the
## leverage, the margin it ties up and the fee. Cancel has the focus, so a
## stray Enter never sends anything.

var title := ""
var message := ""
## [label, value, color or null] rows.
var rows: Array = []
var confirm_text := "Confirm"
var tone := Color.WHITE
var on_confirm := Callable()
var _cancel: FxButton


func _init() -> void:
	width = 540.0


func _build() -> void:
	title_block(title, message, "alert")
	content.add_child(Kit.spacer(0, 4))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 14, Color(1, 1, 1, 0.07), 1, 18, 10))
	content.add_child(box)
	var list := Kit.vbox(0)
	box.add_child(list)
	for r in rows:
		var row := Kit.hbox(12)
		row.custom_minimum_size.y = 34
		list.add_child(row)
		var k := Kit.label(str(r[0]), 14, 500, App.TEXT_MUTE)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(k)
		var v := DesktopBelow._num(str(r[1]), 15, 600, r[2] if r.size() > 2 and r[2] is Color else App.TEXT)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(v)
	content.add_child(Kit.spacer(0, 6))
	var buttons := Kit.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(buttons)
	_cancel = FxButton.make("Cancel", "", FxButton.Style.GHOST, 46)
	_cancel.pressed.connect(close)
	buttons.add_child(_cancel)
	var go := Button.new()
	go.text = confirm_text
	go.focus_mode = Control.FOCUS_NONE
	go.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	go.custom_minimum_size = Vector2(200, 46)
	go.add_theme_font_override("font", Kit.font(700))
	go.add_theme_font_size_override("font_size", 15)
	go.add_theme_color_override("font_color", Color(0.03, 0.05, 0.07))
	go.add_theme_color_override("font_hover_color", Color(0.03, 0.05, 0.07))
	go.add_theme_color_override("font_pressed_color", Color(0.03, 0.05, 0.07))
	go.add_theme_stylebox_override("normal", Kit.box(Color(tone, 0.92), 14, Color(0, 0, 0, 0), 0, 18, 0))
	go.add_theme_stylebox_override("hover", Kit.box(tone.lightened(0.08), 14, Color(0, 0, 0, 0), 0, 18, 0))
	go.add_theme_stylebox_override("pressed", Kit.box(tone.darkened(0.08), 14, Color(0, 0, 0, 0), 0, 18, 0))
	go.pressed.connect(func() -> void:
		Sfx.play(&"select")
		if on_confirm.is_valid():
			on_confirm.call()
		close()
	)
	buttons.add_child(go)


func _focus_first() -> void:
	_cancel.grab_focus()
