class_name UpdateOverlay
extends Modal
## The update experience: what's new -> download (a glass orb filling with
## water, speed, ETA) -> verified (shockwave, check) -> restart (the water
## swirls and the screen settles into the boot wallpaper, so the relaunch
## picks up exactly where this leaves off). Follows Updater state, so it can
## be opened at any point.

const TIPS := [
	"Tip: press Ctrl + Alt + O in any app to open Start.",
	"Tip: right-click any app or game to add it to your favourites.",
	"Tip: start typing on the desktop to search for anything.",
	"Tip: Alt + Tab shows live previews of every open window.",
	"Tip: Ctrl + Alt + D takes you straight back to your desktop.",
	"Tip: Oazy picks its colours from the game you are looking at.",
]
const STEPS := ["Download", "Verify", "Restart"]
const PROGRESS_WIDTH := 680.0

var _notes_view: Control
var _progress_view: Control
var _orb: UpdateOrb
var _percent: Label
var _check: TextureRect
var _steps: Array[Dictionary] = []
var _dl_title: Label
var _dl_stats: Label
var _stats_row: HBoxContainer
var _stat_values: Array[Label] = []
var _tip: Label
var _dl_buttons: HBoxContainer
var _tip_index := 0
var _update_btn: FxButton
var _cards: NotesCards
var _veil: Control
var _step_pulse := 0.0
var _stack: Control
var _shown_state: StringName = &""
## The version the notes view was built for; a recheck may find a newer one.
var _notes_version := ""


func _init() -> void:
	width = 1000.0


func _build() -> void:
	_stack = Control.new()
	_stack.custom_minimum_size = Vector2(0, 580)
	content.add_child(_stack)
	_notes_view = _build_notes()
	_stack.add_child(_notes_view)
	_progress_view = _build_progress()
	_stack.add_child(_progress_view)
	Updater.state_changed.connect(_on_state)
	Updater.progress.connect(_on_progress)
	var tip_timer := Timer.new()
	tip_timer.wait_time = 4.5
	tip_timer.autostart = true
	tip_timer.timeout.connect(_next_tip)
	add_child(tip_timer)
	_on_state(Updater.state)
	if _notes_view.visible:
		_cards.reveal.call_deferred(0.2)


func _focus_first() -> void:
	if _notes_view.visible and _update_btn:
		_update_btn.grab_focus()


## A recheck found an even newer update while the notes were open.
func _rebuild_notes() -> void:
	var old := _notes_view
	_notes_view = _build_notes()
	_notes_view.visible = old.visible
	_notes_view.modulate.a = old.modulate.a
	_stack.add_child(_notes_view)
	_stack.move_child(_notes_view, 0)
	old.queue_free()
	_cards.reveal(0.0)
	_update_btn.grab_focus.call_deferred()


func _build_notes() -> Control:
	_notes_version = str(Updater.latest.get("version", ""))
	var view := Kit.hbox(36)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := Kit.vbox(12)
	left.custom_minimum_size.x = 300
	view.add_child(left)

	# A little glass orb, already part full.
	var art := Control.new()
	art.custom_minimum_size = Vector2(170, 170)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(art)
	var orb := UpdateOrb.new(170, 0.78)
	orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orb.snap(0.34)
	orb.mat.set_shader_parameter("waves", 0.7)
	orb.mat.set_shader_parameter("ripples", 0.6)
	art.add_child(orb)

	left.add_child(Kit.spacer(0, 2))
	left.add_child(Kit.label("UPDATE AVAILABLE", 13, 700, App.accent.lightened(0.35)))
	var latest := str(Updater.latest.get("version", "?"))
	var jump := Kit.hbox(10)
	jump.add_child(Kit.label(App.version, 22, 700, App.TEXT_DIM, true))
	var arrow := Kit.icon_rect("chevron_right", 20, App.accent.lightened(0.3))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jump.add_child(arrow)
	jump.add_child(Kit.label(latest, 34, 700, Color.WHITE, true))
	left.add_child(jump)
	var meta := PackedStringArray()
	if int(Updater.latest.get("size", 0)) > 0:
		meta.append(Fmt.bytes(float(Updater.latest["size"])))
	if str(Updater.latest.get("date", "")) != "":
		meta.append(Fmt.date(str(Updater.latest["date"])))
	if Updater.newer.size() > 1:
		meta.append("%d updates in one" % Updater.newer.size())
	left.add_child(Kit.label("  ·  ".join(meta), 15, 500, App.TEXT_DIM))
	var blurb := Kit.label("Your apps, games and settings stay exactly as they are. Oazy restarts by itself when it's done.", 15, 500, App.TEXT_MUTE)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(blurb)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(grow)
	_update_btn = FxButton.make("Update now", "download", FxButton.Style.PRIMARY, 54)
	_update_btn.pressed.connect(func() -> void: Updater.download())
	left.add_child(_update_btn)
	var later := FxButton.make("Later", "", FxButton.Style.GHOST, 46)
	later.pressed.connect(close)
	left.add_child(later)

	var right := Kit.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(right)
	var head := Kit.hbox(10)
	head.add_child(Kit.icon_rect("sparkles", 20, Color.WHITE))
	head.add_child(Kit.label("What's new", 22, 700, Color.WHITE, true))
	right.add_child(head)
	_cards = NotesCards.new(Updater.combined_notes())
	right.add_child(_cards)
	return view


func _build_progress() -> Control:
	var view := Kit.vbox(0)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.alignment = BoxContainer.ALIGNMENT_CENTER
	view.visible = false

	# Where we are, as a quiet pill: Download, Verify, Restart.
	var steps_holder := CenterContainer.new()
	view.add_child(steps_holder)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 999, Color(1, 1, 1, 0.07), 1, 18, 9))
	steps_holder.add_child(pill)
	var steps := Kit.hbox(12)
	pill.add_child(steps)
	for i in STEPS.size():
		if i > 0:
			var line := ColorRect.new()
			line.color = Color(1, 1, 1, 0.12)
			line.custom_minimum_size = Vector2(28, 1)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			steps.add_child(line)
		var item := Kit.hbox(7)
		var dot := Kit.icon_rect("dot", 16, App.TEXT_MUTE)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		var label := Kit.label(STEPS[i], 14, 700, App.TEXT_MUTE)
		item.add_child(label)
		steps.add_child(item)
		_steps.append({"item": item, "dot": dot, "label": label, "state": -1})

	var orb_holder := CenterContainer.new()
	view.add_child(orb_holder)
	var orb_box := Control.new()
	orb_box.custom_minimum_size = Vector2(340, 340)
	orb_holder.add_child(orb_box)
	_orb = UpdateOrb.new(340, 0.62)
	_orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orb_box.add_child(_orb)
	_percent = Kit.label("0%", 54, 700, Color.WHITE, true)
	_percent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	orb_box.add_child(_percent)
	_check = Kit.icon_rect("check", 80, Color.WHITE)
	_check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_check.pivot_offset = Vector2(170, 170)
	_check.visible = false
	orb_box.add_child(_check)

	_dl_title = Kit.label("", 26, 700, Color.WHITE, true)
	_dl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(_dl_title)
	view.add_child(Kit.spacer(0, 6))
	# While downloading: three tidy figures. Otherwise: one line of text.
	var stats_holder := CenterContainer.new()
	view.add_child(stats_holder)
	_stats_row = Kit.hbox(0)
	stats_holder.add_child(_stats_row)
	for i in 3:
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.08)
			sep.custom_minimum_size = Vector2(1, 30)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_stats_row.add_child(sep)
		var cell := Kit.vbox(2)
		cell.custom_minimum_size.x = 150
		var value := Kit.label("–", 19, 700, Color.WHITE, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(value)
		var caption := Kit.label(["DOWNLOADED", "SPEED", "TIME LEFT"][i], 11, 700, App.TEXT_MUTE)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		_stats_row.add_child(cell)
		_stat_values.append(value)
	_dl_stats = Kit.label("", 15, 500, App.TEXT_DIM)
	_dl_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dl_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dl_stats.custom_minimum_size.x = 480
	_dl_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.add_child(_dl_stats)
	view.add_child(Kit.spacer(0, 20))
	_dl_buttons = Kit.hbox(12)
	_dl_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	view.add_child(_dl_buttons)
	view.add_child(Kit.spacer(0, 16))
	_tip = Kit.label(TIPS[0], 13, 500, App.TEXT_MUTE)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(_tip)
	return view


## Downloading shows the three figures; every other state a line of text.
func _show_figures(on: bool) -> void:
	_stats_row.visible = on
	_dl_stats.visible = not on
	if on:
		for v in _stat_values:
			v.text = "–"


## 0 waiting, 1 active, 2 done.
func _set_steps(active: int) -> void:
	for i in _steps.size():
		var s: Dictionary = _steps[i]
		var st := 2 if i < active else (1 if i == active else 0)
		if s["state"] == st:
			continue
		s["state"] = st
		var dot: TextureRect = s["dot"]
		var label: Label = s["label"]
		match st:
			2:
				dot.texture = Icons.tex("check", 18, App.accent.lightened(0.45))
				label.add_theme_color_override("font_color", App.TEXT)
			1:
				dot.texture = Icons.tex("dot", 18, App.accent.lightened(0.3))
				label.add_theme_color_override("font_color", Color.WHITE)
			_:
				dot.texture = Icons.tex("dot", 18, App.TEXT_MUTE)
				label.add_theme_color_override("font_color", App.TEXT_MUTE)
		dot.pivot_offset = Vector2(9, 9)
		dot.scale = Vector2.ONE * 0.4
		dot.create_tween().tween_property(dot, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		dot.modulate.a = 1.0


func _set_buttons(specs: Array) -> void:
	for c in _dl_buttons.get_children():
		c.queue_free()
	var first: FxButton = null
	for s in specs:
		var b := FxButton.make(s[0], s[1], s[2], 50)
		b.pressed.connect(s[3])
		_dl_buttons.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _show_progress_view() -> void:
	if _progress_view.visible:
		return
	_progress_view.visible = true
	_progress_view.modulate.a = 0.0
	_orb.snap(0.0)
	_orb.pivot_offset = _orb.custom_minimum_size / 2.0
	_orb.scale = Vector2.ONE * 0.85
	var t := create_tween().set_parallel(true)
	t.tween_property(_notes_view, "modulate:a", 0.0, 0.25)
	t.tween_property(_progress_view, "modulate:a", 1.0, 0.45).set_delay(0.15)
	t.tween_property(_orb, "scale", Vector2.ONE, 0.8).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func() -> void: _notes_view.visible = false)
	# The card narrows around the progress so it reads as one tidy column.
	t.chain().tween_property(card, "custom_minimum_size:x", PROGRESS_WIDTH, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _on_state(state: StringName) -> void:
	if not is_inside_tree():
		return
	# A recheck runs quietly underneath; coming back to the same ready state
	# shouldn't replay the ready animation.
	if state == &"checking" or (state == &"ready" and _shown_state == &"ready"):
		return
	_shown_state = state
	var v := str(Updater.latest.get("version", ""))
	match state:
		&"available":
			if str(Updater.latest.get("version", "")) != _notes_version:
				_rebuild_notes()
			if _progress_view.visible:
				card.custom_minimum_size.x = width
				_notes_view.visible = true
				_notes_view.modulate.a = 0.0
				var t := create_tween().set_parallel(true)
				t.tween_property(_progress_view, "modulate:a", 0.0, 0.2)
				t.tween_property(_notes_view, "modulate:a", 1.0, 0.35).set_delay(0.1)
				t.chain().tween_callback(func() -> void: _progress_view.visible = false)
				_update_btn.grab_focus.call_deferred()
			dismissable = true
		&"downloading":
			_show_progress_view()
			dismissable = true
			_check.visible = false
			_percent.visible = true
			_percent.modulate.a = 1.0
			_orb.set_look({"waves": 1.0, "error": 0.0, "ripples": 1.0, "swirl": 0.0}, 0.3)
			_set_steps(0)
			_dl_title.text = "Downloading Oazy %s" % v
			_show_figures(true)
			_tip.visible = true
			_set_buttons([["Cancel", "", FxButton.Style.GHOST, func() -> void: Updater.cancel_download()], ["Hide", "", FxButton.Style.PLAIN, close]])
		&"ready":
			_show_progress_view()
			_orb.target = 1.0
			_orb.set_look({"waves": 0.35, "error": 0.0}, 1.2)
			_orb.shockwave()
			_set_steps(2)
			var fade := create_tween()
			fade.tween_property(_percent, "modulate:a", 0.0, 0.2)
			fade.tween_callback(func() -> void: _percent.visible = false)
			_check.texture = Icons.tex("check", 80, Color.WHITE)
			_check.visible = true
			_check.scale = Vector2.ONE * 0.3
			_check.modulate.a = 0.0
			var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(_check, "scale", Vector2.ONE, 0.6).set_delay(0.15)
			t.tween_property(_check, "modulate:a", 1.0, 0.3).set_delay(0.15)
			Sfx.play(&"notify")
			_dl_title.text = "Oazy %s is ready" % v
			_show_figures(false)
			_tip.visible = false
			if Updater.can_install():
				_dl_stats.text = "Downloaded and verified. Restart now to finish, it only takes a moment."
				_set_buttons([["Restart now", "refresh", FxButton.Style.PRIMARY, func() -> void: Updater.install()], ["Later", "", FxButton.Style.GHOST, close]])
			else:
				_dl_stats.text = "Downloaded and verified. Installing works in the packaged Windows app."
				_set_buttons([["Close", "check", FxButton.Style.PRIMARY, close]])
		&"installing":
			_show_progress_view()
			dismissable = false
			_percent.visible = false
			_orb.target = 1.0
			_orb.set_look({"swirl": 1.0, "waves": 0.6}, 0.9)
			_orb.shockwave(1.0)
			_set_steps(2)
			var spin := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			spin.tween_property(_check, "scale", Vector2.ZERO, 0.35)
			_dl_title.text = "Restarting into Oazy %s…" % v
			_show_figures(false)
			_dl_stats.text = "See you in a second."
			_tip.visible = false
			_set_buttons([])
			_show_veil(v)
		&"error":
			_show_progress_view()
			dismissable = true
			_percent.visible = false
			_check.visible = true
			_check.texture = Icons.tex("alert", 80, App.WARNING)
			_check.scale = Vector2.ONE
			_check.modulate.a = 1.0
			_orb.set_look({"error": 1.0, "waves": 0.25, "ripples": 0.15, "swirl": 0.0}, 0.8)
			_set_steps(-1)
			_dl_title.text = "That didn't work"
			_show_figures(false)
			_dl_stats.text = Updater.error_text
			_tip.visible = false
			_set_buttons([["Try again", "refresh", FxButton.Style.PRIMARY, _retry], ["Close", "", FxButton.Style.GHOST, close]])


## The screen settles into the same wallpaper and orb the boot screen opens
## with, so the restart reads as one continuous move.
func _show_veil(version: String) -> void:
	if _veil:
		return
	_veil = Control.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)
	LoadingScreen.build_stage(_veil, "Restarting into %s" % version, 1.0)
	_veil.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(_veil, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _retry() -> void:
	_check.texture = Icons.tex("check", 80, Color.WHITE)
	_orb.snap(0.0)
	if Updater.latest.is_empty():
		Updater.check()
	else:
		Updater.state = &"available"
		Updater.download()


func _on_progress(done: int, total: int, speed: float) -> void:
	if Updater.state != &"downloading":
		return
	if total > 0:
		_orb.target = clampf(float(done) / float(total), 0.0, 1.0)
	_stat_values[0].text = "%s / %s" % [Fmt.bytes(done), Fmt.bytes(total)] if total > 0 else Fmt.bytes(done)
	_stat_values[1].text = "%s/s" % Fmt.bytes(speed) if speed > 0.0 else "–"
	_stat_values[2].text = Fmt.duration(float(total - done) / speed) if speed > 0.0 and total > 0 else "–"


func _process(delta: float) -> void:
	if _orb == null:
		return
	if _percent.visible:
		_percent.text = "%d%%" % int(round(_orb.shown * 100.0))
	# The active step breathes.
	_step_pulse += delta
	for s in _steps:
		if s["state"] == 1:
			(s["dot"] as TextureRect).modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_step_pulse * 4.0))


func _next_tip() -> void:
	if not _tip.visible:
		return
	_tip_index = (_tip_index + 1) % TIPS.size()
	var t := create_tween()
	t.tween_property(_tip, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void: _tip.text = TIPS[_tip_index])
	t.tween_property(_tip, "modulate:a", 1.0, 0.35)
