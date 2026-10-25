class_name SettingsPage
extends Control
## Settings, grouped into calm cards.

const COLUMN := 880.0

var main: Node
var _col: VBoxContainer
var _update_status: Label
var _update_btn: FxButton
var _update_icon: TextureRect
var _scan_btn: FxButton
var _swatches: Array[Button] = []
var _auto_accent: ToggleSwitch
var _effects := {}
var _first_row := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := Kit.hbox(0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	center.add_child(Kit.spacer(0, 0, true))
	_col = Kit.vbox(14)
	_col.custom_minimum_size.x = COLUMN
	center.add_child(_col)
	center.add_child(Kit.spacer(0, 0, true))

	_col.add_child(Kit.spacer(0, 14))
	_col.add_child(Kit.label("Settings", 44, 800, Color.WHITE, true))
	_col.add_child(Kit.spacer(0, 6))

	_build_updates()

	var general := _section("General", "monitor")
	_toggle_row(general, "Minimise when launching", "Oazy steps out of the way while you play.", "minimize_on_launch")
	_toggle_row(general, "Start with Windows", "Open Oazy automatically when you sign in.", "launch_at_startup", func(on: bool) -> void: main.set_autostart(on))
	_toggle_row(general, "Open in fullscreen", "Great for TVs and controllers. F11 toggles any time.", "start_fullscreen")

	var library := _section("Library", "grid")
	_scan_btn = _button_row(library, "Find installed games", "Imports Steam, Epic Games and GOG games. Already added ones are skipped.", "Scan now", "sparkles", func() -> void: main.scan_stores())
	_button_row(library, "Add a game or app", "Any .exe, shortcut, Steam link or web address.", "Add", "plus", func() -> void: main.open_add({}))
	_button_row(library, "Refresh artwork", "Forget downloaded covers and fetch them again.", "Refresh", "refresh", func() -> void:
		Art.clear_downloads()
		App.toast("Artwork refreshed", &"success")
	)

	var look := _section("Appearance", "palette")
	_auto_accent = _toggle_row(look, "Match the selected game", "The whole interface takes on the colours of what you're looking at.", "", func(on: bool) -> void:
		Settings.set_value("accent_mode", "auto" if on else "fixed")
		_sync_swatches()
	)
	_auto_accent.set_on(Settings.get_value("accent_mode") == "auto")
	_swatch_row(look)
	_effects_row(look)
	_toggle_row(look, "Interface sounds", "Soft clicks and chimes as you move around.", "ui_sounds")
	_slider_row(look, "Sound volume", "volume")

	var about := _section("About", "info")
	_button_row(about, "Data folder", "Your library, settings and downloaded artwork live here.", "Open", "folder", func() -> void: OS.shell_open(App.data_dir()))
	var credits := Kit.label("Oazy Launcher %s  ·  Made with Godot  ·  Inter & Outfit typefaces (SIL OFL)" % App.version, 14, 500, App.TEXT_MUTE)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(Kit.spacer(0, 8))
	_col.add_child(credits)
	_col.add_child(Kit.spacer(0, 60))

	Updater.state_changed.connect(func(_s: StringName) -> void: _sync_update())
	Library.import_finished.connect(func(_a: int, _f: int) -> void: _sync_scan())
	_sync_update()


func on_shown() -> void:
	_sync_update()
	_sync_scan()


# --- Sections -------------------------------------------------------------------

func _build_updates() -> void:
	var card := PanelContainer.new()
	var s := Kit.box(Color(1, 1, 1, 0.055), 22, Color(1, 1, 1, 0.08), 1, 26, 22)
	card.add_theme_stylebox_override("panel", s)
	_col.add_child(card)
	var row := Kit.hbox(20)
	card.add_child(row)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(64, 64)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(logo)
	var text := Kit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label("Oazy Launcher %s" % App.version, 22, 700, Color.WHITE, true))
	var status_row := Kit.hbox(8)
	text.add_child(status_row)
	_update_icon = Kit.icon_rect("check", 16, App.SUCCESS)
	_update_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_update_icon)
	_update_status = Kit.label("", 15, 500, App.TEXT_DIM)
	status_row.add_child(_update_status)
	var notes := FxButton.make("Patch notes", "sparkles", FxButton.Style.GHOST, 46)
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	notes.pressed.connect(func() -> void: main.show_patch_notes())
	row.add_child(notes)
	_update_btn = FxButton.make("Check for updates", "refresh", FxButton.Style.PRIMARY, 46)
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.pressed.connect(_on_update_button)
	row.add_child(_update_btn)
	var opts := _section("", "")
	_toggle_row(opts, "Check for updates automatically", "Oazy checks GitHub quietly in the background.", "auto_check_updates")


func _section(title: String, icon_name: String) -> VBoxContainer:
	if title != "":
		var head := Kit.hbox(10)
		head.add_child(Kit.icon_rect(icon_name, 18, App.TEXT_DIM))
		head.add_child(Kit.label(title.to_upper(), 13, 700, App.TEXT_DIM))
		_col.add_child(Kit.spacer(0, 12))
		_col.add_child(head)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.045), 20, Color(1, 1, 1, 0.07), 1, 24, 8))
	_col.add_child(card)
	var list := Kit.vbox(0)
	card.add_child(list)
	_first_row = true
	return list


func _row(list: VBoxContainer, title: String, desc: String) -> HBoxContainer:
	if list.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.06)
		line.custom_minimum_size.y = 1
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(line)
	var row := Kit.hbox(18)
	row.custom_minimum_size.y = 74
	list.add_child(row)
	var text := Kit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label(title, 17, 600, App.TEXT))
	if desc != "":
		var d := Kit.label(desc, 14, 500, App.TEXT_MUTE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(d)
	return row


func _toggle_row(list: VBoxContainer, title: String, desc: String, key: String, extra: Callable = Callable()) -> ToggleSwitch:
	var row := _row(list, title, desc)
	var sw := ToggleSwitch.new()
	if key != "":
		sw.set_on(bool(Settings.get_value(key)))
	sw.toggled.connect(func(on: bool) -> void:
		if key != "":
			Settings.set_value(key, on)
		if extra.is_valid():
			extra.call(on)
	)
	row.add_child(sw)
	return sw


func _button_row(list: VBoxContainer, title: String, desc: String, label_text: String, icon_name: String, cb: Callable) -> FxButton:
	var row := _row(list, title, desc)
	var b := FxButton.make(label_text, icon_name, FxButton.Style.GHOST, 42)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _swatch_row(list: VBoxContainer) -> void:
	var row := _row(list, "Accent colour", "Used when matching is off.")
	var box := Kit.hbox(10)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for c in App.ACCENT_SWATCHES:
		var col: Color = c
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "#" + col.to_html(false)
		b.set_meta("color", col)
		b.pressed.connect(func() -> void:
			Sfx.play(&"toggle")
			Settings.set_value("accent_color", col.to_html(false))
			Settings.set_value("accent_mode", "fixed")
			_auto_accent.set_on(false)
			App.set_accent(col)
			_sync_swatches()
		)
		box.add_child(b)
		_swatches.append(b)
	_sync_swatches()


func _sync_swatches() -> void:
	var fixed: bool = Settings.get_value("accent_mode") == "fixed"
	var chosen := Color(str(Settings.get_value("accent_color")))
	for b in _swatches:
		var col: Color = b.get_meta("color")
		var on := fixed and col.is_equal_approx(chosen)
		var n := Kit.box(col, 999, Color(1, 1, 1, 0.95) if on else Color(1, 1, 1, 0.12), 3 if on else 1)
		var h := Kit.box(col.lightened(0.12), 999, Color(1, 1, 1, 0.6), 2)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", n)
		b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 999, Color(1, 1, 1, 0.9), 2))
		b.modulate.a = 1.0 if fixed else 0.55
	if fixed:
		App.set_accent(chosen)


func _effects_row(list: VBoxContainer) -> void:
	var row := _row(list, "Visual effects", "Eco calms the animations and caps the frame rate to save power.")
	var box := Kit.hbox(8)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for spec in [["high", "Stunning"], ["eco", "Eco"]]:
		var b := FxButton.make(spec[1], "", FxButton.Style.CHIP, 38)
		b.pressed.connect(func() -> void:
			Settings.set_value("effects", spec[0])
			App.refresh_fps()
			_sync_effects()
		)
		box.add_child(b)
		_effects[spec[0]] = b
	_sync_effects()


func _sync_effects() -> void:
	for key in _effects.keys():
		var b: FxButton = _effects[key]
		b.selected = Settings.get_value("effects") == key


func _slider_row(list: VBoxContainer, title: String, key: String) -> void:
	var row := _row(list, title, "")
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(Settings.get_value(key))
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	slider.drag_ended.connect(func(_c: bool) -> void: Sfx.play(&"select"))
	row.add_child(slider)


# --- Live state -----------------------------------------------------------------

func _sync_scan() -> void:
	if _scan_btn:
		_scan_btn.disabled = Library.importing
		_scan_btn.text = "Scanning…" if Library.importing else "Scan now"


func _sync_update() -> void:
	if _update_status == null:
		return
	var icon := "check"
	var color := App.SUCCESS
	var btn := "Check for updates"
	match Updater.state:
		&"checking":
			_update_status.text = "Checking for updates…"
			icon = "refresh"
			color = App.TEXT_DIM
		&"current":
			_update_status.text = "You're up to date"
		&"available":
			_update_status.text = "Version %s is available" % Updater.latest.get("version", "?")
			icon = "sparkles"
			color = App.accent
			btn = "See what's new"
		&"downloading":
			_update_status.text = "Downloading version %s…" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Show progress"
		&"ready":
			_update_status.text = "Version %s is ready to install" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Restart to update"
		&"error":
			_update_status.text = Updater.error_text
			icon = "alert"
			color = App.WARNING
			btn = "Try again"
		_:
			_update_status.text = "Updates come straight from GitHub"
			icon = "info"
			color = App.TEXT_DIM
	_update_icon.texture = Icons.tex(icon, 16, color)
	_update_btn.text = btn
	_update_btn.disabled = Updater.state == &"checking"


func _on_update_button() -> void:
	match Updater.state:
		&"available", &"downloading", &"ready":
			main.show_update()
		_:
			Updater.check()
