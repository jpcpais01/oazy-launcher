class_name LibraryPage
extends Control
## Everything in one grid: filters, instant search, sorting and quick play.

const SIDE := 64.0
const GAP_X := 26.0
const GAP_Y := 30.0

var main: Node
var _filter := "all"
var _sort := "recent"
var _chips := {}
var _search: LineEdit
var _sort_btn: FxButton
var _count: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: Label
var _cards: Array[LibraryCard] = []
var _dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root := Kit.vbox(22)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = SIDE
	root.offset_right = -SIDE
	root.offset_top = 18
	add_child(root)

	var head := Kit.hbox(16)
	root.add_child(head)
	var title := Kit.label("Library", 44, 800, Color.WHITE, true)
	head.add_child(title)
	_count = Kit.label("", 17, 600, App.TEXT_MUTE)
	_count.size_flags_vertical = Control.SIZE_SHRINK_END
	_count.custom_minimum_size.y = 40
	head.add_child(_count)
	head.add_child(Kit.spacer(0, 0, true))
	_search = LineEdit.new()
	_search.placeholder_text = "Search your library"
	_search.custom_minimum_size = Vector2(320, 46)
	_search.right_icon = Icons.tex("search", 18, Color(1, 1, 1, 0.5))
	_search.clear_button_enabled = true
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.text_changed.connect(func(_t: String) -> void: refresh(false))
	head.add_child(_search)
	_sort_btn = FxButton.make("Recent", "sort", FxButton.Style.GHOST, 46)
	_sort_btn.tooltip_text = "Change sort order"
	_sort_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sort_btn.pressed.connect(_cycle_sort)
	head.add_child(_sort_btn)
	var add := FxButton.make("Add", "plus", FxButton.Style.PRIMARY, 46)
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: main.open_add({}))
	head.add_child(add)

	var chips := Kit.hbox(10)
	root.add_child(chips)
	for spec in [["all", "All"], ["games", "Games"], ["apps", "Apps"], ["favorites", "Favourites"]]:
		var c := FxButton.make(spec[1], "", FxButton.Style.CHIP, 38)
		c.pressed.connect(func() -> void: _set_filter(spec[0]))
		chips.add_child(c)
		_chips[spec[0]] = c
	_set_filter("all", false)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	root.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 48)
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	_scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(GAP_X))
	_grid.add_theme_constant_override("v_separation", int(GAP_Y))
	pad.add_child(_grid)

	_empty = Kit.label("", 18, 500, App.TEXT_DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty.visible = false
	add_child(_empty)

	_scroll.resized.connect(_update_columns)
	Library.changed.connect(func() -> void:
		_dirty = true
		if is_visible_in_tree():
			refresh(false)
	)


func on_shown() -> void:
	refresh(true)


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


func refresh(animate: bool) -> void:
	_dirty = false
	for c in _cards:
		c.queue_free()
	_cards.clear()
	var list := Library.query(_filter, _search.text, _sort)
	for i in list.size():
		var card := LibraryCard.new().setup(str(list[i]["id"]))
		card.open.connect(func(id: String) -> void: main.focus_entry(id))
		card.play.connect(func(id: String) -> void: main.launch(id))
		card.context.connect(func(id: String, at: Vector2) -> void: main.show_entry_menu(id, at))
		_grid.add_child(card)
		_cards.append(card)
		if animate:
			card.intro(0.025 * mini(i, 24))
	var total := Library.entries.size()
	_count.text = "%d %s" % [total, "item" if total == 1 else "items"]
	_empty.visible = list.is_empty()
	if list.is_empty():
		if total == 0:
			_empty.text = "Your library is empty.\nAdd a game or scan this PC from the Home screen."
		elif _search.text.strip_edges() != "":
			_empty.text = "Nothing matches “%s”." % _search.text.strip_edges()
		else:
			_empty.text = "Nothing here yet."
	_update_columns()


func _update_columns() -> void:
	var w := _scroll.size.x - 12.0
	_grid.columns = maxi(1, int((w + GAP_X) / (LibraryCard.W + GAP_X)))


func _set_filter(f: String, refresh_now: bool = true) -> void:
	_filter = f
	for key in _chips.keys():
		var c: FxButton = _chips[key]
		c.selected = key == f
	if refresh_now:
		refresh(true)


func _cycle_sort() -> void:
	var order := ["recent", "name", "playtime"]
	_sort = order[(order.find(_sort) + 1) % order.size()]
	_sort_btn.text = {"recent": "Recent", "name": "A–Z", "playtime": "Most played"}[_sort]
	refresh(true)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or main == null or main.modal_open():
		return
	if event.is_action_pressed("ui_down") and get_viewport().gui_get_focus_owner() == null and not _cards.is_empty():
		_cards[0].grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.unicode > 32 and get_viewport().gui_get_focus_owner() == null:
		# Type anywhere to search.
		_search.grab_focus()
		_search.text += char(event.unicode)
		_search.caret_column = _search.text.length()
		refresh(false)
		get_viewport().set_input_as_handled()
