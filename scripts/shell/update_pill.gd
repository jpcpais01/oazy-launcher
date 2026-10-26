class_name UpdatePill
extends Control
## A small glass pill on the right edge of the screen while Oazy has an update
## going: the water orb filling as it downloads, a short label beside it. It
## lives on its own always-on-top layer, so it stays over every window (and
## steps aside for fullscreen games). Hover and it slides open into the
## details with one action (update, restart, retry); click it for the full
## update screen. When something new happens (an update found, the download
## done) it opens by itself for a few seconds.

const H := 56.0
const ORB := 44.0
const PAD := 6.0
const EDGE := 16.0
## Where it sits, as a part of the screen height (clear of title bars).
const AT := 0.36
## Seconds it stays open by itself after news.
const NEWS_TIME := 4.5

var main: Node
var _card: Control
var _glass: GlassPanel
var _orb: UpdateOrb
var _check: TextureRect
var _short: Label
var _detail: HBoxContainer
var _title: Label
var _sub: Label
var _action: FxButton
var _action_cb := Callable()
var _state: StringName = &"idle"
## 0 hidden .. 1 on screen; the pill slides in from the edge.
var _in := 0.0
var _want_in := false
var _open := false
var _hovered := false
var _news_left := 0.0
var _w := 0.0
var _w_vel := 0.0
var _hover_grace := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Control.new()
	_card.clip_contents = true
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_card.mouse_entered.connect(func() -> void: _set_hover(true))
	_card.mouse_exited.connect(func() -> void: _set_hover(false))
	_card.gui_input.connect(_on_card_input)
	_card.visible = false
	# The glass sits beside the card, not in it, so the clip that hides the
	# details while closed doesn't cut its shadow off.
	_glass = GlassPanel.new(true, H * 0.5, GlassPanel.TINT_POPUP)
	_glass.set_shadow_strength(0.3, 16, 5.0)
	_glass.visible = false
	add_child(_glass)
	add_child(_card)

	var row := Kit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(PAD, 0)
	row.custom_minimum_size.y = H
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_card.add_child(row)
	var orb_box := Control.new()
	orb_box.custom_minimum_size = Vector2(ORB, ORB)
	orb_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(orb_box)
	_orb = UpdateOrb.new(ORB, 0.86)
	_orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_orb.mat.set_shader_parameter("ripples", 0.0)
	_orb.mat.set_shader_parameter("waves", 0.7)
	orb_box.add_child(_orb)
	_check = Kit.icon_rect("check", 18, Color.WHITE)
	_check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_check.pivot_offset = Vector2(ORB, ORB) * 0.5
	_check.visible = false
	orb_box.add_child(_check)

	_short = Kit.label("", 15, 700, Color.WHITE, true)
	_short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_short)

	_detail = Kit.hbox(14)
	_detail.visible = false
	_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_detail)
	var col := Kit.vbox(0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(col)
	_title = Kit.label("", 15, 700, Color.WHITE, true)
	col.add_child(_title)
	_sub = Kit.label("", 13, 500, App.TEXT_DIM)
	col.add_child(_sub)
	_action = FxButton.make("", "", FxButton.Style.PRIMARY, 36)
	_action.focus_mode = Control.FOCUS_NONE
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action.pressed.connect(func() -> void:
		if _action_cb.is_valid():
			_action_cb.call()
	)
	_detail.add_child(_action)

	Updater.state_changed.connect(_on_state)
	Updater.progress.connect(_on_progress)
	_on_state(Updater.state)


func shell_shape() -> Array[Rect2]:
	if not _card.visible:
		return []
	return [_glass.shadow_rect()]


## The state that shows: a recheck changes nothing, and a failed background
## check is not news (only a download that failed).
func _on_state(state: StringName) -> void:
	if state == &"checking":
		return
	if state == &"error" and _state not in [&"downloading", &"ready", &"error"]:
		state = &"idle"
	var was := _state
	_state = state
	_want_in = state in [&"available", &"downloading", &"ready", &"installing", &"error"]
	if not _want_in:
		return
	var v := str(Updater.latest.get("version", ""))
	_check.visible = false
	_short.modulate = Color.WHITE
	match state:
		&"available":
			_orb.snap(0.12)
			_orb.set_look({"waves": 0.7, "error": 0.0, "swirl": 0.0}, 0.4)
			_show_check("download", Color.WHITE, was != &"available")
			_short.text = "Update"
			_title.text = "Oazy %s is here" % v
			_sub.text = _size_text()
			_set_action("Update", func() -> void: Updater.download())
		&"downloading":
			_orb.set_look({"waves": 1.0, "error": 0.0, "swirl": 0.0}, 0.4)
			_title.text = "Downloading Oazy %s" % v
			_sub.text = "Starting…"
			_short.text = "0%"
			_set_action("Details", _details)
		&"ready":
			_orb.target = 1.0
			_orb.set_look({"waves": 0.35, "error": 0.0, "swirl": -0.3}, 1.0)
			_show_check("check", Color.WHITE, was != &"ready")
			_short.text = "Restart"
			_title.text = "Oazy %s is ready" % v
			_sub.text = "Restart to finish, it takes a moment"
			if Updater.can_install():
				_set_action("Restart", func() -> void: Updater.install())
			else:
				_set_action("Details", _details)
		&"installing":
			_orb.target = 1.0
			_orb.set_look({"swirl": 1.0, "waves": 0.6}, 0.9)
			_short.text = "Restarting"
			_title.text = "Restarting into %s" % v
			_sub.text = "See you in a second"
			_set_action("", Callable())
		&"error":
			_orb.set_look({"error": 1.0, "waves": 0.25, "swirl": 0.0}, 0.6)
			_show_check("alert", App.WARNING, was != &"error")
			_short.text = "Retry"
			_short.modulate = App.WARNING.lightened(0.3)
			_title.text = "The update didn't finish"
			_sub.text = "Try again, or open the details"
			_set_action("Try again", _retry)
	if state != was and state in [&"available", &"ready", &"error"]:
		_orb.shockwave(0.8)
		_news_left = NEWS_TIME
		_refresh_open()


func _on_progress(done: int, total: int, speed: float) -> void:
	if _state != &"downloading":
		return
	if total > 0:
		_orb.target = clampf(float(done) / float(total), 0.0, 1.0)
	var bits: Array[String] = []
	bits.append("%s of %s" % [Fmt.bytes(done), Fmt.bytes(total)] if total > 0 else Fmt.bytes(done))
	if speed > 0.0:
		bits.append("%s/s" % Fmt.bytes(speed))
		if total > 0:
			bits.append("%s left" % Fmt.duration(float(total - done) / speed))
	_sub.text = " · ".join(bits)


func _size_text() -> String:
	var bits: Array[String] = []
	if int(Updater.latest.get("size", 0)) > 0:
		bits.append(Fmt.bytes(float(Updater.latest["size"])))
	if Updater.newer.size() > 1:
		bits.append("%d updates in one" % Updater.newer.size())
	bits.append("See what's new")
	return " · ".join(bits)


func _set_action(text: String, cb: Callable) -> void:
	_action.text = text
	_action.visible = text != ""
	_action_cb = cb


func _show_check(icon: String, color: Color, pop: bool) -> void:
	_check.texture = Icons.tex(icon, 18, color)
	_check.visible = true
	if pop:
		_check.scale = Vector2.ONE * 0.3
		var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_check, "scale", Vector2.ONE, 0.5).set_delay(0.1)


func _details() -> void:
	if main:
		main.show_update()


func _retry() -> void:
	_orb.snap(0.0)
	if Updater.latest.is_empty():
		Updater.check()
	else:
		Updater.state = &"available"
		Updater.download()


func _on_card_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_details()
		accept_event()


func _set_hover(on: bool) -> void:
	if on:
		_hovered = true
		_hover_grace = 0.0
		_refresh_open()
	else:
		# Moving between the pill and its button reads as leaving for a frame.
		_hover_grace = 0.3


func _refresh_open() -> void:
	var want := _hovered or _news_left > 0.0
	if want == _open:
		return
	_open = want
	if want:
		_short.visible = false
		_detail.visible = true
		_detail.modulate.a = 0.0
		Kit.hover_tween(_detail).tween_property(_detail, "modulate:a", 1.0, 0.3).set_delay(0.08)
	else:
		_detail.visible = false
		_short.visible = true
		_short.modulate.a = 0.0
		Kit.hover_tween(_short).tween_property(_short, "modulate:a", 1.0, 0.25).set_delay(0.12)


## Out of the way while the full update screen is open, and before Oazy has
## finished loading.
func _is_ready() -> bool:
	return main != null and bool(main.get("loaded")) and not main.update_screen_open()


func _target_width() -> float:
	# From the labels themselves: a container that was hidden still holds
	# the minimum size it had before its text changed.
	var inner := _short.get_minimum_size().x
	if _open:
		inner = maxf(_title.get_minimum_size().x, _sub.get_minimum_size().x)
		if _action.visible:
			inner += 14.0 + _action.get_minimum_size().x
	return PAD + ORB + 10.0 + inner + (PAD + 10.0 if _open else 18.0)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if _hover_grace > 0.0:
		_hover_grace -= dt
		if _hover_grace <= 0.0:
			_hovered = _card.get_global_rect().has_point(get_global_mouse_position()) and _card.visible
			_refresh_open()
	if _news_left > 0.0:
		_news_left -= dt
		if _news_left <= 0.0:
			_refresh_open()
	var show := _want_in and _is_ready()
	_in = move_toward(_in, 1.0 if show else 0.0, dt / (0.45 if show else 0.3))
	_card.visible = _in > 0.0
	_glass.visible = _card.visible
	if not _card.visible:
		_w = _target_width()
		_w_vel = 0.0
		return
	if _state == &"downloading":
		_short.text = "%d%%" % int(round(_orb.shown * 100.0))
	# A soft spring: slides open with the slightest overshoot, never a snap.
	var target := _target_width()
	# In small steps, so a slow frame can't make the spring fly off.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 120.0)
		_w_vel += (target - _w) * 240.0 * h
		_w_vel *= exp(-24.0 * h)
		_w += _w_vel * h
		left -= h
	var ease_in := 1.0 - pow(1.0 - _in, 3.0)
	var view := size
	_card.size = Vector2(maxf(_w, H), H)
	_card.position = Vector2(view.x - EDGE - _card.size.x + (1.0 - ease_in) * (_card.size.x + EDGE + 24.0), round(view.y * AT - H * 0.5))
	_card.modulate.a = ease_in
	_glass.position = _card.position
	_glass.size = _card.size
	_glass.modulate.a = ease_in
	_glass.set_shadow_fade(ease_in)
