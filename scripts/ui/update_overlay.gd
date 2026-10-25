class_name UpdateOverlay
extends Modal
## The update experience: what's new -> download (live ring, speed, ETA) ->
## verified -> restart. Follows Updater state, so it can be opened at any point.

const RING := preload("res://shaders/ring.gdshader")
const TIPS := [
	"Tip: drop any .exe or shortcut onto Oazy to add it.",
	"Tip: press F on Home to favourite the selected game.",
	"Tip: start typing on the Library page to search instantly.",
	"Tip: F11 switches to fullscreen, perfect with a controller.",
	"Tip: right-click any game for quick actions.",
	"Tip: Oazy picks its colours from the game you are looking at.",
]

var _notes_view: Control
var _progress_view: Control
var _ring_mat: ShaderMaterial
var _percent: Label
var _check: TextureRect
var _dl_title: Label
var _dl_stats: Label
var _tip: Label
var _dl_buttons: HBoxContainer
var _tip_index := 0
var _shown_progress := 0.0
var _target_progress := 0.0
var _update_btn: FxButton


func _init() -> void:
	width = 980.0


func _build() -> void:
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 520)
	content.add_child(stack)
	_notes_view = _build_notes()
	stack.add_child(_notes_view)
	_progress_view = _build_progress()
	stack.add_child(_progress_view)
	Updater.state_changed.connect(_on_state)
	Updater.progress.connect(_on_progress)
	var tip_timer := Timer.new()
	tip_timer.wait_time = 4.5
	tip_timer.autostart = true
	tip_timer.timeout.connect(_next_tip)
	add_child(tip_timer)
	_on_state(Updater.state)


func _focus_first() -> void:
	if _notes_view.visible and _update_btn:
		_update_btn.grab_focus()


func _build_notes() -> Control:
	var view := Kit.hbox(36)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := Kit.vbox(14)
	left.custom_minimum_size.x = 300
	view.add_child(left)

	var art := Control.new()
	art.custom_minimum_size = Vector2(120, 120)
	left.add_child(art)
	var halo := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = RING
	m.set_shader_parameter("progress", 1.0)
	m.set_shader_parameter("color_a", App.accent)
	m.set_shader_parameter("color_b", App.accent_pair(App.accent))
	m.set_shader_parameter("thickness", 0.06)
	halo.material = m
	halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(halo)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(26, 26)
	logo.size = Vector2(68, 68)
	art.add_child(logo)

	left.add_child(Kit.spacer(0, 4))
	var kicker := Kit.label("UPDATE AVAILABLE", 13, 700, App.accent.lightened(0.35))
	left.add_child(kicker)
	var latest := str(Updater.latest.get("version", "?"))
	var jump := Kit.label("%s  →  %s" % [App.version, latest], 32, 800, Color.WHITE, true)
	left.add_child(jump)
	var meta := PackedStringArray()
	if int(Updater.latest.get("size", 0)) > 0:
		meta.append(Fmt.bytes(float(Updater.latest["size"])))
	if str(Updater.latest.get("date", "")) != "":
		meta.append(Fmt.date(str(Updater.latest["date"])))
	if Updater.newer.size() > 1:
		meta.append("%d updates in one" % Updater.newer.size())
	left.add_child(Kit.label("  ·  ".join(meta), 15, 500, App.TEXT_DIM))
	var blurb := Kit.label("Your library and settings stay exactly as they are. Oazy restarts by itself when it's done.", 15, 500, App.TEXT_MUTE)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(blurb)
	left.add_child(Kit.spacer(0, 0, false))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(grow)
	_update_btn = FxButton.make("Update now", "download", FxButton.Style.PRIMARY, 54)
	_update_btn.pressed.connect(func() -> void: Updater.download())
	left.add_child(_update_btn)
	var later := FxButton.make("Later", "", FxButton.Style.GHOST, 46)
	later.pressed.connect(close)
	left.add_child(later)

	var right := Kit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(right)
	var head := Kit.hbox(10)
	head.add_child(Kit.icon_rect("sparkles", 20, Color.WHITE))
	head.add_child(Kit.label("What's new", 22, 800, Color.WHITE, true))
	right.add_child(head)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.22), 18, Color(1, 1, 1, 0.06), 1, 22, 18))
	right.add_child(frame)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.selection_enabled = true
	text.text = Markdown.to_bbcode(Updater.combined_notes(), App.accent.lightened(0.25))
	text.meta_clicked.connect(func(meta_v: Variant) -> void: OS.shell_open(str(meta_v)))
	frame.add_child(text)
	return view


func _build_progress() -> Control:
	var view := Kit.vbox(16)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.alignment = BoxContainer.ALIGNMENT_CENTER
	view.visible = false

	var ring_holder := CenterContainer.new()
	view.add_child(ring_holder)
	var ring_box := Control.new()
	ring_box.custom_minimum_size = Vector2(250, 250)
	ring_holder.add_child(ring_box)
	var ring := ColorRect.new()
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING
	_ring_mat.set_shader_parameter("color_a", App.accent)
	_ring_mat.set_shader_parameter("color_b", App.accent_pair(App.accent))
	_ring_mat.set_shader_parameter("thickness", 0.07)
	ring.material = _ring_mat
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_box.add_child(ring)
	_percent = Kit.label("0%", 54, 800, Color.WHITE, true)
	_percent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring_box.add_child(_percent)
	_check = Kit.icon_rect("check", 84, Color.WHITE)
	_check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_check.pivot_offset = Vector2(125, 125)
	_check.visible = false
	ring_box.add_child(_check)

	view.add_child(Kit.spacer(0, 6))
	_dl_title = Kit.label("", 26, 800, Color.WHITE, true)
	_dl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(_dl_title)
	_dl_stats = Kit.label("", 16, 500, App.TEXT_DIM)
	_dl_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dl_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(_dl_stats)
	_tip = Kit.label(TIPS[0], 14, 500, App.TEXT_MUTE)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(_tip)
	view.add_child(Kit.spacer(0, 6))
	_dl_buttons = Kit.hbox(12)
	_dl_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	view.add_child(_dl_buttons)
	return view


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
	var t := create_tween().set_parallel(true)
	t.tween_property(_notes_view, "modulate:a", 0.0, 0.25)
	t.tween_property(_progress_view, "modulate:a", 1.0, 0.4).set_delay(0.15)
	t.chain().tween_callback(func() -> void: _notes_view.visible = false)


func _on_state(state: StringName) -> void:
	if not is_inside_tree():
		return
	var v := str(Updater.latest.get("version", ""))
	match state:
		&"available":
			if _progress_view.visible:
				_notes_view.visible = true
				_notes_view.modulate.a = 1.0
				_progress_view.visible = false
			dismissable = true
		&"downloading":
			_show_progress_view()
			dismissable = true
			_check.visible = false
			_percent.visible = true
			_ring_mat.set_shader_parameter("indeterminate", 0.0)
			_dl_title.text = "Downloading Oazy %s" % v
			_dl_stats.text = "Connecting…"
			_tip.visible = true
			_set_buttons([["Cancel", "", FxButton.Style.GHOST, func() -> void: Updater.cancel_download()], ["Hide", "", FxButton.Style.PLAIN, close]])
		&"ready":
			_show_progress_view()
			_target_progress = 1.0
			_percent.visible = false
			_check.visible = true
			_check.scale = Vector2.ONE * 0.3
			_check.modulate.a = 0.0
			var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(_check, "scale", Vector2.ONE, 0.55)
			t.tween_property(_check, "modulate:a", 1.0, 0.3)
			Sfx.play(&"notify")
			_dl_title.text = "Oazy %s is ready" % v
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
			_check.visible = false
			_ring_mat.set_shader_parameter("indeterminate", 1.0)
			_dl_title.text = "Restarting into Oazy %s…" % v
			_dl_stats.text = "See you in a second."
			_tip.visible = false
			_set_buttons([])
		&"error":
			_show_progress_view()
			dismissable = true
			_percent.visible = false
			_check.visible = true
			_check.texture = Icons.tex("alert", 84, App.WARNING)
			_ring_mat.set_shader_parameter("indeterminate", 0.0)
			_target_progress = 0.0
			_dl_title.text = "That didn't work"
			_dl_stats.text = Updater.error_text
			_tip.visible = false
			_set_buttons([["Try again", "refresh", FxButton.Style.PRIMARY, _retry], ["Close", "", FxButton.Style.GHOST, close]])


func _retry() -> void:
	_check.texture = Icons.tex("check", 84, Color.WHITE)
	if Updater.latest.is_empty():
		Updater.check()
	else:
		Updater.state = &"available"
		Updater.download()


func _on_progress(done: int, total: int, speed: float) -> void:
	if total > 0:
		_target_progress = clampf(float(done) / float(total), 0.0, 1.0)
	var parts := PackedStringArray()
	parts.append("%s of %s" % [Fmt.bytes(done), Fmt.bytes(total)] if total > 0 else Fmt.bytes(done))
	if speed > 0.0:
		parts.append("%s/s" % Fmt.bytes(speed))
		if total > 0:
			parts.append("%s left" % Fmt.duration(float(total - done) / speed))
	if Updater.state == &"downloading":
		_dl_stats.text = "  ·  ".join(parts)


func _process(delta: float) -> void:
	if _ring_mat == null:
		return
	_shown_progress = lerpf(_shown_progress, _target_progress, 1.0 - exp(-delta * 8.0))
	_ring_mat.set_shader_parameter("progress", _shown_progress)
	if _percent.visible:
		_percent.text = "%d%%" % int(round(_shown_progress * 100.0))


func _next_tip() -> void:
	if not _tip.visible:
		return
	_tip_index = (_tip_index + 1) % TIPS.size()
	var t := create_tween()
	t.tween_property(_tip, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void: _tip.text = TIPS[_tip_index])
	t.tween_property(_tip, "modulate:a", 1.0, 0.35)
