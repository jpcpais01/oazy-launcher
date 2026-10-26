class_name Flyout
extends Control
## A small glass card that rises from the taskbar tray (quick settings, the
## calendar). Subclasses fill `content` in _build(). Closes on a click outside,
## Esc, or when its tray button is pressed again. Lives in Start's layer so it
## floats above apps in shell mode.

signal opened_changed(open: bool)

const PAD := 20.0

var is_open := false
var width := 360.0
var anchor: Control
var content: VBoxContainer
var _glass: GlassPanel
var _tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glass = GlassPanel.new(true, 22.0, GlassPanel.TINT_POPUP)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.set_shadow_strength(0.32, 28, 10.0)
	add_child(_glass)
	content = Kit.vbox(14)
	content.position = Vector2(PAD, PAD)
	add_child(content)
	_build()
	content.resized.connect(func() -> void:
		if is_open and modulate.a > 0.99:
			size = content.size + Vector2(PAD * 2.0, PAD * 2.0)
			_place()
	)
	var surface := Shell.surface_of(self)
	if surface:
		# Its own OS window in shell mode: going to any other window closes it.
		surface.focus_exited.connect(func() -> void:
			await get_tree().create_timer(0.15).timeout
			if is_open and not surface.has_focus() and not surface.just_shown(400):
				close()
		)


func shell_shape() -> Array[Rect2]:
	return [_glass.shadow_rect()]


func _build() -> void:
	pass


## Called right before the card shows, to refresh what it displays.
func _on_open() -> void:
	pass


func toggle(from: Control = null) -> void:
	if is_open:
		close()
	else:
		open(from)


func open(from: Control = null) -> void:
	if from:
		anchor = from
	is_open = true
	_on_open()
	visible = true
	content.custom_minimum_size.x = width - PAD * 2.0
	content.reset_size()
	await get_tree().process_frame
	if not is_open:
		return
	size = content.size + Vector2(PAD * 2.0, PAD * 2.0)
	_place()
	pivot_offset = _pivot()
	modulate.a = 0.0
	scale = Vector2.ONE * 0.97
	var y := position.y
	position.y += 14.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.35)
	_tween.tween_property(self, "position:y", y, 0.35)
	Sfx.play(&"open")
	Shell.focus(self)
	opened_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_tween.tween_property(self, "position:y", position.y + 10.0, 0.12)
	_tween.chain().tween_callback(func() -> void: visible = false)
	opened_changed.emit(false)


## Where it grows from as it opens.
func _pivot() -> Vector2:
	return Vector2(size.x * 0.5, size.y)


## Sits above the anchor, right-aligned to it, inside the viewport.
func _place() -> void:
	var vp := Shell.view_size()
	var r := anchor.get_global_rect() if anchor and is_instance_valid(anchor) else Rect2(vp - Vector2(10, 80), Vector2.ZERO)
	var x := clampf(r.end.x - size.x + 40.0, 10.0, vp.x - size.x - 10.0)
	position = Vector2(x, r.position.y - size.y - 18.0)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		var on_anchor := anchor != null and is_instance_valid(anchor) and anchor.get_global_rect().has_point(p)
		if not get_global_rect().has_point(p) and not on_anchor:
			close()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- Shared bits ---------------------------------------------------------------------

## A rounded tile with an icon and a label, like Windows' quick settings.
static func tile(icon_name: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = text
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.07), 16, Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.13), 16, Color(1, 1, 1, 0.16), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(App.accent, 0.3), 16, Color(App.accent, 0.6), 1))
	var col := Kit.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var ic := Kit.icon_rect(icon_name, 20, Color(1, 1, 1, 0.9))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ic)
	var l := Kit.label(text, 12, 600, App.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		cb.call()
	)
	return b
