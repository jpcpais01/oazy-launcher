class_name TaskPreview
extends Control
## The card that rises above a taskbar button: each window of that app with
## its title, a close button and a live preview drawn by Windows (DWM
## thumbnails), or just the app's name for pinned apps that aren't open.

signal hover_changed(on: bool)

const CARD_W := 252.0
const THUMB := Vector2(228, 132)

var button: TaskbarButton
var main: Node
var _glass: GlassPanel
var _content: HBoxContainer
var _slots: Array = []
var _tween: Tween
var _thumbs_on := false
var _serial := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_glass = GlassPanel.new(true, 18.0, GlassPanel.TINT_POPUP)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glass)
	_content = Kit.hbox(8)
	_content.position = Vector2(10, 10)
	add_child(_content)
	mouse_entered.connect(func() -> void: hover_changed.emit(true))
	mouse_exited.connect(func() -> void:
		if not get_global_rect().has_point(get_global_mouse_position()):
			hover_changed.emit(false)
	)


func is_showing() -> bool:
	return visible and modulate.a > 0.01


func show_for(btn: TaskbarButton) -> void:
	_serial += 1
	var serial := _serial
	clear_thumbs()
	button = btn
	for c in _content.get_children():
		c.queue_free()
	_slots.clear()
	if btn.window_count() == 0:
		var pill := Kit.vbox(2)
		pill.add_child(Kit.label(str(btn.item.get("name", "")), 15, 600, App.TEXT))
		var sub := str(btn.item.get("sub", ""))
		if sub != "":
			pill.add_child(Kit.label(sub, 13, 500, App.TEXT_MUTE))
		var m := MarginContainer.new()
		for side in ["left", "right"]:
			m.add_theme_constant_override("margin_" + side, 6)
		m.add_child(pill)
		_content.add_child(m)
	else:
		if btn.shell_window != null:
			_content.add_child(_card_for_shell(btn.shell_window))
		for w in btn.windows.slice(0, 4):
			_content.add_child(_card_for_window(w))
	visible = true
	await get_tree().process_frame
	if serial != _serial or not is_instance_valid(btn):
		return
	_content.reset_size()
	size = _content.size + Vector2(20, 20)
	var center := btn.get_global_rect().get_center()
	var vp := get_viewport_rect().size
	var top := btn.get_global_rect().position.y - 14.0 - size.y
	position = Vector2(clampf(center.x - size.x / 2.0, 10.0, vp.x - size.x - 10.0), top)
	pivot_offset = Vector2(center.x - position.x, size.y)
	if _tween and _tween.is_valid():
		_tween.kill()
	if modulate.a < 0.5:
		modulate.a = 0.0
		scale = Vector2.ONE * 0.94
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.3)
	await get_tree().create_timer(0.2).timeout
	if serial == _serial and visible:
		_show_thumbs()


func hide_preview() -> void:
	_serial += 1
	clear_thumbs()
	if not visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_tween.tween_callback(func() -> void: visible = false)


func clear_thumbs() -> void:
	if _thumbs_on:
		Host.thumb_clear()
		_thumbs_on = false


func _card(title_text: String, close_cb: Callable, pick_cb: Callable) -> Dictionary:
	var card := PanelContainer.new()
	var normal := Kit.box(Color(1, 1, 1, 0.0), 12, Color(0, 0, 0, 0), 0, 8, 8)
	var hot := Kit.box(Color(1, 1, 1, 0.1), 12, Color(1, 1, 1, 0.14), 1, 8, 8)
	card.add_theme_stylebox_override("panel", normal)
	card.custom_minimum_size.x = CARD_W - 16.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hot))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal))
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pick_cb.call()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_MIDDLE:
			close_cb.call()
	)
	var col := Kit.vbox(8)
	card.add_child(col)
	var head := Kit.hbox(8)
	col.add_child(head)
	var t := Kit.label(title_text, 13, 600, App.TEXT)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var x := FxButton.icon_only("close", "Close", 14, 24)
	x.focus_mode = Control.FOCUS_NONE
	x.hover_scale = 1.0
	x.add_theme_stylebox_override("hover", Kit.box(Color(1.0, 0.36, 0.42, 0.9), 999))
	x.pressed.connect(close_cb)
	head.add_child(x)
	var slot := Panel.new()
	slot.custom_minimum_size = THUMB
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.22), 10))
	col.add_child(slot)
	return {"card": card, "slot": slot}


func _card_for_window(w: Dictionary) -> Control:
	var hwnd := int(w["hwnd"])
	var on_close := func() -> void:
		Host.close_window(hwnd)
		hide_preview()
	var on_pick := func() -> void:
		Host.focus(hwnd)
		hide_preview()
	var parts := _card(str(w.get("title", "")), on_close, on_pick)
	var slot: Panel = parts["slot"]
	if not Host.available or bool(w.get("min", false)):
		_fill_icon(slot, button.item, "Minimised" if bool(w.get("min", false)) else "")
	_slots.append([slot, hwnd, bool(w.get("min", false))])
	return parts["card"]


func _card_for_shell(win: ShellWindow) -> Control:
	var on_close := func() -> void:
		win.close()
		hide_preview()
	var on_pick := func() -> void:
		if main:
			main.focus_shell_window(win)
		hide_preview()
	var parts := _card(win.title, on_close, on_pick)
	_fill_icon(parts["slot"], Catalog.item(win.app_ref), "Minimised" if win.minimized else "")
	return parts["card"]


func _fill_icon(slot: Control, it: Dictionary, note: String) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(center)
	var col := Kit.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(52, 52)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	col.add_child(ic)
	if note != "":
		var l := Kit.label(note, 12, 500, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)


func _show_thumbs() -> void:
	if not Host.available:
		return
	var xf_view := get_viewport().get_final_transform()
	for s in _slots:
		var slot: Control = s[0]
		if bool(s[2]) or not is_instance_valid(slot):
			continue
		var xf := xf_view * slot.get_global_transform_with_canvas()
		var origin := xf.origin
		var span := xf.basis_xform(slot.size)
		var r := Rect2i(Vector2i(origin.round()), Vector2i(span.round())).grow(-4)
		Host.thumb(int(s[1]), r)
		_thumbs_on = true
