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
## should be each frame. Each card shows a picture of its window, taken by the
## companion (PrintWindow) when the switcher opens; the selected one keeps
## refreshing a few times a second, and minimised windows keep their last.

const SCRIM := preload("res://shaders/scrim.gdshader")
const CARD := preload("res://shaders/switcher_card.gdshader")
const ROUNDED := preload("res://shaders/rounded_tex.gdshader")
## How often the selected window's picture refreshes, in seconds.
const REFRESH := 0.35
## Card size n places from the selected one.
const SCALES := [1.0, 0.66, 0.52, 0.44]
const GAP := 28.0
const PAD := 12.0
const HEAD := 50.0
## Room around a card's pane for its glow.
const GLOW_PAD := 70.0

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
	_info.add_child(Kit.spacer(0, 6))
	var hint := Kit.label("Tab to move   ·   Delete to close   ·   Esc to cancel", 13, 500, Color(App.TEXT_MUTE, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(hint)


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
	# Full frame rate from the first moment, even over another app.
	App.switcher_open = true
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
		App.switcher_open = false
		return
	_shown = false
	_closing = true
	if picked:
		Sfx.play(&"select", 1.15)


func _finish_close() -> void:
	_closing = false
	set_process(false)
	visible = false
	if not is_open:
		App.switcher_open = false
	for c in _cards:
		(c["node"] as Node).queue_free()
	_cards.clear()
	for n in _stage.get_children():
		n.queue_free()


func _retire(c: Dictionary) -> void:
	# A closed window's card shrinks away on its own.
	var node: Control = c["node"]
	var t := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	node.pivot_offset = node.size / 2.0
	t.tween_property(node, "scale", Vector2.ONE * 0.6, 0.25)
	t.tween_property(node, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(node.queue_free)


# --- Cards -------------------------------------------------------------------------------

func _measure() -> void:
	var vp := Shell.view_size()
	var w := clampf(vp.x * 0.3, 340.0, 620.0)
	w = minf(w, (vp.y * 0.52) / 0.66)
	# The two cards either side of the selected one always fit on screen.
	var k := (SCALES[0] + SCALES[1]) / 2.0 + (SCALES[1] + SCALES[2]) / 2.0 + SCALES[2] / 2.0
	w = minf(w, (vp.x / 2.0 - 24.0 - GAP * 2.0) / k)
	_base = Vector2(w, w * 0.66).round()
	_center = Vector2(vp.x / 2.0, vp.y * 0.42)
	_scrim_mat.set_shader_parameter("rect_size", vp)
	_scrim_mat.set_shader_parameter("focus", _center)
	_scrim_mat.set_shader_parameter("glow_size", _base * 1.3)
	_scrim_mat.set_shader_parameter("accent", App.accent)
	_info.size = Vector2(minf(vp.x - 80.0, _base.x * 1.6), 0)
	_info.position = Vector2((vp.x - _info.size.x) / 2.0, _center.y + _base.y / 2.0 + 34.0)


func _slot() -> Rect2:
	return Rect2(PAD, HEAD, _base.x - PAD * 2.0, _base.y - HEAD - PAD)


func _make_card(i: int) -> Dictionary:
	var e: Dictionary = _entries[i]
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.size = _base
	_stage.add_child(node)
	var live: bool = Host.available and e.get("shell") == null and not bool(e["min"])
	var it: Dictionary = e["item"]
	var tint := Catalog.icon_color(str(it.get("icon_key", "")))
	var mat := ShaderMaterial.new()
	mat.shader = CARD
	var pane := ColorRect.new()
	pane.color = Color.WHITE
	pane.material = mat
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position = -Vector2(GLOW_PAD, GLOW_PAD)
	pane.size = _base + Vector2(GLOW_PAD, GLOW_PAD) * 2.0
	mat.set_shader_parameter("size", _base)
	mat.set_shader_parameter("pad", GLOW_PAD)
	mat.set_shader_parameter("radius", 24.0)
	mat.set_shader_parameter("hole_radius", 12.0)
	node.add_child(pane)

	# Header: the app, the window's title and a close button.
	var icon := AppIcon.new()
	icon.size = Vector2(24, 24)
	icon.position = Vector2(PAD + 4.0, (HEAD - 24.0) / 2.0 + 1.0)
	icon.set_item(it)
	node.add_child(icon)
	var title := str(e["title"])
	if title == "":
		title = str(it.get("name", ""))
	var t := Kit.label(title, 15, 600, App.TEXT)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.position = Vector2(PAD + 38.0, 1.0)
	t.size = Vector2(_base.x - PAD * 2.0 - 38.0 - 40.0, HEAD)
	node.add_child(t)
	var x := FxButton.icon_only("close", "Close window", 14, 30)
	x.focus_mode = Control.FOCUS_NONE
	x.hover_scale = 1.0
	x.add_theme_stylebox_override("hover", Kit.box(Color(1.0, 0.36, 0.42, 0.95), 999))
	x.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.08), 999))
	x.position = Vector2(_base.x - PAD - 30.0, (HEAD - 30.0) / 2.0 + 1.0)
	x.size = Vector2(30, 30)
	node.add_child(x)

	var icon_box := _fill_icon(node, e)
	var shot := TextureRect.new()
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_SCALE
	var shot_mat := ShaderMaterial.new()
	shot_mat.shader = ROUNDED
	shot.material = shot_mat
	shot.visible = false
	node.add_child(shot)
	var c := {"node": node, "mat": mat, "x_btn": x, "x": 0.0, "y": 0.0, "sc": 1.0, "al": 0.0, "hot": 0.0,
		"hover": 0.0, "over": false, "live": live, "hwnd": int(e.get("hwnd", 0)), "tint": tint,
		"shot": shot, "icon_box": icon_box, "busy": false, "since": 0.0, "failed": false}
	var cached: Texture2D = Host.captures.get(c["hwnd"]) if e.get("shell") == null else null
	if cached:
		_set_shot(c, cached, false)
	x.pressed.connect(func() -> void:
		var at := _cards.find(c)
		if is_open and at >= 0:
			selected = at
			close_selected()
	)
	node.mouse_entered.connect(func() -> void:
		c["over"] = true
		var at := _cards.find(c)
		if is_open and _mouse_moved and at >= 0 and at != selected:
			_select(at)
	)
	node.mouse_exited.connect(func() -> void:
		if not node.get_global_rect().has_point(node.get_global_mouse_position()):
			c["over"] = false
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


## Oazy's own windows and minimised apps have no live picture: the app's icon,
## large, on a wash of its own colour.
func _fill_icon(node: Control, e: Dictionary) -> Control:
	var it: Dictionary = e["item"]
	var slot := _slot()
	var wash := Panel.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.position = slot.position
	wash.size = slot.size
	var tint := Catalog.icon_color(str(it.get("icon_key", "")))
	if tint.a <= 0.0:
		tint = App.accent
	var box := Kit.box(Color(tint.darkened(0.55), 0.55), 14, Color(tint.lightened(0.2), 0.12), 1)
	wash.add_theme_stylebox_override("panel", box)
	node.add_child(wash)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.position = slot.position
	center.size = slot.size
	node.add_child(center)
	var col := Kit.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(1, 1) * roundf(slot.size.y * 0.42)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	col.add_child(ic)
	var note := "Minimised" if bool(e["min"]) else ("Oazy" if e.get("shell") != null else "")
	if note != "":
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pill.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.32), 999, Color(1, 1, 1, 0.08), 1, 12, 4))
		var l := Kit.label(note, 13, 600, App.TEXT_DIM)
		pill.add_child(l)
		col.add_child(pill)
	return center


## How large a card is n places away from the selected one.
func _scale_at(n: int) -> float:
	return SCALES[mini(n, SCALES.size() - 1)]


## How far a card's centre sits from the middle, n places away: each card
## clears its neighbour by GAP, however large or small both are.
func _offset_at(n: int) -> float:
	var x := 0.0
	for k in range(1, n + 1):
		x += _base.x * (_scale_at(k - 1) + _scale_at(k)) / 2.0 + GAP
	return x


## Where card i belongs: x offset from the middle, y, and scale in z.
func _target(i: int) -> Vector3:
	var d := i - selected
	var n := absi(d)
	var sc := _scale_at(n)
	return Vector3(signf(d) * _offset_at(n), _base.y * (1.0 - sc) * 0.06, sc)


func _target_alpha(i: int) -> float:
	var n := absi(i - selected)
	return 1.0 if n <= 2 else 0.0


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
		c["hover"] = lerpf(c["hover"], 1.0 if bool(c["over"]) else 0.0, k)
		c["since"] = float(c["since"]) + delta
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
	node.scale = Vector2(sc, sc)
	node.position = (_center + Vector2(c["x"], c["y"]) - _base * sc / 2.0).round()
	node.visible = al > 0.01
	# Cards stay solid; the ones off to the side sink into the dusk instead.
	var v := lerpf(0.6, 1.0, hot)
	node.modulate = Color(v, v, v, al)
	var x: Control = c["x_btn"]
	x.modulate.a = maxf(hot, float(c["hover"]))
	x.mouse_filter = Control.MOUSE_FILTER_STOP if x.modulate.a > 0.5 else Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = c["mat"]
	var tint: Color = c["tint"]
	var fill := Color(0.075, 0.09, 0.11, 0.98)
	if tint.a > 0.0:
		fill = fill.lerp(Color(tint.darkened(0.75), 0.98), 0.35)
	mat.set_shader_parameter("fill", fill.lerp(Color(App.accent.darkened(0.66), 0.98), hot * 0.6))
	mat.set_shader_parameter("rim", Color(1, 1, 1, 0.1).lerp(Color(App.accent.lightened(0.35), 0.95), hot))
	mat.set_shader_parameter("rim_w", lerpf(1.0, 2.0, hot) / sc)
	mat.set_shader_parameter("glow", Color(0, 0.01, 0.02, 0.5).lerp(Color(App.accent, 0.5), hot))
	mat.set_shader_parameter("glow_size", lerpf(26.0, 44.0, hot))
	mat.set_shader_parameter("glow_drop", lerpf(14.0, 0.0, hot))
	if bool(c["live"]) and not _closing and _shown:
		# Everyone gets a picture once; the selected one keeps it fresh.
		var shot: TextureRect = c["shot"]
		var due := float(c["since"]) >= (REFRESH * 4.0 if bool(c["failed"]) else REFRESH)
		if (not shot.visible and not bool(c["failed"])) or (hot > 0.5 and due):
			_request_shot(c)


## Asks the companion for a fresh picture of a card's window.
func _request_shot(c: Dictionary) -> void:
	if not bool(c["live"]) or bool(c["busy"]) or not Host.available:
		return
	c["busy"] = true
	c["since"] = 0.0
	var px := Vector2i((_slot().size * Shell.scale * 1.1).round())
	Host.capture(int(c["hwnd"]), px, func(tex: ImageTexture) -> void:
		c["busy"] = false
		c["failed"] = tex == null
		if tex and _cards.has(c):
			_set_shot(c, tex, true)
	)


## Shows a window's picture, fitted to the card, and fades the icon away.
func _set_shot(c: Dictionary, tex: Texture2D, animate: bool) -> void:
	var shot: TextureRect = c["shot"]
	var slot := _slot()
	var src := Vector2(tex.get_size())
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var k := minf(slot.size.x / src.x, slot.size.y / src.y)
	var fit := (src * k).floor()
	shot.position = slot.position + ((slot.size - fit) / 2.0).floor()
	shot.size = fit
	(shot.material as ShaderMaterial).set_shader_parameter("size", fit)
	var first := not shot.visible
	shot.texture = tex
	shot.visible = true
	var icon_box: Control = c["icon_box"]
	if first and animate:
		shot.modulate.a = 0.0
		var t := shot.create_tween().set_parallel(true)
		t.tween_property(shot, "modulate:a", 1.0, 0.18)
		t.tween_property(icon_box, "modulate:a", 0.0, 0.18)
	else:
		icon_box.modulate.a = 0.0
