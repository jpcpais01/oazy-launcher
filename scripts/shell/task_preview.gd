class_name TaskPreview
extends Control
## The card that rises above a taskbar button: each window of that app with
## its title, a close button and a live preview drawn by Windows (DWM
## thumbnails), or just the app's name for pinned apps that aren't open.
## Minimised windows show too: Windows draws them as they were, and under
## that sits the last picture Oazy kept of them (or the app's icon).
## There is only ever one: moving along the taskbar glides it from app to app
## (the taskbar decides when, see Taskbar._step_preview).

const CARD_W := 252.0
const THUMB := Vector2(228, 132)
## Space between the card and the taskbar button it belongs to.
const GAP := 14.0
const ROUNDED := preload("res://shaders/rounded_tex.gdshader")

var button: TaskbarButton
var main: Node
## Showing (or on its way in) for `button`; false once it starts to close.
var open := false
## Where the card is going to be for `button` (empty until it's laid out).
## Pointer logic aims here, not at a card still gliding over from another app.
var target_rect := Rect2()
var _glass: GlassPanel
var _clip: Control
var _content: HBoxContainer
var _slots: Array = []
var _tween: Tween
var _thumbs_on := false
var _serial := 0
## What the card was built from, so going back to the same app doesn't rebuild it.
var _built := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_glass = GlassPanel.new(true, 18.0, GlassPanel.TINT_POPUP)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glass)
	# While the card glides and reshapes from one app to the next, the new
	# app's windows stay inside it instead of spilling over its edges.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_clip)
	_content = Kit.hbox(8)
	_content.position = Vector2(10, 10)
	_clip.add_child(_content)


## The card, plus the strip between it and its button, so the pointer stays
## on Oazy's taskbar all the way up.
func shell_shape() -> Array[Rect2]:
	var shape: Array[Rect2] = [_glass.shadow_rect()]
	if open and is_instance_valid(button):
		var bottom := position.y + size.y
		var top := button.get_global_rect().position.y
		if top > bottom:
			shape.append(Rect2(position.x, bottom, size.x, top - bottom + 2.0))
	return shape


func is_showing() -> bool:
	return visible and modulate.a > 0.01


## `p` is on the card, or where it's gliding to, give or take `margin`.
func covers(p: Vector2, margin: float) -> bool:
	if get_global_rect().grow(margin).has_point(p):
		return true
	return open and target_rect.has_area() and target_rect.grow(margin).has_point(p)


## Where the card is headed, or where it is while that's still being worked out.
func aim_rect() -> Rect2:
	return target_rect if open and target_rect.has_area() else get_global_rect()


func _signature(btn: TaskbarButton) -> String:
	var parts := PackedStringArray([btn.ref, str(btn.item.get("name", ""))])
	if btn.shell_window != null:
		parts.append("oazy:%d:%s:%s" % [btn.shell_window.get_instance_id(), btn.shell_window.title, btn.shell_window.minimized])
	for w in btn.windows.slice(0, 4):
		parts.append("%d:%s:%s" % [int(w["hwnd"]), str(w.get("title", "")), bool(w.get("min", false))])
	return "|".join(parts)


func show_for(btn: TaskbarButton) -> void:
	var sig := _signature(btn)
	if open and btn == button and sig == _built and is_showing():
		return
	_serial += 1
	var serial := _serial
	# Stop a fade-out first, or its "hide" at the end would land after this.
	if _tween and _tween.is_valid():
		_tween.kill()
	var gliding := open and is_showing()
	open = true
	clear_thumbs()
	if btn != button:
		target_rect = Rect2()
	button = btn
	if sig != _built:
		_built = sig
		for c in _content.get_children():
			_content.remove_child(c)
			c.queue_free()
		_slots.clear()
		_build(btn)
	# Laid out next frame; until then the old card keeps its shape, empty,
	# rather than the new contents spilling out of it.
	_content.modulate.a = 0.0
	visible = true
	await get_tree().process_frame
	if serial != _serial or not is_instance_valid(btn):
		return
	_content.reset_size()
	var want := _content.size + Vector2(20, 20)
	var center := btn.get_global_rect().get_center()
	var vp := Shell.view_size()
	var top := btn.get_global_rect().position.y - GAP - want.y
	var at := Vector2(clampf(center.x - want.x / 2.0, 10.0, vp.x - want.x - 10.0), top)
	target_rect = Rect2(at, want)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if gliding:
		# Already up for another app: slide and reshape into place.
		_tween.tween_property(self, "position", at, 0.22)
		_tween.tween_property(self, "size", want, 0.22)
		_tween.tween_property(self, "modulate:a", 1.0, 0.1)
		_tween.tween_property(self, "scale", Vector2.ONE, 0.2)
		_tween.tween_property(_content, "modulate:a", 1.0, 0.16).set_delay(0.06)
	else:
		position = at
		size = want
		if modulate.a < 0.5:
			modulate.a = 0.0
			scale = Vector2.ONE * 0.94
		_tween.tween_property(self, "modulate:a", 1.0, 0.16)
		_tween.tween_property(self, "scale", Vector2.ONE, 0.3)
		_content.modulate.a = 1.0
	pivot_offset = Vector2(center.x - at.x, want.y)
	# Live pictures go in once the card has stopped moving.
	await get_tree().create_timer(0.24).timeout
	if serial == _serial and open:
		_show_thumbs()


func _build(btn: TaskbarButton) -> void:
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


func hide_preview() -> void:
	_serial += 1
	open = false
	target_rect = Rect2()
	clear_thumbs()
	if not visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_tween.tween_callback(func() -> void:
		visible = false
		_built = ""
	)


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
	var minimised := bool(w.get("min", false))
	var pic := Host.picture_of(hwnd) if minimised else null
	if pic:
		_fill_pic(slot, pic)
	elif not Host.available or minimised:
		_fill_icon(slot, button.item, "Minimised" if minimised else "")
	_slots.append([slot, hwnd])
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
	var pic := win.snapshot()
	if pic:
		_fill_pic(parts["slot"], pic)
	else:
		_fill_icon(parts["slot"], Catalog.item(win.app_ref), "Minimised" if win.minimized else "")
	return parts["card"]


## A still of the window, fitted into the slot with rounded corners.
func _fill_pic(slot: Control, tex: Texture2D) -> void:
	var src := Vector2(tex.get_size())
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var room := THUMB - Vector2(8, 8)
	var fit := (src * minf(room.x / src.x, room.y / src.y)).floor()
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = tex
	r.position = ((THUMB - fit) / 2.0).floor()
	r.size = fit
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED
	mat.set_shader_parameter("size", fit)
	mat.set_shader_parameter("radius", 6.0)
	r.material = mat
	slot.add_child(r)


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
		if not is_instance_valid(slot):
			continue
		var xf := xf_view * slot.get_global_transform_with_canvas()
		var origin := xf.origin
		var span := xf.basis_xform(slot.size)
		var r := Rect2i(Vector2i(origin.round()), Vector2i(span.round())).grow(-4)
		Host.thumb(int(s[1]), r, Callable(), Shell.hwnd_of(self))
		_thumbs_on = true
