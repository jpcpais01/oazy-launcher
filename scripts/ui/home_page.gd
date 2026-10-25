class_name HomePage
extends Control
## PS5-style home: a carousel of tiles up top, the focused game's artwork
## filling the screen and its details + Play button bottom-left.

const TILE := 112.0
const TILE_FOCUS := 158.0
const GAP := 16.0
const ROW_Y := 22.0
const LEFT := 64.0

var main: Node
var _tiles: Array[HomeTile] = []
var _index := 0
var _row: Control
var _row_name: Label
var _info: VBoxContainer
var _kicker: HBoxContainer
var _source_chip: Label
var _fav_badge: TextureRect
var _logo: TextureRect
var _title: Label
var _meta: Label
var _buttons: HBoxContainer
var _play: FxButton
var _fav_btn: FxButton
var _more_btn: FxButton
var _empty: VBoxContainer
var _scan_btn: FxButton
var _hints: Label
var _hero_timer: Timer
var _order_dirty := false
var _first_build := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)

	_row_name = Kit.label("", 15, 600, App.TEXT)
	_row_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_row_name.add_theme_constant_override("shadow_offset_y", 1)
	_row_name.add_theme_constant_override("shadow_outline_size", 6)
	add_child(_row_name)

	_build_info()
	_build_empty()

	_hints = Kit.label("←  →  Browse      ↵  Play      F  Favourite      Tab  Library", 13, 500, Color(1, 1, 1, 0.38))
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints.offset_right = -48
	_hints.offset_bottom = -30
	add_child(_hints)

	_hero_timer = Timer.new()
	_hero_timer.one_shot = true
	_hero_timer.wait_time = 0.14
	_hero_timer.timeout.connect(_apply_hero)
	add_child(_hero_timer)

	Library.changed.connect(rebuild)
	Library.entry_changed.connect(_on_entry_changed)
	Library.launched.connect(func(_id: String) -> void: _order_dirty = true)
	Library.import_finished.connect(func(_a: int, _f: int) -> void: _sync_scan_button())
	Art.art_ready.connect(_on_art_ready)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "accent_mode" or key == "accent_color":
			_apply_accent()
	)
	resized.connect(func() -> void: _layout(true))
	rebuild()


func _build_info() -> void:
	_info = Kit.vbox(14)
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_left = LEFT
	_info.offset_bottom = -64
	_info.custom_minimum_size.x = 640
	add_child(_info)

	_kicker = Kit.hbox(10)
	_info.add_child(_kicker)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.12), 999, Color(1, 1, 1, 0.1), 1, 12, 4))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_chip = Kit.label("", 13, 700, Color(1, 1, 1, 0.92))
	chip.add_child(_source_chip)
	_kicker.add_child(chip)
	_fav_badge = Kit.icon_rect("heart_fill", 18, Color("ff6b8a"))
	_fav_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kicker.add_child(_fav_badge)

	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(_logo)

	_title = Kit.label("", 66, 800, Color.WHITE, true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 860
	_title.max_lines_visible = 2
	_title.add_theme_constant_override("line_spacing", -10)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.add_theme_constant_override("shadow_outline_size", 12)
	_info.add_child(_title)

	_meta = Kit.label("", 17, 500, Color(1, 1, 1, 0.78))
	_info.add_child(_meta)
	_info.add_child(Kit.spacer(0, 8))

	_buttons = Kit.hbox(12)
	_info.add_child(_buttons)
	_play = FxButton.make("Play", "play", FxButton.Style.PRIMARY, 56)
	_play.custom_minimum_size.x = 196
	_play.pressed.connect(activate)
	_buttons.add_child(_play)
	_fav_btn = FxButton.icon_only("heart", "Favourite", 22, 56)
	_fav_btn.variant = FxButton.Style.GHOST
	_fav_btn._apply_style()
	_fav_btn.pressed.connect(func() -> void:
		var id := current_id()
		if not id.begins_with("__"):
			Library.toggle_favorite(id)
	)
	_buttons.add_child(_fav_btn)
	_more_btn = FxButton.icon_only("more", "More options", 22, 56)
	_more_btn.variant = FxButton.Style.GHOST
	_more_btn._apply_style()
	_more_btn.pressed.connect(func() -> void:
		var id := current_id()
		if not id.begins_with("__"):
			main.show_entry_menu(id, _more_btn.global_position + Vector2(0, _more_btn.size.y + 8))
	)
	_buttons.add_child(_more_btn)


func _build_empty() -> void:
	_empty = Kit.vbox(18)
	_empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_empty.offset_left = LEFT + 8
	_empty.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_empty)
	var kicker := Kit.label("YOUR GAMES, ONE PLACE", 14, 700, Color(1, 1, 1, 0.6))
	var kv := FontVariation.new()
	kv.base_font = Kit.font(700)
	kv.spacing_glyph = 3
	kicker.add_theme_font_override("font", kv)
	_empty.add_child(kicker)
	_empty.add_child(Kit.label("Welcome to Oazy", 76, 800, Color.WHITE, true))
	var sub := Kit.label("Bring every game and app on this PC into one beautiful place.\nOazy can find your Steam, Epic Games and GOG installs in a second.", 19, 500, Color(1, 1, 1, 0.72))
	_empty.add_child(sub)
	_empty.add_child(Kit.spacer(0, 10))
	var row := Kit.hbox(12)
	_empty.add_child(row)
	_scan_btn = FxButton.make("Scan this PC for games", "sparkles", FxButton.Style.PRIMARY, 56)
	_scan_btn.pressed.connect(func() -> void: main.scan_stores())
	row.add_child(_scan_btn)
	var add := FxButton.make("Add manually", "plus", FxButton.Style.GHOST, 56)
	add.pressed.connect(func() -> void: main.open_add({}))
	row.add_child(add)
	var foot := Kit.label("Tip: you can also drop any .exe, shortcut or Steam link straight onto this window.", 14, 500, Color(1, 1, 1, 0.45))
	_empty.add_child(Kit.spacer(0, 4))
	_empty.add_child(foot)


# --- Data ---------------------------------------------------------------------------

func current_id() -> String:
	if _index >= 0 and _index < _tiles.size():
		return _tiles[_index].entry_id
	return ""


func rebuild() -> void:
	var keep := current_id()
	if _first_build:
		keep = str(Settings.get_value("last_selected"))
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	var ids: Array[String] = []
	for e in Library.recent():
		ids.append(str(e["id"]))
	ids.append("__add")
	if not Library.entries.is_empty():
		ids.append("__library")
	for id in ids:
		var tile := HomeTile.new().setup(id)
		tile.clicked.connect(_on_tile_clicked)
		tile.double_clicked.connect(_on_tile_double)
		tile.context.connect(_on_tile_context)
		_row.add_child(tile)
		_tiles.append(tile)
	_index = maxi(0, ids.find(keep))
	if keep == "" or not ids.has(keep):
		_index = 0
	var empty := Library.entries.is_empty()
	_empty.visible = empty
	_info.visible = not empty
	_row.visible = not empty
	_row_name.visible = not empty
	_hints.visible = not empty
	_sync_scan_button()
	_layout(true)
	for i in _tiles.size():
		_tiles[i].set_focused(i == _index)
		_tiles[i].refresh_dim()
	_update_info(false)
	_first_build = false
	_order_dirty = false


func on_shown() -> void:
	if _order_dirty:
		rebuild()


func intro() -> void:
	for i in _tiles.size():
		_tiles[i].intro(0.05 * mini(i, 10))
	var targets: Array[Control] = [_info, _row_name, _empty]
	for c in targets:
		if c.visible:
			var a := c.modulate.a
			c.modulate.a = 0.0
			var t := create_tween()
			t.tween_property(c, "modulate:a", maxf(a, 1.0), 0.8).set_delay(0.25)


func select_id(id: String) -> void:
	for i in _tiles.size():
		if _tiles[i].entry_id == id:
			_set_index(i, false)
			return


func move(delta: int) -> void:
	if _tiles.is_empty():
		return
	var target := clampi(_index + delta, 0, _tiles.size() - 1)
	if target == _index:
		_tiles[_index].bump(delta)
		return
	_set_index(target, true)


func _set_index(i: int, sound: bool) -> void:
	if i == _index and not _tiles.is_empty():
		_update_info(true)
		return
	_index = i
	if sound:
		Sfx.play(&"move")
	for k in _tiles.size():
		_tiles[k].set_focused(k == _index)
	_layout(false)
	_update_info(true)
	var id := current_id()
	if not id.begins_with("__"):
		Settings.set_value("last_selected", id)


func activate() -> void:
	var id := current_id()
	match id:
		"":
			return
		"__add":
			main.open_add({})
		"__library":
			main.go(&"library")
		_:
			main.launch(id)


# --- Layout & info ------------------------------------------------------------------

func _layout(instant: bool) -> void:
	if _tiles.is_empty():
		return
	var x_focus := LEFT + (TILE + GAP if _index > 0 else 0.0)
	var small_y := ROW_Y + (TILE_FOCUS - TILE) / 2.0
	for i in _tiles.size():
		var rect: Rect2
		var alpha := 1.0
		if i == _index:
			rect = Rect2(x_focus, ROW_Y, TILE_FOCUS, TILE_FOCUS)
		elif i < _index:
			var x := x_focus - float(_index - i) * (TILE + GAP)
			rect = Rect2(x, small_y, TILE, TILE)
			if x < LEFT - 1.0:
				alpha = 0.0
		else:
			var x2 := x_focus + TILE_FOCUS + GAP + float(i - _index - 1) * (TILE + GAP)
			rect = Rect2(x2, small_y, TILE, TILE)
			if x2 > size.x + 40.0:
				alpha = 0.0
		_tiles[i].move_to(rect, alpha, instant)
	_row_name.position = Vector2(x_focus, ROW_Y + TILE_FOCUS + 12.0)


func _update_info(animate: bool) -> void:
	var id := current_id()
	var e := Library.get_entry(id)
	_fav_btn.visible = not e.is_empty()
	_more_btn.visible = not e.is_empty()
	_fav_badge.visible = false
	_logo.visible = false
	_title.visible = true
	match id:
		"__add":
			_source_chip.text = "NEW"
			_title.text = "Add a game or app"
			_meta.text = "Pick any program or shortcut, or let Oazy scan for Steam, Epic and GOG games."
			_play.text = "Add"
			_play.set_icon_name("plus")
			_row_name.text = "Add"
		"__library":
			var games := 0
			for x in Library.entries:
				if x["kind"] == "game":
					games += 1
			_source_chip.text = "LIBRARY"
			_title.text = "Your library"
			_meta.text = "%d games  ·  %d apps" % [games, Library.entries.size() - games]
			_play.text = "Open library"
			_play.set_icon_name("grid")
			_row_name.text = "Library"
		_:
			if e.is_empty():
				return
			var is_game: bool = e["kind"] == "game"
			_source_chip.text = Library.source_label(e).to_upper()
			_fav_badge.visible = bool(e["favorite"])
			_title.text = str(e["name"])
			_row_name.text = str(e["name"])
			var parts := PackedStringArray()
			if is_game:
				parts.append(Fmt.playtime(int(e["playtime"])) if int(e["playtime"]) > 0 else ("Ready to play" if int(e["launches"]) == 0 else "Played %d times" % int(e["launches"])))
			else:
				parts.append("Opened %d times" % int(e["launches"]) if int(e["launches"]) > 0 else "Ready to open")
			if int(e["last_played"]) > 0:
				parts.append(("Last played " if is_game else "Last used ") + Fmt.ago(int(e["last_played"])).to_lower())
			_meta.text = "  ·  ".join(parts)
			_play.text = "Play" if is_game else "Open"
			_play.set_icon_name("play" if is_game else "external")
			_fav_btn.set_icon_name("heart_fill" if e["favorite"] else "heart", Color("ff6b8a") if e["favorite"] else Color.WHITE)
			_fav_btn.tooltip_text = "Remove from favourites" if e["favorite"] else "Add to favourites"
			_apply_logo(id)
	_apply_accent()
	_hero_timer.start()
	if animate:
		_info.pivot_offset = Vector2(0, _info.size.y)
		_info.modulate.a = 0.0
		_info.scale = Vector2.ONE * 0.985
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(_info, "modulate:a", 1.0, 0.45)
		t.tween_property(_info, "scale", Vector2.ONE, 0.6)
		_row_name.modulate.a = 0.0
		var t2 := create_tween()
		t2.tween_property(_row_name, "modulate:a", 1.0, 0.35).set_delay(0.12)


func _apply_logo(id: String) -> void:
	var tex := Art.get_art(id, &"logo")
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(560.0 / sz.x, 150.0 / sz.y)
	_logo.texture = tex
	_logo.custom_minimum_size = sz * s
	_logo.visible = true
	_title.visible = false


func _apply_accent() -> void:
	if str(Settings.get_value("accent_mode")) == "fixed":
		App.set_accent(Color(str(Settings.get_value("accent_color"))))
		return
	var e := Library.get_entry(current_id())
	var hex := str(e.get("color", ""))
	App.set_accent(Color(hex) if hex != "" else App.DEFAULT_ACCENT)


func _apply_hero() -> void:
	if main == null or not visible:
		return
	var id := current_id()
	main.backdrop.set_hero(null if id.begins_with("__") else Art.get_art(id, &"hero"))


func _sync_scan_button() -> void:
	if _scan_btn == null:
		return
	_scan_btn.disabled = Library.importing
	_scan_btn.text = "Scanning…" if Library.importing else "Scan this PC for games"


# --- Events ---------------------------------------------------------------------------

func _on_entry_changed(id: String) -> void:
	if id == current_id():
		_update_info(false)


func _on_art_ready(id: String, kind: StringName) -> void:
	if id != current_id():
		return
	if kind == &"hero":
		_apply_hero()
	elif kind == &"logo":
		_apply_logo(id)
	elif kind == &"cover":
		_apply_accent()


func _on_tile_clicked(tile: HomeTile) -> void:
	var i := _tiles.find(tile)
	if i >= 0:
		_set_index(i, true)
		if tile.is_special():
			activate()


func _on_tile_double(tile: HomeTile) -> void:
	var i := _tiles.find(tile)
	if i >= 0 and not tile.is_special():
		_set_index(i, false)
		activate()


func _on_tile_context(tile: HomeTile, at: Vector2) -> void:
	if not tile.is_special():
		_set_index(_tiles.find(tile), true)
		main.show_entry_menu(tile.entry_id, at)


func _buttons_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and _buttons.is_ancestor_of(f)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or main == null or main.modal_open():
		return
	if event.is_action_pressed("ui_up") and _buttons_focused():
		get_viewport().gui_release_focus()
		Sfx.play(&"move")
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or main == null or main.modal_open() or Library.entries.is_empty():
		return
	var in_row := not _buttons_focused()
	if in_row and event.is_action_pressed("ui_left", true):
		move(-1)
	elif in_row and event.is_action_pressed("ui_right", true):
		move(1)
	elif in_row and event.is_action_pressed("ui_accept"):
		activate()
	elif in_row and event.is_action_pressed("ui_down"):
		_play.grab_focus()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		var id := current_id()
		if not id.begins_with("__"):
			Library.toggle_favorite(id)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		var id2 := current_id()
		if not id2.begins_with("__"):
			main.confirm_remove(id2)
	elif event is InputEventMouseButton and event.pressed and get_local_mouse_position().y < ROW_Y + TILE_FOCUS + 50.0:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			move(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			move(1)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()
