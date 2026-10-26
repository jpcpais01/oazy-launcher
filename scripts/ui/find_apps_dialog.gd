class_name FindAppsDialog
extends Modal
## "Find apps": every installed app that isn't in the library yet, with its
## icon. Tick the ones you want and they join the library with artwork.

const ROW_H := 52.0

var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _note: Label
var _count: Label
var _add: FxButton
var _rows: Array[Button] = []
var _picked := {}


func _init() -> void:
	width = 640.0


func _build() -> void:
	title_block("Find apps", "Pick the apps you want in your Library. They get a cover and sit next to your games.", "apps")

	_search = LineEdit.new()
	_search.placeholder_text = "Search installed apps"
	_search.custom_minimum_size = Vector2(0, 42)
	_search.right_icon = Icons.tex("search", 16, Color(1, 1, 1, 0.45))
	_search.clear_button_enabled = true
	_search.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.045), 999, Color(1, 1, 1, 0.07), 1, 18, 9))
	_search.add_theme_stylebox_override("focus", Kit.box(Color(1, 1, 1, 0.065), 999, Color(App.accent, 0.45), 1, 18, 9))
	_search.add_theme_font_size_override("font_size", 15)
	_search.text_changed.connect(func(_t: String) -> void: _filter())
	_search.text_submitted.connect(func(_t: String) -> void:
		# Enter picks the only match, so "spot", Enter, Enter adds Spotify.
		var shown := _rows.filter(func(r: Button) -> bool: return r.visible)
		if shown.size() == 1:
			_toggle(shown[0])
	)
	content.add_child(_search)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.025), 16, Color(1, 1, 1, 0.05), 1, 6, 6))
	content.add_child(frame)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 400
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_scroll)
	_list = Kit.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_note = Kit.label("", 15, 500, App.TEXT_DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(0, 400)
	_note.visible = false
	frame.add_child(_note)

	var row := Kit.hbox(12)
	content.add_child(row)
	_count = Kit.label("", 14, 500, App.TEXT_MUTE)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_count)
	var cancel := FxButton.make("Cancel", "", FxButton.Style.GHOST, 46)
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_add = FxButton.make("Add", "plus", FxButton.Style.PRIMARY, 46)
	_add.pressed.connect(_add_picked)
	row.add_child(_add)

	Catalog.apps_changed.connect(_fill)
	_fill()


func _focus_first() -> void:
	_search.grab_focus()


## Installed apps that aren't in the library yet (as an app, or as a game
## with the same name), by name.
static func candidates() -> Array[Dictionary]:
	var taken := Catalog.library_app_ids()
	var names := {}
	for e in Library.entries:
		names[Art.norm_title(str(e["name"]))] = true
	var out: Array[Dictionary] = []
	for a in Catalog.apps:
		if taken.has(str(a["id"]).to_lower()) or names.has(Art.norm_title(str(a["name"]))):
			continue
		out.append(a)
	return out


func _fill() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	var list := candidates()
	for a in list:
		var b := _row(a)
		_list.add_child(b)
		_rows.append(b)
	_note.visible = list.is_empty()
	_scroll.visible = not list.is_empty()
	if not App.is_windows() and Catalog.apps.is_empty():
		_note.text = "Finding apps works on Windows."
	elif not Catalog.apps_loaded:
		_note.text = "Reading your installed apps…"
	else:
		_note.text = "Every app you have is already in your Library."
	_filter()
	_sync()


func _row(a: Dictionary) -> Button:
	var id := str(a["id"])
	var b := Button.new()
	b.custom_minimum_size.y = ROW_H
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("id", id)
	b.set_meta("name", str(a["name"]).to_lower())
	b.add_theme_stylebox_override("normal", Kit.box(Color(0, 0, 0, 0), 12))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.05), 12))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.07), 12))
	b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 12, Color(App.accent, 0.5), 1))
	b.pressed.connect(_toggle.bind(b))

	var h := Kit.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon := AppIcon.new().set_item(Catalog.item("app:" + id))
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var name := Kit.label(str(a["name"]), 15, 500, App.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name)
	if Art.brand_art(str(a["name"]), &"cover") != "":
		var tag := Kit.label("Artwork", 12, 600, App.TEXT_MUTE)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.tooltip_text = "Oazy has its own cover for this app"
		h.add_child(tag)
	var tick := PanelContainer.new()
	tick.custom_minimum_size = Vector2(24, 24)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Kit.icon_rect("check", 14, Color.WHITE)
	mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tick.add_child(mark)
	h.add_child(tick)
	b.set_meta("tick", tick)
	_paint(b)
	return b


func _toggle(b: Button) -> void:
	var id := str(b.get_meta("id"))
	if _picked.has(id):
		_picked.erase(id)
	else:
		_picked[id] = true
	Sfx.play(&"move")
	_paint(b)
	_sync()


func _paint(b: Button) -> void:
	var on := _picked.has(str(b.get_meta("id")))
	var tick: PanelContainer = b.get_meta("tick")
	tick.add_theme_stylebox_override("panel", Kit.box(App.accent if on else Color(0, 0, 0, 0), 999, Color(0, 0, 0, 0) if on else Color(1, 1, 1, 0.22), 1))
	tick.get_child(0).visible = on


func _filter() -> void:
	var needle := _search.text.strip_edges().to_lower()
	var shown := 0
	for r in _rows:
		r.visible = needle == "" or str(r.get_meta("name")).contains(needle)
		if r.visible:
			shown += 1
	if not _rows.is_empty():
		_note.visible = shown == 0
		_scroll.visible = shown > 0
		if shown == 0:
			_note.text = "No installed app matches “%s”." % _search.text.strip_edges()


func _sync() -> void:
	var n := _picked.size()
	if n > 0:
		_count.text = "%d of %d selected" % [n, _rows.size()]
	else:
		_count.text = "%d apps not in your Library" % _rows.size() if not _rows.is_empty() else ""
	_add.text = "Add %d %s" % [n, "app" if n == 1 else "apps"] if n > 0 else "Add"
	_add.disabled = n == 0


func _add_picked() -> void:
	var added := 0
	# In the list's order, so they land in the library alphabetically.
	for r in _rows:
		var id := str(r.get_meta("id"))
		if _picked.has(id) and Catalog.add_to_library("app:" + id) != "":
			added += 1
	if added > 0:
		App.toast("Added %d %s to your Library" % [added, "app" if added == 1 else "apps"], &"success")
	close()
