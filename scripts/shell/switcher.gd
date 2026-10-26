class_name Switcher
extends Control
## Oazy's Alt+Tab: a pane of glass in the middle of the screen with every open
## window (Oazy's own and other apps') as a live preview. Tab and Shift+Tab or
## the arrow keys move, Delete closes, Esc backs out and letting go of Alt
## switches. The companion catches the keys (see Host.switch_key), so this
## layer never needs focus. A quick tap switches straight to the last window
## without showing anything, like Windows does.

const CARD := Vector2(236, 184)
const PAD := 10.0
const HEAD := 32.0
const GAP := 14.0
const MARGIN := 20.0
const MAX_COLS := 6
const MAX_ROWS := 3
## How long Alt+Tab has to be held before the switcher shows.
const DELAY := 0.1

var main: Node
var is_open := false
var selected := 0
var _entries: Array[Dictionary] = []
var _cards: Array[Control] = []
var _glass: GlassPanel
var _holder: Control
var _ring: Panel
var _cols := 1
var _card_size := CARD
var _shown := false
var _serial := 0
var _tween: Tween
var _ring_tween: Tween
var _thumbs_on := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_glass = GlassPanel.new(true, 26.0, GlassPanel.TINT_WINDOW)
	_glass.set_shadow_strength(0.5, 44, 18.0)
	_glass.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_glass)
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.add_child(_holder)
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_ring)
	_style_ring()
	App.accent_changed.connect(func(_c: Color) -> void: _style_ring())


func shell_shape() -> Array[Rect2]:
	return [_glass.shadow_rect()]


func is_showing() -> bool:
	return visible and _shown


## One of the keys the companion passes on while Alt is held.
func handle_key(key: String) -> void:
	match key:
		"open", "open_back":
			open(key == "open_back")
		"next", "right":
			step(1)
		"prev", "left":
			step(-1)
		"down":
			_move_row(1)
		"up":
			_move_row(-1)
		"close":
			close_selected()
		"done":
			commit()
		"cancel":
			cancel()


func open(back: bool = false) -> void:
	if is_open:
		step(-1 if back else 1)
		return
	_entries = _collect()
	if _entries.is_empty():
		return
	is_open = true
	_serial += 1
	var serial := _serial
	selected = (_entries.size() - 1 if back else 1) if _entries.size() > 1 else 0
	if main:
		main.preview.hide_preview()
		if main.start.is_open:
			main.start.close()
	await get_tree().create_timer(DELAY).timeout
	if serial == _serial and is_open:
		_show()


func step(d: int) -> void:
	if not is_open or _entries.is_empty():
		return
	_select(posmod(selected + d, _entries.size()))


func _move_row(d: int) -> void:
	if not is_open or _entries.is_empty():
		return
	var to := selected + d * _cols
	if to >= 0 and to < _entries.size():
		_select(to)


## Switches to the selected window and closes.
func commit() -> void:
	if not is_open:
		return
	var e: Dictionary = _entries[selected] if selected < _entries.size() else {}
	_hide()
	if e.is_empty():
		return
	var win: ShellWindow = e.get("shell")
	if win != null:
		if is_instance_valid(win) and main:
			main.focus_shell_window(win)
	else:
		Host.focus(int(e["hwnd"]))


func cancel() -> void:
	if is_open:
		_hide()


func close_selected() -> void:
	if not is_open or selected >= _entries.size():
		return
	var e: Dictionary = _entries[selected]
	var win: ShellWindow = e.get("shell")
	if win != null:
		if is_instance_valid(win):
			win.close()
	else:
		Host.close_window(int(e["hwnd"]))
	_entries.remove_at(selected)
	if _entries.is_empty():
		_hide()
		return
	selected = mini(selected, _entries.size() - 1)
	if _shown:
		_clear_thumbs()
		_build()
		_show_thumbs()


## Every window you can switch to, most recently used first: Oazy's own
## windows go first while you're in them, else right after the window in front.
func _collect() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in Host.windows:
		var ref := Catalog.ref_for_window(w)
		var it := Catalog.item(ref)
		if ref.begins_with("win:"):
			it["name"] = Catalog.window_group_name(w)
		out.append({"hwnd": int(w["hwnd"]), "title": str(w.get("title", "")), "item": it, "min": bool(w.get("min", false))})
	var own: Array[Dictionary] = []
	if main:
		var list: Array[ShellWindow] = main.layer.windows()
		list.reverse()
		for win in list:
			if win._closing:
				continue
			var e := {"shell": win, "title": win.title, "item": Catalog.item(win.app_ref), "min": win.minimized}
			if win.active:
				own.push_front(e)
			else:
				own.append(e)
	var at := 0 if (main and main.windows_in_front()) or Host.self_foreground else mini(1, out.size())
	for i in own.size():
		out.insert(at + i, own[i])
	return out.slice(0, MAX_COLS * MAX_ROWS * 2)


func _show() -> void:
	_build()
	visible = true
	_shown = true
	_glass.pivot_offset = _glass.size / 2.0
	_glass.modulate.a = 0.0
	_glass.scale = Vector2.ONE * 0.95
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_glass, "modulate:a", 1.0, 0.14)
	_tween.tween_property(_glass, "scale", Vector2.ONE, 0.24)
	var surface := Shell.surface_of(self)
	if surface:
		surface.reveal()
	var serial := _serial
	await get_tree().create_timer(0.16).timeout
	if serial == _serial and _shown:
		_show_thumbs()


func _hide() -> void:
	is_open = false
	_serial += 1
	_clear_thumbs()
	if not _shown:
		return
	_shown = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_glass, "modulate:a", 0.0, 0.1)
	_tween.tween_property(_glass, "scale", Vector2.ONE * 0.97, 0.1)
	_tween.chain().tween_callback(func() -> void:
		if not _shown:
			visible = false
	)


# --- Layout -----------------------------------------------------------------------

func _build() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	var vp := Shell.view_size()
	var n := _entries.size()
	var fit_cols := int(floor((vp.x - 120.0 - MARGIN * 2.0 + GAP) / (CARD.x + GAP)))
	_cols = clampi(mini(n, fit_cols), 1, MAX_COLS)
	var rows := int(ceil(float(n) / _cols))
	# Lots of windows: smaller cards rather than a pane taller than the screen.
	var room := vp.y - 160.0 - MARGIN * 2.0
	var k := minf(1.0, (room + GAP) / (rows * (CARD.y + GAP)))
	_card_size = (CARD * k).floor()
	var grid := Vector2(_cols * _card_size.x + (_cols - 1) * GAP, rows * _card_size.y + (rows - 1) * GAP)
	_glass.size = grid + Vector2(MARGIN, MARGIN) * 2.0
	_glass.position = ((vp - _glass.size) / 2.0 - Vector2(0, vp.y * 0.03)).round()
	_glass.pivot_offset = _glass.size / 2.0
	_holder.position = Vector2(MARGIN, MARGIN)
	for i in n:
		var row := i / _cols
		var col := i % _cols
		# The last row is centred under the others.
		var in_row := mini(_cols, n - row * _cols)
		var shift := (_cols - in_row) * (_card_size.x + GAP) / 2.0
		var card := _card(i)
		card.position = Vector2(shift + col * (_card_size.x + GAP), row * (_card_size.y + GAP))
		_holder.add_child(card)
		_cards.append(card)
	_select(selected, false)


func _card(i: int) -> Control:
	var e: Dictionary = _entries[i]
	var card := Control.new()
	card.size = _card_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func() -> void:
		if is_open and i < _entries.size():
			_select(i)
	)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			selected = i
			commit()
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			selected = i
			close_selected()
	)
	var icon := AppIcon.new()
	icon.size = Vector2(20, 20)
	icon.position = Vector2(PAD + 2.0, (HEAD - 20.0) / 2.0 + 2.0)
	icon.set_item(e["item"])
	card.add_child(icon)
	var title := str(e["title"])
	if title == "":
		title = str(e["item"].get("name", ""))
	var t := Kit.label(title, 13, 600, App.TEXT_DIM)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.position = Vector2(PAD + 30.0, 2.0)
	t.size = Vector2(_card_size.x - PAD * 2.0 - 32.0, HEAD)
	card.add_child(t)
	card.set_meta("title", t)
	var slot := Panel.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.position = Vector2(PAD, HEAD + 4.0)
	slot.size = Vector2(_card_size.x - PAD * 2.0, _card_size.y - HEAD - 4.0 - PAD)
	slot.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.24), 12))
	card.add_child(slot)
	card.set_meta("slot", slot)
	# Oazy's own windows and minimised apps have no live picture: show the app.
	var live: bool = Host.available and e.get("shell") == null and not bool(e["min"])
	card.set_meta("live", live)
	if not live:
		_fill_icon(slot, e["item"], "Minimised" if bool(e["min"]) else "")
	return card


func _fill_icon(slot: Control, it: Dictionary, note: String) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(center)
	var col := Kit.vbox(8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var ic := AppIcon.new()
	var px := clampf(slot.size.y * 0.42, 28.0, 60.0)
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	col.add_child(ic)
	if note != "":
		var l := Kit.label(note, 12, 500, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)


func _select(i: int, animate: bool = true) -> void:
	selected = i
	if i >= _cards.size():
		return
	for j in _cards.size():
		var l: Label = _cards[j].get_meta("title")
		l.add_theme_color_override("font_color", Color.WHITE if j == i else App.TEXT_DIM)
	var target := Rect2(_cards[i].position, _cards[i].size)
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	if not animate or not _ring.visible:
		_ring.position = target.position
		_ring.size = target.size
		_ring.visible = true
		return
	_ring_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_ring, "position", target.position, 0.16)
	_ring_tween.tween_property(_ring, "size", target.size, 0.16)
	Sfx.play(&"move", 1.25)


func _style_ring() -> void:
	var s := Kit.box(Color(App.accent, 0.13), 16, Color(App.accent.lightened(0.25), 0.9), 2)
	Kit.shadowed(s, Color(App.accent, 0.3), 16, Vector2.ZERO)
	_ring.add_theme_stylebox_override("panel", s)


# --- Live previews ------------------------------------------------------------------

func _show_thumbs() -> void:
	if not Host.available:
		return
	var xf_view := get_viewport().get_final_transform()
	var dest := Shell.hwnd_of(self)
	for i in _cards.size():
		var card := _cards[i]
		if not bool(card.get_meta("live")):
			continue
		var slot: Control = card.get_meta("slot")
		var xf := xf_view * slot.get_global_transform_with_canvas()
		var span := xf.basis_xform(slot.size)
		var r := Rect2i(Vector2i(xf.origin.round()), Vector2i(span.round())).grow(-4)
		Host.thumb(int(_entries[i]["hwnd"]), r, Callable(), dest)
		_thumbs_on = true


func _clear_thumbs() -> void:
	if _thumbs_on:
		Host.thumb_clear()
		_thumbs_on = false
