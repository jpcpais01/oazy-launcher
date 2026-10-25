class_name LibraryApp
extends Control
## The Library window: every game and app with filters, instant search and
## sorting, plus a details page for each game.

const GAP_X := 22.0
const GAP_Y := 26.0

var main: Node
var _filter := "all"
var _sort := "recent"
var _filters := {}
var _search: LineEdit
var _sort_btn: FxButton
var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: Label
var _cards: Array[LibraryCard] = []
var _grid_view: Control
var _detail: GameDetail


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var split := Kit.hbox(0)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	# Sidebar.
	var side_bg := PanelContainer.new()
	side_bg.custom_minimum_size.x = 214
	side_bg.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.12), 0, Color(0, 0, 0, 0), 0, 14, 18))
	split.add_child(side_bg)
	var side := Kit.vbox(4)
	side_bg.add_child(side)
	var title := Kit.label("Library", 26, 800, Color.WHITE, true)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 10)
	tm.add_theme_constant_override("margin_bottom", 10)
	tm.add_child(title)
	side.add_child(tm)
	for spec in [["all", "Everything", "layers"], ["games", "Games", "gamepad"], ["apps", "Apps", "app"], ["favorites", "Favourites", "heart"]]:
		var b := _side_button(spec[1], spec[2])
		b.pressed.connect(func() -> void: set_filter(spec[0]))
		side.add_child(b)
		_filters[spec[0]] = b
	side.add_child(Kit.spacer(0, 0, true))
	var add := FxButton.make("Add", "plus", FxButton.Style.PRIMARY, 44)
	add.pressed.connect(func() -> void: main.open_add({}))
	side.add_child(add)
	side.add_child(Kit.spacer(0, 4))
	var scan := FxButton.make("Find games", "sparkles", FxButton.Style.GHOST, 44)
	scan.pressed.connect(func() -> void: main.scan_stores())
	side.add_child(scan)

	# Content: grid and details page share the space.
	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.clip_contents = true
	split.add_child(content)

	_grid_view = Kit.vbox(16)
	_grid_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid_view.offset_left = 26
	_grid_view.offset_right = -18
	_grid_view.offset_top = 20
	content.add_child(_grid_view)
	var head := Kit.hbox(12)
	_grid_view.add_child(head)
	_search = LineEdit.new()
	_search.placeholder_text = "Search your library"
	_search.custom_minimum_size = Vector2(0, 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.right_icon = Icons.tex("search", 18, Color(1, 1, 1, 0.5))
	_search.clear_button_enabled = true
	_search.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.06), 999, Color(1, 1, 1, 0.09), 1, 18, 10))
	_search.add_theme_stylebox_override("focus", Kit.box(Color(1, 1, 1, 0.09), 999, Color(App.accent, 0.6), 1, 18, 10))
	_search.text_changed.connect(func(_t: String) -> void: refresh(false))
	head.add_child(_search)
	_sort_btn = FxButton.make("Recent", "sort", FxButton.Style.GHOST, 44)
	_sort_btn.tooltip_text = "Change sort order"
	_sort_btn.pressed.connect(_cycle_sort)
	head.add_child(_sort_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_grid_view.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 28)
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	_scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(GAP_X))
	_grid.add_theme_constant_override("v_separation", int(GAP_Y))
	pad.add_child(_grid)

	_empty = Kit.label("", 17, 500, App.TEXT_DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty.visible = false
	content.add_child(_empty)

	_detail = GameDetail.new()
	_detail.main = main
	_detail.visible = false
	_detail.back.connect(show_grid)
	content.add_child(_detail)

	_scroll.resized.connect(_update_columns)
	Library.changed.connect(func() -> void:
		if _detail.visible and not Library.has_entry(_detail.entry_id):
			show_grid()
		refresh(false)
	)
	set_filter("all", false)
	refresh(true)


func _side_button(text: String, icon_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.tex(icon_name, 18, Color.WHITE)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 42
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Kit.font(600))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("h_separation", 12)
	return b


func set_filter(f: String, refresh_now: bool = true) -> void:
	_filter = f
	for key in _filters.keys():
		var b: Button = _filters[key]
		var on: bool = key == f
		b.add_theme_stylebox_override("normal", Kit.box(Color(App.accent, 0.2) if on else Color(0, 0, 0, 0), 12, Color(App.accent, 0.4) if on else Color(0, 0, 0, 0), 1, 12, 6))
		b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.1), 12, Color(0, 0, 0, 0), 0, 12, 6))
		b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 12, Color(0, 0, 0, 0), 0, 12, 6))
		b.add_theme_color_override("font_color", Color.WHITE if on else App.TEXT_DIM)
		b.add_theme_color_override("icon_normal_color", Color.WHITE if on else App.TEXT_DIM)
	if refresh_now:
		show_grid()
		refresh(true)


func refresh(animate: bool) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	var list := Library.query(_filter, _search.text, _sort)
	for i in list.size():
		var card := LibraryCard.new().setup(str(list[i]["id"]))
		card.open.connect(show_entry)
		card.play.connect(func(id: String) -> void: main.launch(id))
		card.context.connect(func(id: String, at: Vector2) -> void: main.show_entry_menu(id, at))
		_grid.add_child(card)
		_cards.append(card)
		if animate:
			card.intro(0.02 * mini(i, 24))
	_empty.visible = list.is_empty() and _grid_view.visible
	if list.is_empty():
		if Library.entries.is_empty():
			_empty.text = "Your library is empty.\nFind your games or add one with + Add."
		elif _search.text.strip_edges() != "":
			_empty.text = "Nothing matches “%s”." % _search.text.strip_edges()
		else:
			_empty.text = "Nothing here yet."
	_update_columns()


func _update_columns() -> void:
	var w := _scroll.size.x - 8.0 - 14.0
	if w <= 0.0:
		return
	var base := 172.0
	var cols := maxi(1, int((w + GAP_X) / (base + GAP_X)))
	_grid.columns = cols
	var card_w := floorf((w - GAP_X * (cols - 1)) / cols)
	for c in _cards:
		c.set_card_width(clampf(card_w, base * 0.85, base * 1.35))


func _cycle_sort() -> void:
	var order := ["recent", "name", "playtime"]
	_sort = order[(order.find(_sort) + 1) % order.size()]
	_sort_btn.text = {"recent": "Recent", "name": "A–Z", "playtime": "Most played"}[_sort]
	refresh(true)


func show_entry(id: String) -> void:
	if not Library.has_entry(id):
		return
	Sfx.play(&"select")
	_detail.show_entry(id)
	_detail.visible = true
	_empty.visible = false
	_detail.modulate.a = 0.0
	_detail.position.x = 40.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_detail, "modulate:a", 1.0, 0.3)
	t.tween_property(_detail, "position:x", 0.0, 0.45)
	t.tween_property(_grid_view, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(func() -> void: _grid_view.visible = false)


func show_grid() -> void:
	if _grid_view.visible and not _detail.visible:
		return
	_grid_view.visible = true
	_grid_view.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_grid_view, "modulate:a", 1.0, 0.3)
	t.tween_property(_detail, "modulate:a", 0.0, 0.15)
	t.chain().tween_callback(func() -> void: _detail.visible = false)


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


func card_count() -> int:
	return _cards.size()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or main == null or main.modal_open():
		return
	var win := get_parent()
	while win != null and not win is ShellWindow:
		win = win.get_parent()
	if win == null or not win.active or not _grid_view.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.unicode > 32 and get_viewport().gui_get_focus_owner() == null and not event.ctrl_pressed and not event.alt_pressed:
		# Type anywhere in the window to search.
		_search.grab_focus()
		_search.text += char(event.unicode)
		_search.caret_column = _search.text.length()
		refresh(false)
		get_viewport().set_input_as_handled()
