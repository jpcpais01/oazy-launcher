class_name AssistantPanel
extends Control
## The Start orb's assistant: Claude in a compact glass popup that rises from
## the orb. Underneath it is the Claude Code on this PC, signed in as you and
## started in your home folder (ClaudeCli). Replies stream in, what Claude is
## doing shows as one quiet line, and anything that would change your PC waits
## for Allow. Past chats (Claude Code's own history for your home folder) open
## again from the clock, and it sits in Alt+Tab like a window while you have a
## conversation going. "Open in Claude" carries the conversation over to the
## full Oazy Claude app. Claude itself (ClaudeBlob) lives on the popup's roof,
## outside the glass, and now and then says an idea it had about one of your
## projects (ClaudeIdeas) from up there. Built once and kept in Start's layer, so opening it is only
## showing it; claude itself is started as it opens, so the first reply
## doesn't wait for it.

signal visibility_changed_to(open: bool)
## Claude is working on a reply (the taskbar orb stirs).
signal busy_changed(on: bool)
## A reply finished or Claude asked something while the popup was closed.
signal needs_you(why: String)

const W := 468.0
const H := 600.0
## The strip above the glass Claude lives on (the blob's whole box), and how
## much of it ever shows: room kept free above the popup.
const ROOF := 84.0
const ROOF_SHOWN := 82.0
const PAD := 18.0
## Stops claude this long after the popup closed with nothing running; the
## next message resumes the same conversation.
const IDLE_STOP := 600.0
## [icon, text on the chip, what it sends (or puts in the box when it ends
## with a space, for you to finish)].
const SUGGESTIONS := [
	["downloads", "What's taking up space in my Downloads?", "What's taking up the most space in my Downloads folder? Just look, don't delete anything."],
	["clock", "What did I work on this week?", "Look at the files in my home folder changed in the last 7 days and tell me what I seem to have been working on."],
	["edit", "Help me write a message", "Help me write a message to "],
	["sparkles", "Explain something simply", "Explain this to me simply: "],
]
const LOOK_WORKING := {"swirl": -1.1, "waves": 0.9}

var main: Node
var is_open := false
## The window you went to when you last left it (Host hwnd): while it's still
## the one in front, Alt+Tab puts Claude next.
var left_to := 0
## Screenshots and tests: no claude, events come from handle_message().
var mock := false
var running := false

var _cli: ClaudeCli
var _glass: GlassPanel
var _home: Control
## Claude itself, living on the roof.
var _blob: ClaudeBlob
## Its ideas, and the bubble it says them in.
var _ideas: ClaudeIdeas
var _bubble: PanelContainer
var _bubble_repo: Label
var _bubble_text: Label
var _bubble_tween: Tween
var _seen_timer: Timer
## The small settings card over the bottom of the popup, from the gear.
var _settings: PanelContainer
var _settings_btn: Button
var _ideas_switch: ToggleSwitch
var _allow_switch: ToggleSwitch
var _project_list: VBoxContainer
var _project_note: Label
var _projects_serial := 0
var _greeting: Label
var _chips: VBoxContainer
var _setup: Control
var _scroll: ScrollContainer
var _thread: VBoxContainer
var _working: HBoxContainer
var _work_orb: UpdateOrb
var _work_label: Label
var _work_pulse: Tween
var _composer: PanelContainer
var _prompt: TextEdit
var _send: Button
var _expand: Button
var _history_btn: Button
## Past chats: the list, and the rows in it.
var _history: Control
var _history_list: VBoxContainer
var _history_empty: Control
var _history_serial := 0
## The last picture of the popup, for its Alt+Tab card.
var _shot: Texture2D
## Ask first / Allow all, under the box.
var _mode: Button
var _tween: Tween
var _idle: Timer
var _follow := true
## Stream state for the message being written: content index -> block.
var _blocks := {}
var _streamed := {}
var _tools := {}
var _asks := {}
var _writing := false
var _dirty: Array[Dictionary] = []
var _since := 0
## What was last sent to claude, to send again on your API key if the plan's
## usage ran out on it.
var _sent := ""
## Unix time the plan's usage comes back once claude said it's out (0: not
## said when, -1: it isn't out).
var _limit_at := -1.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(W, H)
	_glass = GlassPanel.new(true, 26.0, GlassPanel.TINT_POPUP)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.set_shadow_strength(0.3, 28, 8.0)
	add_child(_glass)

	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = PAD
	col.offset_right = -PAD
	col.offset_top = PAD
	col.offset_bottom = -PAD
	add_child(col)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.clip_contents = true
	col.add_child(stack)
	_home = _build_home()
	stack.add_child(_home)
	_history = _build_history()
	stack.add_child(_history)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	stack.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	_scroll.add_child(pad)
	_thread = Kit.vbox(16)
	_thread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_thread)
	_working = _build_working()
	_thread.add_child(_working)
	var bar := _scroll.get_v_scroll_bar()
	bar.value_changed.connect(func(_v: float) -> void: _follow = bar.value >= bar.max_value - bar.page - 48.0)
	bar.changed.connect(func() -> void:
		if _follow:
			_scroll_down.call_deferred()
	)

	col.add_child(_build_composer())
	var foot := Kit.hbox(8)
	col.add_child(foot)
	_mode = Button.new()
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mode.add_theme_font_override("font", Kit.font(500))
	_mode.add_theme_font_size_override("font_size", 12)
	_mode.pressed.connect(func() -> void:
		Settings.set_value("claude_auto_allow", not bool(Settings.get_value("claude_auto_allow")))
		Sfx.play(&"toggle")
	)
	foot.add_child(_mode)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(gap)
	_build_buttons(foot)
	_build_roof()
	_build_settings()
	_sync_mode()
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "claude_auto_allow":
			_sync_mode()
	)
	col.add_theme_constant_override("separation", 10)

	_cli = ClaudeCli.new()
	_cli.cwd = ClaudeCli.home()
	_cli.message.connect(handle_message)
	_cli.exited.connect(_on_exit)
	add_child(_cli)
	_ideas = ClaudeIdeas.new()
	_ideas.mock = mock
	_ideas.arrived.connect(_on_idea)
	add_child(_ideas)
	_seen_timer = Timer.new()
	_seen_timer.one_shot = true
	_seen_timer.wait_time = 2.5
	_seen_timer.timeout.connect(func() -> void:
		if is_open and _bubble.visible:
			_ideas.seen()
	)
	add_child(_seen_timer)
	_idle = Timer.new()
	_idle.one_shot = true
	_idle.wait_time = IDLE_STOP
	_idle.timeout.connect(func() -> void:
		if not is_open and not running:
			_cli.stop()
	)
	add_child(_idle)
	App.accent_changed.connect(func(_c: Color) -> void: _sync_send())

	var surface := Shell.surface_of(self)
	if surface:
		# Start's layer in shell mode: clicking any other window closes it.
		surface.focus_exited.connect(func() -> void:
			await get_tree().create_timer(0.15).timeout
			if is_open and not surface.has_focus() and not surface.just_shown(400):
				close()
		)


func shell_shape() -> Array[Rect2]:
	return [_glass.shadow_rect(), _roof_rect()]


## Where Claude and its bubble can be, above the glass.
func _roof_rect() -> Rect2:
	var r := _blob.get_global_rect()
	return Rect2(r.position.x, r.end.y - ROOF_SHOWN, r.size.x, ROOF_SHOWN)


# --- Building ------------------------------------------------------------------------------

## Claude's roof: a strip over the top edge of the glass, outside it, that
## the jelly walks along, with the bubble it says its ideas in.
func _build_roof() -> void:
	_blob = ClaudeBlob.new()
	_blob.area = self
	_blob.inset = 20.0
	_blob.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_blob.offset_top = -ROOF
	_blob.offset_bottom = 0.0
	add_child(_blob)

	_bubble = PanelContainer.new()
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bubble.tooltip_text = "Ask Claude about this idea"
	_bubble.add_theme_stylebox_override("panel", Kit.box(Color(0.075, 0.1, 0.14, 0.9), 16, Color(1, 1, 1, 0.08), 1, 12, 8))
	_bubble.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_bubble.accept_event()
			_ask_about_idea()
	)
	_bubble.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bubble.offset_left = _blob.home_room()
	_bubble.offset_right = -_blob.inset - 2.0
	_bubble.offset_bottom = -ClaudeBlob.FLOOR - 5.0
	_bubble.offset_top = _bubble.offset_bottom
	_bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_blob.add_child(_bubble)
	var row := Kit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(row)
	var words := Kit.vbox(1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_bubble_repo = Kit.label("", 10, 600, App.TEXT_MUTE)
	_bubble_repo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_repo.clip_text = true
	_bubble_repo.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(_bubble_repo)
	_bubble_text = Kit.label("", 13, 500, App.TEXT)
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.max_lines_visible = 2
	_bubble_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(_bubble_text)
	var x := FxButton.icon_only("close", "Not now", 12, 24)
	x.focus_mode = Control.FOCUS_NONE
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.4))
	x.add_theme_color_override("icon_hover_color", Color.WHITE)
	x.pressed.connect(func() -> void:
		_ideas.clear()
		_sync_idea()
	)
	row.add_child(x)


## Settings, past chats, a new chat and the Claude app, at the right end of
## the footer.
func _build_buttons(row: HBoxContainer) -> void:
	_settings_btn = _head_button("settings", "Settings")
	_settings_btn.pressed.connect(func() -> void: _show_settings(not _settings.visible))
	row.add_child(_settings_btn)
	_history_btn = _head_button("history", "Past chats")
	_history_btn.pressed.connect(func() -> void:
		if _history.visible:
			_show_thread(_has_conversation())
		else:
			show_history()
	)
	row.add_child(_history_btn)
	var fresh := _head_button("edit", "New chat")
	fresh.pressed.connect(new_chat)
	row.add_child(fresh)
	_expand = _head_button("expand", "Open in the Claude app")
	_expand.pressed.connect(_open_in_app)
	row.add_child(_expand)


## A small card over the bottom right of the popup: ideas on or off, asking
## first, and which of your GitHub projects Claude thinks about.
func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.visible = false
	_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Kit.box(Color(0.07, 0.09, 0.13, 1.0), 18, Color(1, 1, 1, 0.08), 1, 16, 14)
	_settings.add_theme_stylebox_override("panel", Kit.shadowed(box, Color(0, 0, 0, 0.3), 24, Vector2(0, 8)))
	_settings.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_settings.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_settings.offset_right = -PAD
	_settings.offset_left = -PAD - 330.0
	_settings.offset_bottom = -PAD - 40.0
	_settings.offset_top = _settings.offset_bottom
	add_child(_settings)
	var col := Kit.vbox(10)
	_settings.add_child(col)
	col.add_child(Kit.label("Settings", 15, 600, App.TEXT))

	_ideas_switch = _settings_switch(col, "Ideas from Claude", "Now and then Claude reads one of your projects and suggests something.", "claude_ideas")
	_allow_switch = _settings_switch(col, "Allow everything", "Edits and commands go through without asking first.", "claude_auto_allow")

	var head := Kit.hbox(6)
	col.add_child(head)
	var title := Kit.label("Projects Claude thinks about", 12, 600, App.TEXT_DIM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var refresh := FxButton.icon_only("refresh", "Check GitHub again", 13, 26)
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.5))
	refresh.add_theme_color_override("icon_hover_color", Color.WHITE)
	refresh.pressed.connect(func() -> void: _fill_projects(true))
	head.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 168
	col.add_child(scroll)
	_project_list = Kit.vbox(2)
	_project_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_project_list)
	_project_note = Kit.label("", 11, 500, App.TEXT_MUTE)
	_project_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_project_note.custom_minimum_size = Vector2(290, 32)
	_project_list.add_child(_project_note)
	Settings.changed.connect(func(key: String, v: Variant) -> void:
		if key == "claude_ideas":
			_ideas_switch.set_on(bool(v))
		elif key == "claude_auto_allow":
			_allow_switch.set_on(bool(v))
	)


func _settings_switch(col: VBoxContainer, title: String, desc: String, key: String) -> ToggleSwitch:
	var row := Kit.hbox(12)
	col.add_child(row)
	var words := Kit.vbox(1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(Kit.label(title, 13, 500, App.TEXT))
	var d := Kit.label(desc, 11, 500, App.TEXT_MUTE)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(220, 30)
	words.add_child(d)
	var sw := ToggleSwitch.new()
	sw.focus_mode = Control.FOCUS_NONE
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.set_on(bool(Settings.get_value(key)))
	sw.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	row.add_child(sw)
	return sw


func _show_settings(on: bool) -> void:
	if on == _settings.visible:
		return
	_settings.visible = on
	if not on:
		return
	_settings.modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_settings, "modulate:a", 1.0, 0.16)
	Sfx.play(&"open")
	_fill_projects(false)


## The project list, each one ticked unless you've left it out.
func _fill_projects(fresh: bool) -> void:
	_projects_serial += 1
	var serial := _projects_serial
	for c in _project_list.get_children():
		if c != _project_note:
			c.queue_free()
	_project_note.visible = true
	_project_note.text = "Looking at GitHub…"
	var list: Array = await _ideas.projects(fresh)
	if serial != _projects_serial or not is_inside_tree():
		return
	if list.is_empty():
		_project_note.text = "Couldn't reach your GitHub projects. Sign in with the GitHub CLI (gh auth login) to include private ones."
		return
	_project_note.visible = false
	for r in list:
		_project_list.add_child(_project_row(str(r)))


func _project_row(repo: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = repo.get_slice("/", 1)
	b.tooltip_text = repo
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_override("font", Kit.font(500))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_stylebox_override("normal", Kit.empty(8, 6))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.05), 10, Color(0, 0, 0, 0), 0, 8, 6))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.08), 10, Color(0, 0, 0, 0), 0, 8, 6))
	b.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.08), 10, Color(0, 0, 0, 0), 0, 8, 6))
	var sync := func() -> void:
		var skip: Array = Settings.get_value("claude_projects_skip")
		var on := not skip.has(repo)
		b.icon = Icons.tex("check" if on else "dot", 14, Color.WHITE)
		var tint := App.accent if on else Color(1, 1, 1, 0.22)
		for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			b.add_theme_color_override(c, tint)
		var text := App.TEXT if on else App.TEXT_MUTE
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, text)
	sync.call()
	b.pressed.connect(func() -> void:
		var skip: Array = (Settings.get_value("claude_projects_skip") as Array).duplicate()
		if skip.has(repo):
			skip.erase(repo)
		else:
			skip.append(repo)
		Settings.set_value("claude_projects_skip", skip)
		sync.call()
		Sfx.play(&"toggle")
	)
	return b


func _head_button(icon_name: String, tip: String) -> Button:
	var b := FxButton.icon_only(icon_name, tip, 15, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.62))
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	return b


func _build_home() -> Control:
	var view := Kit.vbox(0)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.alignment = BoxContainer.ALIGNMENT_CENTER
	_greeting = Kit.label("", 24, 600, App.TEXT, true)
	_greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(_greeting)
	view.add_child(Kit.spacer(0, 6))
	var sub := Kit.label("What can I help with?", 15, 500, App.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(sub)
	view.add_child(Kit.spacer(0, 28))
	_chips = Kit.vbox(8)
	view.add_child(_chips)
	for s in SUGGESTIONS:
		_chips.add_child(_chip(str(s[0]), str(s[1]), str(s[2])))
	_setup = _build_setup()
	_setup.visible = false
	view.add_child(_setup)
	view.add_child(Kit.spacer(0, 24))
	return view


func _chip(icon_name: String, text: String, prompt: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size.y = 46
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.045), 15, Color(1, 1, 1, 0.065), 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.09), 15, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.13), 15, Color(1, 1, 1, 0.12), 1))
	var row := Kit.hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 15
	row.offset_right = -12
	b.add_child(row)
	var ic := Kit.icon_rect(icon_name, 17, Color(1, 1, 1, 0.7))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Kit.label(text, 14, 500, Color(1, 1, 1, 0.86))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	var go := Kit.icon_rect("chevron_right", 15, Color(1, 1, 1, 0.0))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go)
	b.mouse_entered.connect(func() -> void: Kit.hover_tween(go).tween_property(go, "modulate", Color(1, 1, 1, 1), 0.18))
	b.mouse_exited.connect(func() -> void: Kit.hover_tween(go).tween_property(go, "modulate", Color(1, 1, 1, 0), 0.18))
	go.texture = Icons.tex("chevron_right", 15, Color(1, 1, 1, 0.5))
	go.modulate.a = 0.0
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		if prompt.ends_with(" "):
			_prompt.text = prompt
			_prompt.set_caret_column(prompt.length())
			_prompt.grab_focus()
			_fit_input()
			_sync_send()
		else:
			submit(prompt)
	)
	return b


## Past chats: one quiet list, newest first, the one you're in marked.
func _build_history() -> Control:
	var view := Kit.vbox(10)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	var head := Kit.label("Past chats", 13, 600, App.TEXT_MUTE)
	head.custom_minimum_size.y = 22
	view.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)
	_history_list = Kit.vbox(2)
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_history_list)
	_history_empty = Kit.vbox(6)
	_history_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_history_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_empty.visible = false
	var none := Kit.label("No past chats yet", 15, 600, App.TEXT_DIM)
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_history_empty.add_child(none)
	var hint := Kit.label("Conversations you have here show up in this list.", 13, 500, App.TEXT_MUTE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_history_empty.add_child(hint)
	view.add_child(_history_empty)
	return view


func _history_row(e: Dictionary) -> Button:
	var current := str(e["id"]) == _cli.session and _has_conversation()
	var b := Button.new()
	b.custom_minimum_size.y = 50
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(e["title"])
	var bg := Color(1, 1, 1, 0.07) if current else Color(1, 1, 1, 0.0)
	b.add_theme_stylebox_override("normal", Kit.box(bg, 13))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, bg.a + 0.05), 13))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, bg.a + 0.09), 13))
	var row := Kit.hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic := Kit.icon_rect("chat", 15, Color(1, 1, 1, 0.75 if current else 0.42))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := Kit.vbox(1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := Kit.label(str(e["title"]), 14, 500, App.TEXT if current else Color(1, 1, 1, 0.86))
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(t)
	var when := Fmt.ago(int(e.get("at", 0)))
	if when == "Never played":
		when = ""
	var sub := Kit.label("This chat" if current else when, 12, 500, App.TEXT_MUTE)
	sub.visible = sub.text != ""
	col.add_child(sub)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		if current:
			_show_thread(true)
		else:
			load_chat(e)
	)
	return b


func _build_setup() -> Control:
	var box := Kit.vbox(12)
	var l := Kit.label("Claude Code isn't set up on this PC yet. Set it up once in the Claude app and it works here too, signed in as you.", 14, 500, App.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = W - PAD * 2.0 - 40.0
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(l)
	var b := FxButton.make("Set up Claude Code", "", FxButton.Style.PRIMARY, 40)
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		close()
		ClaudeApp.open()
	)
	box.add_child(b)
	return box


func _build_working() -> HBoxContainer:
	var row := Kit.hbox(10)
	row.visible = false
	_work_orb = UpdateOrb.icon(24, 0.9, LOOK_WORKING["swirl"])
	_work_orb.mat.set_shader_parameter("waves", LOOK_WORKING["waves"])
	_work_orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_work_orb)
	_work_label = Kit.label("Thinking", 13, 500, App.TEXT_DIM)
	_work_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_work_label)
	return row


func _build_composer() -> Control:
	_composer = PanelContainer.new()
	_composer.add_theme_stylebox_override("panel", _composer_box(false))
	var row := Kit.hbox(8)
	_composer.add_child(row)
	_prompt = TextEdit.new()
	_prompt.placeholder_text = "Ask Claude anything"
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prompt.scroll_fit_content_height = false
	_prompt.caret_blink = true
	_prompt.context_menu_enabled = false
	for s in ["normal", "focus", "read_only"]:
		_prompt.add_theme_stylebox_override(s, Kit.empty(2, 8))
	_prompt.add_theme_font_override("font", Kit.font(400))
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", App.TEXT)
	_prompt.add_theme_color_override("font_placeholder_color", App.TEXT_MUTE)
	_prompt.add_theme_color_override("caret_color", Color.WHITE)
	_prompt.add_theme_color_override("selection_color", Color(App.accent, 0.35))
	_prompt.add_theme_color_override("background_color", Color(0, 0, 0, 0))
	_prompt.add_theme_constant_override("line_spacing", 3)
	_prompt.text_changed.connect(func() -> void:
		_fit_input()
		_sync_send()
		if _prompt.text != "":
			_blob.typing()
	)
	_prompt.gui_input.connect(_on_input_key)
	_prompt.focus_entered.connect(func() -> void: _composer.add_theme_stylebox_override("panel", _composer_box(true)))
	_prompt.focus_exited.connect(func() -> void: _composer.add_theme_stylebox_override("panel", _composer_box(false)))
	row.add_child(_prompt)
	_send = Button.new()
	_send.custom_minimum_size = Vector2(36, 36)
	_send.size_flags_vertical = Control.SIZE_SHRINK_END
	_send.focus_mode = Control.FOCUS_NONE
	_send.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_send.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_send.pressed.connect(func() -> void:
		if running:
			stop()
		else:
			submit()
	)
	row.add_child(_send)
	_fit_input()
	_sync_send()
	return _composer


## Ask before changes, or let everything through (setting "claude_auto_allow").
func _sync_mode() -> void:
	var auto := bool(Settings.get_value("claude_auto_allow"))
	var tint := App.WARNING if auto else Color(1, 1, 1, 0.62)
	_mode.text = "Allow all" if auto else "Ask first"
	_mode.icon = Icons.tex("bolt" if auto else "shield", 13, Color.WHITE)
	_mode.tooltip_text = "Claude edits files and runs commands without asking. Click to have it ask first." if auto else "Claude asks before it edits files or runs commands. Click to allow everything without asking."
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_mode.add_theme_color_override(c, tint)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		_mode.add_theme_color_override(c, tint)
	var bg := Color(App.WARNING, 0.12) if auto else Color(1, 1, 1, 0.05)
	var line := Color(App.WARNING, 0.28) if auto else Color(1, 1, 1, 0.07)
	_mode.add_theme_stylebox_override("normal", Kit.box(bg, 999, line, 1, 10, 4))
	_mode.add_theme_stylebox_override("hover", Kit.box(Color(bg, bg.a + 0.05), 999, line, 1, 10, 4))
	_mode.add_theme_stylebox_override("pressed", Kit.box(Color(bg, bg.a + 0.08), 999, line, 1, 10, 4))
	_mode.add_theme_stylebox_override("hover_pressed", Kit.box(Color(bg, bg.a + 0.08), 999, line, 1, 10, 4))
	# Anything waiting for an answer goes through once you switch it on.
	if auto:
		for id in _asks.keys():
			_answer(str(id), true)


func _composer_box(focus: bool) -> StyleBoxFlat:
	return Kit.box(Color(1, 1, 1, 0.07 if focus else 0.055), 22, Color(App.accent, 0.42) if focus else Color(1, 1, 1, 0.09), 1, 14, 7)


## The box grows with what you type, up to six lines, then scrolls.
func _fit_input() -> void:
	var lines := clampi(_prompt.get_line_count() + _wrapped_extra(), 1, 6)
	var h := lines * _prompt.get_line_height() + 16
	_prompt.custom_minimum_size.y = maxf(36.0, h)


func _wrapped_extra() -> int:
	var extra := 0
	for i in _prompt.get_line_count():
		extra += _prompt.get_line_wrap_count(i)
	return extra


func _sync_send() -> void:
	if _send == null:
		return
	var has_text := _prompt.text.strip_edges() != ""
	var bg: Color
	var fg: Color
	if running:
		_send.icon = Icons.tex("stop", 18, Color.WHITE)
		_send.tooltip_text = "Stop"
		bg = Color(1, 1, 1, 0.14)
		fg = Color.WHITE
	else:
		_send.icon = Icons.tex("arrow_up", 18, Color.WHITE)
		_send.tooltip_text = "Send"
		bg = Color("eef0f4") if has_text else Color(1, 1, 1, 0.08)
		fg = Color("0b0c12") if has_text else Color(1, 1, 1, 0.4)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		_send.add_theme_color_override(c, fg)
	_send.add_theme_stylebox_override("normal", Kit.box(bg, 999))
	_send.add_theme_stylebox_override("hover", Kit.box(bg.lightened(0.08) if has_text or running else Color(1, 1, 1, 0.11), 999))
	_send.add_theme_stylebox_override("pressed", Kit.box(bg.darkened(0.08), 999))
	_send.add_theme_stylebox_override("hover_pressed", Kit.box(bg.darkened(0.08), 999))
	_send.add_theme_stylebox_override("focus", Kit.empty())


# --- Opening and closing ---------------------------------------------------------------------

## Builds what it can ahead of the first open (Warmup).
func prepare() -> void:
	_sync_greeting()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		_prompt.grab_focus()
		return
	is_open = true
	_ideas.mock = mock
	_idle.stop()
	_sync_greeting()
	_fit_input()
	var have := mock or ClaudeCli.find() != ""
	_chips.visible = have
	_setup.visible = not have
	_composer.modulate.a = 1.0 if have else 0.5
	_show_thread(_has_conversation())
	_place()
	visible = true
	pivot_offset = Vector2(0, size.y)
	modulate.a = 0.0
	scale = Vector2.ONE * 0.97
	var target_y := position.y
	position.y += 16.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.32)
	_tween.tween_property(self, "position:y", target_y, 0.32)
	_blob.set_active(true)
	_sync_idea()
	Sfx.play(&"open")
	Shell.focus(self)
	_prompt.grab_focus()
	visibility_changed_to.emit(true)
	# Claude Code takes a moment to start: do it now, while you type.
	if have and not mock and not _cli.running():
		_start_cli()


func close() -> void:
	if not is_open:
		return
	_take_shot()
	is_open = false
	_prompt.release_focus()
	left_to = 0
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not is_open:
			left_to = Host.foreground
	)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	_tween.tween_property(self, "position:y", position.y + 14.0, 0.14)
	_tween.chain().tween_callback(func() -> void: visible = false)
	if not running:
		_idle.start()
	_blob.set_active(false)
	_seen_timer.stop()
	# Seen: it's said. Not yet: it waits for next time.
	if not _ideas.current.is_empty() and not _ideas.waiting():
		_ideas.clear()
	_blob.present(false)
	_show_settings(false)
	visibility_changed_to.emit(false)


func _place() -> void:
	var vp := Shell.view_size()
	size = Vector2(minf(W, vp.x - 20.0), minf(H, vp.y - Taskbar.RESERVE - 14.0 - ROOF_SHOWN))
	position = Vector2(Taskbar.MARGIN, vp.y - Taskbar.RESERVE - 4.0 - size.y)


func _sync_greeting() -> void:
	var h := int(Time.get_datetime_dict_from_system()["hour"])
	var part := "Good evening"
	if h >= 5 and h < 12:
		part = "Good morning"
	elif h >= 12 and h < 18:
		part = "Good afternoon"
	elif h < 5:
		part = "Hello"
	var name := Account.first_name()
	_greeting.text = part + (", " + name if name != "" else "")


## Alt+Tab lists it while it's open or there's a conversation to come back to.
func in_switcher() -> bool:
	return is_open or running or _has_conversation()


func _has_conversation() -> bool:
	return _thread.get_child_count() > 1


## What the conversation's about: its first message, for Alt+Tab and the app.
func title() -> String:
	for c in _thread.get_children():
		if c.has_meta("user_text"):
			return str(c.get_meta("user_text")).replace("\n", " ").strip_edges().left(80)
	return ""


## A picture of the popup as it looks now (the last one when it's closed), or
## null if there's never been one.
func snapshot() -> Texture2D:
	_take_shot()
	return _shot


func _take_shot() -> void:
	if not is_open or not visible or modulate.a < 0.9 or DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	var k := Vector2(img.get_size()) / vp.get_visible_rect().size
	var r := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	var px := Rect2i(Rect2(r.position * k, r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if px.size.x < 8 or px.size.y < 8:
		return
	_shot = ImageTexture.create_from_image(img.get_region(px))


func _show_thread(on: bool) -> void:
	_history.visible = false
	_home.visible = not on
	_scroll.visible = on
	_sync_history_btn()


func _sync_history_btn() -> void:
	var on := _history.visible
	_history_btn.add_theme_color_override("icon_normal_color", Color.WHITE if on else Color(1, 1, 1, 0.62))
	_history_btn.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.1), 999) if on else Kit.empty())


## The list of past chats, read fresh each time.
func show_history() -> void:
	_home.visible = false
	_scroll.visible = false
	_history.visible = true
	_sync_history_btn()
	_history_serial += 1
	var serial := _history_serial
	var cwd := ClaudeCli.home()
	if mock:
		_fill_history(serial, ClaudeHistory.recent(cwd))
		return
	WorkerThreadPool.add_task(func() -> void:
		var list := ClaudeHistory.recent(cwd)
		_fill_history.call_deferred(serial, list)
	, false, "Claude past chats")


func _fill_history(serial: int, list: Array[Dictionary]) -> void:
	if serial != _history_serial:
		return
	for c in _history_list.get_children():
		c.queue_free()
	for e in list:
		_history_list.add_child(_history_row(e))
	_history_list.get_parent().visible = not list.is_empty()
	_history_empty.visible = list.is_empty()


## Opens a past chat: its messages as they were, and the next one carries on
## from there (claude --resume).
func load_chat(e: Dictionary) -> void:
	_reset()
	_cli.session = str(e["id"])
	if str(e.get("cwd", "")) != "" and DirAccess.dir_exists_absolute(str(e["cwd"])):
		_cli.cwd = str(e["cwd"])
	_show_thread(true)
	_follow = true
	var path := str(e["path"])
	var id := _cli.session
	if mock:
		_replay(id, ClaudeHistory.lines(path))
		return
	WorkerThreadPool.add_task(func() -> void:
		var ls := ClaudeHistory.lines(path)
		_replay.call_deferred(id, ls)
	, false, "Claude chat")


func _replay(id: String, ls: Array[Dictionary]) -> void:
	if _cli.session != id or running:
		return
	for m in ls:
		if str(m.get("type", "")) == "assistant":
			_on_assistant(m)
		elif not bool(m.get("isMeta", false)):
			var text := ClaudeHistory.user_text(m)
			if text != "":
				_add(_user_bubble(text))
			else:
				_on_user(m)
	for t in _tools.values():
		if not t["done"]:
			t["done"] = true
			_sync_tool(t)
	_work_label.text = "Thinking"
	_streamed.clear()
	_scroll_down.call_deferred()
	if is_open:
		_prompt.grab_focus()
		if not mock and not _cli.running() and ClaudeCli.find() != "":
			_start_cli()


## Typing that reached another of Oazy's layers while this is open (shell
## mode, when Windows kept focus elsewhere) still goes into the box.
func forward_key(k: InputEventKey) -> void:
	if k.keycode == KEY_ESCAPE:
		close()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		if not k.shift_pressed:
			submit()
	elif k.keycode == KEY_BACKSPACE:
		_prompt.text = _prompt.text.substr(0, maxi(0, _prompt.text.length() - 1))
	elif k.unicode >= 32 and not k.ctrl_pressed and not k.alt_pressed:
		_prompt.text += char(k.unicode)
	else:
		return
	_prompt.set_caret_line(_prompt.get_line_count() - 1)
	_prompt.set_caret_column(_prompt.get_line(_prompt.get_line_count() - 1).length())
	_fit_input()
	_sync_send()


func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k: InputEventKey = event
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		if k.shift_pressed:
			_prompt.insert_text_at_caret("\n")
		else:
			submit()
		_prompt.accept_event()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton and event.pressed:
		var over_orb: bool = main != null and main.get("taskbar") != null and main.taskbar.orb.get_global_rect().has_point(event.position)
		if _settings.visible and not _settings.get_global_rect().has_point(event.position) and not _settings_btn.get_global_rect().has_point(event.position):
			_show_settings(false)
		var on_roof := _blob.get_body_rect().has_point(event.position) or (_bubble.visible and _bubble.get_global_rect().has_point(event.position))
		if not get_global_rect().has_point(event.position) and not over_orb and not on_roof:
			close()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _settings.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()


# --- Claude's ideas --------------------------------------------------------------------------

## An idea came to it in the background: said now if you're here, otherwise
## the orb ripples and it waits for you.
func _on_idea(_idea: Dictionary) -> void:
	if is_open:
		_sync_idea()
	else:
		needs_you.emit("idea")


## The bubble is up while the popup is open, there's an idea to say and Claude
## isn't busy with your conversation.
func _sync_idea() -> void:
	var idea := _ideas.current
	var show := is_open and not idea.is_empty() and not running
	_blob.present(show)
	if not show:
		_seen_timer.stop()
		if _bubble.visible:
			if _bubble_tween and _bubble_tween.is_valid():
				_bubble_tween.kill()
			_bubble_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_bubble_tween.tween_property(_bubble, "modulate:a", 0.0, 0.12)
			_bubble_tween.tween_callback(func() -> void: _bubble.visible = false)
		return
	_bubble_repo.text = str(idea.get("repo", "")).get_slice("/", 1)
	_bubble_text.text = str(idea.get("idea", ""))
	# A wrapping label needs its width up front to know how tall it is:
	# the bubble less its padding and the close button.
	var w := size.x + _bubble.offset_right - _bubble.offset_left - 24.0 - 24.0 - 8.0
	_bubble_text.custom_minimum_size.x = maxf(80.0, w)
	_bubble_text.size.x = _bubble_text.custom_minimum_size.x
	var lines := clampi(_bubble_text.get_line_count(), 1, 2)
	_bubble_text.custom_minimum_size.y = lines * (_bubble_text.get_line_height() + 4)
	# Grows up from the roof, never down over the glass.
	_bubble.offset_top = _bubble.offset_bottom - _bubble.get_combined_minimum_size().y
	if _ideas.waiting():
		_seen_timer.start()
	if _bubble.visible and _bubble.modulate.a > 0.99:
		return
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	_bubble.pivot_offset = Vector2(0, _bubble.size.y)
	_bubble.scale = Vector2.ONE * 0.94
	if _bubble_tween and _bubble_tween.is_valid():
		_bubble_tween.kill()
	# Just after its little jump of surprise.
	_bubble_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(_bubble, "modulate:a", 1.0, 0.24).set_delay(0.3)
	_bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.3).set_delay(0.3)


## Tests and screenshots: says this idea as if it had just come ({} takes it
## away again).
func say_idea(idea: Dictionary) -> void:
	if idea.is_empty():
		_ideas.clear()
		_sync_idea()
		return
	_ideas.current = idea
	_on_idea(idea)


## Clicked: Claude tells you more, in the chat, with the project at hand.
func _ask_about_idea() -> void:
	var idea := _ideas.current
	if idea.is_empty() or running:
		return
	var repo := str(idea.get("repo", ""))
	var text := "You had an idea for my project %s: \"%s\". Tell me more about it." % [repo.get_slice("/", 1), str(idea.get("idea", ""))]
	var why := str(idea.get("why", ""))
	var path := str(idea.get("path", "")).replace("/", "\\") if App.is_windows() else str(idea.get("path", ""))
	_ideas.clear()
	_sync_idea()
	Sfx.play(&"select")
	# What you see is the question; Claude also gets what it was thinking and
	# where the project is.
	submit(text, "Not shown to the user. When you had the idea you noted: %s The latest version of github.com/%s is checked out at %s if you want to look." % [why, repo, path])


# --- Talking to Claude -----------------------------------------------------------------------

## Sends `text` as you (typed, or a chip); `context` goes along to Claude
## without showing in the chat.
func submit(text: String = "", context: String = "") -> void:
	if text == "":
		text = _prompt.text.strip_edges()
		if text == "":
			return
		_prompt.text = ""
		_fit_input()
	if running:
		return
	if not mock and ClaudeCli.find() == "":
		_setup.visible = true
		_chips.visible = false
		return
	_show_thread(true)
	_add(_user_bubble(text))
	_blob.heard(text)
	_follow = true
	_set_running(true)
	if not mock:
		if not _cli.running():
			if not _start_cli():
				_set_running(false)
				return
		_sent = text if context == "" else "%s\n\n%s%s</oazy-context>" % [text, ClaudeHistory.CONTEXT_TAG, context]
		_limit_at = -1.0
		_cli.send_text(_sent)
	_sync_send()


func stop() -> void:
	if not running:
		return
	for id in _asks.keys():
		_answer(str(id), false)
	if mock:
		_set_running(false)
		return
	_cli.interrupt()
	_work_label.text = "Stopping"
	_blob.feel("calm")


## A fresh conversation: the old one stays in Claude Code's history.
func new_chat() -> void:
	_reset()
	_show_thread(false)
	if is_open:
		_prompt.grab_focus()
		if not mock and ClaudeCli.find() != "":
			_start_cli()


## Clears the thread and leaves claude stopped.
func _reset() -> void:
	_cli.stop()
	_cli.session = ""
	_cli.cwd = ClaudeCli.home()
	_set_running(false)
	for c in _thread.get_children():
		if c != _working:
			_thread.remove_child(c)
			c.queue_free()
	_blocks.clear()
	_streamed.clear()
	_tools.clear()
	_asks.clear()
	_dirty.clear()
	_writing = false
	_prompt.text = ""
	_fit_input()
	_sync_send()
	_blob.reset()


func _start_cli() -> bool:
	var err := _cli.start()
	if err == "":
		return true
	if err == "missing":
		_setup.visible = true
		_chips.visible = false
	else:
		_notice("Couldn't start Claude Code", err)
	return false


## The whole conversation in Oazy Claude, where it carries on.
func _open_in_app() -> void:
	var sid := _cli.session
	close()
	if sid == "" or not _has_conversation():
		ClaudeApp.open({"cwd": _cli.cwd})
		return
	var cwd := _cli.cwd
	_cli.stop()
	ClaudeApp.open({"cwd": cwd, "resume": sid, "title": title()})
	new_chat()


func _set_running(on: bool) -> void:
	if running == on:
		_sync_working()
		return
	running = on
	_sync_idea()
	_since = Time.get_ticks_msec()
	_work_label.text = "Thinking"
	_sync_working()
	_sync_send()
	busy_changed.emit(on)
	if not on and not is_open:
		_idle.start()


func _sync_working() -> void:
	var show := running and _asks.is_empty() and not _writing
	if show and not _working.visible:
		_thread.move_child(_working, -1)
		_working.modulate.a = 0.0
		Kit.hover_tween(_working).tween_property(_working, "modulate:a", 1.0, 0.25)
		if _work_pulse == null or not _work_pulse.is_valid():
			_work_pulse = create_tween().set_loops()
			_work_pulse.tween_property(_work_label, "modulate:a", 0.55, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_work_pulse.tween_property(_work_label, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not show and _work_pulse and _work_pulse.is_valid():
		_work_pulse.kill()
		_work_label.modulate.a = 1.0
	_working.visible = show
	if show:
		_thread.move_child(_working, -1)


## One line from claude (or from a test).
func handle_message(m: Dictionary) -> void:
	match str(m.get("type", "")):
		"stream_event":
			if m.get("parent_tool_use_id") == null:
				_on_stream(m.get("event", {}))
		"assistant":
			_on_assistant(m)
		"user":
			_on_user(m)
		"result":
			_on_result(m)
		"control_request":
			var req: Dictionary = m.get("request", {})
			if str(req.get("subtype", "")) == "can_use_tool":
				_ask(str(m.get("request_id", "")), req)
			elif str(m.get("request_id", "")) != "":
				_cli.refuse(str(m["request_id"]))
		"control_cancel_request":
			var id := str(m.get("request_id", ""))
			if _asks.has(id):
				(_asks[id] as Control).queue_free()
				_asks.erase(id)
				_sync_working()
		"rate_limit_event":
			# "rejected" only means the plan's own window is used up: with extra
			# usage on, claude carries on with it (as Claude Code's own UI does).
			var info: Dictionary = m.get("rate_limit_info", {})
			if str(info.get("status", "")) == "rejected" and not bool(info.get("isUsingOverage", false)) and not bool(info.get("overageInUse", false)):
				# The turn ends in an error next: _on_result says so, or carries on
				# with your API key.
				var at := int(info.get("resetsAt", 0))
				_limit_at = float(at) if at > 0 else 0.0


func _on_stream(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"message_start":
			var msg: Dictionary = e.get("message", {})
			if str(msg.get("id", "")) != "":
				_streamed[str(msg["id"])] = true
			_blocks.clear()
		"content_block_start":
			var cb: Dictionary = e.get("content_block", {})
			var idx := int(e.get("index", 0))
			match str(cb.get("type", "")):
				"text":
					_blocks[idx] = {"type": "text", "view": _reply_view(), "src": "", "moods": 0}
					_writing = true
					_blob.writing()
				"thinking", "redacted_thinking":
					_blocks[idx] = {"type": "thinking"}
					_work_label.text = "Thinking"
					_blob.thinking()
				"tool_use", "server_tool_use":
					_writing = false
					_blocks[idx] = {"type": "tool", "id": str(cb.get("id", "")), "json": ""}
					_tool_row(str(cb.get("id", "")), str(cb.get("name", "")))
					_blob.working(str(cb.get("name", "")))
			_sync_working()
		"content_block_delta":
			var b: Dictionary = _blocks.get(int(e.get("index", 0)), {})
			var d: Dictionary = e.get("delta", {})
			if b.is_empty():
				return
			if str(d.get("type", "")) == "text_delta" and b["type"] == "text":
				var piece := str(d.get("text", ""))
				b["src"] = str(b["src"]) + piece
				_blob.talk(piece.length())
				_feel_from(b)
				if not _dirty.has(b):
					_dirty.append(b)
			elif str(d.get("type", "")) == "input_json_delta" and b["type"] == "tool":
				b["json"] = str(b["json"]) + str(d.get("partial_json", ""))
				# Enough of the input to say what it's doing before it's all here.
				var re := RegEx.create_from_string("\"(file_path|command|pattern|url|query|description|path)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
				var hit := re.search(str(b["json"]))
				if hit:
					var row: Dictionary = _tools.get(str(b["id"]), {})
					if not row.is_empty() and not (row["input"] as Dictionary).has(hit.get_string(1)):
						var v: Variant = JSON.parse_string("\"" + hit.get_string(2) + "\"")
						if v is String:
							row["input"][hit.get_string(1)] = v
							_sync_tool(row)
		"content_block_stop":
			var b: Dictionary = _blocks.get(int(e.get("index", 0)), {})
			if b.is_empty():
				return
			if b["type"] == "text":
				_writing = false
				_render(b)
				_dirty.erase(b)
			elif b["type"] == "tool" and str(b["json"]) != "":
				var input: Variant = JSON.parse_string(str(b["json"]))
				var row: Dictionary = _tools.get(str(b["id"]), {})
				if input is Dictionary and not row.is_empty():
					row["input"] = input
					_sync_tool(row)
			_sync_working()


func _on_assistant(m: Dictionary) -> void:
	if m.get("parent_tool_use_id") != null:
		return
	# An API error dressed as a reply ("You've hit your limit"): the result
	# right after it says so in a notice, or the turn carries on with your key.
	if m.get("error") != null:
		return
	var msg: Dictionary = m.get("message", {})
	var streamed := _streamed.has(str(msg.get("id", "")))
	var content: Variant = msg.get("content", [])
	if not content is Array:
		return
	for c in content:
		if not c is Dictionary:
			continue
		var t := str(c.get("type", ""))
		if t == "tool_use":
			if not streamed:
				_blob.working(str(c.get("name", "")))
			var row := _tool_row(str(c.get("id", "")), str(c.get("name", "")))
			if c.get("input") is Dictionary:
				row["input"] = c["input"]
				_sync_tool(row)
		elif t == "text" and not streamed and str(c.get("text", "")) != "":
			var b := {"type": "text", "view": _reply_view(), "src": str(c["text"]), "moods": 0}
			_feel_from(b)
			_render(b)


func _on_user(m: Dictionary) -> void:
	if m.get("parent_tool_use_id") != null:
		return
	var msg: Dictionary = m.get("message", {})
	var content: Variant = msg.get("content", [])
	if not content is Array:
		return
	for c in content:
		if c is Dictionary and str(c.get("type", "")) == "tool_result":
			var row: Dictionary = _tools.get(str(c.get("tool_use_id", "")), {})
			if not row.is_empty() and not row["done"]:
				row["done"] = true
				row["error"] = bool(c.get("is_error", false))
				_sync_tool(row)
	_work_label.text = "Thinking"
	if running:
		_blob.thinking()


func _on_result(m: Dictionary) -> void:
	for id in _tools:
		var row: Dictionary = _tools[id]
		if not row["done"]:
			row["done"] = true
			_sync_tool(row)
	var sub := str(m.get("subtype", ""))
	var failed := bool(m.get("is_error", false)) or (sub != "" and sub != "success")
	var text := str(m.get("result", ""))
	if text == "" and m.get("errors") is Array:
		text = "\n".join(PackedStringArray(m["errors"]))
	if failed and _sent != "" and (_limit_at >= 0.0 or _is_limit(text)) and _cli.can_use_key():
		_use_key()
		return
	_blob.done(_last_reply())
	if failed:
		if _limit_at >= 0.0 or _is_limit(text):
			_limit_notice(int(_limit_at))
		elif _is_sign_in(text):
			_sign_in_notice(text)
		elif sub == "error_max_turns":
			_notice("Claude stopped after many steps", "Send a message to let it carry on.")
		elif text != "" and not text.to_lower().contains("interrupt") and not text.to_lower().contains("abort"):
			_notice("Claude ran into a problem", text)
	for id in _asks.keys():
		(_asks[id] as Control).queue_free()
	_asks.clear()
	_writing = false
	for b in _dirty:
		_render(b)
	_dirty.clear()
	_set_running(false)
	if not is_open:
		needs_you.emit("done")


func _on_exit(code: int, err: String) -> void:
	var was := running
	_asks.clear()
	_writing = false
	_set_running(false)
	if _is_sign_in(err):
		_sign_in_notice(err)
	elif was or (code != 0 and err != ""):
		_notice("Claude Code stopped", err.right(400) if err != "" else "It closed unexpectedly. Send your message again to pick up where you left off.")


func _is_limit(text: String) -> bool:
	var t := text.to_lower()
	return t.contains("hit your limit") or t.contains("usage limit") or t.contains("reached your")


func _limit_notice(at: int) -> void:
	_notice("You've reached your usage limit", ("It resets at %s." % Time.get_time_string_from_unix_time(at + _utc_offset()).left(5)) if at > 0 else "")


## Your Claude plan is out of usage and an ANTHROPIC_API_KEY is set: carry
## on with the key until the plan resets, and send the message again on it.
func _use_key() -> void:
	var at := _limit_at
	_limit_at = -1.0
	_cli.key_until = at if at > Time.get_unix_time_from_system() else Time.get_unix_time_from_system() + 5 * 3600
	_cli.stop()
	if not _start_cli():
		_set_running(false)
		return
	_cli.send_text(_sent)
	var back := Time.get_time_string_from_unix_time(int(_cli.key_until) + _utc_offset()).left(5)
	_notice("Using your API key", "Your Claude plan is out of usage until %s, so Claude carries on with your API credits." % back)


func _is_sign_in(text: String) -> bool:
	var t := text.to_lower()
	for w in ["login", "log in", "authenticat", "api key", "oauth", "credential"]:
		if t.contains(w):
			return true
	return false


func _sign_in_notice(text: String) -> void:
	_notice("Claude Code needs you to sign in", "Sign in once in the Claude app, then come back here.", "Open Claude", func() -> void:
		close()
		ClaudeApp.open()
	)
	if text != "":
		push_warning("Claude sign in: " + text.left(200))


func _process(_delta: float) -> void:
	# Streamed text is drawn at most once a frame, however many pieces came.
	if _dirty.is_empty():
		return
	for b in _dirty:
		_render(b)
	_dirty.clear()


## A mood tag that just arrived in a reply goes to the avatar.
func _feel_from(b: Dictionary) -> void:
	var src := str(b["src"])
	if not src.contains("[["):
		return
	var moods := ClaudeMood.found(src)
	if moods.size() > int(b.get("moods", 0)):
		b["moods"] = moods.size()
		_blob.feel(moods[moods.size() - 1])


## What the latest reply said, for a mood when it didn't tag one.
func _last_reply() -> String:
	for b in _blocks.values():
		if b["type"] == "text":
			return str(b["src"])
	return ""


# --- Thread pieces --------------------------------------------------------------------------

func _add(c: Control) -> void:
	_thread.add_child(c)
	_thread.move_child(_working, -1)
	_show_thread(true)


func _scroll_down() -> void:
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = int(bar.max_value)


func _user_bubble(text: String) -> Control:
	var row := Kit.hbox(0)
	row.set_meta("user_text", text)
	row.add_child(Kit.spacer(0, 0, true))
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.085), 18, Color(1, 1, 1, 0.06), 1, 15, 10))
	row.add_child(bubble)
	var l := Kit.label(text, 15, 400, App.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var most := W - PAD * 2.0 - 10.0 - 80.0 - 30.0
	var need := Kit.font(400).get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 2.0
	l.custom_minimum_size.x = minf(need, most)
	bubble.add_child(l)
	return row


## Where a reply's text goes: Markdown drawn as text runs and code blocks.
func _reply_view() -> VBoxContainer:
	var v := Kit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add(v)
	return v


func _render(b: Dictionary) -> void:
	var view: VBoxContainer = b["view"]
	if not is_instance_valid(view):
		return
	var parts := ChatMarkdown.blocks(str(b["src"]))
	for i in parts.size():
		var p := parts[i]
		var have: Control = view.get_child(i) if i < view.get_child_count() else null
		if have and str(have.get_meta("kind", "")) != str(p["t"]):
			view.remove_child(have)
			have.queue_free()
			have = null
		if have == null:
			have = _rich() if p["t"] == "text" else _code_box()
			have.set_meta("kind", p["t"])
			view.add_child(have)
			view.move_child(have, i)
		if p["t"] == "text":
			var r := have as RichTextLabel
			if r.text != str(p["bb"]):
				r.text = str(p["bb"])
		else:
			var code: RichTextLabel = have.get_meta("code")
			var lang: Label = have.get_meta("lang")
			lang.text = str(p["lang"])
			lang.visible = lang.text != ""
			if code.text != str(p["code"]):
				code.text = str(p["code"])
	while view.get_child_count() > parts.size():
		var extra := view.get_child(view.get_child_count() - 1)
		view.remove_child(extra)
		extra.queue_free()


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = true
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wheel turns still reach the thread underneath.
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_override("normal_font", Kit.font(400))
	r.add_theme_font_override("bold_font", Kit.font(600))
	r.add_theme_font_override("bold_italics_font", Kit.font(600))
	r.add_theme_font_override("italics_font", Kit.italic_font())
	r.add_theme_font_override("mono_font", Kit.mono_font())
	for s in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		r.add_theme_font_size_override(s, 15)
	r.add_theme_font_size_override("mono_font_size", 13)
	r.add_theme_color_override("default_color", Color(1, 1, 1, 0.9))
	r.add_theme_color_override("selection_color", Color(App.accent, 0.35))
	r.add_theme_constant_override("line_separation", 4)
	r.add_theme_constant_override("paragraph_separation", 9)
	r.meta_clicked.connect(func(meta: Variant) -> void:
		var url := str(meta)
		if url.begins_with("http"):
			if Browser.handles_links():
				Browser.open(url)
			else:
				OS.shell_open(url)
	)
	return r


func _code_box() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.24), 12, Color(1, 1, 1, 0.06), 1, 13, 10))
	var v := Kit.vbox(6)
	box.add_child(v)
	var lang := Kit.label("", 11, 600, App.TEXT_MUTE)
	v.add_child(lang)
	var code := RichTextLabel.new()
	code.bbcode_enabled = false
	code.fit_content = true
	code.scroll_active = false
	code.selection_enabled = true
	code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code.mouse_filter = Control.MOUSE_FILTER_PASS
	code.add_theme_font_override("normal_font", Kit.mono_font())
	code.add_theme_font_size_override("normal_font_size", 13)
	code.add_theme_color_override("default_color", Color("dfe4ee"))
	code.add_theme_color_override("selection_color", Color(App.accent, 0.35))
	code.add_theme_constant_override("line_separation", 3)
	v.add_child(code)
	box.set_meta("code", code)
	box.set_meta("lang", lang)
	return box


## The steps Claude takes sit together in one quiet list.
func _steps() -> VBoxContainer:
	var n := _thread.get_child_count()
	var last: Node = _thread.get_child(n - 2) if n >= 2 else null
	if last is VBoxContainer and last.has_meta("steps"):
		return last
	var v := Kit.vbox(7)
	v.set_meta("steps", true)
	_add(v)
	return v


func _tool_row(id: String, tool_name: String) -> Dictionary:
	if _tools.has(id):
		return _tools[id]
	var row := Kit.hbox(9)
	var ic := Kit.icon_rect(_tool_icon(tool_name), 14, Color(1, 1, 1, 0.5))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Kit.label("", 13, 500, App.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	_steps().add_child(row)
	var t := {"name": tool_name, "input": {}, "done": false, "error": false, "denied": false, "label": l, "icon": ic}
	_tools[id] = t
	_sync_tool(t)
	return t


func _sync_tool(t: Dictionary) -> void:
	var words := _describe(str(t["name"]), t["input"], bool(t["done"]) and not t["denied"])
	var text := words[0] + (" " + words[1] if words[1] != "" else "")
	if t["denied"]:
		text = "Not allowed: " + _lower_first(text)
	elif t["error"]:
		text += "  ·  didn't work"
	(t["label"] as Label).text = text
	(t["label"] as Label).modulate.a = 0.75 if t["done"] else 1.0
	if not t["done"]:
		# The step itself says what; the orb line only says it's on it.
		_work_label.text = "Working"


static func _tool_icon(tool_name: String) -> String:
	match tool_name:
		"Bash", "PowerShell", "BashOutput", "KillShell":
			return "terminal"
		"Read", "NotebookRead":
			return "document"
		"Edit", "MultiEdit", "Write", "NotebookEdit":
			return "edit"
		"Glob", "Grep", "LS":
			return "search"
		"WebFetch", "WebSearch":
			return "globe"
		"TodoWrite":
			return "check"
	return "sparkles"


## [what it does, what to] for a tool call, as it happens or once it's done.
static func _describe(tool_name: String, i: Dictionary, past: bool) -> Array[String]:
	match tool_name:
		"Bash", "PowerShell":
			if str(i.get("description", "")) != "":
				return [str(i["description"]).left(80), ""]
			return ["Ran" if past else "Running", _short(str(i.get("command", "a command")))]
		"Read":
			return ["Read" if past else "Reading", _rel(str(i.get("file_path", "")))]
		"Edit", "MultiEdit":
			return ["Edited" if past else "Editing", _rel(str(i.get("file_path", "")))]
		"Write":
			return ["Wrote" if past else "Writing", _rel(str(i.get("file_path", "")))]
		"Glob":
			return ["Looked for" if past else "Looking for", str(i.get("pattern", "files"))]
		"Grep":
			return ["Searched for" if past else "Searching for", str(i.get("pattern", ""))]
		"LS":
			return ["Listed" if past else "Listing", _rel(str(i.get("path", "")))]
		"WebFetch":
			return ["Read" if past else "Reading", str(i.get("url", "")).trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)]
		"WebSearch":
			return ["Searched the web for" if past else "Searching the web for", str(i.get("query", ""))]
		"TodoWrite":
			return ["Made a plan" if past else "Planning", ""]
		"Task", "Agent":
			return [str(i.get("description", "Ran a helper")).left(80), ""]
	return ["Used " + tool_name if past else "Using " + tool_name, ""]


static func _short(s: String) -> String:
	s = s.replace("\n", " ").strip_edges()
	return s.left(70) + ("…" if s.length() > 70 else "")


## A path as you'd say it: from your home folder when it's in there.
static func _rel(p: String) -> String:
	var path := p.replace("\\", "/")
	var h := ClaudeCli.home()
	if h != "" and path.to_lower().begins_with(h.to_lower() + "/"):
		path = "~/" + path.substr(h.length() + 1)
	if path.length() > 48:
		path = "…/" + path.get_file()
	return path


## Claude wants to do something: a card with what, and Allow / Deny.
func _ask(id: String, req: Dictionary) -> void:
	var tool_name := str(req.get("tool_name", ""))
	var input: Dictionary = req.get("input", {}) if req.get("input") is Dictionary else {}
	if bool(Settings.get_value("claude_auto_allow")):
		# Allow all: no card, the step just carries on.
		if not mock:
			_cli.answer(id, true, input)
		return
	var title := "Allow Claude to use %s?" % tool_name
	var detail := ""
	match tool_name:
		"Bash", "PowerShell":
			title = "Allow Claude to run a command?"
			detail = str(input.get("command", ""))
			if str(input.get("description", "")) != "":
				title = "Allow Claude to %s?" % _lower_first(str(input["description"]))
		"Edit", "MultiEdit":
			title = "Allow Claude to edit %s?" % str(input.get("file_path", "")).replace("\\", "/").get_file()
			detail = _rel(str(input.get("file_path", "")))
		"Write":
			var p := str(input.get("file_path", "")).replace("\\", "/")
			title = "Allow Claude to %s %s?" % ["overwrite" if FileAccess.file_exists(p) else "create", p.get_file()]
			detail = _rel(p)
		"NotebookEdit":
			title = "Allow Claude to edit a notebook?"
			detail = _rel(str(input.get("notebook_path", "")))
		"WebFetch":
			title = "Allow Claude to open a web page?"
			detail = str(input.get("url", ""))
		"WebSearch":
			title = "Allow Claude to search the web?"
			detail = str(input.get("query", ""))
		_:
			var json := JSON.stringify(input)
			detail = json.left(240)
	var lines := detail.split("\n")
	if lines.size() > 6:
		detail = "\n".join(lines.slice(0, 6)) + "\n…"
	detail = detail.left(600)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.06), 16, Color(1, 1, 1, 0.1), 1, 15, 13))
	var v := Kit.vbox(11)
	card.add_child(v)
	var head := Kit.hbox(9)
	v.add_child(head)
	var ic := Kit.icon_rect("shield", 16, Color(App.accent, 0.95))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(ic)
	var t := Kit.label(title, 14, 600, App.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if detail != "":
		var d := PanelContainer.new()
		d.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.24), 10, Color(0, 0, 0, 0), 1, 11, 8))
		var dl := Label.new()
		dl.text = detail
		dl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		dl.add_theme_font_override("font", Kit.mono_font())
		dl.add_theme_font_size_override("font_size", 12)
		dl.add_theme_color_override("font_color", Color("cdd3de"))
		d.add_child(dl)
		v.add_child(d)
	var buttons := Kit.hbox(8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(buttons)
	var deny := FxButton.make("Deny", "", FxButton.Style.GHOST, 34)
	deny.focus_mode = Control.FOCUS_NONE
	deny.add_theme_font_size_override("font_size", 14)
	deny.pressed.connect(func() -> void: _answer(id, false))
	buttons.add_child(deny)
	var allow := FxButton.make("Allow", "", FxButton.Style.PRIMARY, 34)
	allow.focus_mode = Control.FOCUS_NONE
	allow.add_theme_font_size_override("font_size", 14)
	allow.pressed.connect(func() -> void: _answer(id, true))
	buttons.add_child(allow)
	card.set_meta("input", input)
	card.set_meta("tool_use_id", str(req.get("tool_use_id", "")))
	_asks[id] = card
	_add(card)
	_blob.asking()
	_follow = true
	card.modulate.a = 0.0
	Kit.hover_tween(card).tween_property(card, "modulate:a", 1.0, 0.22)
	_sync_working()
	if not is_open:
		needs_you.emit("ask")


func _answer(id: String, allow: bool) -> void:
	if not _asks.has(id):
		return
	var card: Control = _asks[id]
	_asks.erase(id)
	if not mock:
		_cli.answer(id, allow, card.get_meta("input", {}))
	var row: Dictionary = _tools.get(str(card.get_meta("tool_use_id", "")), {})
	if not row.is_empty() and not allow:
		row["denied"] = true
		_sync_tool(row)
	card.queue_free()
	_blob.answered(allow)
	_sync_working()
	_prompt.grab_focus()


static func _lower_first(s: String) -> String:
	s = s.strip_edges().trim_suffix(".")
	return s.left(1).to_lower() + s.substr(1) if s != "" else s


func _notice(title: String, detail: String, action: String = "", cb: Callable = Callable()) -> void:
	_blob.oops()
	var row := Kit.hbox(11)
	var ic := Kit.icon_rect("alert", 16, Color(App.WARNING, 0.9))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var v := Kit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(Kit.label(title, 14, 600, App.TEXT))
	if detail != "":
		var d := Kit.label(detail.left(400), 13, 500, App.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	if action != "":
		var b := FxButton.make(action, "", FxButton.Style.GHOST, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(cb)
		v.add_child(Kit.spacer(0, 4))
		v.add_child(b)
	_add(row)


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
