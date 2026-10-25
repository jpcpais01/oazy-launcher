class_name EditDialog
extends Modal
## Add or edit a library entry, with a live cover preview.

var entry_id := ""
var prefill := {}
var on_saved := Callable()

var _name: LineEdit
var _path: LineEdit
var _args: LineEdit
var _kind := "game"
var _kind_chips := {}
var _cover_path := ""
var _hero_path := ""
var _cover_label: Label
var _hero_label: Label
var _preview: CoverArt
var _error: Label


func _init() -> void:
	width = 860.0


func _build() -> void:
	var e := Library.get_entry(entry_id)
	var data := e.duplicate() if not e.is_empty() else Library.make_entry(prefill)
	_kind = str(data.get("kind", "game"))
	_cover_path = str(data.get("cover", ""))
	_hero_path = str(data.get("hero", ""))
	var editing := not e.is_empty()
	title_block("Edit details" if editing else "Add to your library",
		"Change how %s looks and launches." % data["name"] if editing else "Pick a program, shortcut or web address. Oazy fills in the rest.",
		"edit" if editing else "plus")

	var body := Kit.hbox(28)
	content.add_child(body)

	var left := Kit.vbox(10)
	body.add_child(left)
	_preview = CoverArt.new()
	_preview.custom_minimum_size = Vector2(196, 294)
	left.add_child(_preview)
	if editing:
		_preview.setup(entry_id, 16.0)
	var hint := Kit.label("Preview", 13, 600, App.TEXT_MUTE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(hint)

	var form := Kit.vbox(14)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(form)

	_name = _field(form, "Name", str(data["name"]) if editing or prefill.has("name") else "", "e.g. Elden Ring")
	_name.text_changed.connect(func(_t: String) -> void: _refresh_preview())

	var source := str(data.get("source", "custom"))
	var path_row := Kit.hbox(10)
	_path = _field(form, "Program, shortcut or URL", str(data.get("path", "")), "C:/Games/MyGame/game.exe", path_row)
	if source == "steam" or source == "epic":
		_path.placeholder_text = "Launched through %s" % Library.source_label(data)
	var browse := FxButton.make("Browse", "folder", FxButton.Style.GHOST, 46)
	browse.pressed.connect(_browse_program)
	path_row.add_child(browse)

	_args = _field(form, "Launch options", str(data.get("args", "")), "Optional, e.g. -windowed -novid")

	form.add_child(Kit.label("Type", 14, 600, App.TEXT_DIM))
	var kinds := Kit.hbox(8)
	form.add_child(kinds)
	for spec in [["game", "Game", "gamepad"], ["app", "App", "app"]]:
		var c := FxButton.make(spec[1], spec[2], FxButton.Style.CHIP, 40)
		c.pressed.connect(func() -> void:
			_kind = spec[0]
			_sync_kind()
		)
		kinds.add_child(c)
		_kind_chips[spec[0]] = c
	_sync_kind()

	form.add_child(Kit.label("Artwork", 14, 600, App.TEXT_DIM))
	_cover_label = _image_row(form, "Cover", "cover")
	_hero_label = _image_row(form, "Background", "hero")
	_sync_image_labels()

	_error = Kit.label("", 14, 600, App.DANGER)
	_error.visible = false
	content.add_child(_error)

	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(row)
	var cancel := FxButton.make("Cancel", "", FxButton.Style.GHOST, 48)
	cancel.pressed.connect(close)
	row.add_child(cancel)
	var save := FxButton.make("Save" if editing else "Add to library", "check", FxButton.Style.PRIMARY, 48)
	save.pressed.connect(_save)
	row.add_child(save)
	_refresh_preview()


func _focus_first() -> void:
	if _name.text == "" and _path.text == "":
		_path.grab_focus()
	else:
		_name.grab_focus()
		_name.caret_column = _name.text.length()


func _field(parent: VBoxContainer, label_text: String, value: String, placeholder: String, row: HBoxContainer = null) -> LineEdit:
	var col := Kit.vbox(6)
	parent.add_child(col)
	col.add_child(Kit.label(label_text, 14, 600, App.TEXT_DIM))
	var le := LineEdit.new()
	le.text = value
	le.placeholder_text = placeholder
	le.custom_minimum_size.y = 46
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(_t: String) -> void: _save())
	if row:
		col.add_child(row)
		row.add_child(le)
	else:
		col.add_child(le)
	return le


func _image_row(parent: VBoxContainer, title: String, which: String) -> Label:
	var row := Kit.hbox(10)
	parent.add_child(row)
	var icon := Kit.icon_rect("image", 18, App.TEXT_DIM)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var l := Kit.label(title, 15, 500, App.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var choose := FxButton.make("Choose", "", FxButton.Style.GHOST, 38)
	choose.pressed.connect(func() -> void: _browse_image(which))
	row.add_child(choose)
	var clear := FxButton.icon_only("close", "Use automatic artwork", 16, 38)
	clear.pressed.connect(func() -> void:
		if which == "cover":
			_cover_path = ""
		else:
			_hero_path = ""
		_sync_image_labels()
		_refresh_preview()
	)
	row.add_child(clear)
	return l


func _sync_kind() -> void:
	for key in _kind_chips.keys():
		var c: FxButton = _kind_chips[key]
		c.selected = key == _kind


func _sync_image_labels() -> void:
	_cover_label.text = "Cover:  " + (_cover_path.get_file() if _cover_path != "" else "automatic")
	_hero_label.text = "Background:  " + (_hero_path.get_file() if _hero_path != "" else "automatic")


func _refresh_preview() -> void:
	if entry_id != "" and _cover_path == str(Library.get_entry(entry_id).get("cover", "")):
		return
	_preview.preview(_name.text.strip_edges(), _cover_path)


func _browse_program() -> void:
	_open_file_dialog(PackedStringArray(["*.exe, *.lnk, *.url, *.bat, *.cmd ; Programs and shortcuts", "* ; All files"]), func(path: String) -> void:
		_path.text = path
		var guess := Library.infer_from_path(path)
		if _name.text.strip_edges() == "":
			_name.text = str(guess["name"])
		_kind = str(guess["kind"])
		_sync_kind()
		prefill.merge(guess, true)
		_refresh_preview()
	)


func _browse_image(which: String) -> void:
	_open_file_dialog(PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"]), func(path: String) -> void:
		if which == "cover":
			_cover_path = path
		else:
			_hero_path = path
		_sync_image_labels()
		_refresh_preview()
	)


func _open_file_dialog(filters: PackedStringArray, done: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = filters
	fd.title = "Choose a file"
	fd.file_selected.connect(func(p: String) -> void:
		done.call(p)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.7)


func _save() -> void:
	var name := _name.text.strip_edges()
	var path := _path.text.strip_edges().replace("\\", "/").trim_prefix("\"").trim_suffix("\"")
	var e := Library.get_entry(entry_id)
	var source := str(e.get("source", prefill.get("source", "custom")))
	if path != "" and str(prefill.get("path", "")) != path and e.is_empty():
		# Typed by hand: re-infer (Steam links, URLs, etc.).
		prefill.merge(Library.infer_from_path(path), true)
		source = str(prefill.get("source", "custom"))
	if name == "":
		name = Fmt.pretty_name(path) if path != "" else ""
	if name == "":
		_show_error("Give it a name.")
		return
	if path == "" and source == "custom":
		_show_error("Pick the program or shortcut to launch.")
		return
	var fields := {
		"name": name,
		"path": path,
		"args": _args.text.strip_edges(),
		"kind": _kind,
		"cover": _cover_path,
		"hero": _hero_path,
	}
	var id := entry_id
	if e.is_empty():
		var all := prefill.duplicate()
		all.merge(fields, true)
		all["color"] = ""
		id = Library.add_entry(all)
		App.toast("Added %s" % name, &"success")
	else:
		if str(e["cover"]) != _cover_path:
			fields["color"] = ""
		Library.update_entry(id, fields)
		App.toast("Saved", &"success")
	if on_saved.is_valid():
		on_saved.call(id)
	close()


func _show_error(text: String) -> void:
	_error.text = text
	_error.visible = true
	Sfx.play(&"error")
	card.pivot_offset = card.size / 2.0
	var t := create_tween()
	for dx in [10.0, -8.0, 6.0, -3.0, 0.0]:
		t.tween_property(card, "position:x", card.position.x + dx, 0.05)
