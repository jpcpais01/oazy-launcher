class_name Switcher
extends Control
## Oazy's Alt+Tab. The screen sinks into a dim dusk and your open windows
## (Oazy's own and other apps') line up as a carousel of live previews: the
## selected one large in the middle on a pool of accent light, its neighbours
## smaller and fading towards the edges. Tab and Shift+Tab or the arrow keys
## glide between them, Delete closes one, Esc backs out and letting go of Alt
## switches. The mouse works too: hover, click, scroll, or click away.
##
## The companion catches the keys (see Host.switch_key), so this layer never
## needs focus. A quick tap switches straight to the last window without
## showing anything, like Windows does. Every card eases towards where it
## should be each frame, and the live previews (DWM thumbnails, drawn by
## Windows on top of the layer) are moved and faded along with their cards.

const SCRIM := preload("res://shaders/scrim.gdshader")

## How long Alt+Tab has to be held before the switcher shows.
const DELAY := 0.1
const MAX_WINDOWS := 40
const MAX_DOTS := 14
## How quickly cards settle (higher is snappier).
const SPEED := 15.0

var main: Node
var is_open := false
var selected := 0
var _entries: Array[Dictionary] = []
## One per entry: {node, frame, style, x, y, sc, al, hot, live, sent_rect, sent_op}.
var _cards: Array[Dictionary] = []
var _scrim: ColorRect
var _scrim_mat: ShaderMaterial
var _stage: Control
var _info: VBoxContainer
var _title: Label
var _sub: Label
var _dots: HBoxContainer
var _count: Label
var _shown := false
var _closing := false
var _fade := 0.0
var _serial := 0
var _base := Vector2(520, 325)
var _center := Vector2.ZERO
var _mouse_moved := false
var _info_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_scrim_mat = ShaderMaterial.new()
	_scrim_mat.shader = SCRIM
	_scrim = ColorRect.new()
	_scrim.color = Color.WHITE
	_scrim.material = _scrim_mat
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			match e.button_index:
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					cancel()
				MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
					step(1)
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
					step(-1)
	)
	add_child(_scrim)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	_info = Kit.vbox(6)
	_info.alignment = BoxContainer.ALIGNMENT_BEGIN
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)
	_title = Kit.label("", 28, 700, Color.WHITE, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.add_theme_constant_override("shadow_outline_size", 8)
	_info.add_child(_title)
	_sub = Kit.label("", 15, 500, App.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_sub)
	_info.add_child(Kit.spacer(0, 10))
	var dots_row := CenterContainer.new()
	dots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(dots_row)
	_dots = Kit.hbox(7)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots_row.add_child(_dots)
	_count = Kit.label("", 13, 600, App.TEXT_MUTE)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_count)


## The whole screen while it's showing: clicking anywhere else backs out.
func shell_shape() -> Variant:
	return null


func is_showing() -> bool:
	return visible and _shown


## One of the keys the companion passes on while Alt is held.
func handle_key(key: String) -> void:
	match key:
		"open", "open_back":
			open(key == "open_back")
		"next", "right", "down":
			step(1)
		"prev", "left", "up":
			step(-1)
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
	if _closing:
		_finish_close()
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


## Switches to the selected window and closes.
func commit() -> void:
	if not is_open:
		return
	var e: Dictionary = _entries[selected] if selected < _entries.size() else {}
	_close(true)
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
		_close(false)


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
	if selected < _cards.size():
		var c: Dictionary = _cards[selected]
		_cards.remove_at(selected)
		_retire(c)
	if _entries.is_empty():
		_close(false)
		return
	_select(mini(selected, _entries.size() - 1), true)


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
	return out.slice(0, MAX_WINDOWS)


# --- Showing and hiding ---------------------------------------------------------------

func _show() -> void:
	_shown = true
	_closing = false
	_mouse_moved = false
	_measure()
	for i in _entries.size():
		_cards.append(_make_card(i))
	_select(selected, false)
	# Cards bloom out from the middle, the far ones a beat later.
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var t := _target(i)
		c["x"] = t.x * 0.55
		c["y"] = 34.0
		c["sc"] = t.z * 0.78
		c["al"] = -0.14 * absf(i - selected)
	_fade = 0.0
	visible = true
	set_process(true)
	var surface := Shell.surface_of(self)
	if surface:
		surface.reveal()
	_layout(0.0)
	Sfx.play(&"open", 1.3)


func _close(picked: bool) -> void:
	is_open = false
	_serial += 1
	if not _shown:
		return
	_shown = false
	_closing = true
	if picked:
		Sfx.play(&"select", 1.15)


func _finish_close() -> void:
	_closing = false
	set_process(false)
	visible = false
	_clear_thumbs()
	for c in _cards:
		(c["node"] as Node).queue_free()
	_cards.clear()
	for n in _stage.get_children():
		n.queue_free()


func _retire(c: Dictionary) -> void:
	# A closed window's card shrinks away on its own.
	var node: Control = c["node"]
	if bool(c["live"]) and int(c["sent_op"]) > 0:
		Host.thumb(int(c["hwnd"]), Rect2i(0, 0, 1, 1), Callable(), Shell.hwnd_of(self), 0)
	var t := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	node.pivot_offset = node.size / 2.0
	t.tween_property(node, "scale", Vector2.ONE * 0.6, 0.25)
	t.tween_property(node, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(node.queue_free)


# --- Cards -------------------------------------------------------------------------------

func _measure() -> void:
	var vp := Shell.view_size()
	var w := clampf(vp.x * 0.3, 340.0, 620.0)
	w = minf(w, (vp.y * 0.5) / 0.625)
	_base = Vector2(w, w * 0.625).round()
	_center = Vector2(vp.x / 2.0, vp.y * 0.43)
	_scrim_mat.set_shader_parameter("rect_size", vp)
	_scrim_mat.set_shader_parameter("focus", _center)
	_scrim_mat.set_shader_parameter("glow_size", _base * 1.25)
	_scrim_mat.set_shader_parameter("accent", App.accent)
	_info.size = Vector2(minf(vp.x - 80.0, _base.x * 1.6), 0)
	_info.position = Vector2((vp.x - _info.size.x) / 2.0, _center.y + _base.y / 2.0 + 34.0)


func _make_card(i: int) -> Dictionary:
	var e: Dictionary = _entries[i]
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(node)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := Kit.box(Color(0.07, 0.09, 0.11, 0.97), 22, Color(1, 1, 1, 0.1), 1)
	Kit.shadowed(style, Color(0, 0, 0, 0.4), 30, Vector2(0, 14))
	frame.add_theme_stylebox_override("panel", style)
	node.add_child(frame)
	var live: bool = Host.available and e.get("shell") == null and not bool(e["min"])
	if not live:
		_fill_icon(node, e)
	var c := {"node": node, "frame": frame, "style": style, "x": 0.0, "y": 0.0, "sc": 1.0, "al": 0.0, "hot": 0.0,
		"live": live, "hwnd": int(e.get("hwnd", 0)), "sent_rect": Rect2i(), "sent_op": -1}
	node.mouse_entered.connect(func() -> void:
		var at := _cards.find(c)
		if is_open and _mouse_moved and at >= 0 and at != selected:
			_select(at)
	)
	node.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		var at := _cards.find(c)
		if at < 0:
			return
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				selected = at
				commit()
			MOUSE_BUTTON_MIDDLE:
				selected = at
				close_selected()
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				step(1)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				step(-1)
	)
	return c


## Oazy's own windows and minimised apps have no live picture: the app's icon
## on a soft wash of its colour instead.
func _fill_icon(node: Control, e: Dictionary) -> void:
	var it: Dictionary = e["item"]
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(center)
	var col := Kit.vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(1, 1) * roundf(_base.y * 0.3)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	col.add_child(ic)
	var note := "Minimised" if bool(e["min"]) else ("Oazy" if e.get("shell") != null else "")
	if note != "":
		var l := Kit.label(note, 14, 600, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)


## Where card i belongs: x offset from the middle, y, and scale in z.
func _target(i: int) -> Vector3:
	var d := float(i - selected)
	var a := absf(d)
	var near := _base.x * 0.5 + _base.x * 0.31 + 36.0
	var x := a * near if a <= 1.0 else near + (a - 1.0) * (_base.x * 0.52 + 26.0)
	var sc := lerpf(1.0, 0.62, a) if a <= 1.0 else maxf(0.42, 0.62 - (a - 1.0) * 0.1)
	var y := 0.0 if a < 0.5 else _base.y * (1.0 - sc) * 0.08
	return Vector3(signf(d) * x, y, sc)


func _target_alpha(i: int) -> float:
	var a := absf(i - selected)
	if a <= 2.0:
		return 1.0
	return clampf(1.0 - (a - 2.0) * 0.9, 0.0, 1.0)


func _select(i: int, animate: bool = true) -> void:
	var changed := i != selected
	selected = clampi(i, 0, maxi(_entries.size() - 1, 0))
	if _cards.is_empty():
		return
	# Nearest cards draw on top.
	var order: Array = range(_cards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absi(a - selected) > absi(b - selected))
	for k in order.size():
		_stage.move_child(_cards[order[k]]["node"], k)
	_sync_info(animate and changed)
	if animate and changed:
		Sfx.play(&"move", 1.3)


func _sync_info(animate: bool) -> void:
	if selected >= _entries.size():
		return
	var e: Dictionary = _entries[selected]
	var name := str(e["item"].get("name", ""))
	var title := str(e["title"])
	if title == "":
		title = name
	_title.text = title
	_sub.text = name if name != "" and name != title else ""
	_sub.visible = _sub.text != ""
	var n := _entries.size()
	var use_dots := n > 1 and n <= MAX_DOTS
	_dots.get_parent().visible = use_dots
	_count.visible = n > MAX_DOTS
	_count.text = "%d of %d" % [selected + 1, n]
	if use_dots:
		while _dots.get_child_count() < n:
			var dot := Panel.new()
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.add_theme_stylebox_override("panel", Kit.box(Color.WHITE, 99))
			_dots.add_child(dot)
		while _dots.get_child_count() > n:
			var gone := _dots.get_child(_dots.get_child_count() - 1)
			_dots.remove_child(gone)
			gone.queue_free()
		for k in n:
			var dot: Panel = _dots.get_child(k)
			var on := k == selected
			var want := Vector2(22 if on else 6, 6)
			var col := App.accent.lightened(0.2) if on else Color(1, 1, 1, 0.28)
			if animate:
				var t := dot.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
				t.tween_property(dot, "custom_minimum_size", want, 0.22)
				t.tween_property(dot, "self_modulate", col, 0.22)
			else:
				dot.custom_minimum_size = want
				dot.self_modulate = col
	if animate:
		if _info_tween and _info_tween.is_valid():
			_info_tween.kill()
		_title.modulate.a = 0.35
		_sub.modulate.a = 0.35
		_info_tween = create_tween().set_parallel(true)
		_info_tween.tween_property(_title, "modulate:a", 1.0, 0.18)
		_info_tween.tween_property(_sub, "modulate:a", 1.0, 0.22)


# --- Motion ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _shown and event is InputEventMouseMotion and event.relative.length() > 1.5:
		_mouse_moved = true


func _process(delta: float) -> void:
	_layout(delta)


func _layout(delta: float) -> void:
	var k := 1.0 - exp(-delta * SPEED)
	var ka := 1.0 - exp(-delta * SPEED * 0.9)
	_fade = lerpf(_fade, 0.0 if _closing else 1.0, 1.0 - exp(-delta * (22.0 if _closing else 14.0)))
	_scrim_mat.set_shader_parameter("amount", _fade)
	_info.modulate.a = _fade
	_info.position.y = _center.y + _base.y / 2.0 + 34.0 + (1.0 - _fade) * 14.0
	var settled := true
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var t := _target(i)
		var ta := _target_alpha(i)
		var hot := 1.0 if i == selected else 0.0
		if _closing:
			t.z *= 1.05 if i == selected else 0.9
			ta = 0.0
		c["x"] = lerpf(c["x"], t.x, k)
		c["y"] = lerpf(c["y"], t.y, k)
		c["sc"] = lerpf(c["sc"], t.z, k)
		c["al"] = lerpf(c["al"], ta, ka)
		c["hot"] = lerpf(c["hot"], hot, k)
		if absf(c["x"] - t.x) > 0.3 or absf(c["sc"] - t.z) > 0.002 or absf(c["al"] - ta) > 0.004 or absf(c["hot"] - hot) > 0.01:
			settled = false
		_place(c)
	if _closing and _fade < 0.02 and settled:
		_finish_close()


func _place(c: Dictionary) -> void:
	var node: Control = c["node"]
	var sc: float = c["sc"]
	var al := clampf(c["al"], 0.0, 1.0)
	var hot: float = c["hot"]
	var sz := (_base * sc).round()
	node.size = sz
	node.position = (_center + Vector2(c["x"], c["y"]) - sz / 2.0).round()
	# Cards stay solid; the ones off to the side sink into the dusk instead.
	var v := lerpf(0.62, 1.0, hot)
	node.modulate = Color(v, v, v, al)
	node.visible = al > 0.01
	var s: StyleBoxFlat = c["style"]
	s.set_corner_radius_all(int(roundf(lerpf(16.0, 26.0, sc))))
	s.border_color = Color(1, 1, 1, 0.1).lerp(Color(App.accent.lightened(0.3), 0.95), hot)
	s.set_border_width_all(1 + int(roundf(hot)))
	s.shadow_color = Color(0, 0.01, 0.02, 0.45).lerp(Color(App.accent, 0.42), hot)
	s.shadow_size = int(lerpf(26.0, 46.0, hot) * sc)
	s.shadow_offset = Vector2(0, lerpf(14.0, 0.0, hot) * sc)
	s.bg_color = Color(0.07, 0.09, 0.11, 0.97).lerp(Color(App.accent.darkened(0.62), 0.97), hot * 0.55)
	if bool(c["live"]):
		_place_thumb(c, al * lerpf(0.62, 1.0, hot))


func _place_thumb(c: Dictionary, opacity: float) -> void:
	if not Host.available:
		return
	var node: Control = c["node"]
	var inset := roundf(9.0 * float(c["sc"]))
	var xf := get_viewport().get_final_transform() * node.get_global_transform_with_canvas()
	var span := xf.basis_xform(node.size - Vector2(inset, inset) * 2.0)
	var origin := xf * Vector2(inset, inset)
	var r := Rect2i(Vector2i(origin.round()), Vector2i(span.round()).max(Vector2i.ONE))
	var op := int(roundf(clampf(opacity, 0.0, 1.0) * 255.0))
	if op < 4:
		op = 0
	if r == c["sent_rect"] and op == int(c["sent_op"]):
		return
	if op == 0 and int(c["sent_op"]) <= 0:
		return
	c["sent_rect"] = r
	c["sent_op"] = op
	Host.thumb(int(c["hwnd"]), r, Callable(), Shell.hwnd_of(self), op)


func _clear_thumbs() -> void:
	for c in _cards:
		c["sent_op"] = -1
	if Host.available:
		Host.thumb_clear()
