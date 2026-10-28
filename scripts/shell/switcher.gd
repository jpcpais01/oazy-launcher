class_name Switcher
extends Control
## Oazy's Alt+Tab. The screen sinks into a quiet dusk and your open windows
## (Oazy's own and other apps') stand in a stack, each card turned a little
## and leaning back into the screen, the chosen one at the front and the rest
## climbing away behind it, with the window's name underneath. Tab and
## Shift+Tab or the arrow keys cycle the stack: the front card steps off and
## rejoins at the back. Delete closes one, Esc backs out and letting go of Alt
## switches. The mouse works too: click a card, scroll, or click away.
##
## The companion catches the keys (see Host.switch_key), so this layer never
## needs focus. A quick tap switches straight to the last window without
## showing anything, like Windows does. Every card eases towards its place in
## the stack each frame and is drawn in perspective by flip_card.gdshader.
## Each card shows a picture of its window, taken by the companion
## (PrintWindow) when the switcher opens; the front one keeps refreshing a few
## times a second. Minimised windows show the last picture kept of them, and
## Oazy's own windows a picture of themselves.

const SCRIM := preload("res://shaders/scrim.gdshader")
const FLIP := preload("res://shaders/flip_card.gdshader")
## How often the front window's picture refreshes, in seconds.
const REFRESH := 0.35
const RADIUS := 14.0
## How many cards stand behind the front one before the stack fades out.
const DEPTH := 6
## How far each card is turned about its upright axis (radians): the left
## edge nearer, the right edge leaning away.
const TURN := 0.4
## Room around a card, in its own plane, for its shadow.
const SHADOW_PAD := 56.0
const TITLE_ICON := 26.0

## How long Alt+Tab has to be held before the switcher shows.
const DELAY := 0.1
const MAX_WINDOWS := 40
const MAX_DOTS := 14
## How quickly cards settle (higher is snappier).
const SPEED := 13.0

var main: Node
var is_open := false
var selected := 0
var _entries: Array[Dictionary] = []
## One per entry: {node, mat, slot, goal, exit, hot, hover, size, hinv, live, ...}.
var _cards: Array[Dictionary] = []
## Card indices in drawing order, back to front.
var _order: Array = []
var _scrim: ColorRect
var _scrim_mat: ShaderMaterial
var _stage: Control
var _info: VBoxContainer
var _title_row: HBoxContainer
var _title_icon: AppIcon
var _title: Label
var _sub: Label
var _dots: HBoxContainer
var _count: Label
var _shown := false
var _closing := false
var _fade := 0.0
var _serial := 0
## The largest a card can be (at the front), and the stack's geometry: the
## screen point the camera looks along, its focal length, where the front
## card's centre is (from that point, in pixels at the front) and how far
## each card behind it moves.
var _box := Vector2(640, 400)
var _eye := Vector2.ZERO
var _focal := 1600.0
var _front := Vector3.ZERO
var _step := Vector3.ZERO
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
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	_info = Kit.vbox(4)
	_info.alignment = BoxContainer.ALIGNMENT_BEGIN
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)
	var title_center := CenterContainer.new()
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(title_center)
	_title_row = Kit.hbox(12)
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.add_child(_title_row)
	_title_icon = AppIcon.new()
	_title_icon.custom_minimum_size = Vector2(TITLE_ICON, TITLE_ICON)
	_title_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_row.add_child(_title_icon)
	_title = Kit.label("", 21, 600, App.TEXT)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_row.add_child(_title)
	_sub = Kit.label("", 14, 500, App.TEXT_MUTE)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_sub)
	_info.add_child(Kit.spacer(0, 12))
	var dots_row := CenterContainer.new()
	dots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(dots_row)
	_dots = Kit.hbox(6)
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
	if main and main.get("assistant") != null:
		var a: AssistantPanel = main.assistant
		if e.has("assistant"):
			a.open()
			_lift.call_deferred(Shell.hwnd_of(a))
			return
		# Going somewhere else leaves Claude, even if Windows never told its layer.
		a.close()
	var win: ShellWindow = e.get("shell")
	if win != null:
		if is_instance_valid(win) and main:
			main.focus_shell_window(win)
			# Over another app Godot can't take the foreground itself, and its
			# focus state can lag, so the companion always lifts the layer.
			_lift.call_deferred(Shell.hwnd_of(win))
	else:
		Host.focus(int(e["hwnd"]))


func _lift(hwnd: int) -> void:
	if hwnd != 0:
		Host.focus(hwnd)


func cancel() -> void:
	if is_open:
		_close(false)


func close_selected() -> void:
	if not is_open or selected >= _entries.size():
		return
	var e: Dictionary = _entries[selected]
	var win: ShellWindow = e.get("shell")
	if e.has("assistant"):
		# Closing Claude's card puts the conversation away (it stays in past chats).
		main.assistant.close()
		main.assistant.new_chat()
	elif win != null:
		if is_instance_valid(win):
			win.close()
	else:
		Host.close_window(int(e["hwnd"]))
	_entries.remove_at(selected)
	if selected < _cards.size():
		var c: Dictionary = _cards[selected]
		_cards.remove_at(selected)
		_order.clear()
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
		# One read of Oazy's windows as they are on screen, cut into a picture each.
		var frame: Image = null
		for win in list:
			if not win._closing and not win.minimized and win.is_visible_in_tree() and DisplayServer.get_name() != "headless":
				frame = win.get_viewport().get_texture().get_image()
				break
		for win in list:
			if win._closing:
				continue
			var e := {"shell": win, "title": win.title, "item": Catalog.item(win.app_ref), "min": win.minimized}
			var pic := win.snapshot(frame)
			if pic:
				e["pic"] = pic
			if win.active:
				own.push_front(e)
			else:
				own.append(e)
	var at := 0 if (main and main.windows_in_front()) or Host.self_foreground else mini(1, out.size())
	for i in own.size():
		out.insert(at + i, own[i])
	# Claude's popup, while there's a conversation: first while it's open, next
	# when you've only just left it, else after Oazy's own windows.
	if main and main.get("assistant") != null and (main.assistant as AssistantPanel).in_switcher():
		var a: AssistantPanel = main.assistant
		var e := {"assistant": true, "title": a.title() if a.title() != "" else "Claude", "item": Catalog.item(ClaudeApp.REF), "min": false, "pic": a.snapshot()}
		var pos := mini(at + own.size(), out.size())
		if a.is_open:
			pos = 0
		elif a.left_to != 0 and a.left_to == Host.foreground:
			pos = mini(1, out.size())
		out.insert(pos, e)
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
	# The stack settles in from a little further back.
	for c in _cards:
		c["slot"] = float(c["goal"]) + 0.9
	_fade = 0.0
	visible = true
	set_process(true)
	var surface := Shell.surface_of(self)
	if surface:
		surface.reveal()
		# Above everything, a fullscreen app that keeps itself on top included.
		Host.raise_window(surface.hwnd())
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
	_order.clear()
	for n in _stage.get_children():
		n.queue_free()


func _retire(c: Dictionary) -> void:
	# A closed window's card fades away where it is.
	var node: Control = c["node"]
	var t := node.create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 0.0, 0.2)
	t.tween_callback(node.queue_free)


# --- Cards -------------------------------------------------------------------------------

func _measure() -> void:
	var vp := Shell.view_size()
	var w := clampf(vp.x * 0.4, 380.0, 900.0)
	w = minf(w, vp.y * 0.48 / 0.625)
	_box = Vector2(w, w * 0.625).round()
	_eye = vp * Vector2(0.5, 0.45)
	_focal = vp.y * 1.6
	# The front card sits right of centre and a little low; the rest of the
	# stack climbs away from it up and to the left.
	_front = Vector3(w * 0.32, _box.y * 0.1, 0.0)
	_step = Vector3(-w * 0.3, -_box.y * 0.2, w * 0.34)
	var info_w := minf(vp.x - 80.0, _box.x * 1.2)
	_info.size = Vector2(info_w, 0)
	_info.position = Vector2(clampf(_eye.x + _front.x - info_w / 2.0, 40.0, vp.x - 40.0 - info_w), _info_y())


func _info_y() -> float:
	return _eye.y + _front.y + _box.y / 2.0 + 30.0


func _make_card(i: int) -> Dictionary:
	var e: Dictionary = _entries[i]
	var node := ColorRect.new()
	node.color = Color.WHITE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = FLIP
	mat.set_shader_parameter("radius", RADIUS)
	mat.set_shader_parameter("fill", Color(0.075, 0.082, 0.095))
	node.material = mat
	_stage.add_child(node)
	var live: bool = Host.available and e.get("shell") == null and not e.has("assistant") and not bool(e["min"])
	var c := {"node": node, "mat": mat, "slot": 0.0, "goal": 0, "exit": false, "hot": 0.0, "hover": 0.0,
		"over": false, "size": _box, "hinv": Basis.IDENTITY, "live": live, "hwnd": int(e.get("hwnd", 0)),
		"has_pic": false, "glyph": null, "busy": false, "since": 0.0, "failed": false}
	var cached: Texture2D = e.get("pic") if e.has("pic") else (Host.picture_of(c["hwnd"]) if e.get("shell") == null else null)
	if cached:
		_set_pic(c, cached)
	else:
		_make_glyph(c, e)
	return c


## Windows without a picture (yet): the app's icon, large, on the card's own
## quiet colour. Drawn once into a little viewport the card shader samples.
func _make_glyph(c: Dictionary, e: Dictionary) -> void:
	var units := (_box * Vector2(0.6, 0.6)).round()
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i((units * maxf(Shell.scale, 1.0)).round())
	vp.size_2d_override = Vector2i(units)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(c["node"] as Node).add_child(vp)
	var center := CenterContainer.new()
	center.size = units
	vp.add_child(center)
	var col := Kit.vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(1, 1) * roundf(_box.y * 0.3)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(e["item"])
	col.add_child(ic)
	if bool(e["min"]):
		var l := Kit.label("Minimised", 15, 500, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	c["glyph"] = vp
	var mat: ShaderMaterial = c["mat"]
	mat.set_shader_parameter("glyph", vp.get_texture())
	mat.set_shader_parameter("glyph_size", units)
	mat.set_shader_parameter("has_glyph", 1.0)


## Where card i belongs in the stack: 0 at the front, then each one behind.
func _goal(i: int) -> int:
	return posmod(i - selected, maxi(_entries.size(), 1))


func _select(i: int, animate: bool = true) -> void:
	var changed := i != selected
	selected = clampi(i, 0, maxi(_entries.size() - 1, 0))
	var n := _cards.size()
	for k in n:
		var c: Dictionary = _cards[k]
		var g := _goal(k)
		var cur: float = c["slot"]
		c["goal"] = g
		if not animate:
			c["slot"] = float(g)
			c["exit"] = false
		elif n > 2 and g - cur > n / 2.0:
			# The front card steps off towards you, then rejoins at the back.
			c["exit"] = true
		elif n > 2 and cur - g > n / 2.0:
			# Going back: the last card comes round to the front.
			c["exit"] = false
			c["slot"] = -1.0
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
	var font := _title.get_theme_font("font")
	var fsize := _title.get_theme_font_size("font_size")
	var room := _info.size.x - TITLE_ICON - 12.0
	_title.custom_minimum_size.x = minf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 4.0, room) if font else room
	_title_icon.set_item(e["item"])
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
			var want := Vector2(16 if on else 5, 5)
			var col := Color(1, 1, 1, 0.85) if on else Color(1, 1, 1, 0.22)
			if animate:
				var t := dot.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				t.tween_property(dot, "custom_minimum_size", want, 0.2)
				t.tween_property(dot, "self_modulate", col, 0.2)
			else:
				dot.custom_minimum_size = want
				dot.self_modulate = col
	if animate:
		if _info_tween and _info_tween.is_valid():
			_info_tween.kill()
		_title_row.modulate.a = 0.4
		_sub.modulate.a = 0.4
		_info_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_info_tween.tween_property(_title_row, "modulate:a", 1.0, 0.16)
		_info_tween.tween_property(_sub, "modulate:a", 1.0, 0.2)


# --- Mouse -------------------------------------------------------------------------------

func _on_scrim_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var at := _card_at(_stage.get_local_mouse_position())
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if at >= 0:
				selected = at
				commit()
			else:
				cancel()
		MOUSE_BUTTON_RIGHT:
			cancel()
		MOUSE_BUTTON_MIDDLE:
			if at >= 0:
				selected = at
				close_selected()
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			step(1)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			step(-1)


## The card under `p` (stage pixels), nearest first; -1 if none.
func _card_at(p: Vector2) -> int:
	var best := -1
	var best_slot := INF
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		if not (c["node"] as CanvasItem).visible or (c["node"] as CanvasItem).modulate.a < 0.3:
			continue
		var q: Vector3 = (c["hinv"] as Basis) * Vector3(p.x, p.y, 1.0)
		if q.z <= 0.0:
			continue
		var local := Vector2(q.x, q.y) / q.z
		if Rect2(Vector2.ZERO, c["size"]).has_point(local) and float(c["slot"]) < best_slot:
			best_slot = c["slot"]
			best = i
	return best


# --- Motion ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _shown and event is InputEventMouseMotion and event.relative.length() > 1.5:
		_mouse_moved = true


func _process(delta: float) -> void:
	_layout(delta)


func _layout(delta: float) -> void:
	var k := 1.0 - exp(-delta * SPEED)
	_fade = lerpf(_fade, 0.0 if _closing else 1.0, 1.0 - exp(-delta * (22.0 if _closing else 14.0)))
	_scrim_mat.set_shader_parameter("amount", _fade)
	_info.modulate.a = _fade
	_info.position.y = _info_y() + (1.0 - _fade) * 8.0
	var over := _card_at(_stage.get_local_mouse_position()) if _mouse_moved and not _closing else -1
	var settled := true
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var goal := float(c["goal"])
		if bool(c["exit"]):
			goal = -1.0
		if _closing and i == selected:
			# The window you picked comes forward to meet you as it all fades.
			goal = -0.35
		c["slot"] = lerpf(c["slot"], goal, k)
		if bool(c["exit"]) and float(c["slot"]) < -0.7:
			c["exit"] = false
			c["slot"] = maxf(float(c["goal"]) + 1.0, DEPTH + 0.6)
		var hot := 1.0 if i == selected else 0.0
		c["hot"] = lerpf(c["hot"], hot, k)
		c["hover"] = lerpf(c["hover"], 1.0 if i == over else 0.0, k)
		c["since"] = float(c["since"]) + delta
		if absf(float(c["slot"]) - goal) > 0.004 or bool(c["exit"]):
			settled = false
		_place(c)
	_sort()
	if _closing and _fade < 0.02:
		_finish_close()


## Furthest cards draw first.
func _sort() -> void:
	var order: Array = range(_cards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(_cards[a]["slot"]) > float(_cards[b]["slot"]))
	if order == _order:
		return
	_order = order
	for k in order.size():
		_stage.move_child(_cards[order[k]]["node"], k)


## Where a point of a card (its own pixels, from the top-left) lands on
## screen: the card leans TURN about its upright axis and sits `slot` steps
## back in the stack, seen through a camera `_focal` away.
func _homography(slot: float, sz: Vector2) -> Basis:
	var c := _front + _step * slot
	var a := Vector3(cos(TURN), 0.0, sin(TURN))
	var b := Vector3(0.0, 1.0, 0.0)
	var o := c - a * sz.x / 2.0 - b * sz.y / 2.0
	# Rows of the 3x3 map (x, y, 1) -> homogeneous screen point.
	var wr := Vector3(a.z, b.z, o.z + _focal)
	var xr := Vector3(a.x, b.x, o.x) * _focal + wr * _eye.x
	var yr := Vector3(a.y, b.y, o.y) * _focal + wr * _eye.y
	return Basis(Vector3(xr.x, yr.x, wr.x), Vector3(xr.y, yr.y, wr.y), Vector3(xr.z, yr.z, wr.z))


func _place(c: Dictionary) -> void:
	var node: ColorRect = c["node"]
	var slot: float = c["slot"]
	var al := clampf(1.0 + slot, 0.0, 1.0) * clampf(DEPTH + 0.5 - slot, 0.0, 1.0) * _fade
	node.visible = al > 0.01
	if not node.visible:
		return
	node.modulate.a = al
	var sz: Vector2 = c["size"]
	var h := _homography(slot, sz)
	# The node covers the card and its shadow, as they land on screen.
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in [Vector2(-SHADOW_PAD, -SHADOW_PAD), Vector2(sz.x + SHADOW_PAD, -SHADOW_PAD),
			Vector2(-SHADOW_PAD, sz.y + SHADOW_PAD * 1.4), Vector2(sz.x + SHADOW_PAD, sz.y + SHADOW_PAD * 1.4)]:
		var q := h * Vector3(p.x, p.y, 1.0)
		var s := Vector2(q.x, q.y) / maxf(q.z, 0.001)
		lo = lo.min(s)
		hi = hi.max(s)
	lo = lo.floor()
	hi = hi.ceil()
	node.position = lo
	node.size = hi - lo
	var hinv := h.inverse()
	c["hinv"] = hinv
	var mat: ShaderMaterial = c["mat"]
	mat.set_shader_parameter("hinv", hinv)
	mat.set_shader_parameter("origin", lo)
	mat.set_shader_parameter("size", sz)
	# Further back sinks into the dusk; the chosen one, or the one under the
	# pointer, stands out.
	var depth := clampf(slot / float(DEPTH), 0.0, 1.0)
	var lift := maxf(float(c["hot"]), float(c["hover"]) * 0.7)
	mat.set_shader_parameter("shade", lerpf(lerpf(0.82, 0.42, depth), 1.0, lift))
	mat.set_shader_parameter("shadow_a", lerpf(0.24, 0.42, float(c["hot"])))
	if bool(c["live"]) and not _closing and _shown:
		# Everyone in view gets a picture once; the front one keeps it fresh.
		var due := float(c["since"]) >= (REFRESH * 4.0 if bool(c["failed"]) else REFRESH)
		if (not bool(c["has_pic"]) and not bool(c["failed"])) or (float(c["hot"]) > 0.5 and due):
			_request_shot(c)


## Asks the companion for a fresh picture of a card's window.
func _request_shot(c: Dictionary) -> void:
	if not bool(c["live"]) or bool(c["busy"]) or not Host.available:
		return
	c["busy"] = true
	c["since"] = 0.0
	var px := Vector2i((_box * Shell.scale).round())
	Host.capture(int(c["hwnd"]), px, func(tex: ImageTexture) -> void:
		c["busy"] = false
		c["failed"] = tex == null
		if tex and _cards.has(c):
			_set_pic(c, tex)
	)


## Shows a window's picture: the card takes the picture's shape, as large as
## fits the stack, and the icon stand-in goes.
func _set_pic(c: Dictionary, tex: Texture2D) -> void:
	var src := Vector2(tex.get_size())
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var k := minf(_box.x / src.x, _box.y / src.y)
	c["size"] = (src * k).floor()
	c["has_pic"] = true
	var mat: ShaderMaterial = c["mat"]
	mat.set_shader_parameter("pic", tex)
	mat.set_shader_parameter("has_pic", 1.0)
	mat.set_shader_parameter("has_glyph", 0.0)
	var glyph: SubViewport = c["glyph"]
	if glyph:
		mat.set_shader_parameter("glyph", null)
		c["glyph"] = null
		glyph.queue_free()
