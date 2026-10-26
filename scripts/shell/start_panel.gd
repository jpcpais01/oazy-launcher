class_name StartPanel
extends Control
## Start: search everything as you type, pinned apps, what you played last,
## every installed app, your folders, and power options. Rises from the orb.

signal visibility_changed_to(open: bool)

const W := 900.0
const H := 700.0
const COLS := 6
const WEB_SEARCH := "https://www.google.com/search?q="

var main: Node
var is_open := false
var _glass: GlassPanel
var _root: VBoxContainer
var _search: LineEdit
var _home: Control
var _all: Control
var _results: Control
var _pinned: GridContainer
var _favs: GridContainer
var _fav_title: Label
var _recent: HBoxContainer
var _recent_title: Label
var _all_list: VBoxContainer
var _result_list: VBoxContainer
var _rows: Array[Control] = []
var _sel := 0
var _tween: Tween
var _menu: PopupMenu
var _menu_ref := ""
var _power: PopupMenu
var _user_name: Label
var _avatar_letter: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(W, H)
	_glass = GlassPanel.new(true, 26.0, GlassPanel.TINT_POPUP)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.set_shadow_strength(0.45, 38, 10.0)
	add_child(_glass)

	var root := Kit.vbox(18)
	_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 26
	root.offset_right = -26
	root.offset_top = 24
	root.offset_bottom = -22
	add_child(root)

	_search = LineEdit.new()
	_search.placeholder_text = "Search apps, games and the web"
	_search.custom_minimum_size.y = 52
	_search.right_icon = Icons.tex("search", 20, Color(1, 1, 1, 0.6))
	_search.add_theme_font_size_override("font_size", 17)
	_search.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.08), 999, Color(1, 1, 1, 0.1), 1, 22, 12))
	_search.add_theme_stylebox_override("focus", Kit.box(Color(1, 1, 1, 0.11), 999, Color(App.accent, 0.7), 1, 22, 12))
	_search.text_changed.connect(_on_text)
	_search.gui_input.connect(_on_search_key)
	root.add_child(_search)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	_home = _build_home()
	stack.add_child(_home)
	_all = _build_all()
	stack.add_child(_all)
	_results = _build_results()
	stack.add_child(_results)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_power = PopupMenu.new()
	_power.id_pressed.connect(_on_power)
	add_child(_power)

	Catalog.pins_changed.connect(func() -> void:
		if is_open:
			_fill_pinned()
	)
	Catalog.favorites_changed.connect(func() -> void:
		if is_open:
			_fill_pinned()
	)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "user_name":
			_sync_user()
	)
	var surface := Shell.surface_of(self)
	if surface:
		# Its own layer in shell mode: clicking any other window closes it.
		surface.focus_exited.connect(func() -> void:
			# Opening one of Start's own menus can blink focus too; only close
			# if focus is still elsewhere a moment later.
			await get_tree().create_timer(0.15).timeout
			if is_open and not surface.has_focus() and not surface.just_shown(400) and not _menu.visible and not _power.visible:
				close()
		)


func shell_shape() -> Array[Rect2]:
	return [_glass.shadow_rect()]


# --- Views ------------------------------------------------------------------------------

func _build_home() -> Control:
	var view := Kit.hbox(26)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := Kit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(left)
	_fav_title = _section_title("Favourites")
	left.add_child(_fav_title)
	_favs = GridContainer.new()
	_favs.columns = COLS
	_favs.add_theme_constant_override("h_separation", 4)
	left.add_child(_favs)
	var head := Kit.hbox(8)
	left.add_child(head)
	head.add_child(_section_title("Pinned"))
	head.add_child(Kit.spacer(0, 0, true))
	var all_btn := FxButton.make("All apps", "chevron_right", FxButton.Style.GHOST, 34)
	all_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	all_btn.add_theme_font_size_override("font_size", 14)
	all_btn.focus_mode = Control.FOCUS_NONE
	all_btn.pressed.connect(func() -> void: _show_view(_all))
	head.add_child(all_btn)
	_pinned = GridContainer.new()
	_pinned.columns = COLS
	_pinned.add_theme_constant_override("h_separation", 4)
	_pinned.add_theme_constant_override("v_separation", 4)
	left.add_child(_pinned)
	left.add_child(Kit.spacer(0, 0, true))
	_recent_title = _section_title("Jump back in")
	left.add_child(_recent_title)
	_recent = Kit.hbox(14)
	_recent.custom_minimum_size.y = 150
	left.add_child(_recent)

	var right := Kit.vbox(4)
	right.custom_minimum_size.x = 188
	view.add_child(right)
	var user := Kit.hbox(12)
	user.custom_minimum_size.y = 56
	right.add_child(user)
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(42, 42)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.add_theme_stylebox_override("panel", Kit.box(Color(App.accent, 0.35), 999, Color(1, 1, 1, 0.3), 1))
	_avatar_letter = Kit.label("", 18, 700, Color.WHITE, true)
	_avatar_letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(_avatar_letter)
	user.add_child(avatar)
	_user_name = Kit.label("", 16, 700, Color.WHITE)
	_user_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_user_name.clip_text = true
	_user_name.custom_minimum_size.x = 120
	_user_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	user.add_child(_user_name)
	right.add_child(Kit.spacer(0, 6))
	right.add_child(_place("Library", "grid", func() -> void: _run(func() -> void: main.open_app(&"library"))))
	right.add_child(_place("File Explorer", "folder", func() -> void: _run(func() -> void: _open_folder(""))))
	right.add_child(_place("Downloads", "downloads", func() -> void: _run(func() -> void: _open_folder(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)))))
	right.add_child(_place("Documents", "document", func() -> void: _run(func() -> void: _open_folder(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)))))
	right.add_child(_place("Pictures", "image", func() -> void: _run(func() -> void: _open_folder(OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)))))
	right.add_child(_place("Settings", "settings", func() -> void: _run(func() -> void: main.open_app(&"settings"))))
	right.add_child(_place("What's new", "sparkles", func() -> void: _run(func() -> void: main.show_patch_notes())))
	right.add_child(Kit.spacer(0, 0, true))
	var power := FxButton.make("Power", "power", FxButton.Style.GHOST, 42)
	power.focus_mode = Control.FOCUS_NONE
	power.pressed.connect(func() -> void: _open_power(power))
	right.add_child(power)
	return view


func _build_all() -> Control:
	var view := Kit.vbox(10)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	var head := Kit.hbox(8)
	view.add_child(head)
	var back := FxButton.make("Back", "chevron_left", FxButton.Style.GHOST, 34)
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 14)
	back.pressed.connect(func() -> void: _show_view(_home))
	head.add_child(back)
	head.add_child(Kit.spacer(0, 0, true))
	head.add_child(_section_title("All apps"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)
	_all_list = Kit.vbox(2)
	_all_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_all_list)
	return view


func _build_results() -> Control:
	var view := Kit.vbox(10)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_child(_section_title("Best matches"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)
	_result_list = Kit.vbox(2)
	_result_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_result_list)
	return view


func _section_title(text: String) -> Label:
	return Kit.label(text, 15, 700, App.TEXT_DIM)


func _place(text: String, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.tex(icon_name, 18, Color(1, 1, 1, 0.85))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 40
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Kit.font(500))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("h_separation", 12)
	b.add_theme_stylebox_override("normal", Kit.empty(12, 6))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.09), 12, Color(0, 0, 0, 0), 0, 12, 6))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 12, Color(0, 0, 0, 0), 0, 12, 6))
	b.add_theme_color_override("font_color", App.TEXT)
	b.pressed.connect(cb)
	return b


## A clickable tile (icon over name) for Pinned.
func _tile(ref: String) -> Control:
	var it := Catalog.item(ref)
	var b := Button.new()
	b.custom_minimum_size = Vector2(104, 100)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(it["name"])
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.09), 14, Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 14))
	var col := Kit.vbox(8)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(col)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(46, 46)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	col.add_child(ic)
	var l := Kit.label(str(it["name"]), 13, 500, App.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 96
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(l)
	b.pressed.connect(func() -> void: _launch(ref))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_show_menu(ref, b.get_global_mouse_position())
	)
	return b


## A row (icon, name, kind) for All apps and search results.
func _row(it: Dictionary, sub: String = "") -> Button:
	var ref := str(it["ref"])
	var b := Button.new()
	b.custom_minimum_size.y = 50
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.08), 12))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 12))
	b.set_meta("ref", ref)
	var row := Kit.hbox(14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	b.add_child(row)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(32, 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	row.add_child(ic)
	var name := Kit.label(str(it["name"]), 15, 600, App.TEXT)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	var kind := sub if sub != "" else _kind_label(it)
	if kind != "":
		var k := Kit.label(kind, 13, 500, App.TEXT_MUTE)
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(k)
	b.pressed.connect(func() -> void: _launch(ref))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_show_menu(ref, b.get_global_mouse_position())
	)
	return b


func _kind_label(it: Dictionary) -> String:
	match str(it.get("kind", "")):
		"game":
			return "Game  ·  " + str(it.get("sub", ""))
		"oazy":
			return "Oazy"
		"libapp":
			return "App"
	return ""


# --- Fill -----------------------------------------------------------------------------------

func _fill_pinned() -> void:
	for c in _favs.get_children():
		c.queue_free()
	var favs := Catalog.favorites().slice(0, COLS)
	_fav_title.visible = not favs.is_empty()
	_favs.visible = not favs.is_empty()
	for ref in favs:
		_favs.add_child(_tile(ref))
	# Favourites take a row, so Pinned gives one up.
	var rows := 2 if not favs.is_empty() else 3
	for c in _pinned.get_children():
		c.queue_free()
	var refs: Array[String] = []
	for ref in Catalog.pins():
		refs.append(ref)
	# Pad with recently used apps so Start never looks empty.
	for ref in Catalog.recent_apps():
		if refs.size() >= COLS * rows:
			break
		if not refs.has(ref):
			refs.append(ref)
	for ref in ["oazy:library", "oazy:settings"]:
		if not refs.has(ref):
			refs.append(ref)
	for ref in refs.slice(0, COLS * rows):
		_pinned.add_child(_tile(ref))


func _fill_recent() -> void:
	for c in _recent.get_children():
		c.queue_free()
	var games: Array[Dictionary] = []
	for e in Library.recent():
		if e["kind"] == "game":
			games.append(e)
	_recent_title.visible = not games.is_empty()
	_recent.visible = not games.is_empty()
	for e in games.slice(0, 6):
		var id := str(e["id"])
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(94, 141)
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		holder.tooltip_text = str(e["name"])
		var cover := CoverArt.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(cover)
		cover.setup(id, 12.0)
		holder.pivot_offset = Vector2(47, 70)
		holder.mouse_entered.connect(func() -> void:
			cover.sweep()
			var t := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(holder, "scale", Vector2.ONE * 1.06, 0.3)
			t.tween_property(cover, "focus_amount", 1.0, 0.25)
		)
		holder.mouse_exited.connect(func() -> void:
			var t := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			t.tween_property(holder, "scale", Vector2.ONE, 0.3)
			t.tween_property(cover, "focus_amount", 0.0, 0.25)
		)
		holder.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_launch("lib:" + id)
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				_show_menu("lib:" + id, holder.get_global_mouse_position())
		)
		_recent.add_child(holder)


func _fill_all() -> void:
	for c in _all_list.get_children():
		c.queue_free()
	var letter := ""
	for it in Catalog.all_items():
		var first := str(it["name"]).substr(0, 1).to_upper()
		if not first.is_valid_identifier() or first.is_valid_int():
			first = "#"
		if first != letter:
			letter = first
			var l := Kit.label(letter, 14, 700, App.accent.lightened(0.3), true)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", 14)
			m.add_theme_constant_override("margin_top", 8)
			m.add_child(l)
			_all_list.add_child(m)
		_all_list.add_child(_row(it))


func _sync_user() -> void:
	var name := str(Settings.get_value("user_name")).strip_edges()
	if name == "":
		name = App.user_name()
	if name == "":
		name = "You"
	_user_name.text = name
	_avatar_letter.text = name.substr(0, 1).to_upper()


# --- Open / close -------------------------------------------------------------------------

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open(text: String = "") -> void:
	if is_open:
		if text != "":
			_search.text = text
			_search.caret_column = text.length()
			_on_text(text)
		return
	is_open = true
	_sync_user()
	_fill_pinned()
	_fill_recent()
	_search.text = text
	_show_view(_home)
	if text != "":
		_on_text(text)
	_place_panel()
	visible = true
	pivot_offset = Vector2(0, size.y)
	modulate.a = 0.0
	scale = Vector2.ONE * 0.96
	var target_y := position.y
	position.y += 26.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.4)
	_tween.tween_property(self, "position:y", target_y, 0.4)
	Sfx.play(&"open")
	Shell.focus(self)
	_search.grab_focus()
	_search.caret_column = _search.text.length()
	visibility_changed_to.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_search.release_focus()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	_tween.tween_property(self, "position:y", position.y + 16.0, 0.14)
	_tween.chain().tween_callback(func() -> void: visible = false)
	visibility_changed_to.emit(false)


func _place_panel() -> void:
	var vp := Shell.view_size()
	# Never narrower than what's inside (long names, big text), or the side
	# column spills out of the glass.
	var need := _root.get_combined_minimum_size() + Vector2(52.0, 46.0)
	size = Vector2(minf(maxf(W, need.x), vp.x - 20.0), minf(maxf(H, need.y), vp.y - Taskbar.RESERVE - Taskbar.MARGIN - 10.0))
	position = Vector2(Taskbar.MARGIN, vp.y - Taskbar.RESERVE - 4.0 - size.y)


func _show_view(v: Control) -> void:
	for view in [_home, _all, _results]:
		view.visible = view == v
	if v == _all and _all_list.get_child_count() == 0:
		_fill_all()
	if v == _all or v == _home:
		_rows.clear()


# --- Search ----------------------------------------------------------------------------------

func _on_text(text: String) -> void:
	var q := text.strip_edges()
	if q == "":
		_show_view(_home)
		return
	_show_view(_results)
	for c in _result_list.get_children():
		c.queue_free()
	_rows.clear()
	var found: Array[Dictionary] = QuickAnswers.top(q)
	var cmds := QuickAnswers.commands(q)
	# An exact command ("lock", "wifi") beats apps; the rest follow them.
	while not cmds.is_empty() and int(cmds[0]["score"]) >= 90:
		found.append(cmds.pop_front())
	found.append_array(Catalog.search(q, 12 - found.size()))
	found.append_array(cmds)
	for it in found:
		var r := _row(it, str(it.get("sub", "")) if QuickAnswers.owns(str(it["ref"])) else "")
		_result_list.add_child(r)
		_rows.append(r)
	var web := _row({"ref": "web:" + q, "name": "Search the web for “%s”" % q, "kind": "oazy", "glyph": "globe"}, "Web")
	_result_list.add_child(web)
	_rows.append(web)
	_sel = 0
	_highlight()


func _highlight() -> void:
	for i in _rows.size():
		var r: Button = _rows[i]
		if i == _sel:
			r.add_theme_stylebox_override("normal", Kit.box(Color(App.accent, 0.2), 12, Color(App.accent, 0.45), 1))
		else:
			r.add_theme_stylebox_override("normal", Kit.empty())


func _on_search_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k: InputEventKey = event
	if k.keycode == KEY_DOWN and not _rows.is_empty():
		_sel = mini(_sel + 1, _rows.size() - 1)
		_highlight()
		_search.accept_event()
	elif k.keycode == KEY_UP and not _rows.is_empty():
		_sel = maxi(_sel - 1, 0)
		_highlight()
		_search.accept_event()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		if not _rows.is_empty():
			_launch(str(_rows[_sel].get_meta("ref")))
		_search.accept_event()
	elif k.keycode == KEY_ESCAPE:
		close()
		_search.accept_event()


## Typing that reached another of Oazy's windows while Start is open (shell
## mode, when Windows kept focus elsewhere) still goes into the search.
func forward_key(k: InputEventKey) -> void:
	if k.keycode == KEY_BACKSPACE:
		if _search.text != "":
			_search.text = _search.text.substr(0, _search.text.length() - 1)
			_search.caret_column = _search.text.length()
			_on_text(_search.text)
	elif k.unicode >= 32 and not k.ctrl_pressed and not k.alt_pressed:
		_search.text += char(k.unicode)
		_search.caret_column = _search.text.length()
		_on_text(_search.text)
	else:
		_on_search_key(k)


# --- Actions -----------------------------------------------------------------------------------

func _launch(ref: String) -> void:
	if ref.begins_with("web:"):
		OS.shell_open(WEB_SEARCH + ref.substr(4).uri_encode())
	elif QuickAnswers.owns(ref):
		close()
		QuickAnswers.run(ref, main)
		Sfx.play(&"select")
		return
	else:
		Catalog.launch(ref)
		if main and main.taskbar:
			var btn: TaskbarButton = main.taskbar.button_for(ref)
			if btn and btn.window_count() == 0 and not ref.begins_with("oazy:") and Catalog.item(ref)["kind"] != "game":
				btn.start_launching()
	Sfx.play(&"select")
	close()


func _run(cb: Callable) -> void:
	close()
	cb.call()


func _open_folder(path: String) -> void:
	if not App.is_windows():
		if path != "":
			OS.shell_open(path)
		return
	if path == "":
		OS.create_process("explorer.exe", [])
	else:
		OS.create_process("explorer.exe", [path.replace("/", "\\")])


func _show_menu(ref: String, at: Vector2) -> void:
	if QuickAnswers.owns(ref) or ref.begins_with("web:"):
		return
	_menu_ref = ref
	_menu.clear()
	_menu.add_icon_item(Icons.tex("play", 18), "Open", 0)
	main.add_favorite_item(_menu, ref, 3)
	var pinned := Catalog.is_pinned(ref)
	_menu.add_icon_item(Icons.tex("unpin" if pinned else "pin", 18), "Unpin from taskbar" if pinned else "Pin to taskbar", 1)
	if ref.begins_with("lib:"):
		_menu.add_icon_item(Icons.tex("info", 18), "Details", 2)
	_menu.reset_size()
	_menu.position = Vector2i(at)
	Shell.popup(_menu)


func _on_menu(id: int) -> void:
	match id:
		0:
			_launch(_menu_ref)
		1:
			Catalog.set_pinned(_menu_ref, not Catalog.is_pinned(_menu_ref))
		2:
			close()
			main.focus_entry(_menu_ref.substr(4))
		3:
			main.toggle_favorite(_menu_ref)


func _open_power(btn: Control) -> void:
	_power.clear()
	_power.add_icon_item(Icons.tex("lock", 18), "Lock", 0)
	_power.add_icon_item(Icons.tex("moon", 18), "Sleep", 1)
	_power.add_icon_item(Icons.tex("restart", 18), "Restart", 2)
	_power.add_icon_item(Icons.tex("power", 18), "Shut down", 3)
	_power.add_separator()
	_power.add_icon_item(Icons.tex("close", 18), "Close Oazy", 4)
	_power.reset_size()
	var r := btn.get_global_rect()
	_power.position = Vector2i(int(r.position.x), int(r.position.y - _power.size.y - 8))
	Shell.popup(_power)


func _on_power(id: int) -> void:
	close()
	match id:
		0:
			Host.lock_pc()
		1:
			Host.sleep_pc()
		2:
			main.confirm_power("restart")
		3:
			main.confirm_power("shutdown")
		4:
			main.quit()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if _menu.visible or _power.visible:
			return
		var over_orb: bool = main != null and main.taskbar.orb.get_global_rect().has_point(event.position)
		if not get_global_rect().has_point(event.position) and not over_orb:
			close()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
